// zig/syscalls/nova.zig
// Nova-language syscalls: shell execution, VGA color control.

const common = @import("../commands/common.zig");
const user = @import("../user.zig");
const syscalls = @import("mod.zig");
const shell = @import("../shell.zig");
const vga = @import("../drivers/vga.zig");

/// Syscall 53: ShellExec(EBX = cmd_ptr) — execute a shell command string
pub fn shellExec(regs: *user.Registers) void {
    if (syscalls.safe_str_from_user(regs.ebx, syscalls.MAX_SYSCALL_STR_LEN)) |cmd| {
        shell.shell_execute_literal(cmd);
    }
}

/// Syscall 54: SetColor(EBX = fg, ECX = bg) — set VGA foreground/background color
pub fn setColor(regs: *user.Registers) void {
    vga.set_color(@intCast(regs.ebx), @intCast(regs.ecx));
}
