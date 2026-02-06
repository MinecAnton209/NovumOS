const acpi = @import("drivers/acpi.zig");
const memory = @import("memory.zig");
const common = @import("commands/common.zig");

const TRAMPOLINE_ADDR = 0x8000;
const FLAG_ADDR = 0x9000;
const MAILBOX_STACK = 0x7000;
const MAILBOX_ENTRY = 0x7004;
const MAILBOX_ID = 0x7008; // New: Mailbox for passing Core ID

pub const Task = struct {
    func: *const fn (usize) void,
    arg: usize,
};

pub const CoreData = struct {
    lock: u32 = 0,
    tasks: [32]?Task = [_]?Task{null} ** 32,
    task_count: u32 = 0,
    total_tasks: u32 = 0,
    is_busy: bool = false,
    id: u8 = 0,
};

pub var cores: [16]CoreData = [_]CoreData{.{}} ** 16;
var print_lock: u32 = 0;
pub var detected_map: [256]u8 = [_]u8{255} ** 256; // Maps LAPIC_ID -> Core Index
pub var detected_cores: u32 = 1;

const trampoline_bin = @embedFile("trampoline.bin");
var ap_stacks: [16][8192]u8 align(4096) = undefined;

pub const CpuInfo = struct {
    vendor: [13]u8,
    brand: [49]u8 align(4),
    family: u32,
    model: u32,
    stepping: u32,
};

fn spin_lock(lock: *volatile u32) void {
    while (@atomicRmw(u32, lock, .Xchg, 1, .acquire) == 1) {
        asm volatile ("pause");
    }
}

fn spin_unlock(lock: *volatile u32) void {
    @atomicStore(u32, lock, 0, .release);
}

pub fn lock_print() void {
    spin_lock(&print_lock);
}

pub fn unlock_print() void {
    spin_unlock(&print_lock);
}

/// Balancer: Pushes a task to the least loaded core (excluding Core 0 if requested)
pub fn push_task(func: *const fn (usize) void, arg: usize) bool {
    var best_core: u32 = 1; // Try to skip Core 0 for heavy tasks
    var min_tasks: u32 = 999;

    if (detected_cores < 2) best_core = 0; // Fallback to BSP

    var i: u32 = if (detected_cores > 1) 1 else 0;
    while (i < detected_cores) : (i += 1) {
        if (cores[i].task_count < min_tasks) {
            min_tasks = cores[i].task_count;
            best_core = i;
        }
    }

    const target = &cores[best_core];
    spin_lock(&target.lock);
    defer spin_unlock(&target.lock);

    for (&target.tasks) |*slot| {
        if (slot.* == null) {
            slot.* = Task{ .func = func, .arg = arg };
            target.task_count += 1;
            return true;
        }
    }
    return false;
}

fn pop_local_task(core_idx: u32) ?Task {
    const core = &cores[core_idx];
    if (core.task_count == 0) return null;

    spin_lock(&core.lock);
    defer spin_unlock(&core.lock);

    for (&core.tasks) |*slot| {
        if (slot.*) |t| {
            slot.* = null;
            core.task_count -= 1;
            return t;
        }
    }
    return null;
}

fn steal_task(my_idx: u32) ?Task {
    var i: u32 = 0;
    while (i < detected_cores) : (i += 1) {
        if (i == my_idx) continue;
        const target = &cores[i];

        if (target.task_count > 0) {
            spin_lock(&target.lock);
            // Re-check after locking
            if (target.task_count > 0) {
                // Steal from the end of the queue
                var j: usize = 31;
                while (true) : (j -= 1) {
                    if (target.tasks[j]) |t| {
                        target.tasks[j] = null;
                        target.task_count -= 1;
                        spin_unlock(&target.lock);
                        return t;
                    }
                    if (j == 0) break;
                }
            }
            spin_unlock(&target.lock);
        }
    }
    return null;
}

pub export fn ap_kernel_entry() noreturn {
    // Get my core index from mailbox
    const my_idx = @as(*volatile u32, @ptrFromInt(MAILBOX_ID)).*;

    while (true) {
        if (pop_local_task(my_idx)) |task| {
            cores[my_idx].is_busy = true;
            task.func(task.arg);
            cores[my_idx].is_busy = false;
            cores[my_idx].total_tasks += 1;
        } else if (steal_task(my_idx)) |task| {
            lock_print();
            common.printZ(" [SMP] Core ");
            common.printNum(@intCast(my_idx));
            common.printZ(" stole a task!\n");
            unlock_print();

            cores[my_idx].is_busy = true;
            task.func(task.arg);
            cores[my_idx].is_busy = false;
            cores[my_idx].total_tasks += 1;
        } else {
            asm volatile ("pause");
        }
    }
}

