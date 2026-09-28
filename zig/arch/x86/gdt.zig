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

    // Round up to page boundary so we never tighten into the middle of a page
    const limit = (code_len + 0xFFF) & ~@as(usize, 0xFFF);
    writeCodeEntry(@intCast(limit));

    var msg_buf: [64]u8 = undefined;
    const msg = std.fmt.bufPrint(&msg_buf, "gdt: code limit tightened to {d} bytes (W^X)", .{limit}) catch "gdt: limit tightened";
    logger.trace(msg);
}
