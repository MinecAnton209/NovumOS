const std = @import("std");
const SampleTable = @import("profiler_table").SampleTable;

const Table16 = SampleTable(16);

fn countOf(t: *const Table16, addr: u32) u32 {
    for (t.entries) |e| {
        if (e.count != 0 and e.addr == addr) return e.count;
    }
    return 0;
}

test "empty table has no entries and reports nothing" {
    var t: Table16 = .{};
    var out: [4]Table16.Entry = undefined;
    try std.testing.expectEqual(@as(u32, 0), t.total);
    try std.testing.expectEqual(@as(u32, 0), t.dropped);
    try std.testing.expectEqual(@as(usize, 0), t.top(&out));
}

test "recording the same address accumulates its count" {
    var t: Table16 = .{};
    t.record(0xC0101000);
    t.record(0xC0101000);
    t.record(0xC0101000);
    try std.testing.expectEqual(@as(u32, 3), countOf(&t, 0xC0101000));
    try std.testing.expectEqual(@as(u32, 3), t.total);
    try std.testing.expectEqual(@as(u32, 0), t.dropped);
}

test "address zero is a valid sample, not a free slot" {
    var t: Table16 = .{};
    t.record(0);
    t.record(0);
    try std.testing.expectEqual(@as(u32, 2), countOf(&t, 0));
}

test "distinct addresses that collide in the hash still get their own slots" {
    var t: Table16 = .{};
    var addr: u32 = 0x1000;
    while (addr < 0x1000 + 16 * 4) : (addr += 4) t.record(addr);
    try std.testing.expectEqual(@as(u32, 0), t.dropped);
    addr = 0x1000;
    while (addr < 0x1000 + 16 * 4) : (addr += 4) {
        try std.testing.expectEqual(@as(u32, 1), countOf(&t, addr));
    }
}

test "samples past capacity are dropped but still counted in total" {
    var t: Table16 = .{};
    var addr: u32 = 0;
    while (addr < 20) : (addr += 1) t.record(addr * 0x100);
    try std.testing.expectEqual(@as(u32, 20), t.total);
    try std.testing.expectEqual(@as(u32, 4), t.dropped);

    var out: [32]Table16.Entry = undefined;
    try std.testing.expectEqual(@as(usize, 16), t.top(&out));
}

test "dropped samples do not overwrite existing entries" {
    var t: Table16 = .{};
    var addr: u32 = 0;
    while (addr < 16) : (addr += 1) t.record(addr * 0x10);
    t.record(0xDEAD0000);
    try std.testing.expectEqual(@as(u32, 1), t.dropped);
    try std.testing.expectEqual(@as(u32, 0), countOf(&t, 0xDEAD0000));
    try std.testing.expectEqual(@as(u32, 1), countOf(&t, 0));
}

test "top returns entries sorted by count descending" {
    var t: Table16 = .{};
    var i: u32 = 0;
    while (i < 3) : (i += 1) t.record(0xA);
    i = 0;
    while (i < 7) : (i += 1) t.record(0xB);
    t.record(0xC);
    var out: [8]Table16.Entry = undefined;
    const n = t.top(&out);
    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqual(@as(u32, 0xB), out[0].addr);
    try std.testing.expectEqual(@as(u32, 7), out[0].count);
    try std.testing.expectEqual(@as(u32, 0xA), out[1].addr);
    try std.testing.expectEqual(@as(u32, 3), out[1].count);
    try std.testing.expectEqual(@as(u32, 0xC), out[2].addr);
    try std.testing.expectEqual(@as(u32, 1), out[2].count);
}

test "top keeps only the hottest entries when out is smaller than the table" {
    var t: Table16 = .{};
    const counts = [_]u32{ 5, 1, 9, 3, 7, 2 };
    for (counts, 0..) |c, idx| {
        var k: u32 = 0;
        while (k < c) : (k += 1) t.record(@as(u32, @intCast(idx)) + 0x100);
    }
    var out: [3]Table16.Entry = undefined;
    const n = t.top(&out);
    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqual(@as(u32, 9), out[0].count);
    try std.testing.expectEqual(@as(u32, 7), out[1].count);
    try std.testing.expectEqual(@as(u32, 5), out[2].count);
}

test "top with zero-length output writes nothing and returns zero" {
    var t: Table16 = .{};
    t.record(0x42);
    var out: [0]Table16.Entry = .{};
    try std.testing.expectEqual(@as(usize, 0), t.top(&out));
}

test "reset clears counters, entries and drop count" {
    var t: Table16 = .{};
    var addr: u32 = 0;
    while (addr < 20) : (addr += 1) t.record(addr);
    t.reset();
    try std.testing.expectEqual(@as(u32, 0), t.total);
    try std.testing.expectEqual(@as(u32, 0), t.dropped);
    var out: [16]Table16.Entry = undefined;
    try std.testing.expectEqual(@as(usize, 0), t.top(&out));
}

test "counts saturate instead of wrapping" {
    var t: Table16 = .{};
    t.record(0x77);
    for (&t.entries) |*e| {
        if (e.count != 0) e.count = std.math.maxInt(u32);
    }
    t.total = std.math.maxInt(u32);
    t.record(0x77);
    try std.testing.expectEqual(std.math.maxInt(u32), countOf(&t, 0x77));
    try std.testing.expectEqual(std.math.maxInt(u32), t.total);
}
