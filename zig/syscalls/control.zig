// zig/syscalls/control.zig
// Privileged system control syscalls: Shutdown, Reboot.

const common = @import("../commands/common.zig");
const user = @import("../user.zig");
const logger = @import("../logger.zig");

/// Syscall 13: Shutdown(EBX = magic) — privileged
pub fn shutdown(regs: *user.Registers) void {
    if (!user.checkPrivilege(regs, "Shutdown")) return;
    common.shutdown();
}

/// Syscall 14: Reboot(EBX = magic) — privileged
pub fn reboot(regs: *user.Registers) void {
    if (!user.checkPrivilege(regs, "Reboot")) return;
    common.reboot();
}
