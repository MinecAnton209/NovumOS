// CMOS Real Time Clock (RTC) Driver
const common = @import("../commands/common.zig");

const CMOS_ADDR = 0x70;
const CMOS_DATA = 0x71;

pub fn read_rtc(reg: u8) u8 {
    outb(CMOS_ADDR, reg);
    return inb(CMOS_DATA);
}

fn is_updating() bool {
    outb(CMOS_ADDR, 0x0A);
    return (inb(CMOS_DATA) & 0x80) != 0;
}

pub const DateTime = struct {
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
};

pub fn get_datetime() DateTime {
    while (is_updating()) {}

    var second = read_rtc(0x00);
    var minute = read_rtc(0x02);
    var hour = read_rtc(0x04);
    var day = read_rtc(0x07);
    var month = read_rtc(0x08);
    var year: u16 = read_rtc(0x09);

    const registerB = read_rtc(0x0B);

    // Convert BCD to Binary if needed
    if ((registerB & 0x04) == 0) {
        second = (second & 0x0F) + ((second / 16) * 10);
        minute = (minute & 0x0F) + ((minute / 16) * 10);
        hour = ((hour & 0x0F) + (((hour & 0x70) / 16) * 10)) | (hour & 0x80);
        day = (day & 0x0F) + ((day / 16) * 10);
        month = (month & 0x0F) + ((month / 16) * 10);
        year = (year & 0x0F) + ((year / 16) * 10);
    }

    // Convert 12h to 24h if needed
    if ((registerB & 0x02) == 0 and (hour & 0x80) != 0) {
        hour = ((hour & 0x7F) + 12) % 24;
    }

    year += 2000; // Simplified

    return .{
        .year = year,
        .month = month,
        .day = day,
        .hour = hour,
        .minute = minute,
        .second = second,
    };
}

fn outb(port: u16, val: u8) void {
    asm volatile ("outb %[val], %[port]"
        :
        : [val] "{al}" (val),
          [port] "{dx}" (port),
    );
}

fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[ret]"
        : [ret] "={al}" (-> u8),
        : [port] "{dx}" (port),
    );
}
