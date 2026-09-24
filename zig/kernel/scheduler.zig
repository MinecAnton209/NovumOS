const std = @import("std");
const memory = @import("memory.zig");
const logger = @import("logger.zig");
const exceptions = @import("../arch/mod.zig").exceptions;
const smp = @import("../arch/mod.zig").smp;
const common = @import("../commands/common.zig");
const config = @import("../config.zig");

pub const ProcessState = enum {
    Ready,
    Running,
    Blocked,
    Terminated,
};

pub const Process = struct {
    id: u32,
    name: []const u8,
    esp: u32,
    cr3: u32,
    state: ProcessState,
    priority: u32,
    uid: u32,
    gid: u32,
    cwd: []const u8,
    is_idle: bool,
    name_owned: bool,

    // Stack for the process
    stack: []u8,

    // File descriptor table: fd_table[i] = open file index or -1 if unused
    fd_table: [FD_TABLE_SIZE]i16 = [_]i16{-1} ** FD_TABLE_SIZE,
};

pub const FD_TABLE_SIZE = 32;

const NUM_SLOTS = 64;

var processes: [NUM_SLOTS]?*Process = [_]?*Process{null} ** NUM_SLOTS;
var current_process_idx: u32 = 0;
var current_procs: [smp.cores.len]?*Process = [_]?*Process{null} ** smp.cores.len;
var idle_procs: [smp.cores.len]?*Process = [_]?*Process{null} ** smp.cores.len;
var next_pid: u32 = 1;
var bootstrapped: u8 = 0;

// One global lock guards every mutation of scheduler state. sched_held
// is a per-core "inside the critical section" bitmask set BEFORE the
// lock is acquired: a timer tick landing inside this core's own section
// must skip rescheduling, not spin on a lock the interrupted code owns
// (ring 3 cannot cli, so the bit is the only barrier we have).
var sched_lock: u32 = 0;
var sched_held: u16 = 0;

fn myMask() u16 {
    return @as(u16, 1) << @as(u4, @intCast(exceptions.get_core_index()));
}

fn sched_enter() u32 {
    var eflags: u32 = undefined;
    asm volatile ("pushfl; popl %[f]"
        : [f] "=r" (eflags),
    );
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 0) asm volatile ("cli");
    _ = @atomicRmw(u16, &sched_held, .Or, myMask(), .monotonic);
    while (@atomicRmw(u32, &sched_lock, .Xchg, 1, .acquire) == 1) {
        asm volatile ("pause");
    }
    return eflags;
}

fn sched_leave(eflags: u32) void {
    // Lock released before the bit: if the bit cleared first, a tick
    // between the two stores would see "not in section" while we still
    // hold the lock and deadlock on ourselves.
    @atomicStore(u32, &sched_lock, 0, .release);
    _ = @atomicRmw(u16, &sched_held, .And, ~myMask(), .release);
    asm volatile ("pushl %[f]; popfl"
        :
        : [f] "r" (eflags),
        : .{ .memory = true });
}

/// The process running on the calling core (syscalls, fd tables, ...).
pub fn current_process() ?*Process {
    return current_procs[exceptions.get_core_index()];
}

pub fn init() void {
    logger.info("Scheduler: Initializing...");
}

pub fn bootstrap(esp: u32) void {
    const proc = memory.heap.alloc(@sizeOf(Process)) orelse @panic("OOM: Failed to allocate bootstrap process");
    const p = @as(*Process, @ptrCast(@alignCast(proc)));

    p.id = 0;
    p.name = "Kernel/Shell";
    p.name_owned = false;
    p.state = .Running;
    p.priority = 1;
    p.uid = 0;
    p.gid = 0;
    p.cwd = "/";
    p.is_idle = false;
    p.esp = esp;
    p.cr3 = memory.get_current_pd();
    p.stack = &[_]u8{}; // Initial process uses the boot stack
    p.fd_table = [_]i16{-1} ** FD_TABLE_SIZE;

    processes[0] = p;
    current_procs[0] = p;
    current_process_idx = 0;
    @atomicStore(u8, &bootstrapped, 1, .release);

    logger.success("Scheduler: Bootstrap complete.");
}

