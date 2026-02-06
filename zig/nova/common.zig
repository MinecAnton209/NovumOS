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

// String utilities
pub fn streq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (ca != cb) return false;
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
