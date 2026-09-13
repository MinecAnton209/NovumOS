// compat: speaker via syscall 42
const syscall = @import("../syscall.zig");

pub fn beep_async(freq: u32, duration_ms: u32) void {
    _ = syscall.syscall4(42, 0, freq, duration_ms, 0);
}

pub fn beep_async_check() void {
    _ = syscall.syscall4(42, 1, 0, 0, 0);
}

pub fn beep_async_is_pending() bool {
    return syscall.syscall4(42, 1, 0, 0, 0) != 0;
}

pub fn beep_pattern_async(freq: u32, duration_ms: u32, gap_ms: u32) void {
    _ = syscall.syscall4(42, 2, freq, duration_ms, gap_ms);
}
