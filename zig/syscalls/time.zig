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

const CLOCK_REALTIME: u32 = 0;
const CLOCK_MONOTONIC: u32 = 1;

const Timespec = extern struct {
    tv_sec: i32,
    tv_nsec: i32,
};

/// Syscall 110: clock_gettime(EBX=clock_id, ECX=ts_ptr) -> EAX=0 or -1
pub fn clock_gettime(regs: *user.Registers) void {
    if (!syscalls.is_safe_user_range(regs.ecx, @sizeOf(Timespec))) {
        regs.eax = 0xFFFFFFFF; return;
    }
    const ts = @as(*Timespec, @ptrFromInt(regs.ecx));
    if (regs.ebx == CLOCK_MONOTONIC) {
        const t = timer.get_ticks();
        ts.tv_sec = @intCast(t / 100);
        ts.tv_nsec = @intCast((t % 100) * 10_000_000);
        regs.eax = 0;
    } else if (regs.ebx == CLOCK_REALTIME) {
        const dt = rtc.get_datetime();
        const y: i32 = @intCast(dt.year - 1970);
        const d: i32 = @intCast(dt.day);
        const h: i32 = @intCast(dt.hour);
        const m: i32 = @intCast(dt.minute);
        const s: i32 = @intCast(dt.second);
        ts.tv_sec = y * 31536000 + d * 86400 + h * 3600 + m * 60 + s;
        ts.tv_nsec = 0;
        regs.eax = 0;
    } else {
        regs.eax = 0xFFFFFFFF;
    }
}

/// Syscall 111: nanosleep(EBX=req_ptr, ECX=rem_ptr) -> EAX=0 or -1
pub fn nanosleep(regs: *user.Registers) void {
    if (!syscalls.is_safe_user_range(regs.ebx, @sizeOf(Timespec))) {
        regs.eax = 0xFFFFFFFF; return;
    }
    const req = @as(*const Timespec, @ptrFromInt(regs.ebx));
    const total_ms = @as(u32, @intCast(req.tv_sec)) * 1000 + @as(u32, @intCast(req.tv_nsec)) / 1_000_000;
    common.sleep(total_ms);
    if (regs.ecx != 0 and syscalls.is_safe_user_range(regs.ecx, @sizeOf(Timespec))) {
        const rem = @as(*Timespec, @ptrFromInt(regs.ecx));
        rem.tv_sec = 0;
        rem.tv_nsec = 0;
    }
    regs.eax = 0;
}
