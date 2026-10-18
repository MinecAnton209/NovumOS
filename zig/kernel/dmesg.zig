const std = @import("std");
const config = @import("../config.zig");
const common = @import("../commands/common.zig");
const irq = @import("irq.zig");
const LogRing = @import("log_ring.zig").LogRing;

// Written from logger paths that can run in the timer ISR; dump() copies the
// ring under cli so it never reads a half-written line from this core.
// Writes from another core can still interleave bytes; the buffer is best-effort.

pub const CAPACITY = 4096;

var ring: LogRing(CAPACITY) = .{};
var scratch: [CAPACITY]u8 = undefined;

pub fn append(bytes: []const u8) void {
    if (!config.ENABLE_DMESG) return;
    ring.append(bytes);
}

pub fn dump() void {
    if (!config.ENABLE_DMESG) {
        common.printZ("dmesg: disabled (ENABLE_DMESG=n)\n");
        return;
    }

    const flags = irq.irq_save();
    const n = ring.snapshot(&scratch);
    const wrapped = ring.written > CAPACITY;
    irq.irq_restore(flags);

    if (n == 0) {
        common.printZ("dmesg: log is empty (enable ENABLE_KERNEL_LOGGING to record kernel messages)\n");
        return;
    }

    // Once the ring has wrapped, the oldest byte may fall in the middle of a line.
    var start: usize = 0;
    if (wrapped) {
        start = if (std.mem.indexOfScalar(u8, scratch[0..n], '\n')) |nl| nl + 1 else n;
    }
    common.printBuf(scratch[start..n]);
}