pub fn get_online_cores() u8 {
    const flag_ptr = @as(*volatile u32, @ptrFromInt(FLAG_ADDR));
    return @intCast(flag_ptr.* + 1);
}

pub fn get_cpu_info() CpuInfo {
    var info: CpuInfo = undefined;
    var eax: u32 = 0;
    var ebx: u32 = undefined;
    var ecx: u32 = undefined;
    var edx: u32 = undefined;

    asm volatile ("cpuid"
        : [eax_out] "={eax}" (eax),
          [ebx_out] "={ebx}" (ebx),
          [ecx_out] "={ecx}" (ecx),
          [edx_out] "={edx}" (edx),
        : [eax_in] "{eax}" (eax),
    );

    @memcpy(info.vendor[0..4], @as([*]const u8, @ptrCast(&ebx))[0..4]);
    @memcpy(info.vendor[4..8], @as([*]const u8, @ptrCast(&edx))[0..4]);
    @memcpy(info.vendor[8..12], @as([*]const u8, @ptrCast(&ecx))[0..4]);
    info.vendor[12] = 0;

    var eax2: u32 = 1;
    var unused_ebx: u32 = undefined;
    var unused_ecx: u32 = undefined;
    var unused_edx: u32 = undefined;
    asm volatile ("cpuid"
        : [eax_out] "={eax}" (eax2),
          [ebx_out] "={ebx}" (unused_ebx),
          [ecx_out] "={ecx}" (unused_ecx),
          [edx_out] "={edx}" (unused_edx),
        : [eax_in] "{eax}" (eax2),
    );
    info.stepping = eax2 & 0xF;
    info.model = (eax2 >> 4) & 0xF;
    info.family = (eax2 >> 8) & 0xF;
    if (info.family == 15) info.family += (eax2 >> 20) & 0xFF;
    if (info.family == 6 or info.family == 15) info.model += ((eax2 >> 16) & 0xF) << 4;

    return info;
}

pub fn init() void {
    // common.printZ("SMP: Initializing Balancing SMP...\n");

    const tramp_ptr = @as([*]u8, @ptrFromInt(TRAMPOLINE_ADDR));
    @memcpy(tramp_ptr[0..trampoline_bin.len], trampoline_bin);

    const flag_ptr = @as(*volatile u32, @ptrFromInt(FLAG_ADDR));
    flag_ptr.* = 0;

    const mailbox_stack = @as(*volatile u32, @ptrFromInt(MAILBOX_STACK));
    const mailbox_entry = @as(*volatile u32, @ptrFromInt(MAILBOX_ENTRY));
    const mailbox_id = @as(*volatile u32, @ptrFromInt(MAILBOX_ID));
    mailbox_entry.* = @intFromPtr(&ap_kernel_entry);

    var lapic_base = acpi.lapic_addr;
    if (lapic_base == 0) {
        lapic_base = 0xFEE00000;
        // common.printZ("SMP: MADT not found, using default 0xFEE00000\n");
        detected_cores = 1;
    } else {
        detected_cores = acpi.madt_core_count;
    }

    if (!memory.map_page(lapic_base)) {
        // common.printZ("SMP: Failed to map LAPIC memory!\n");
        return;
    }

    const lapic = @as([*]volatile u32, @ptrFromInt(lapic_base));
    lapic[0x310 / 4] = 0;
    lapic[0x300 / 4] = 0x000C4500;
    common.sleep(10);

    var ap_count: u32 = 0;
    for (acpi.lapic_ids[0..acpi.madt_core_count]) |id| {
        // Find BSP. For simplicity, we assume ID 0 is BSP.
        // In a real OS we should use CPUID to get current LAPIC ID.
        if (id == 0) {
            cores[0].id = 0;
            continue;
        }

        const stack_top = @intFromPtr(&ap_stacks[ap_count]) + 8192;
        mailbox_stack.* = stack_top;
        mailbox_id.* = ap_count + 1; // BSP is 0

        const last_flag = flag_ptr.*;

        // common.printZ("SMP: Booting Core Index ");
        // common.printNum(@intCast(ap_count + 1));
        // common.printZ(" (LAPIC ID ");
        // common.printNum(@intCast(id));
        // common.printZ(")...\n");

        lapic[0x310 / 4] = @as(u32, id) << 24;
        lapic[0x300 / 4] = 0x00004608;

        var timeout: u32 = 0;
        while (flag_ptr.* == last_flag and timeout < 1000) : (timeout += 1) {
            common.sleep(1);
        }

        if (flag_ptr.* > last_flag) {
            cores[ap_count + 1].id = id;
            ap_count += 1;
        }
    }

    // const online = get_online_cores();
    // common.printZ("SMP: Status: ");
    // common.printNum(@intCast(online));
    // common.printZ(" cores integrated.\n");
}
