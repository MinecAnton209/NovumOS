const std = @import("std");
const config = @import("../../config.zig");
const logger = @import("../../kernel/logger.zig");

extern const _code_start: anyopaque;
extern const _code_end: anyopaque;

// GDT descriptor and entries live in arch/x86/kernel32.asm
// GDT layout (selector : offset into gdt):
//   0x00: null descriptor
//   0x08: kernel code segment (4GB limit, tightened below for W^X)
//   0x10: kernel data segment
//   0x18..: TSS entries (per-core)
//   0x20: user code, 0x28: user data
const KERNEL_CODE_SELECTOR: u16 = 0x08;
const KERNEL_CODE_GDT_OFF: usize = 0x08;

const GdtEntry = packed struct {
    limit_low: u16,
    base_low: u16,
    base_mid: u8,
    access: u8,
    flags_limit_high: u8,
    base_high: u8,
};

extern var gdt_kernel_start: u8;

/// Compute how many bytes of code-segment limit to use given the raw code
/// length.  Rounds up to the next page so the tightened limit never lands
/// mid-page.
fn codeSegmentLimit(code_len: usize) u32 {
    return @intCast((code_len + 0xFFF) & ~@as(usize, 0xFFF));
}

/// Pack a GDT code-entry: limit (4KiB-gran, 20-bit), base=0, exec/read.
fn packCodeEntry(code_len: usize) GdtEntry {
    const limit = codeSegmentLimit(code_len) - 1;
    return GdtEntry{
        .limit_low = @as(u16, @truncate(limit)),
        .base_low = @as(u16, @truncate(0)),
        .base_mid = 0,
        .access = 0x9A, // code, execute/read, ring 0
        .flags_limit_high = (@as(u8, @truncate((limit >> 16) & 0x0F)) | 0xC0), // 4KiB gran + 32-bit
        .base_high = 0,
    };
}

fn writeCodeEntry(code_limit_bytes: u32) void {
    const entries = @as([*]GdtEntry, @ptrCast(@alignCast(&gdt_kernel_start)));
    const entry = &entries[KERNEL_CODE_GDT_OFF / 8];
    const limit = code_limit_bytes - 1;
    entry.limit_low = @as(u16, @truncate(limit));
    entry.flags_limit_high = (@as(u8, @truncate((limit >> 16) & 0x0F)) | 0xC0); // 4KiB granularity + 32-bit
}

pub fn tighten_code_limit() void {
    if (!config.ENABLE_WX_SEPARATION)
        return;

    const code_start = @intFromPtr(&_code_start);
    const code_end = @intFromPtr(&_code_end);
    const code_len = code_end - code_start;

    const limit = codeSegmentLimit(code_len);
    writeCodeEntry(@intCast(limit));

    var msg_buf: [64]u8 = undefined;
    const msg = std.fmt.bufPrint(&msg_buf, "gdt: code limit tightened to {d} bytes (W^X)", .{limit}) catch "gdt: limit tightened";
    logger.trace(msg);
}

test "codeSegmentLimit rounds up to page boundary" {
    try std.testing.expectEqual(@as(u32, 0x1000), codeSegmentLimit(1));
    try std.testing.expectEqual(@as(u32, 0x1000), codeSegmentLimit(0x1000));
    try std.testing.expectEqual(@as(u32, 0x2000), codeSegmentLimit(0x1001));
    try std.testing.expectEqual(@as(u32, 0x3000), codeSegmentLimit(0x2001));
    // exact page → stays that page
    try std.testing.expectEqual(@as(u32, 0x1000), codeSegmentLimit(0x1000));
}

test "packCodeEntry sets exec/read access and 4KiB granularity flag" {
    const entry = packCodeEntry(0x1000);
    try std.testing.expectEqual(@as(u8, 0x9A), entry.access);
    try std.testing.expectEqual(true, (entry.flags_limit_high & 0xC0) == 0xC0);
}

test "packCodeEntry limit encoding covers small code len" {
    const entry = packCodeEntry(0x10);
    // limit = 0x1000 - 1 = 0xFFF
    try std.testing.expectEqual(@as(u16, 0x0FFF), entry.limit_low);
    try std.testing.expectEqual(@as(u8, 0x00), entry.flags_limit_high & 0x0F);
}
