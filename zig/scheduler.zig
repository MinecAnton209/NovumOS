const std = @import("std");
const memory = @import("memory.zig");
const logger = @import("logger.zig");
const exceptions = @import("exceptions.zig");
const common = @import("commands/common.zig");
const config = @import("config.zig");

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

    // Stack for the process
    stack: []u8,
};

var processes: [64]?*Process = [_]?*Process{null} ** 64;
var current_process_idx: u32 = 0;
pub var current_process: ?*Process = null;
var next_pid: u32 = 1;

pub fn init() void {
    logger.info("Scheduler: Initializing...");
}

pub fn bootstrap(esp: u32) void {
    const proc = memory.heap.alloc(@sizeOf(Process)) orelse @panic("OOM: Failed to allocate bootstrap process");
    const p = @as(*Process, @ptrCast(@alignCast(proc)));

    p.id = 0;
    p.name = "Kernel/Shell";
    p.state = .Running;
    p.priority = 1;
    p.esp = esp;
    p.cr3 = memory.get_current_pd();
    p.stack = &[_]u8{}; // Initial process uses the boot stack

    processes[0] = p;
    current_process = p;
    current_process_idx = 0;

    logger.success("Scheduler: Bootstrap complete.");
}

pub fn create_process(name: []const u8, entry_point: usize, is_user: bool) !*Process {
    const stack_size = 8192;
    const stack_ptr = memory.heap.alloc(stack_size) orelse return error.OutOfMemory;
    const stack = stack_ptr[0..stack_size];

    const proc = memory.heap.alloc(@sizeOf(Process)) orelse return error.OutOfMemory;
    const p = @as(*Process, @ptrCast(@alignCast(proc)));

    p.id = next_pid;
    next_pid += 1;
    p.name = name;
    p.state = .Ready;
    p.priority = 1;
    p.stack = stack;

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

    // Add to list (reuse terminated slots or find empty)
    for (0..64) |idx| {
        if (processes[idx] == null or (processes[idx].?.state == .Terminated and processes[idx].?.id != 0)) {
            if (processes[idx]) |old| {
                // Free old process memory if not kernel
                if (old.stack.len > 0) memory.heap.free(old.stack.ptr);
                memory.heap.free(@ptrCast(@constCast(old)));
            }
            processes[idx] = p;
            break;
        }
    }

    return p;
}

pub fn terminate_process(pid: u32) bool {
    if (pid == 0) return false; // Don't kill kernel
    for (processes) |maybe_p| {
        if (maybe_p) |p| {
            if (p.id == pid) {
                p.state = .Terminated;
                return true;
            }
        }
    }
    return false;
}

pub fn exit_process() noreturn {
    if (current_process) |p| {
        p.state = .Terminated;
    }
    // Yield
    asm volatile ("int $0x20");
    while (true) {}
}

fn process_return_stub() noreturn {
    exit_process();
}

pub fn schedule(current_esp: u32) u32 {
    if (current_process) |curr| {
        curr.esp = current_esp;
        if (curr.state == .Running) curr.state = .Ready;
    }

    // Scatter watchdog check - random based on build hash
    if (config.ENABLE_IDT_WATCHDOG and (current_esp & config.BUILD_HASH) == 0) {
        const idtw = @import("idt_watchdog.zig");
        if (!idtw.check_idt()) {
            idtw.trigger_panic();
        }
    }

    // Simple Round Robin
    var i: u32 = 0;
    while (i < 64) : (i += 1) {
        current_process_idx = (current_process_idx + 1) % 64;
        if (processes[current_process_idx]) |p| {
            if (p.state == .Ready) {
                p.state = .Running;
                current_process = p;

                // Switch address space if needed
                // memory.switch_page_directory(p.cr3);

                return p.esp;
            }
        }
    }

    return current_esp; // No other task, keep running current
}

pub fn list_processes() void {
    common.printZ("PID  Name            State       Space       Priority\n");
    common.printZ("---  --------------  ----------  ----------  --------\n");

    var buf: [32]u8 = undefined;
    for (processes) |maybe_p| {
        if (maybe_p) |p| {
            // PID
            const pid_str = common.intToString(@intCast(p.id), &buf);
            common.printZ(pid_str);
            var pad = 5 - pid_str.len;
            while (pad > 0) : (pad -= 1) common.printZ(" ");

            // Name
            common.printZ(p.name);
            pad = 16 - p.name.len;
            while (pad > 0) : (pad -= 1) common.printZ(" ");

            // State
            const state_str = switch (p.state) {
                .Ready => "Ready",
                .Running => "Running",
                .Blocked => "Blocked",
                .Terminated => "Terminated",
            };
            common.printZ(state_str);
            pad = 12 - state_str.len;
            while (pad > 0) : (pad -= 1) common.printZ(" ");

            // Space (CR3)
            const space_str = common.intToHex(p.cr3, &buf);
            common.printZ(space_str);
            pad = 12 - space_str.len;
            while (pad > 0) : (pad -= 1) common.printZ(" ");

            // Priority
            common.printZ(common.intToString(@intCast(p.priority), &buf));
            common.printZ("\n");
        }
    }
}
