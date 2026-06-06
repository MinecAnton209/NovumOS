const common = @import("../../commands/common.zig");
const rtc_mod = @import("rtc.zig");
const boot_mod = @import("boot_time.zig");

pub const DateTime = rtc_mod.DateTime;

pub fn get_datetime() DateTime {
    const rtc_dt = rtc_mod.get_datetime();

    if (rtc_dt.year >= 2020 and rtc_dt.year <= 2100 and rtc_dt.year != 0) {
        return rtc_dt;
    }

    const boot_dt = boot_mod.get_datetime();
    if (boot_dt.year >= 2020 and boot_dt.year <= 2100) {
        return boot_dt;
    }

    return .{
        .year = 2026,
        .month = 1,
        .day = 1,
        .hour = 0,
        .minute = 0,
        .second = 0,
    };
}

pub fn init() void {
    const dt = get_datetime();

    common.printZ("\n[Time] ");
    if (dt.year >= 2020 and dt.year != 0) {
        common.printZ("RTC: ");
    } else {
        common.printZ("Fallback: ");
    }
    common.printNum(@intCast(dt.year));
    common.print_char('-');
    if (dt.month < 10) common.print_char('0');
    common.printNum(@intCast(dt.month));
    common.print_char('-');
    if (dt.day < 10) common.print_char('0');
    common.printNum(@intCast(dt.day));
    common.print_char(' ');
    if (dt.hour < 10) common.print_char('0');
    common.printNum(@intCast(dt.hour));
    common.print_char(':');
    if (dt.minute < 10) common.print_char('0');
    common.printNum(@intCast(dt.minute));
    common.print_char(':');
    if (dt.second < 10) common.print_char('0');
    common.printNum(@intCast(dt.second));
    common.printZ("\n");
}

pub fn reset_time() void {
    rtc_mod.reset_time();
    boot_mod.reset_time();
}

pub fn set_boot_time(dt: DateTime) void {
    boot_mod.set_boot_time(dt);
}

pub fn set_from_string(time_str: []const u8) bool {
    const dt = boot_mod.parse_time_input(time_str);
    if (dt) |d| {
        boot_mod.set_boot_time(d);
        return true;
    }
    return false;
}

pub fn is_valid() bool {
    const dt = get_datetime();
    return dt.year >= 2020 and dt.year <= 2100;
}

pub fn to_unix_timestamp() u64 {
    const dt = get_datetime();
    var days: u64 = 0;
    var y: u16 = 1970;
    while (y < dt.year) : (y += 1) {
        if (is_leap_year(y)) days += 366 else days += 365;
    }
    var m: u8 = 1;
    while (m < dt.month) : (m += 1) {
        days += days_in_month(m, dt.year);
    }
    days += dt.day - 1;
    return days * 86400 + @as(u64, dt.hour) * 3600 + @as(u64, dt.minute) * 60 + dt.second;
}

fn is_leap_year(year: u16) bool {
    return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
}

fn days_in_month(month: u8, year: u16) u8 {
    const days = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    if (month == 2 and is_leap_year(year)) return 29;
    return days[month - 1];
}
