// Re-export str module for host testing.
// str.zig has no dependencies — pure functions.
const std = @import("std");
const str = @import("str");

test "std_mem_eql: identical strings" {
    const a = "hello";
    const b = "hello";
    try std.testing.expect(str.std_mem_eql(a, b));
}

test "std_mem_eql: different lengths" {
    try std.testing.expect(!str.std_mem_eql("hi", "hello"));
}

test "std_mem_eql: same length different content" {
    try std.testing.expect(!str.std_mem_eql("hello", "world"));
}

test "std_mem_eql: empty strings" {
    try std.testing.expect(str.std_mem_eql("", ""));
}

test "startsWith: matching prefix" {
    try std.testing.expect(str.startsWith("hello world", "hello"));
}

test "startsWith: non-matching" {
    try std.testing.expect(!str.startsWith("hello world", "world"));
}

test "startsWith: longer string than input" {
    try std.testing.expect(!str.startsWith("hi", "hello"));
}

test "startsWith: exact match" {
    try std.testing.expect(str.startsWith("hello", "hello"));
}

test "startsWith: empty prefix" {
    try std.testing.expect(str.startsWith("hello", ""));
}

test "endsWith: matching suffix" {
    try std.testing.expect(str.endsWith("hello world", "world"));
}

test "endsWith: non-matching" {
    try std.testing.expect(!str.endsWith("hello world", "hello"));
}

test "endsWith: longer suffix than input" {
    try std.testing.expect(!str.endsWith("hi", "hello"));
}

test "endsWith: exact match" {
    try std.testing.expect(str.endsWith("hello", "hello"));
}

test "endsWith: empty suffix" {
    try std.testing.expect(str.endsWith("hello", ""));
}

test "endsWith: empty string" {
    try std.testing.expect(str.endsWith("", ""));
}

test "asciiLower: uppercase conversion" {
    try std.testing.expectEqual('a', str.asciiLower('A'));
    try std.testing.expectEqual('z', str.asciiLower('Z'));
}

test "asciiLower: lowercase passthrough" {
    try std.testing.expectEqual('a', str.asciiLower('a'));
    try std.testing.expectEqual('z', str.asciiLower('z'));
}

test "asciiLower: non-alpha passthrough" {
    try std.testing.expectEqual('0', str.asciiLower('0'));
    try std.testing.expectEqual(' ', str.asciiLower(' '));
}

test "startsWithIgnoreCase: matching prefix case-insensitive" {
    try std.testing.expect(str.startsWithIgnoreCase("Hello World", "hello"));
    try std.testing.expect(str.startsWithIgnoreCase("HELLO", "hello"));
    try std.testing.expect(str.startsWithIgnoreCase("hello", "HELLO"));
}

test "startsWithIgnoreCase: non-matching" {
    try std.testing.expect(!str.startsWithIgnoreCase("hello", "world"));
}

test "startsWithIgnoreCase: length mismatch" {
    try std.testing.expect(!str.startsWithIgnoreCase("hi", "hello"));
}

test "lastIndexOf: found" {
    try std.testing.expectEqual(11, str.lastIndexOf("hello.world.txt", '.'));
}

test "lastIndexOf: found at start" {
    // Last '/' in "/path/to/file" is at position 8 (/path/to/)
    try std.testing.expectEqual(8, str.lastIndexOf("/path/to/file", '/'));
}

test "lastIndexOf: not found" {
    try std.testing.expectEqual(null, str.lastIndexOf("hello", '.'));
}

test "lastIndexOf: empty string" {
    try std.testing.expectEqual(null, str.lastIndexOf("", '.'));
}

test "copy: exact length" {
    var dest: [10]u8 = undefined;
    str.copy(&dest, "hello");
    try std.testing.expectEqualSlices(u8, dest[0..5], "hello");
}

test "copy: dest shorter than src" {
    var dest: [3]u8 = undefined;
    str.copy(&dest, "hello");
    try std.testing.expectEqualSlices(u8, dest[0..3], "hel");
}

test "copy: dest longer than src" {
    var dest: [10]u8 = undefined;
    str.copy(&dest, "hi");
    try std.testing.expectEqualSlices(u8, dest[0..2], "hi");
}

test "math_abs: positive" {
    try std.testing.expectEqual(5, str.math_abs(5));
}

test "math_abs: negative" {
    try std.testing.expectEqual(5, str.math_abs(-5));
}

test "math_abs: zero" {
    try std.testing.expectEqual(0, str.math_abs(0));
}

test "math_max: a greater" {
    try std.testing.expectEqual(10, str.math_max(10, 5));
}

test "math_max: b greater" {
    try std.testing.expectEqual(10, str.math_max(5, 10));
}

test "math_max: equal" {
    try std.testing.expectEqual(5, str.math_max(5, 5));
}

test "math_min: a lesser" {
    try std.testing.expectEqual(5, str.math_min(5, 10));
}

test "math_min: b lesser" {
    try std.testing.expectEqual(5, str.math_min(10, 5));
}

test "math_min: equal" {
    try std.testing.expectEqual(5, str.math_min(5, 5));
}
