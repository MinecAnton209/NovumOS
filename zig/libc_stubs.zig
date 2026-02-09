// Minimal libc stubs for freestanding kernel environment

const std = @import("std");

pub export fn memcpy(dest: [*]u8, src: [*]const u8, n: usize) [*]u8 {
    var d = dest;
    var s = src;
    var count = n;
    while (count > 0) : (count -= 1) {
        d[0] = s[0];
        d += 1;
        s += 1;
    }
    return dest;
}

pub export fn memset(dest: [*]u8, c: i32, n: usize) [*]u8 {
    var d = dest;
    var count = n;
    const val = @as(u8, @intCast(c));
    while (count > 0) : (count -= 1) {
        d[0] = val;
        d += 1;
    }
    return dest;
}
