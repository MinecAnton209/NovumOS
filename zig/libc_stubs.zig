// Minimal libc stubs for freestanding kernel environment

const serial = @import("drivers/serial.zig");

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

pub export fn memmove(dest: [*]u8, src: [*]const u8, n: usize) [*]u8 {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        dest[i] = src[i];
    }
    return dest;
}

pub export fn memcmp(s1: [*]const u8, s2: [*]const u8, n: usize) i32 {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (s1[i] != s2[i]) {
            return @as(i32, s1[i]) - @as(i32, s2[i]);
        }
    }
    return 0;
}

pub export fn linenoise_write(buf: [*]const u8, n: usize) void {
    serial.serial_print_str(buf[0..n]);
}

pub export fn linenoise_getch() i32 {
    if (serial.serial_has_data()) {
        return @as(i32, serial.serial_getchar());
    }
    return -1;
}
