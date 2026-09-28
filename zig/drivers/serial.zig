const common = @import("../commands/common.zig");
const config = @import("../config.zig");

// Serial COM1 Driver

pub const PORT = 0x3F8;

/// Initialize COM1 serial port with 115200 baud, 8N1
pub fn init() void {
    // 115200 baud = 1 (divisor), 9600 baud = 12
    const divisor: u16 = 0; // 115200 baud with 1.152MHz clock

    // Disable all interrupts
    outb(PORT + 1, 0x00);

    // Enable DLAB (Divisor Latch Access)
    outb(PORT + 3, 0x80);

    // Set divisor (low and high bytes)
    outb(PORT + 0, @intCast(divisor & 0xFF));
    outb(PORT + 1, @intCast((divisor >> 8) & 0xFF));

    // Set 8 data bits, no parity, 1 stop bit
    outb(PORT + 3, 0x03);

    // FIFO: enable and clear
    outb(PORT + 2, 0xC7);

    // Set RTS/DTR, reset OFF signal
    outb(PORT + 4, 0x0B);

    // Clear any pending interrupts and received data
    _ = inb(PORT);
}

pub export fn serial_print_char(c: u8) void {
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) != 0) {
        // Ring 3 — use serial output syscall if available, else skip
        return serial_print_char_ring3(c);
    }

    _serial_print_char(c);
}

fn serial_print_char_ring3(c: u8) void {
    // Ring 3 serial output not supported via syscalls in current design
    // Kernel serial output through ENABLE_SERIAL_INPUT still works
    _ = c;
}


fn _serial_print_char(c: u8) void {
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
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    // Carry out the operation ONLY in Ring 0
    if ((cs & 3) == 0) {
        asm volatile ("outb %[val], %[port]"
            :
            : [val] "{al}" (val),
              [port] "{dx}" (port),
        );
    }
}

fn inb(port: u16) u8 {
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    // Return actual value only in Ring 0
    if ((cs & 3) == 0) {
        return asm volatile ("inb %[port], %[result]"
            : [result] "={al}" (-> u8),
            : [port] "{dx}" (port),
        );
    }
    return 0xFF;
}
