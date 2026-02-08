// Nova Language - Common utilities
const common = @import("../commands/common.zig");

pub const print_char = common.print_char;
pub const printZ = common.printZ;
pub const printNum = common.printNum;
pub const std_mem_eql = common.std_mem_eql;

pub const reboot = common.reboot;
pub const shutdown = common.shutdown;

pub const fat = @import("../drivers/fat.zig");
pub const ata = @import("../drivers/ata.zig");
pub const global_common = @import("../commands/common.zig");

pub const AngleMode = enum {
    DEG,
    RAD,
};

pub fn toLower(c: u8) u8 {
    if (c >= 'A' and c <= 'Z') return c - 'A' + 'a';
    return c;
}
pub fn streq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (ca != cb) return false;
    }
    return true;
}

pub fn streq_ignore_case(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (toLower(ca) != toLower(cb)) return false;
    }
    return true;
}

pub fn startsWith(str: []const u8, prefix: []const u8) bool {
    if (str.len < prefix.len) return false;
    for (0..prefix.len) |i| {
        if (str[i] != prefix[i]) return false;
    }
    return true;
}

pub fn indexOf(str: []const u8, char: u8) ?usize {
    for (str, 0..) |c, i| {
        if (c == char) return i;
    }
    return null;
}

pub fn copy(dest: []u8, src: []const u8) void {
    const len = if (dest.len < src.len) dest.len else src.len;
    for (0..len) |i| {
        dest[i] = src[i];
    }
}

pub fn parseInt(str: []const u8) i32 {
    var res: i32 = 0;
    var sign: i32 = 1;
    var i: usize = 0;

    if (str.len == 0) return 0;

    // Handle whitespace? Assuming trimmed

    if (str[0] == '-') {
        sign = -1;
        i = 1;
    }

    while (i < str.len) : (i += 1) {
        if (str[i] >= '0' and str[i] <= '9') {
            const digit: i32 = str[i] - '0';
            res = (res * 10) + digit;
        } else {
            break;
        }
    }

    return res * sign;
}

pub fn intToString(val: i32, buf: []u8) []const u8 {
    if (val == 0) {
        if (buf.len > 0) buf[0] = '0';
        return buf[0..1];
    }

    var is_neg = false;
    var uv: u32 = 0;

    if (val < 0) {
        is_neg = true;
        uv = @intCast(-val);
    } else {
        uv = @intCast(val);
    }

    var i: usize = 0;
    while (uv > 0 and i < buf.len) {
        buf[i] = @as(u8, @intCast(uv % 10)) + '0';
        uv = uv / 10;
        i += 1;
    }

    if (is_neg and i < buf.len) {
        buf[i] = '-';
        i += 1;
    }

    // Reverse
    var left: usize = 0;
    var right: usize = i - 1;
    while (left < right) {
        const tmp = buf[left];
        buf[left] = buf[right];
        buf[right] = tmp;
        left += 1;
        right -= 1;
    }

    return buf[0..i];
}

pub fn intToHex(val: u32, buf: []u8) []const u8 {
    if (buf.len < 3) return "0x0";
    buf[0] = '0';
    buf[1] = 'x';
    if (val == 0) {
        buf[2] = '0';
        return buf[0..3];
    }

    var v = val;
    var i: usize = 0;
    var temp_buf: [16]u8 = undefined;

    while (v > 0 and i < 16) {
        const d = @as(u8, @intCast(v % 16));
        temp_buf[i] = if (d < 10) d + '0' else d - 10 + 'A';
        v /= 16;
        i += 1;
    }

    var j: usize = 0;
    while (j < i) : (j += 1) {
        buf[2 + j] = temp_buf[i - j - 1];
    }

    return buf[0 .. 2 + i];
}

pub fn parseFloat(str: []const u8) f32 {
    var res: f32 = 0;
    var sign: f32 = 1.0;
    var i: usize = 0;

    if (str.len == 0) return 0;

    if (str[0] == '-') {
        sign = -1.0;
        i = 1;
    }

    var has_dot = false;
    var divisor: f32 = 10.0;

    while (i < str.len) : (i += 1) {
        if (str[i] >= '0' and str[i] <= '9') {
            const digit: f32 = @floatFromInt(str[i] - '0');
            if (!has_dot) {
                res = (res * 10.0) + digit;
            } else {
                res += digit / divisor;
                divisor *= 10.0;
            }
        } else if (str[i] == '.') {
            has_dot = true;
        } else {
            break;
        }
    }

    return res * sign;
}

pub fn floatToString(val: f32, buf: []u8) []const u8 {
    var v = val;
    var is_neg = false;
    if (v < 0) {
        is_neg = true;
        v = -v;
    }

    const int_part = @as(i32, @intFromFloat(v));
    const frac_part = @as(i32, @intFromFloat((v - @as(f32, @floatFromInt(int_part))) * 1000.0 + 0.5));

    var total_i: usize = 0;
    if (is_neg) {
        buf[0] = '-';
        total_i = 1;
    }

    const s_int = intToString(int_part, buf[total_i..]);
    total_i += s_int.len;

    if (total_i < buf.len) {
        buf[total_i] = '.';
        total_i += 1;
    }

    var f = frac_part;
    if (f < 0) f = -f;

    // 3 decimal places
    buf[total_i] = @as(u8, @intCast(@mod(@divTrunc(f, 100), 10))) + '0';
    buf[total_i + 1] = @as(u8, @intCast(@mod(@divTrunc(f, 10), 10))) + '0';
    buf[total_i + 2] = @as(u8, @intCast(@mod(f, 10))) + '0';
    total_i += 3;

    return buf[0..total_i];
}
