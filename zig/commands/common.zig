// Common Utilities Module
// Provides shared logic for printing, system control, and file system access.

const fs = @import("../fs.zig");
pub const vga = @import("../drivers/vga.zig");
const timer = @import("../drivers/timer.zig");
const acpi = @import("../drivers/acpi.zig");

const serial = @import("../drivers/serial.zig");

// --- Global State ---
pub var selected_disk: i8 = -1; // -1 means RAM FS
pub var current_dir_cluster: u32 = 0; // 0 = Root on FAT12/16
pub var current_path: [256]u8 = [_]u8{0} ** 256;
pub var current_path_len: usize = 0;

pub var redirect_active: bool = false;
pub var redirect_buffer: [32768]u8 = undefined;
pub var redirect_pos: usize = 0;

pub var pipe_active: bool = false;
pub var pipe_buffer: [16384]u8 = [_]u8{0} ** 16384;
pub var pipe_pos: usize = 0;
pub var pipe_read_active: bool = false;

/// Low-level character output
pub fn print_char(c: u8) void {
    if (pipe_active) {
        if (pipe_pos < pipe_buffer.len) {
            pipe_buffer[pipe_pos] = c;
            pipe_pos += 1;
        }
        return;
    }
    if (redirect_active) {
        if (redirect_pos < redirect_buffer.len) {
            redirect_buffer[redirect_pos] = c;
            redirect_pos += 1;
        }
        return;
    }
    vga.zig_print_char(c);
    serial.serial_print_char(c);
}

/// Print a string slice to the console
pub fn printZ(str: []const u8) void {
    for (str) |c| {
        if (c == 0) break;
        print_char(c);
    }
}

/// Print an error message in red
pub fn printError(str: []const u8) void {
    vga.set_color(12, 0); // Red
    printZ(str);
    vga.reset_color();
}

/// Print a signed 32-bit integer to the console
pub fn printNum(n: i32) void {
    if (n < 0) {
        print_char('-');
        printNum(-n);
        return;
    }
    if (n >= 10) {
        printNum(@divTrunc(n, 10));
    }
    print_char(@intCast(@as(u8, @intCast(@mod(n, 10))) + '0'));
}

/// Print a 32-bit hex value to the console
pub fn printHex(val: u32) void {
    printZ("0x");
    var i: i8 = 7;
    while (i >= 0) : (i -= 1) {
        const nibble = @as(u8, @intCast((val >> @as(u5, @intCast(i * 4))) & 0xF));
        const char = if (nibble < 10) '0' + nibble else 'A' + (nibble - 10);
        print_char(char);
    }
}

// --- File System Interface ---
// Re-export core fs functions for easy access by shell commands
pub const fs_init = fs.fs_init;
pub const fs_create = fs.fs_create;
pub const fs_delete = fs.fs_delete;
pub const fs_find = fs.fs_find;
pub const fs_list = fs.fs_list;
pub const fs_getname = fs.fs_getname;
pub const fs_size = fs.fs_size;
pub const fs_read = fs.fs_read;
pub const fs_write = fs.fs_write;

// --- System Control (I/O Ports) ---

/// Send a byte to an I/O port
pub fn outb(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]"
        :
        : [value] "{al}" (value),
          [port] "{dx}" (port),
    );
}

/// Send a word (16-bit) to an I/O port
pub fn outw(port: u16, value: u16) void {
    asm volatile ("outw %[value], %[port]"
        :
        : [value] "{ax}" (value),
          [port] "{dx}" (port),
    );
}

/// Read a byte from an I/O port
pub fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[ret]"
        : [ret] "={al}" (-> u8),
        : [port] "{dx}" (port),
    );
}

/// Read a word (16-bit) from an I/O port
pub fn inw(port: u16) u16 {
    return asm volatile ("inw %[port], %[ret]"
        : [ret] "={ax}" (-> u16),
        : [port] "{dx}" (port),
    );
}

/// Reset the computer via the keyboard controller pulse
pub fn reboot() noreturn {
    printZ("Rebooting...\r\n");
    // Pulse CPU reset line (FE code to command port 64h)
    outb(0x64, 0xFE);
    while (true) {}
}

/// Shutdown the system using ACPI
pub fn shutdown() noreturn {
    printZ("Shutting down...\r\n");
    acpi.shutdown();
}

/// Precise sleep in milliseconds
pub fn sleep(ms: usize) void {
    timer.sleep(ms);
}

var rnd_state: u32 = 0xACE1;
pub fn seed_random_with_tsc() void {
    var low: u32 = undefined;
    var high: u32 = undefined;
    asm volatile ("rdtsc"
        : [low] "={eax}" (low),
          [high] "={edx}" (high),
    );
    rnd_state = low ^ high;
    if (rnd_state == 0) rnd_state = 0xACE1;
}

pub fn get_random(min_v: i32, max_v: i32) i32 {
    if (max_v <= min_v) return min_v;
    // Xorshift PRNG
    rnd_state ^= rnd_state << 13;
    rnd_state ^= rnd_state >> 17;
    rnd_state ^= rnd_state << 5;
    const range = @as(u32, @intCast(max_v - min_v + 1));
    return @as(i32, @intCast(@mod(rnd_state, range))) + min_v;
}

pub fn math_abs(n: i32) i32 {
    return if (n < 0) -n else n;
}
pub fn math_max(a: i32, b: i32) i32 {
    return if (a > b) a else b;
}
pub fn math_min(a: i32, b: i32) i32 {
    return if (a < b) a else b;
}

