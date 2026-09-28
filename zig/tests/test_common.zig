// Test module for pure functions extracted from common.zig
// We test the logic without pulling in the full kernel dependency graph

const std = @import("std");

// --- Pure functions (copied from common.zig with signatures matching production) ---

fn parse_int(s: []const u8) ?i32 {
    if (s.len == 0) return null;
    var res: i32 = 0;
    var i: usize = 0;
    var sign: i32 = 1;
    if (s[0] == '-') {
        sign = -1;
        i = 1;
    }
    if (i >= s.len) return null;

    if (i + 2 <= s.len and s[i] == '0') {
        const next = s[i + 1];
        if (next == 'x' or next == 'X') {
            i += 2;
            while (i < s.len) : (i += 1) {
                const c = s[i];
                var digit: i32 = 0;
                if (c >= '0' and c <= '9') {
                    digit = c - '0';
                } else if (c >= 'a' and c <= 'f') {
                    digit = c - 'a' + 10;
                } else if (c >= 'A' and c <= 'F') {
                    digit = c - 'A' + 10;
                } else break;
                res = (res * 16) + digit;
            }
            return res * sign;
        } else if (next == 'b' or next == 'B') {
            i += 2;
            while (i < s.len) : (i += 1) {
                const c = s[i];
                if (c == '0' or c == '1') {
                    res = (res * 2) + @as(i32, c - '0');
                } else break;
            }
            return res * sign;
        }
    }

    while (i < s.len) : (i += 1) {
        if (s[i] < '0' or s[i] > '9') return null;
        res = res * 10 + @as(i32, s[i] - '0');
    }
    return res * sign;
}

fn intToString(val: i32, buf: []u8) []const u8 {
    if (val == 0) {
        buf[0] = '0';
        return buf[0..1];
    }

    var n = val;
    var i: usize = 0;
    var is_neg = false;

    if (n < 0) {
        is_neg = true;
        n = -n;
    }

    var temp: [16]u8 = undefined;
    var t: usize = 0;

    while (n > 0) {
        temp[t] = @intCast(@mod(n, 10));
        temp[t] += '0';
        n = @divTrunc(n, 10);
        t += 1;
    }

    if (is_neg) {
        buf[i] = '-';
        i += 1;
    }

    while (t > 0) : (t -= 1) {
        buf[i] = temp[t - 1];
        i += 1;
    }
    return buf[0..i];
}

fn intToHex(val: u32, buf: []u8) []const u8 {
    const chars = "0123456789ABCDEF";
    var idx: usize = 0;
    buf[idx] = '0';
    idx += 1;
    buf[idx] = 'x';
    idx += 1;

    var i: i32 = 7;
    while (i >= 0) : (i -= 1) {
        const nibble = (val >> @as(u5, @intCast(i * 4))) & 0xF;
        buf[idx] = chars[nibble];
        idx += 1;
    }
    return buf[0..idx];
}

fn trim(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and (s[start] == ' ' or s[start] == '\t')) : (start += 1) {}
    var end: usize = s.len;
    while (end > start and (s[end - 1] == ' ' or s[end - 1] == '\t')) : (end -= 1) {}
    return s[start..end];
}

