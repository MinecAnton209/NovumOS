// zig/syscalls/process.zig
// Process control syscalls: Exit, Execve, JumpToUser, Yield.

const user = @import("../user.zig");
const memory = @import("../memory.zig");
const logger = @import("../logger.zig");
const syscalls = @import("mod.zig");

extern fn kernel_loop() noreturn;
extern fn jump_to_ring3_entry(entry: usize, stack: usize, eflags: u32) noreturn;

/// Syscall 0: Exit — return to kernel shell
pub fn exit(_: *user.Registers) void {
    logger.info("User mode process exited. Returning to Shell...");
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
