// zig/syscalls/memory.zig
// Memory-related syscalls: malloc, free, MemoryMapRange, GetFreeMemory.

const common = @import("../commands/common.zig");
const memory = @import("../memory.zig");
const user = @import("../user.zig");
const logger = @import("../logger.zig");
const syscalls = @import("mod.zig");
const process_mod = @import("process.zig");

/// Syscall 15: MemoryMapRange(EBX=vaddr, ECX=size)
/// Maps a range of user-space virtual addresses to physical frames.
/// Restricted: no wraparound, no kernel-space, no forbidden ranges, no huge mappings.
pub fn memoryMapRange(regs: *user.Registers) void {
    const vaddr = regs.ebx;
    const size = regs.ecx;
    const kernel_end = @intFromPtr(&memory.ebss_sym);
    const res_end = @addWithOverflow(vaddr, size);

    if (res_end[1] != 0 or vaddr < kernel_end or size == 0 or size > 64 * 1024 * 1024) {
        logger.security("Invalid MemoryMapRange request (bad range or overflow)");
    } else {
        const idt_start = @intFromPtr(&memory.idt_start);
        const forbidden_ranges = [_]struct { usize, usize }{
            .{ idt_start, idt_start + 4096 },
            .{ 0x100000, 0x101000 },
            .{ 0xA0000, 0x100000 },
        };

        var is_forbidden = false;
        for (forbidden_ranges) |range| {
            if (vaddr < range[1] and vaddr + size > range[0]) {
                is_forbidden = true;
                break;
            }
        }

        if (is_forbidden) {
            logger.security("MemoryMapRange: Attempt to map forbidden range");
        } else {
            var addr = vaddr & 0xFFFFF000;
            const end = res_end[0];
            while (addr < end) : (addr += memory.PAGE_SIZE) {
                const pd_idx = addr >> 22;
                const pt_idx = (addr >> 12) & 0x3FF;
                if (memory.page_tables[pd_idx]) |pt| {
                    if ((pt[pt_idx] & 1) == 0) {
                        if (memory.pmm.alloc_page()) |paddr| {
                            pt[pt_idx] = @as(u32, @intCast(paddr)) | 0x7;
                            memory.page_directory[pd_idx] |= 0x04;
                            asm volatile ("invlpg (%[v])"
                                :
                                : [v] "r" (addr),
                                : .{ .memory = true });
                        }
                    }
                } else {
                    _ = memory.map_page(addr, true);
                }
            }
        }
    }
}

/// Syscall 30: Malloc(EBX = size) -> EAX (ptr)
/// If current process is Nova, enforces strict tracking (max 256 allocs).
pub fn malloc(regs: *user.Registers) void {
    if (process_mod.current_is_nova and process_mod.process_alloc_count >= process_mod.MAX_PROCESS_ALLOCS) {
        logger.security("Nova malloc: max allocs reached (256)");
        regs.eax = 0;
        return;
    }
    const size = regs.ebx;
    if (memory.heap.alloc(size)) |ptr| {
        const addr = @intFromPtr(ptr);
        if (!process_mod.track_alloc(@intCast(addr), size)) {
            // Tracker full for Nova — free the just-allocated memory and return OOM
            _ = memory.heap.free_safe(ptr);
            logger.security("Nova malloc: tracker full, freeing and returning OOM");
            regs.eax = 0;
            return;
        }
        regs.eax = addr;
    } else {
        regs.eax = 0;
    }
}

/// Syscall 31: Free(EBX = ptr)
/// If current process is Nova, only frees if pointer is tracked.
pub fn free(regs: *user.Registers) void {
    if (regs.ebx == 0) return;
    if (process_mod.current_is_nova) {
        if (!process_mod.untrack_alloc(regs.ebx)) {
            logger.security("Nova free: untracked pointer (UAF attempt?)");
            return; // Don't free untracked pointers
        }
    }
    _ = memory.heap.free_safe(@ptrFromInt(regs.ebx));
}

/// Syscall 44: GetFreeMemory() -> EAX (bytes)
pub fn getFreeMemory(regs: *user.Registers) void {
    regs.eax = @intCast(memory.get_free_memory());
}

const MAX_MMAP_REGIONS = 64;
const MmapRegion = struct {
    addr: u32,
    size: u32,
};
var mmap_regions: [MAX_MMAP_REGIONS]?MmapRegion = [_]?MmapRegion{null} ** MAX_MMAP_REGIONS;
var mmap_next: u32 = 0x40000000;

/// Syscall 107: mmap(EBX=addr_hint, ECX=length, EDX=prot, ESI=flags, EDI=fd) -> EAX=addr or -1
pub fn mmap(regs: *user.Registers) void {
    _ = regs.ebx; // addr_hint — ignored for now
    const length = (regs.ecx + 0xFFF) & ~@as(u32, 0xFFF);
    if (length == 0) { regs.eax = 0xFFFFFFFF; return; }
    const addr = mmap_next;
    mmap_next += length;
    var page = addr;
    while (page < addr + length) : (page += 0x1000) {
        const paddr = memory.pmm.alloc_page() orelse {
            regs.eax = 0xFFFFFFFF; return;
        };
        _ = memory.map_page_at(page, paddr, true);
    }
    for (&mmap_regions) |*slot| {
        if (slot.* == null) {
            slot.* = .{ .addr = addr, .size = length };
            regs.eax = addr;
            return;
        }
    }
    regs.eax = addr;
}

/// Syscall 108: munmap(EBX=addr, ECX=length) -> EAX=0 or -1
pub fn munmap(regs: *user.Registers) void {
    const addr = regs.ebx;
    const length = (regs.ecx + 0xFFF) & ~@as(u32, 0xFFF);
    var found = false;
    for (&mmap_regions) |*slot| {
        if (slot.*) |r| {
            if (r.addr == addr and r.size == length) {
                var page = addr;
                while (page < addr + length) : (page += 0x1000) {
                    const pd_idx = page >> 22;
                    const pt_idx = (page >> 12) & 0x3FF;
                    if (memory.page_tables[pd_idx]) |pt| {
                        const paddr = pt[pt_idx] & 0xFFFFF000;
                        if (paddr != 0) {
                            memory.pmm.free_page(paddr);
                            pt[pt_idx] = 0;
                        }
                    }
                }
                slot.* = null;
                found = true;
                break;
            }
        }
    }
    regs.eax = if (found) 0 else 0xFFFFFFFF;
}
