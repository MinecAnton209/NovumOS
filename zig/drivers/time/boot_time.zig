const common = @import("../../commands/common.zig");
const rtc_mod = @import("rtc.zig");

pub const DateTime = rtc_mod.DateTime;

var boot_time: DateTime = .{ .year = 2026, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0 };
var boot_time_set: bool = false;

pub fn get_datetime() DateTime {
    return boot_time;
}

pub fn set_boot_time(dt: DateTime) void {
    boot_time = dt;
    boot_time_set = true;
}

pub fn reset_time() void {
    boot_time_set = false;
}

pub fn prompt_boot_time() void {
    common.printZ("\nEnter current time (HH:MM): ");
}

pub fn parse_time_input(input: []const u8) ?DateTime {
    if (input.len < 5 or input[2] != ':') {
        return null;
    }

    const hour = parse_digit(input[0]) * 10 + parse_digit(input[1]);
    const minute = parse_digit(input[3]) * 10 + parse_digit(input[4]);

    if (hour > 23 or minute > 59) {
        return null;
    }

    return .{
        .year = 2026,
        .month = 1,
        .day = 1,
        .hour = hour,
        .minute = minute,
        .second = 0,
    };
}

fn parse_digit(c: u8) u8 {
    if (c >= '0' and c <= '9') return c - '0';
    return 0;
}
