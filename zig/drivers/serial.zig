// Serial COM1 Driver
const common = @import("../commands/common.zig");

pub const PORT = 0x3F8;

pub export fn serial_print_char(c: u8) void {
    while (!is_transmit_empty()) {}
    // Map LF to CRLF for serial terminal consistency
    if (c == 10) {
        outb(PORT, 13);
        while (!is_transmit_empty()) {}
    }
    outb(PORT, c);
}

pub fn serial_print_str(str: []const u8) void {
    for (str) |c| serial_print_char(c);
}

fn is_transmit_empty() bool {
    return (inb(PORT + 5) & 0x20) != 0;
}

pub fn serial_has_data() bool {
    return (inb(PORT + 5) & 1) != 0;
}

pub fn serial_getchar() u8 {
    return inb(PORT);
}

pub fn serial_clear_screen() void {
    serial_print_str("\x1B[2J\x1B[H");
}

pub fn serial_clear_line() void {
    serial_print_str("\x1B[K");
}

pub fn serial_hide_cursor() void {
    serial_print_str("\x1B[?25l");
}

pub fn serial_show_cursor() void {
    serial_print_str("\x1B[?25h");
}

pub fn serial_set_cursor(row: u8, col: u8) void {
    var buf: [32]u8 = undefined;
    const str = common.fmt_to_buf(&buf, "\x1B[{d};{d}H", .{ @as(u32, row) + 1, @as(u32, col) + 1 });
    serial_print_str(str);
}

pub fn serial_set_color(fg: u8) void {
    // Basic ANSI colors (30-37)
    var buf: [16]u8 = undefined;
    const ansi_color = switch (fg & 0x07) {
        0 => @as(u32, 30), // Black
        1 => 34, // Blue
        2 => 32, // Green
        3 => 36, // Cyan
        4 => 31, // Red
        5 => 35, // Magenta
        6 => 33, // Yellow
        7 => 37, // White
        else => 37,
    };
    const str = common.fmt_to_buf(&buf, "\x1B[{d}m", .{ansi_color});
    serial_print_str(str);
}

fn outb(port: u16, val: u8) void {
    asm volatile ("outb %[val], %[port]"
        :
        : [val] "{al}" (val),
          [port] "{dx}" (port),
    );
}

fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[result]"
        : [result] "={al}" (-> u8),
        : [port] "{dx}" (port),
    );
}
