// zig/syscalls/process.zig
// Process control syscalls: Exit, Execve, JumpToUser, Yield.
// Also hosts per-process alloc tracking for Nova Ring 3 protection.

const user = @import("../user.zig");
const memory = @import("../memory.zig");
const logger = @import("../logger.zig");
const syscalls = @import("mod.zig");

extern fn kernel_loop() noreturn;
extern fn jump_to_ring3_entry(entry: usize, stack: usize, eflags: u32) noreturn;

// Per-process allocation tracking (CVE-2026-40573 mitigation)
// When current_is_nova is true, malloc/free (syscalls 30/31) are strict:
// - max 256 simultaneous allocations
// - free only succeeds if pointer is found in tracker (prevents UAF via fake header)
// - no degraded mode: if tracker full → OOM; untracked free → security log + no-op

pub const MAX_PROCESS_ALLOCS = 256;

const ProcessAlloc = struct {
    ptr: u32,
    size: u32,
};

pub var process_allocs: [MAX_PROCESS_ALLOCS]ProcessAlloc = [_]ProcessAlloc{.{ .ptr = 0, .size = 0 }} ** MAX_PROCESS_ALLOCS;
pub var process_alloc_count: u32 = 0;
pub var current_is_nova: bool = false;

/// Track a new allocation. Returns false if tracker is full.
pub fn track_alloc(ptr: u32, size: u32) bool {
    if (!current_is_nova) return true; // not tracking for non-Nova
    if (process_alloc_count >= MAX_PROCESS_ALLOCS) return false;
    process_allocs[process_alloc_count] = .{ .ptr = ptr, .size = size };
    process_alloc_count += 1;
    return true;
}

/// Find and remove an allocation from the tracker. Returns true if found.
pub fn untrack_alloc(ptr: u32) bool {
    if (!current_is_nova) return true; // no tracking for non-Nova
    var i: u32 = 0;
    while (i < process_alloc_count) : (i += 1) {
        if (process_allocs[i].ptr == ptr) {
            // Swap with last and decrement
            process_alloc_count -= 1;
            if (i < process_alloc_count) {
                process_allocs[i] = process_allocs[process_alloc_count];
            }
            return true;
        }
    }
    return false; // not found
}

pub fn is_nova_filename(name: []const u8) bool {
    return name.len >= 4 and
        (name[0] | 0x20) == 'n' and
        (name[1] | 0x20) == 'o' and
        (name[2] | 0x20) == 'v' and
        (name[3] | 0x20) == 'a';
}

/// Reset tracking state (called before launching a new user process)
pub fn reset_alloc_tracking() void {
    process_alloc_count = 0;
    current_is_nova = false;
}

/// Syscall 0: Exit — return to kernel shell
pub fn exit(_: *user.Registers) void {
    logger.info("User mode process exited. Returning to Shell...");
    reset_alloc_tracking();
    user.jump_to_user_mode_with_entry(@intFromPtr(&kernel_loop), true);
}

/// Syscall 12: JumpToUser(EBX = entry) — raw jump to Ring 3
/// Restricted: entry must be in user-space, no kernel-pointer jumps.
pub fn jumpToUser(regs: *user.Registers) void {
    const entry = regs.ebx;
    const kernel_end = @intFromPtr(&memory.ebss_sym);
    const max_user_addr = 0x40000000;

    if (entry < kernel_end or entry >= max_user_addr) {
        logger.security("JumpToUser: Invalid entry point (not in user-space)");
        regs.eax = 0;
    } else {
        const user_esp = 0x3FF000 + 4096 - 16;
        const eflags: u32 = if (user.get_is_privileged()) 0x3202 else 0x0202;
        jump_to_ring3_entry(entry, user_esp, eflags);
    }
}

/// Syscall 40: Execve(EBX = filename_ptr) — execute ELF from simplefs
pub fn execve(regs: *user.Registers) void {
    const fs_mod = @import("../fs.zig");
    const elf_mod = @import("../elf.zig");

    if (syscalls.safe_str_from_user(regs.ebx, 32)) |filename| {
        // Reset tracking and detect Nova
        reset_alloc_tracking();
        current_is_nova = is_nova_filename(filename);
        const file_id = fs_mod.fs_find(filename.ptr, @intCast(filename.len));
        if (file_id < 0) {
            regs.eax = 0xFFFFFFFF;
            return;
        }
        const file = &fs_mod.files[@intCast(file_id)];
        if (!file.used or file.size == 0) {
            regs.eax = 0xFFFFFFFF;
            return;
        }
        const data = file.data[0..file.size];
        elf_mod.load_and_run(data) catch {
            regs.eax = 0xFFFFFFFF;
            return;
        };
    } else {
        logger.security("Invalid filename in Execve");
        regs.eax = 0xFFFFFFFF;
    }
}

/// Syscall 41: Yield() — yield CPU via int $0x20
pub fn yield(regs: *user.Registers) void {
    asm volatile ("int $0x20");
    regs.eax = 0;
}