pub fn create_process(name: []const u8, entry_point: usize, is_user: bool) !*Process {
    const eflags = sched_enter();
    defer sched_leave(eflags);
    reap_zombies(current_process());
    return create_process_locked(name, entry_point, is_user, false);
}

/// Caller must hold the scheduler lock.
fn create_process_locked(name: []const u8, entry_point: usize, is_user: bool, is_idle: bool) !*Process {
    // Claim an empty slot first so allocation failures unwind nothing.
    // Terminated slots are never reused in place — their memory may
    // still be a stack another core is executing on; reap_zombies
    // turns them into null slots one reschedule point later.
    var slot: usize = 0;
    var found = false;
    for (0..NUM_SLOTS) |idx| {
        if (processes[idx] == null) {
            slot = idx;
            found = true;
            break;
        }
    }
    if (!found) return error.ProcessTableFull;

    const stack_size = 8192;
    const stack_ptr = memory.heap.alloc(stack_size) orelse return error.OutOfMemory;
    const stack = stack_ptr[0..stack_size];

    // Copy the name into heap memory owned by the Process: the caller
    // may pass a temporary or stack buffer that dies after we return.
    var owned_name: []const u8 = "";
    if (name.len > 0) {
        const nb = memory.heap.alloc(name.len) orelse {
            memory.heap.free(stack_ptr);
            return error.OutOfMemory;
        };
        @memcpy(nb[0..name.len], name);
        owned_name = nb[0..name.len];
    }

    const proc = memory.heap.alloc(@sizeOf(Process)) orelse {
        memory.heap.free(stack_ptr);
        if (owned_name.len > 0) memory.heap.free(@ptrCast(@constCast(owned_name.ptr)));
        return error.OutOfMemory;
    };
    const p = @as(*Process, @ptrCast(@alignCast(proc)));

    p.id = next_pid;
    next_pid += 1;
    p.name = owned_name;
    p.name_owned = owned_name.len > 0;
    p.state = .Ready;
    p.priority = 1;
    p.uid = 0;
    p.gid = 0;
    p.cwd = "/";
    p.is_idle = is_idle;
    p.stack = stack;
    p.fd_table = [_]i16{-1} ** FD_TABLE_SIZE;

    // Initialize stack for context switch
    // [eflags, cs, eip, error_code, vector, gs, fs, es, ds, eax, ecx, edx, ebx, dummy_esp, ebp, esi, edi]
    var stack_top = @as([*]u32, @ptrCast(@alignCast(stack.ptr + stack_size)));

    // IRET frame
    if (is_user) {
        // User Mode IRET Frame: [SS, ESP, EFLAGS, CS, EIP]
        stack_top -= 5;
        stack_top[4] = 0xAB; // SS
        stack_top[3] = 0x3FF000 + 4096 - 16; // User ESP (placeholder)
        stack_top[2] = 0x202; // EFLAGS
        stack_top[1] = 0xA3; // CS
        stack_top[0] = entry_point;
    } else {
        // Kernel Mode: Push Return Address for RET
        stack_top -= 1;
        stack_top[0] = @intFromPtr(&process_return_stub);

        // Kernel Mode IRET Frame: [EFLAGS, CS, EIP]
        stack_top -= 3;
        stack_top[2] = 0x202; // EFLAGS
        stack_top[1] = 0x08; // CS
        stack_top[0] = entry_point;
    }

    // Segments
    stack_top -= 4;
    const ds: u32 = if (is_user) 0xAB else 0x10;
    stack_top[3] = ds; // GS
    stack_top[2] = ds; // FS
    stack_top[1] = ds; // ES
    stack_top[0] = ds; // DS

    // PUSHAD
    stack_top -= 8;
    for (0..8) |j| stack_top[j] = 0; // EAX, ECX, EDX, EBX, ESP, EBP, ESI, EDI

    p.esp = @intFromPtr(stack_top);
    p.cr3 = memory.get_current_pd(); // Inherit kernel page directory for now

    processes[slot] = p;
    return p;
}

