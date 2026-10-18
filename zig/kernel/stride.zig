const std = @import("std");

// Stride scheduling: a runnable task advances its `pass` by `stride` every time it
// gets a quantum, and the task with the smallest pass runs next. A task with twice
// the weight has half the stride, so over time it receives twice the CPU.

pub const MIN_WEIGHT: u32 = 1;
pub const MAX_WEIGHT: u32 = 16;

/// Larger than any weight so that STRIDE1 / weight keeps enough precision for 16 weights.
pub const STRIDE1: u32 = 1 << 20;

pub fn clampWeight(weight: u32) u32 {
    return std.math.clamp(weight, MIN_WEIGHT, MAX_WEIGHT);
}

pub fn strideFor(weight: u32) u32 {
    return STRIDE1 / clampWeight(weight);
}

/// Pass values wrap around; compare by signed distance so a long-running task
/// does not suddenly look "later" than new tasks after 2^32 quanta.
pub fn passBefore(a: u32, b: u32) bool {
    return @as(i32, @bitCast(a -% b)) < 0;
}

/// Index of the eligible entry with the smallest pass, or null if none is eligible.
pub fn pickIndex(passes: []const u32, eligible: []const bool) ?usize {
    std.debug.assert(passes.len == eligible.len);
    var best: ?usize = null;
    for (passes, eligible, 0..) |pass, ok, idx| {
        if (!ok) continue;
        if (best == null or passBefore(pass, passes[best.?])) best = idx;
    }
    return best;
}
