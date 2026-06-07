// zig/syscalls/debug.zig
// Debug-only syscalls: IDT watchdog check/inject, ctrl-c detection, WriteBuf.

const common = @import("../commands/common.zig");
const user = @import("../user.zig");
const keyboard = @import("../keyboard_isr.zig");
const logger = @import("../logger.zig");
const config = @import("../config.zig");
const syscalls = @import("mod.zig");

/// Syscall 32: CheckCtrlC() -> EAX (1 = Ctrl+C pressed, 0 = otherwise)
pub fn checkCtrlC(regs: *user.Registers) void {
    regs.eax = if (keyboard.check_ctrl_c_kernel()) 1 else 0;
}

/// Syscall 33: SYS_IDT_CHECK (debug) -> EAX (1 = IDT intact, 0 = modified)
pub fn idtCheck(regs: *user.Registers) void {
    if (!config.ENABLE_DEBUG_COMMANDS) {
        regs.eax = 0;
        return;
    }
    const idt_watchdog = @import("../idt_watchdog.zig");
    regs.eax = if (idt_watchdog.check_idt()) @as(u32, 1) else @as(u32, 0);
}

/// Syscall 34: SYS_IDT_MOVE (debug) — corrupt IDT to test watchdog detection
pub fn idtMove(regs: *user.Registers) void {
    if (!config.ENABLE_DEBUG_COMMANDS) {
        regs.eax = 0;
        return;
    }
    const idt_watchdog = @import("../idt_watchdog.zig");
    const idt_base = idt_watchdog.get_idt_base();
    const idt_ptr = @as([*]u8, @ptrFromInt(idt_base));
    idt_ptr[0x90 * 8] = 0xCC; // Modify unused vector
    regs.eax = 1;
}

/// Syscall 43: WriteBuf(EBX = ptr, ECX = len) — batched Ring-3 print
pub fn writeBuf(regs: *user.Registers) void {
    const ptr = @as([*]const u8, @ptrFromInt(regs.ebx));
    const len: usize = @intCast(regs.ecx);
    if (len > syscalls.MAX_SYSCALL_STR_LEN) {
        logger.security("WriteBuf: length exceeds MAX_SYSCALL_STR_LEN");
        regs.eax = 0;
    } else if (len == 0) {
        regs.eax = 0;
    } else if (syscalls.is_safe_user_range(regs.ebx, len)) {
        common.printBuf(ptr[0..len]);
        regs.eax = len;
    } else {
        logger.security("WriteBuf: invalid user buffer");
        regs.eax = 0;
    }
}