/// Check if two memory slices are equal
pub fn std_mem_eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, 0..) |item, i| {
        if (item != b[i]) return false;
    }
    return true;
}

pub fn endsWithIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len < b.len) return false;
    const start = a.len - b.len;
    for (0..b.len) |i| {
        if (asciiLower(a[start + i]) != asciiLower(b[i])) return false;
    }
    return true;
}

/// Check if string starts with prefix
pub fn startsWith(a: []const u8, b: []const u8) bool {
    if (a.len < b.len) return false;
    return std_mem_eql(a[0..b.len], b);
}

pub fn endsWith(a: []const u8, b: []const u8) bool {
    if (a.len < b.len) return false;
    return std_mem_eql(a[a.len - b.len ..], b);
}

pub fn lastIndexOf(slice: []const u8, c: u8) ?usize {
    var i: usize = slice.len;
    while (i > 0) {
        i -= 1;
        if (slice[i] == c) return i;
    }
    return null;
}

/// Simple indexOf for memory slices
pub fn std_mem_indexOf(comptime T: type, slice: []const T, sub: []const T) ?usize {
    if (sub.len == 0) return 0;
    if (slice.len < sub.len) return null;
    var i: usize = 0;
    while (i <= slice.len - sub.len) : (i += 1) {
        if (std_mem_eql(slice[i .. i + sub.len], sub)) return i;
    }
    return null;
}

/// Remove leading and trailing spaces
pub fn trim(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and s[start] == ' ') : (start += 1) {}
    var end: usize = s.len;
    while (end > start and s[end - 1] == ' ') : (end -= 1) {}
    return s[start..end];
}

pub fn asciiLower(c: u8) u8 {
    if (c >= 'A' and c <= 'Z') return c + 32;
    return c;
}

pub fn startsWithIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len < b.len) return false;
    for (0..b.len) |i| {
        if (asciiLower(a[i]) != asciiLower(b[i])) return false;
    }
    return true;
}

pub fn copy(dest: []u8, src: []const u8) void {
    const len = @min(dest.len, src.len);
    for (0..len) |i| dest[i] = src[i];
}

/// Parse command line arguments with support for quoted strings
pub fn parseArgs(input: []const u8, argv: *[8][]const u8) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i < input.len and count < 8) {
        // Skip leading spaces
        while (i < input.len and input[i] == ' ') : (i += 1) {}
        if (i >= input.len) break;

        if (input[i] == '"') {
            i += 1; // Skip opening quote
            const start = i;
            while (i < input.len and input[i] != '"') : (i += 1) {}
            argv[count] = input[start..i];
            count += 1;
            if (i < input.len) i += 1; // Skip closing quote
        } else {
            const start = i;
            while (i < input.len and input[i] != ' ') : (i += 1) {}
            argv[count] = input[start..i];
            count += 1;
        }
    }
    return count;
}

/// Format string to buffer. Supports {d} and {s}.
pub fn fmt_to_buf(buf: []u8, comptime fmt: []const u8, args: anytype) []const u8 {
    var buf_idx: usize = 0;
    comptime var fmt_idx: usize = 0;
    comptime var arg_idx: usize = 0;

    inline while (fmt_idx < fmt.len) {
        if (buf_idx >= buf.len) break;

        if (fmt_idx + 2 < fmt.len and fmt[fmt_idx] == '{') {
            const spec = fmt[fmt_idx + 1];
            if (fmt[fmt_idx + 2] == '}') {
                if (spec == 'd') {
                    buf_idx += fmtIntToBuf(buf[buf_idx..], args[arg_idx]);
                    arg_idx += 1;
                    fmt_idx += 3;
                    continue;
                } else if (spec == 's') {
                    const str = args[arg_idx];
                    for (str) |c| {
                        if (buf_idx >= buf.len) break;
                        buf[buf_idx] = c;
                        buf_idx += 1;
                    }
                    arg_idx += 1;
                    fmt_idx += 3;
                    continue;
                }
            }
        }
        buf[buf_idx] = fmt[fmt_idx];
        buf_idx += 1;
        fmt_idx += 1;
    }
    return buf[0..buf_idx];
}

fn fmtIntToBuf(buf: []u8, n_in: anytype) usize {
    var n: i32 = @intCast(n_in);
    if (n == 0) {
        if (buf.len > 0) {
            buf[0] = '0';
            return 1;
        }
        return 0;
    }

    var len: usize = 0;
    if (n < 0) {
        if (buf.len > 0) {
            buf[0] = '-';
            len = 1;
        }
        n = -n;
    }

    var temp: [12]u8 = undefined;
    var i: usize = 0;
    var un: u32 = @intCast(n);
    while (un > 0) {
        temp[i] = @intCast((un % 10) + '0');
        un /= 10;
        i += 1;
    }

    var j: usize = 0;
    while (j < i) : (j += 1) {
        if (len + j < buf.len) {
            buf[len + j] = temp[i - 1 - j];
        }
    }
    return len + i;
}

pub fn parse_int(s: []const u8) ?i32 {
    if (s.len == 0) return null;
    var res: i32 = 0;
    var i: usize = 0;
    var sign: i32 = 1;
    if (s[0] == '-') {
        sign = -1;
        i = 1;
    }
    if (i >= s.len) return null;
    while (i < s.len) : (i += 1) {
        if (s[i] < '0' or s[i] > '9') return null;
        res = res * 10 + @as(i32, @intCast(s[i] - '0'));
    }
    return res * sign;
}
