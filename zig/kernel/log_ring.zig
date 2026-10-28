const std = @import("std");

/// Byte ring that keeps the most recent kernel log output for `dmesg`.
/// Overwrites the oldest bytes once full; `written` counts every byte ever appended.
pub fn LogRing(comptime capacity: usize) type {
    comptime std.debug.assert(capacity > 0);

    return struct {
        const Self = @This();

        buf: [capacity]u8 = @splat(0),
        written: usize = 0,

        pub fn append(self: *Self, bytes: []const u8) void {
            for (bytes) |c| {
                self.buf[self.written % capacity] = c;
                self.written +%= 1;
            }
        }

        /// Copies the newest bytes that fit into `out`, oldest first.
        /// Returns the number of bytes written to `out`.
        pub fn snapshot(self: *const Self, out: []u8) usize {
            const available = @min(self.written, capacity);
            const n = @min(available, out.len);
            const start = self.written -% n;
            for (0..n) |i| {
                out[i] = self.buf[(start +% i) % capacity];
            }
            return n;
        }

        pub fn reset(self: *Self) void {
            self.* = .{};
        }
    };
}