pub fn terminate_process(pid: u32) bool {
    const eflags = sched_enter();
    defer sched_leave(eflags);
    if (pid == 0) return false; // Don't kill kernel
    for (processes) |maybe_p| {
        if (maybe_p) |p| {
            if (p.id == pid) {
                if (p.is_idle) return false;
                if (p.state != .Terminated) p.state = .Terminated;
                reap_zombies(current_process());
                return true;
            }
        }
    }
    return false;
}

pub fn exit_process() noreturn {
    const cpu = exceptions.get_core_index();
    const eflags = sched_enter();
    if (current_procs[cpu]) |p| {
        if (p.state != .Terminated) p.state = .Terminated;
    }
    sched_leave(eflags);
    // Yield: schedule() will run us down to an idle thread or a Ready
    // task; we never resume because our state is Terminated.
    asm volatile ("int $0x20");
    while (true) asm volatile ("sti; hlt");
}

fn process_return_stub() noreturn {
    exit_process();
}

fn idle_entry() noreturn {
    while (true) {
        asm volatile ("sti; hlt");
    }
}

/// Deferred reclamation: free a Terminated process only once no core
/// lists it as current and it is not `protect` — the stack the caller
/// itself is standing on. Must be called with the scheduler lock held.
/// A kill therefore frees one or two reschedule points later, never
/// under a stack that is still executing somewhere.
fn reap_zombies(protect: ?*Process) void {
    for (processes, 0..) |maybe_p, idx| {
        const p = maybe_p orelse continue;
        if (p.state != .Terminated or p.is_idle) continue;
        if (protect) |pr| {
            if (pr == p) continue;
        }
        var running_elsewhere = false;
        for (current_procs) |cur| {
            if (cur) |c| {
                if (c == p) {
                    running_elsewhere = true;
                    break;
                }
            }
        }
        if (running_elsewhere) continue;

        if (p.stack.len > 0) memory.heap.free(p.stack.ptr);
        if (p.name_owned and p.name.len > 0) {
            memory.heap.free(@ptrCast(@constCast(p.name.ptr)));
        }
        processes[idx] = null;
    }
}

/// Scatter watchdog check - random based on build hash.
fn maybe_watchdog(current_esp: u32) void {
    if (config.ENABLE_IDT_WATCHDOG and (current_esp & config.BUILD_HASH) == 0) {
        const idtw = @import("../arch/mod.zig").idt_watchdog;
        if (!idtw.check_idt()) {
            idtw.trigger_panic();
        }
    }
}

/// Round robin over real Ready processes; when none exist this core's
/// own idle thread takes over (created on first use). null means
/// nothing is runnable and no idle could be created — the caller keeps
/// the interrupted context as a last resort.
fn pick_next_esp_locked(cpu: u8) ?u32 {
    var i: u32 = 0;
    while (i < NUM_SLOTS) : (i += 1) {
        current_process_idx = (current_process_idx + 1) % NUM_SLOTS;
        if (processes[current_process_idx]) |p| {
            if (p.state == .Ready and !p.is_idle) {
                p.state = .Running;
                current_procs[cpu] = p;
                return p.esp;
            }
        }
    }

    if (idle_procs[cpu]) |idle| {
        if (idle.state == .Ready) {
            idle.state = .Running;
            current_procs[cpu] = idle;
            return idle.esp;
        }
    } else if (create_process_locked("idle", @intFromPtr(&idle_entry), false, true)) |idle| {
        idle.state = .Running;
        idle_procs[cpu] = idle;
        current_procs[cpu] = idle;
        return idle.esp;
    } else |_| {}

    return null;
}