fn fmtIntToBuf(buf: []u8, n_in: i32) usize {
    var n: i32 = n_in;
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
        temp[i] = @intCast(@mod(un, 10) + '0');
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

fn fmt_to_buf(buf: []u8, comptime fmt: []const u8, args: anytype) []const u8 {
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
                    const str_val = args[arg_idx];
                    for (str_val) |c| {
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

fn parseArgs(input: []const u8, max_args: usize) ![]const []const u8 {
    const allocator = std.heap.page_allocator;
    const args = try allocator.alloc([]const u8, max_args);
    var count: usize = 0;
    var i: usize = 0;
    while (i < input.len and count < max_args) {
        while (i < input.len and (input[i] == ' ' or input[i] == '\t')) : (i += 1) {}
        if (i >= input.len) break;

        if (input[i] == '"') {
            i += 1;
            const start = i;
            while (i < input.len and input[i] != '"') : (i += 1) {}
            args[count] = input[start..i];
            count += 1;
            if (i < input.len) i += 1;
        } else {
            const start = i;
            while (i < input.len and input[i] != ' ' and input[i] != '\t') : (i += 1) {}
            args[count] = input[start..i];
            count += 1;
        }
    }
    return args[0..count];
}

// --- parse_int tests ---

test "parse_int: positive decimal" {
    try std.testing.expectEqual(@as(?i32, 42), parse_int("42"));
}

test "parse_int: negative decimal" {
    try std.testing.expectEqual(@as(?i32, -17), parse_int("-17"));
}

test "parse_int: zero" {
    try std.testing.expectEqual(@as(?i32, 0), parse_int("0"));
}

test "parse_int: positive with plus (not handled, treated as non-digit)" {
    // parse_int does not handle '+', returns null
    try std.testing.expectEqual(@as(?i32, null), parse_int("+42"));
}

test "parse_int: empty string returns null" {
    try std.testing.expectEqual(@as(?i32, null), parse_int(""));
}

test "parse_int: just minus returns null" {
    try std.testing.expectEqual(@as(?i32, null), parse_int("-"));
}

test "parse_int: non-numeric returns null" {
    try std.testing.expectEqual(@as(?i32, null), parse_int("abc"));
}

test "parse_int: partial non-numeric returns null" {
    try std.testing.expectEqual(@as(?i32, null), parse_int("12abc"));
}

test "parse_int: hex lowercase" {
    try std.testing.expectEqual(@as(?i32, 255), parse_int("0xFF"));
}

test "parse_int: hex uppercase prefix" {
    try std.testing.expectEqual(@as(?i32, 255), parse_int("0Xff"));
}

test "parse_int: hex with lowercase digits" {
    try std.testing.expectEqual(@as(?i32, 255), parse_int("0xff"));
}

test "parse_int: hex uppercase digits" {
    // 0xBEEF = 48879 decimal
    try std.testing.expectEqual(@as(?i32, 48879), parse_int("0xBEEF"));
}

test "parse_int: hex lowercase digits" {
    // 0xbeef = 48879 decimal
    try std.testing.expectEqual(@as(?i32, 48879), parse_int("0xbeef"));
}

test "parse_int: hex with zero value" {
    try std.testing.expectEqual(@as(?i32, 0), parse_int("0x0"));
}

test "parse_int: hex with invalid char stops" {
    try std.testing.expectEqual(@as(?i32, 10), parse_int("0xAZ"));
}

test "parse_int: binary lowercase prefix" {
    try std.testing.expectEqual(@as(?i32, 10), parse_int("0b1010"));
}

test "parse_int: binary uppercase prefix" {
    try std.testing.expectEqual(@as(?i32, 10), parse_int("0B1010"));
}

test "parse_int: binary with invalid char stops" {
    // 0b102 — stops at '2', parses 0b10 = 2
    try std.testing.expectEqual(@as(?i32, 2), parse_int("0b102"));
}

test "parse_int: negative hex" {
    try std.testing.expectEqual(@as(?i32, -255), parse_int("-0xFF"));
}

test "parse_int: negative binary" {
    try std.testing.expectEqual(@as(?i32, -10), parse_int("-0b1010"));
}

test "parse_int: large number" {
    try std.testing.expectEqual(@as(?i32, 2147483647), parse_int("2147483647"));
}

// --- intToString tests ---

test "intToString: zero" {
    var buf: [16]u8 = undefined;
    const result = intToString(0, &buf);
    try std.testing.expectEqualSlices(u8, result, "0");
}

test "intToString: positive integer" {
    var buf: [16]u8 = undefined;
    const result = intToString(123, &buf);
    try std.testing.expectEqualSlices(u8, result, "123");
}

test "intToString: negative integer" {
    var buf: [16]u8 = undefined;
    const result = intToString(-456, &buf);
    try std.testing.expectEqualSlices(u8, result, "-456");
}

test "intToString: single digit" {
    var buf: [16]u8 = undefined;
    const result = intToString(7, &buf);
    try std.testing.expectEqualSlices(u8, result, "7");
}

test "intToString: large positive" {
    var buf: [16]u8 = undefined;
    const result = intToString(1000000, &buf);
    try std.testing.expectEqualSlices(u8, result, "1000000");
}

test "intToString: negative one" {
    var buf: [16]u8 = undefined;
    const result = intToString(-1, &buf);
    try std.testing.expectEqualSlices(u8, result, "-1");
}

test "intToString: buffer exactly sized" {
    var buf: [1]u8 = undefined;
    const result = intToString(0, &buf);
    try std.testing.expectEqualSlices(u8, result, "0");
}

test "intToString: negative i32 min (wraps)" {
    // i32.min = -2147483648; -n would overflow, so this is UB
    // We test with i32.max instead: 2147483647
    var buf: [16]u8 = undefined;
    const result = intToString(2147483647, &buf);
    try std.testing.expectEqualSlices(u8, result, "2147483647");
}

// --- intToHex tests ---

test "intToHex: zero" {
    var buf: [32]u8 = undefined;
    const result = intToHex(0, &buf);
    try std.testing.expectEqualSlices(u8, result, "0x00000000");
}

test "intToHex: simple value" {
    var buf: [32]u8 = undefined;
    const result = intToHex(255, &buf);
    try std.testing.expectEqualSlices(u8, result, "0x000000FF");
}

test "intToHex: large value" {
    var buf: [32]u8 = undefined;
    const result = intToHex(0xDEADBEEF, &buf);
    try std.testing.expectEqualSlices(u8, result, "0xDEADBEEF");
}

test "intToHex: negative as u32" {
    var buf: [32]u8 = undefined;
    const result = intToHex(0xFFFFFFFF, &buf);
    try std.testing.expectEqualSlices(u8, result, "0xFFFFFFFF");
}

test "intToHex: one" {
    var buf: [32]u8 = undefined;
    const result = intToHex(1, &buf);
    try std.testing.expectEqualSlices(u8, result, "0x00000001");
}

// --- trim tests ---

test "trim: no whitespace" {
    try std.testing.expectEqualSlices(u8, trim("hello"), "hello");
}

test "trim: leading spaces" {
    try std.testing.expectEqualSlices(u8, trim("  hello"), "hello");
}

test "trim: trailing spaces" {
    try std.testing.expectEqualSlices(u8, trim("hello  "), "hello");
}

test "trim: both sides" {
    try std.testing.expectEqualSlices(u8, trim("  hello  "), "hello");
}

test "trim: only spaces" {
    try std.testing.expectEqualSlices(u8, trim("   "), "");
}

test "trim: empty string" {
    try std.testing.expectEqualSlices(u8, trim(""), "");
}

test "trim: tabs" {
    try std.testing.expectEqualSlices(u8, trim("\t\thello\t\t"), "hello");
}

test "trim: mixed spaces and tabs" {
    try std.testing.expectEqualSlices(u8, trim(" \t hello \t "), "hello");
}

test "trim: internal spaces preserved" {
    try std.testing.expectEqualSlices(u8, trim("  hello world  "), "hello world");
}

// --- fmt_to_buf tests ---

test "fmt_to_buf: literal string" {
    var buf: [64]u8 = undefined;
    const result = fmt_to_buf(&buf, "hello", .{});
    try std.testing.expectEqualSlices(u8, result, "hello");
}

test "fmt_to_buf: integer substitution" {
    var buf: [64]u8 = undefined;
    const result = fmt_to_buf(&buf, "value={d}", .{42});
    try std.testing.expectEqualSlices(u8, result, "value=42");
}

test "fmt_to_buf: string substitution" {
    var buf: [64]u8 = undefined;
    const result = fmt_to_buf(&buf, "name={s}", .{"test"});
    try std.testing.expectEqualSlices(u8, result, "name=test");
}

test "fmt_to_buf: mixed substitutions" {
    var buf: [64]u8 = undefined;
    const result = fmt_to_buf(&buf, "{s}={d}", .{"count", 5});
    try std.testing.expectEqualSlices(u8, result, "count=5");
}

test "fmt_to_buf: negative integer" {
    var buf: [64]u8 = undefined;
    const result = fmt_to_buf(&buf, "temp={d}", .{-10});
    try std.testing.expectEqualSlices(u8, result, "temp=-10");
}

test "fmt_to_buf: buffer too small" {
    var buf: [4]u8 = undefined;
    const result = fmt_to_buf(&buf, "hello world", .{});
    try std.testing.expectEqualSlices(u8, result, "hell");
}

test "fmt_to_buf: multiple integers" {
    var buf: [64]u8 = undefined;
    const result = fmt_to_buf(&buf, "{d}+{d}={d}", .{1, 2, 3});
    try std.testing.expectEqualSlices(u8, result, "1+2=3");
}

// --- parseArgs tests ---

test "parseArgs: simple command" {
    const input = "ls -la";
    const result = try parseArgs(input, 16);
    try std.testing.expectEqual(result.len, 2);
    try std.testing.expectEqualSlices(u8, result[0], "ls");
    try std.testing.expectEqualSlices(u8, result[1], "-la");
}

test "parseArgs: quoted argument" {
    const input = "echo \"hello world\"";
    const result = try parseArgs(input, 16);
    try std.testing.expectEqual(result.len, 2);
    try std.testing.expectEqualSlices(u8, result[0], "echo");
    try std.testing.expectEqualSlices(u8, result[1], "hello world");
}

test "parseArgs: multiple spaces" {
    const input = "a  b   c";
    const result = try parseArgs(input, 16);
    try std.testing.expectEqual(result.len, 3);
    try std.testing.expectEqualSlices(u8, result[0], "a");
    try std.testing.expectEqualSlices(u8, result[1], "b");
    try std.testing.expectEqualSlices(u8, result[2], "c");
}

test "parseArgs: empty input" {
    const input = "";
    const result = try parseArgs(input, 16);
    try std.testing.expectEqual(result.len, 0);
}

test "parseArgs: only spaces" {
    const input = "   ";
    const result = try parseArgs(input, 16);
    try std.testing.expectEqual(result.len, 0);
}

test "parseArgs: unclosed quote" {
    const input = "echo \"unclosed";
    const result = try parseArgs(input, 16);
    try std.testing.expectEqual(result.len, 2);
    try std.testing.expectEqualSlices(u8, result[0], "echo");
    try std.testing.expectEqualSlices(u8, result[1], "unclosed");
}

test "parseArgs: exceeds max_args" {
    const input = "a b c d e";
    const result = try parseArgs(input, 3);
    try std.testing.expectEqual(result.len, 3);
    try std.testing.expectEqualSlices(u8, result[0], "a");
    try std.testing.expectEqualSlices(u8, result[2], "c");
}

test "parseArgs: tabs as separators" {
    const input = "cmd\targ1\targ2";
    const result = try parseArgs(input, 16);
    try std.testing.expectEqual(result.len, 3);
    try std.testing.expectEqualSlices(u8, result[0], "cmd");
    try std.testing.expectEqualSlices(u8, result[1], "arg1");
    try std.testing.expectEqualSlices(u8, result[2], "arg2");
}
