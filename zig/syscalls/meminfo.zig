const user = @import("../arch/mod.zig").user;
const memory = @import("../kernel/memory.zig");
const syscalls = @import("mod.zig");

/// meminfo: write a 3-u32 summary { total_pages, free_pages, used_pages }
/// into the user buffer at ebx.  Returns 0 on success, 1 on bad range.
const MEMINFO_COUNT: usize = 3;

pub fn memInfo(regs: *user.Registers) void {
    const buf_addr = regs.ebx;
    if (!syscalls.is_safe_user_range(buf_addr, MEMINFO_COUNT * 4)) {
        regs.eax = 1;
        return;
    }
    const dst = @as([*]u32, @ptrFromInt(buf_addr));
    dst[0] = @intCast(memory.totalPages());
    dst[1] = @intCast(memory.freePages());
    dst[2] = @intCast(memory.usedPages());
    regs.eax = 0;
}

/// pagebin: ecx = bin index (0-7), ebx = user ptr to 2-u32 buffer
/// writes { free_in_bin, total_in_bin }.  Returns 0 ok, 1 bad range, 2 bad bin.
const BINS = 8;
pub fn pageBin(regs: *user.Registers) void {
    const bin = regs.ecx;
    if (bin >= BINS) {
        regs.eax = 2;
        return;
    }
    const buf_addr = regs.ebx;
    if (!syscalls.is_safe_user_range(buf_addr, 8)) {
        regs.eax = 1;
        return;
    }
    const total = memory.totalPages();
    var free_in: usize = 0;
    var total_in: usize = 0;
    const start = bin * total / BINS;
    const end = (bin + 1) * total / BINS;
    var i = start;
    while (i < end) : (i += 1) {
        total_in += 1;
        if (memory.pageIsFree(@intCast(i))) free_in += 1;
    }
    const dst = @as([*]u32, @ptrFromInt(buf_addr));
    dst[0] = @intCast(free_in);
    dst[1] = @intCast(total_in);
    regs.eax = 0;
}
