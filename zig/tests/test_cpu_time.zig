const std = @import("std");
const cpu_time = @import("cpu_time").ticksToMs;

test "zero ticks is zero milliseconds" {
    try std.testing.expectEqual(@as(u64, 0), cpu_time(0, 100));
}

test "one tick at 100 Hz is 10 ms" {
    try std.testing.expectEqual(@as(u64, 10), cpu_time(1, 100));
}

test "one second of ticks at 100 Hz is 1000 ms" {
    try std.testing.expectEqual(@as(u64, 1000), cpu_time(100, 100));
}

test "non-divisible tick rate rounds down" {
    try std.testing.expectEqual(@as(u64, 333), cpu_time(1, 3));
}

test "zero frequency never divides by zero" {
    try std.testing.expectEqual(@as(u64, 0), cpu_time(12345, 0));
}

test "maximum tick count does not overflow the 64-bit result" {
    const ms = cpu_time(std.math.maxInt(u32), 100);
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u32)) * 10, ms);
}