/// Timer ISR reschedule point. ASSUMPTION: the timer vector is an
/// interrupt gate (idt.asm installs every gate as 0x8E — hardware
/// clears IF on entry). Unlike sched_enter, this path never sets the
/// sched_held bit: that is safe only because nothing inside
/// schedule()/maybe_watchdog()/reap_zombies() re-enables interrupts
/// (heap alloc/free restore the ISR's saved IF=0) or calls back into
/// schedule() on this core. A trap gate (IF stays set) or an accidental
/// sti on this path would self-deadlock on sched_lock.
pub fn schedule(current_esp: u32) u32 {
    if (@atomicLoad(u8, &bootstrapped, .acquire) == 0) return current_esp;

    const cpu = exceptions.get_core_index();
    // This core is inside its own critical section (interrupted ring 3
    // shell holding the lock): skip this tick instead of deadlocking.
    if ((@atomicLoad(u16, &sched_held, .monotonic) & myMask()) != 0) return current_esp;

    while (@atomicRmw(u32, &sched_lock, .Xchg, 1, .acquire) == 1) {
        asm volatile ("pause");
    }
    defer @atomicStore(u32, &sched_lock, 0, .release);

    const old = current_procs[cpu];
    if (old) |curr| {
        curr.esp = current_esp;
        if (curr.state == .Running) curr.state = .Ready;
    }

    maybe_watchdog(current_esp);
    reap_zombies(old);

    if (pick_next_esp_locked(cpu)) |next_esp| return next_esp;

    // Nothing runnable and no idle: resume the interrupted context.
    if (old) |o| {
        if (o.state == .Ready) o.state = .Running;
    }
    return current_esp;
}

pub fn list_processes() void {
    common.printZ("PID  Name            State       Space       Priority\n");
    common.printZ("---  --------------  ----------  ----------  --------\n");

    var buf: [32]u8 = undefined;
    for (0..NUM_SLOTS) |idx| {
        // Copy the row under the lock, print outside it: holding the
        // scheduler lock across the vga lock is a deadlock pair.
        const eflags = sched_enter();
        var occupied = false;
        var id: u32 = 0;
        var name_buf: [16]u8 = undefined;
        var name_len: usize = 0;
        var state: ProcessState = .Ready;
        var cr3: u32 = 0;
        var priority: u32 = 0;
        if (processes[idx]) |p| {
            occupied = true;
            id = p.id;
            name_len = @min(p.name.len, name_buf.len);
            @memcpy(name_buf[0..name_len], p.name[0..name_len]);
            state = p.state;
            cr3 = p.cr3;
            priority = p.priority;
        }
        sched_leave(eflags);
        if (!occupied) continue;

        // PID
        const pid_str = common.intToString(@intCast(id), &buf);
        common.printZ(pid_str);
        var pad = 5 - pid_str.len;
        while (pad > 0) : (pad -= 1) common.printZ(" ");

        // Name (truncated to the column width)
        common.printZ(name_buf[0..name_len]);
        pad = 16 - name_len;
        while (pad > 0) : (pad -= 1) common.printZ(" ");

        // State
        const state_str = switch (state) {
            .Ready => "Ready",
            .Running => "Running",
            .Blocked => "Blocked",
            .Terminated => "Terminated",
        };
        common.printZ(state_str);
        pad = 12 - state_str.len;
        while (pad > 0) : (pad -= 1) common.printZ(" ");

        // Space (CR3)
        const space_str = common.intToHex(cr3, &buf);
        common.printZ(space_str);
        pad = 12 - space_str.len;
        while (pad > 0) : (pad -= 1) common.printZ(" ");

        // Priority
        common.printZ(common.intToString(@intCast(priority), &buf));
        common.printZ("\n");
    }
}
