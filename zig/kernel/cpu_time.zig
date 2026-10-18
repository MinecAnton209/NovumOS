const std = @import("std");

/// Converts scheduler timer ticks into milliseconds of CPU time.
/// `hz` is the tick frequency the ticks were counted at; zero yields zero rather than dividing by it.
pub fn ticksToMs(ticks: u32, hz: u32) u64 {
    if (hz == 0) return 0;
    return @as(u64, ticks) * std.time.ms_per_s / hz;
}
