const std = @import("std");
const stride = @import("stride");

test "clampWeight keeps weights inside the supported range" {
    try std.testing.expectEqual(stride.MIN_WEIGHT, stride.clampWeight(0));
    try std.testing.expectEqual(@as(u32, 5), stride.clampWeight(5));
    try std.testing.expectEqual(stride.MAX_WEIGHT, stride.clampWeight(1000));
}

test "stride is inversely proportional to weight" {
    try std.testing.expectEqual(stride.STRIDE1, stride.strideFor(1));
    try std.testing.expectEqual(stride.STRIDE1 / 4, stride.strideFor(4));
    try std.testing.expectEqual(stride.strideFor(1), 2 * stride.strideFor(2));
}

test "passBefore orders values across the u32 wrap" {
    try std.testing.expect(stride.passBefore(1, 2));
    try std.testing.expect(!stride.passBefore(2, 1));
    try std.testing.expect(!stride.passBefore(5, 5));
    try std.testing.expect(stride.passBefore(0xFFFF_FFF0, 0x10));
    try std.testing.expect(!stride.passBefore(0x10, 0xFFFF_FFF0));
}

test "pickIndex chooses the smallest eligible pass" {
    const passes = [_]u32{ 30, 10, 20 };
    const all = [_]bool{ true, true, true };
    try std.testing.expectEqual(@as(?usize, 1), stride.pickIndex(&passes, &all));
}

test "pickIndex skips ineligible entries even if their pass is smallest" {
    const passes = [_]u32{ 30, 1, 20 };
    const eligible = [_]bool{ true, false, true };
    try std.testing.expectEqual(@as(?usize, 2), stride.pickIndex(&passes, &eligible));
}

test "pickIndex returns null when nothing is eligible" {
    const passes = [_]u32{ 1, 2 };
    const none = [_]bool{ false, false };
    try std.testing.expectEqual(@as(?usize, null), stride.pickIndex(&passes, &none));
}

test "pickIndex on an empty set returns null" {
    const passes = [_]u32{};
    const eligible = [_]bool{};
    try std.testing.expectEqual(@as(?usize, null), stride.pickIndex(&passes, &eligible));
}

/// Runs the scheduler loop for `quanta` steps and returns how many quanta each task got.
fn simulate(weights: []const u32, quanta: usize, out: []usize) void {
    var passes: [8]u32 = @splat(0);
    var eligible: [8]bool = @splat(false);
    for (weights, 0..) |_, idx| eligible[idx] = true;
    for (out[0..weights.len]) |*c| c.* = 0;

    var step: usize = 0;
    while (step < quanta) : (step += 1) {
        const idx = stride.pickIndex(passes[0..weights.len], eligible[0..weights.len]).?;
        out[idx] += 1;
        passes[idx] +%= stride.strideFor(weights[idx]);
    }
}

test "equal weights get equal shares" {
    const weights = [_]u32{ 1, 1, 1 };
    var got: [3]usize = undefined;
    simulate(&weights, 3000, &got);
    try std.testing.expectEqual(@as(usize, 1000), got[0]);
    try std.testing.expectEqual(@as(usize, 1000), got[1]);
    try std.testing.expectEqual(@as(usize, 1000), got[2]);
}

test "shares follow weights 1:2:4 over a long run" {
    const weights = [_]u32{ 1, 2, 4 };
    var got: [3]usize = undefined;
    simulate(&weights, 7000, &got);
    try std.testing.expectEqual(@as(usize, 1000), got[0]);
    try std.testing.expectEqual(@as(usize, 2000), got[1]);
    try std.testing.expectEqual(@as(usize, 4000), got[2]);
}

test "a heavy task cannot starve a light one" {
    const weights = [_]u32{ 16, 1 };
    var got: [2]usize = undefined;
    simulate(&weights, 1700, &got);
    try std.testing.expect(got[1] >= 100);
    try std.testing.expectEqual(@as(usize, 1600), got[0]);
}
