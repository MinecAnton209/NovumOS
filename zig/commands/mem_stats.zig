const std = @import("std");
const common = @import("common.zig");
const memory = @import("../kernel/memory.zig");

const BINS = 8;

fn binIndex(page_idx: usize, total: usize) usize {
    if (total == 0) return 0;
    const pct = page_idx * 100 / total;
    return @min(pct * BINS / 100, BINS - 1);
}

var free_bins: [BINS]usize = .{0} ** BINS;
var busy_bins: [BINS]usize = .{0} ** BINS;

fn resetBins() void {
    var i: usize = 0;
    while (i < BINS) : (i += 1) {
        free_bins[i] = 0;
        busy_bins[i] = 0;
    }
}

fn fillBins() void {
    resetBins();
    const total = memory.totalPages();
    var i: usize = 0;
    while (i < total) : (i += 1) {
        const b = binIndex(i, total);
        if (memory.pageIsFree(@intCast(i))) free_bins[b] += 1;
    }
}

// Compute how many cells should be filled for `count` of `total` at `width`.
fn barFilled(count: usize, total: usize, width: usize) usize {
    if (total == 0) return 0;
    return count * width / total;
}

// Render `count` of `total` into a bar of width `width` using '#' and '-'.
fn renderBar(count: usize, total: usize, width: usize) usize {
    const filled = barFilled(count, total, width);
    var i: usize = 0;
    while (i < filled) : (i += 1) common.print_char('#');
    while (i < width) : (i += 1) common.print_char('-');
    return filled;
}

pub fn lsmem() void {
    fillBins();
    const freep = memory.freePages();
    const usedp = memory.usedPages();

    common.printZ("Physical memory map (lsmem)\r\n");
    common.printZ("----------------------------------------\r\n");
    common.printZ("Total:  ");
    common.printNum(@as(i32, @intCast(memory.DETECTED_MEMORY / 524288)));
    common.printZ(" MB | ");
    common.printNum(@divExact(@as(i32, @intCast(usedp)) * 4, 1024));  // pages*4KB→MB (approx)
    common.printZ(" MB used | ");
    common.printNum(@divExact(@as(i32, @intCast(freep)) * 4, 1024));
    common.printZ(" MB free\r\n");

    common.printZ("Heap regions: ");
    common.printNum(@as(i32, @intCast(memory.heap.regionCount())));
    common.printZ("\r\n");

    var r: usize = 0;
    while (r < memory.heap.regionCount()) : (r += 1) {
        const base = memory.heap.regionBase(@intCast(r));
        const end = memory.heap.regionEnd(@intCast(r));
        const size_kb = (end - base + 1023) / 1024;
        common.printZ("  [heap] 0x");
        common.printHex(@intCast(base));
        common.printZ("-0x");
        common.printHex(@intCast(end));
        common.printZ(" (");
        common.printNum(@intCast(size_kb));
        common.printZ(" KB)\r\n");
    }
    common.printZ("----------------------------------------\r\n");
}

pub fn pmap() void {
    fillBins();
    const total = memory.totalPages();
    const freep = memory.freePages();

    common.printZ("Page-bin histogram (pmap)\r\n");
    common.printZ("--------------------\r\n");
    var i: usize = 0;
    while (i < BINS) : (i += 1) {
        const label = (i * 100 / BINS);
        common.printZ(" ");
        if (label < 10) common.printZ(" ");
        if (label < 100) common.printZ(" ");
    common.printNum(@as(i32, @intCast(label)));
    common.printZ("% ");
    common.printZ("[");
    _ = renderBar(free_bins[i], freep, 20);
    common.printZ("] free ");
    common.printNum(@as(i32, @intCast(free_bins[i])));
    common.printZ(" / ");
    common.printNum(@as(i32, @intCast(free_bins[i] + busy_bins[i])));
    common.printZ("\r\n");
}
common.printZ("--------------------\r\n");
common.printZ("Total pages: ");
common.printNum(@as(i32, @intCast(total)));
common.printZ(" | Free: ");
common.printNum(@as(i32, @intCast(freep)));
common.printZ(" | Used: ");
common.printNum(@as(i32, @intCast(memory.usedPages())));
    common.printZ("\r\n");
}

test "barFilled clamps to [0,width]" {
    try std.testing.expectEqual(@as(usize, 0), barFilled(0, 10, 10));
    try std.testing.expectEqual(@as(usize, 10), barFilled(10, 10, 10));
    try std.testing.expectEqual(@as(usize, 5), barFilled(5, 10, 10));
    try std.testing.expectEqual(@as(usize, 7), barFilled(70, 100, 10));
    // count > total still yields width
    try std.testing.expectEqual(@as(usize, 10), barFilled(20, 10, 10));
    // total == 0 → no div-by-zero, 0 filled
    try std.testing.expectEqual(@as(usize, 0), barFilled(5, 0, 10));
}
