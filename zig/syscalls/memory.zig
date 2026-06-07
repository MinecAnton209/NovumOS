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
