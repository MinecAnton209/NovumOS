// Host-test stub for zig/drivers/time/time.zig: a fixed date keeps directory timestamps deterministic.
pub const DateTime = struct {
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
};

pub fn get_datetime() DateTime {
    return .{ .year = 2026, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0 };
}
