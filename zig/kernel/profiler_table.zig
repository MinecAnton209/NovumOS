const std = @import("std");

/// Fixed-capacity open-addressing histogram of sampled instruction pointers.
/// A slot is free while `count == 0`, so every stored entry has `count >= 1`.
pub fn SampleTable(comptime capacity: usize) type {
    comptime std.debug.assert(capacity > 0 and std.math.isPowerOfTwo(capacity));

    return struct {
        const Self = @This();

        pub const Entry = struct {
            addr: u32 = 0,
            count: u32 = 0,
        };

        entries: [capacity]Entry = [_]Entry{.{}} ** capacity,
        /// Samples recorded into the table, including the ones that were dropped.
        total: u32 = 0,
        /// Samples that could not get a slot because the table was full.
        dropped: u32 = 0,

        pub fn reset(self: *Self) void {
            self.* = .{};
        }

        pub fn record(self: *Self, addr: u32) void {
            self.total +|= 1;
            const mask = capacity - 1;
            // Multiplicative hash: sequential instruction addresses would otherwise
            // cluster into neighbouring slots and make probing long.
            var idx: usize = (addr *% 0x9E3779B1) >> @intCast(32 - @ctz(capacity));
            var probes: usize = 0;
            while (probes < capacity) : (probes += 1) {
                const slot = &self.entries[idx];
                if (slot.count == 0) {
                    slot.* = .{ .addr = addr, .count = 1 };
                    return;
                }
                if (slot.addr == addr) {
                    slot.count +|= 1;
                    return;
                }
                idx = (idx + 1) & mask;
            }
            self.dropped +|= 1;
        }

        /// Writes up to `out.len` hottest entries into `out`, sorted by count descending.
        /// Returns the number of entries written.
        pub fn top(self: *const Self, out: []Entry) usize {
            if (out.len == 0) return 0;
            var n: usize = 0;
            for (self.entries) |e| {
                if (e.count == 0) continue;
                if (n == out.len and e.count <= out[n - 1].count) continue;

                var pos: usize = if (n < out.len) n else out.len - 1;
                if (n < out.len) n += 1;
                while (pos > 0 and out[pos - 1].count < e.count) : (pos -= 1) {
                    out[pos] = out[pos - 1];
                }
                out[pos] = e;
            }
            return n;
        }
    };
}
