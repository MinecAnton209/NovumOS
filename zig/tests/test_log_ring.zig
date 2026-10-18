const std = @import("std");
const LogRing = @import("log_ring").LogRing;

test "empty ring snapshots nothing" {
    var r: LogRing(8) = .{};
    var out: [8]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 0), r.snapshot(&out));
}

test "bytes below capacity come back in append order" {
    var r: LogRing(16) = .{};
    r.append("[ Kernel ] boot\n");
    var out: [16]u8 = undefined;
    const n = r.snapshot(&out);
    try std.testing.expectEqualStrings("[ Kernel ] boot\n", out[0..n]);
}

test "multiple appends concatenate in order" {
    var r: LogRing(32) = .{};
    r.append("abc");
    r.append("def");
    var out: [32]u8 = undefined;
    const n = r.snapshot(&out);
    try std.testing.expectEqualStrings("abcdef", out[0..n]);
}

test "overflow keeps only the newest capacity bytes in chronological order" {
    var r: LogRing(8) = .{};
    r.append("0123456789ABCDEF");
    var out: [16]u8 = undefined;
    const n = r.snapshot(&out);
    try std.testing.expectEqual(@as(usize, 8), n);
    try std.testing.expectEqualStrings("89ABCDEF", out[0..n]);
}

test "snapshot into a smaller buffer returns the newest bytes that fit" {
    var r: LogRing(8) = .{};
    r.append("abcdefgh");
    var out: [3]u8 = undefined;
    const n = r.snapshot(&out);
    try std.testing.expectEqualStrings("fgh", out[0..n]);
}

test "wrap boundary exactly at capacity keeps order" {
    var r: LogRing(4) = .{};
    r.append("wxyz");
    var out: [4]u8 = undefined;
    const n = r.snapshot(&out);
    try std.testing.expectEqualStrings("wxyz", out[0..n]);
    r.append("1");
    const m = r.snapshot(&out);
    try std.testing.expectEqualStrings("xyz1", out[0..m]);
}

test "many small appends across several wraps stay ordered" {
    var r: LogRing(5) = .{};
    var i: u8 = 0;
    while (i < 23) : (i += 1) {
        const b = [_]u8{'a' + i};
        r.append(&b);
    }
    var out: [5]u8 = undefined;
    const n = r.snapshot(&out);
    try std.testing.expectEqualStrings("stuvw", out[0..n]);
}

test "reset clears content and counter" {
    var r: LogRing(8) = .{};
    r.append("hello");
    r.reset();
    var out: [8]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 0), r.snapshot(&out));
    try std.testing.expectEqual(@as(usize, 0), r.written);
}
