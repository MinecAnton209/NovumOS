// zig/syscalls/time.zig
// Time-related syscalls: sleep, ticks, datetime.

const common = @import("../commands/common.zig");
const timer = @import("../drivers/timer.zig");
const rtc = @import("../drivers/time/time.zig");
const user = @import("../user.zig");
const logger = @import("../logger.zig");
const syscalls = @import("mod.zig");

/// Syscall 10: Sleep(EBX = ms) — busy-wait sleep
pub fn sleep(regs: *user.Registers) void {
    common.sleep(@intCast(regs.ebx));
}

/// Syscall 11: GetTicks() -> EAX — monotonic ticks since boot
pub fn getTicks(regs: *user.Registers) void {
    regs.eax = @intCast(timer.get_ticks());
}

/// Syscall 19: GetDateTime(EBX = ptr to DateTime struct) — fill user struct
pub fn getDateTime(regs: *user.Registers) void {
    if (!syscalls.is_safe_user_range(regs.ebx, @sizeOf(rtc.DateTime))) {
        logger.security("Invalid DateTime pointer for GetDateTime");
        return;
    }
    const dt_ptr = @as(*rtc.DateTime, @ptrFromInt(regs.ebx));
    dt_ptr.* = rtc.get_datetime();
}
