// compat: commands/common.zig — syscall-based Ring 3 implementations
// replaces kernel's commands/common.zig
const syscall = @import("../syscall.zig");
const str_util = @import("str");
pub const std_mem_eql = str_util.std_mem_eql;
pub const startsWith = str_util.startsWith;
pub const endsWith = str_util.endsWith;
pub const asciiLower = str_util.asciiLower;
pub const startsWithIgnoreCase = str_util.startsWithIgnoreCase;
pub const lastIndexOf = str_util.lastIndexOf;
pub const copy = str_util.copy;
pub const math_abs = str_util.math_abs;
pub const math_max = str_util.math_max;
pub const math_min = str_util.math_min;

// Thin wrappers for callers that reference common.syscall0/1/2
pub fn syscall0(n: u32) u32 {
    return syscall.syscall0(n);
}
pub fn syscall1(n: u32, a1: u32) u32 {
    return syscall.syscall1(n, a1);
}
pub fn syscall2(n: u32, a1: u32, a2: u32) u32 {
    return syscall.syscall2(n, a1, a2);
}

// VGA/console
pub var current_color: u16 = 0x07;

pub fn print_char(c: u8) void {
    const buf = [_]u8{c};
    _ = syscall2(43, @intFromPtr(&buf), 1);
}

pub fn printZ(str: []const u8) void {
    _ = syscall1(1, @intFromPtr(str.ptr));
}

pub fn printBuf(buf: []const u8) void {
    _ = syscall2(43, @intFromPtr(buf.ptr), @intCast(buf.len));
}

pub fn printNum(n: i32) void {
    var buf: [32]u8 = undefined;
    const s = intToString(n, &buf);
    printBuf(s);
}

pub fn printHex(val: u32) void {
    var buf: [32]u8 = undefined;
    const s = intToHex(val, &buf);
    printBuf(s);
}

pub fn printError(str: []const u8) void {
    printBuf(str);
}

pub fn clear_screen() void {
    _ = syscall0(5);
}

pub fn set_cursor(row: u8, col: u8) void {
    _ = syscall2(3, row, col);
}

pub fn get_cursor_row() u8 {
    const val = syscall0(4);
    return @intCast((val >> 8) & 0xFF);
}

pub fn get_cursor_col() u8 {
    const val = syscall0(4);
    return @intCast(val & 0xFF);
}

pub fn draw_char_at(row: u8, col: u8, c: u8, attr: u16) void {
    _ = syscall1(18, (@as(u32, row) << 24) | (@as(u32, col) << 16) | (@as(u32, c) << 8) | attr);
    // Simpler: just set cursor and print
    set_cursor(row, col);
    print_char(c);
}

pub fn get_char() u8 {
    return @intCast(syscall1(2, 0));
}

// Sleep
pub fn sleep(ms: usize) void {
    _ = syscall1(10, @intCast(ms));
}

// File system state (Ring 3 — always root)
pub var selected_disk: i8 = 0; // ATA Master
pub var current_dir_cluster: u32 = 0;
pub var current_path: [256]u8 = [_]u8{'/'} ** 256;
pub var current_path_len: usize = 1;

// Random
pub fn seed_random_with_tsc() void {}

pub fn get_random(min_v: i32, max_v: i32) i32 {
    // LCG prng seeded by free memory (syscall 44)
    const seed = syscall0(44);
    var state: u32 = seed;
    state = state * 1103515245 + 12345;
    const r = (state >> 16) & 0x7FFF;
    const range = max_v - min_v + 1;
    if (range <= 0) return min_v;
    return min_v + @rem(@as(i32, @intCast(r)), range);
}

// String utilities (same implementations as kernel)
pub fn fmt_to_buf(buf: []u8, comptime fmt: []const u8, args: anytype) []const u8 {
    _ = buf;
    _ = fmt;
    _ = args;
    return "";
}

pub fn parse_int(s: []const u8) ?i32 {
    if (s.len == 0) return null;
    var i: usize = 0;
    var neg = false;
    if (s[0] == '-') {
        neg = true;
        i += 1;
    } else if (s[0] == '+') {
        i += 1;
    }
    if (i >= s.len) return null;
    var val: i32 = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] < '0' or s[i] > '9') return null;
        val = val * 10 + (s[i] - '0');
    }
    return if (neg) -val else val;
}

pub fn intToHex(val: u32, buf: []u8) []const u8 {
    const hex = "0123456789ABCDEF";
    var i: usize = buf.len;
    buf[i - 1] = 0;
    i -= 1;
    if (val == 0) {
        buf[i - 1] = '0';
        return buf[i - 1 .. buf.len - 1];
    }
    var v = val;
    while (v > 0 and i > 0) {
        i -= 1;
        buf[i] = hex[v & 0xF];
        v >>= 4;
    }
    return buf[i .. buf.len - 1];
}

pub fn intToString(val: i32, buf: []u8) []const u8 {
    var i: usize = buf.len;
    buf[i - 1] = 0;
    i -= 1;
    var v = if (val < 0) -val else val;
    if (v == 0) {
        buf[i - 1] = '0';
        return buf[i - 1 .. buf.len - 1];
    }
    while (v > 0 and i > 0) {
        i -= 1;
        buf[i] = @as(u8, @intCast((v % 10) + '0'));
        v /= 10;
    }
    if (val < 0 and i > 0) {
        i -= 1;
        buf[i] = '-';
    }
    return buf[i .. buf.len - 1];
}

pub fn trim(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and (s[start] == ' ' or s[start] == '\t')) : (start += 1) {}
    var end = s.len;
    while (end > start and (s[end - 1] == ' ' or s[end - 1] == '\t')) : (end -= 1) {}
    return s[start..end];
}

pub fn parseArgs(input: []const u8, argv: anytype) usize {
    _ = input;
    _ = argv;
    return 0;
}
