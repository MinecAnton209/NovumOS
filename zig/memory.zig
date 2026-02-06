// NovumOS Memory Management Module - Advanced Edition
const common = @import("commands/common.zig");
const config = @import("config.zig");

pub const PAGE_SIZE = 4096;
pub var MAX_MEMORY: usize = 128 * 1024 * 1024; // Default to 128MB, updated at boot
pub var DETECTED_MEMORY: u64 = 128 * 1024 * 1024;
pub var TOTAL_PAGES: usize = 0;
pub var BITMAP_SIZE: usize = 0;

extern const ebss: anyopaque;

// We'll allocate a fixed-size bitmap for up to 4GB (128KB bitmap)
var bitmap: [131072]u8 = [_]u8{0} ** 131072;
var last_free_page: u32 = 0;

/// Physical Memory Manager (PMM)
pub const pmm = struct {
    pub fn init() void {
        detect_max_memory();
        TOTAL_PAGES = MAX_MEMORY / PAGE_SIZE;
        BITMAP_SIZE = TOTAL_PAGES / 8;

        const kernel_end = @intFromPtr(&ebss);
        for (&bitmap) |*b| b.* = 0;
        // Reserve memory for kernel, BIOS, and stack (up to 8MB)
        // Our stack is at 0x500000 (5MB), so 8MB is a safe bound.
        const reserved_up_to = if (kernel_end < 0x800000) 0x800000 else kernel_end;
        const reserved_pages = (reserved_up_to / PAGE_SIZE) + 1;
        var i: u32 = 0;
        while (i < reserved_pages) : (i += 1) set_page_busy(i);
    }

    pub fn alloc_page() ?usize {
        var i = last_free_page;
        while (i < TOTAL_PAGES) : (i += 1) {
            if (!is_page_busy(i)) {
                set_page_busy(i);
                last_free_page = i;
                return i * PAGE_SIZE;
            }
        }
        return null; // OOM
    }

    pub fn free_page(addr: usize) void {
        const idx = @as(u32, @intCast(addr / PAGE_SIZE));
        clear_page_busy(idx);
        if (idx < last_free_page) last_free_page = idx;
    }
};

pub fn set_page_busy(idx: u32) void {
    if (idx >= TOTAL_PAGES) return;
    bitmap[idx / 8] |= @as(u8, 1) << @as(u3, @intCast(idx % 8));
}

fn read_cmos(reg: u8) u8 {
    const addr = 0x70;
    const data = 0x71;
    asm volatile ("outb %[val], %[port]"
        :
        : [val] "{al}" (reg),
          [port] "{dx}" (@as(u16, addr)),
    );
    return asm volatile ("inb %[port], %[ret]"
        : [ret] "={al}" (-> u8),
        : [port] "{dx}" (@as(u16, data)),
    );
}

fn detect_max_memory() void {
    // 1. Read memory between 1MB and 64MB (in KB)
    const base_low = read_cmos(0x30);
    const base_high = read_cmos(0x31);
    var base_kb = @as(u32, base_low) | (@as(u32, base_high) << 8);

    // Cap base extension at 15MB (up to 16MB total) to avoid overlap with 0x34/35
    if (base_kb > 15360) base_kb = 15360;

    // 2. Read memory above 16MB (in 64KB chunks)
    const ext_low = read_cmos(0x34);
    const ext_high = read_cmos(0x35);
    const ext_64kb = @as(u32, ext_low) | (@as(u32, ext_high) << 8);

    // Total = 1MB (Standard) + Extension (1MB-16MB) + Extension (Above 16MB)
    const total_kb = 1024 + base_kb + (@as(u32, ext_64kb) * 64);

    // 3. Read memory above 4GB (SeaBIOS specific)
    const hi_low = read_cmos(0x5B);
    const hi_mid = read_cmos(0x5C);
    const hi_high = read_cmos(0x5D);
    const hi_64kb = @as(u64, hi_low) | (@as(u64, hi_mid) << 8) | (@as(u64, hi_high) << 16);

    DETECTED_MEMORY = (@as(u64, total_kb) * 1024) + (hi_64kb * 65536);

    // Safety cap at 4GB (bitmap limit)
    const max_32bit = 0xFFFFF000;

    if (DETECTED_MEMORY >= 4096 * 1024 * 1024) {
        MAX_MEMORY = max_32bit;
    } else {
        MAX_MEMORY = @as(usize, @intCast(DETECTED_MEMORY));
    }

    // Safety check: if CMOS reported too little or failed, fallback to 128MB.
    if (MAX_MEMORY < 16 * 1024 * 1024) {
        MAX_MEMORY = 128 * 1024 * 1024;
        DETECTED_MEMORY = 128 * 1024 * 1024;
    }
}

fn clear_page_busy(idx: u32) void {
    if (idx >= TOTAL_PAGES) return;
    bitmap[idx / 8] &= ~(@as(u8, 1) << @as(u3, @intCast(idx % 8)));
}

fn is_page_busy(idx: u32) bool {
    if (idx >= TOTAL_PAGES) return true;
    return (bitmap[idx / 8] & (@as(u8, 1) << @as(u3, @intCast(idx % 8)))) != 0;
}

// Paging structures
pub const PageDirectory = [1024]u32;
pub const PageTable = [1024]u32;

// Paging structures - MUST be 4096-byte aligned for the CPU
pub var page_directory: PageDirectory align(4096) = [_]u32{0} ** 1024;
pub var page_tables: [1024]?*PageTable = [_]?*PageTable{null} ** 1024;

// Statically allocate enough page tables to safely cover the first 16MB (Kernel, stack, IDT)
var first_16mb_pts: [4]PageTable align(4096) = [_]PageTable{[_]u32{0} ** 1024} ** 4;

pub var pf_count: usize = 0;

pub fn init_paging() void {
    // 1. Disable Interrupts during this critical transition
    asm volatile ("cli");

    // 2. Enable PSE (Page Size Extension) in CR4
    asm volatile (
        \\mov %%cr4, %%eax
        \\or $0x00000010, %%eax
        \\mov %%eax, %%cr4
        ::: "eax");

    // 3. Setup Page Directory Index 0-3 (0-16MB) using 4KB pages
    // This is the CRITICAL zone: Kernel (1MB), Stack (5MB), IDT, early buffers.
    // Using 4KB pages here is safer for these sensitive regions.
    var pd_idx: u32 = 0;
    while (pd_idx < 4) : (pd_idx += 1) {
        if (create_page_table(pd_idx)) |pt| {
            for (0..1024) |j| {
                const addr = (pd_idx * 1024 * PAGE_SIZE) + (j * PAGE_SIZE);
                if (addr == 0) {
                    pt[j] = 0x0 | 0x2; // NULL protection
                } else {
                    pt[j] = @as(u32, @intCast(addr)) | 0x3; // Present, RW
                }
            }
        }
    }

    // 4. Map RAM above 16MB using HUGE PAGES (4MB each)
    const coverage = 1024 * PAGE_SIZE; // 4MB
    const max_pd_idx = (MAX_MEMORY + coverage - 1) / coverage;

    var i: u32 = 4; // Start from 16MB
    while (i < 1024) : (i += 1) {
        if (i < max_pd_idx) {
            const addr = i * coverage;
            // 16-64MB present, rest demand
            if (addr < 64 * 1024 * 1024) {
                page_directory[i] = addr | 0x83; // PS=1, RW=1, P=1
            } else {
                page_directory[i] = addr | 0x82; // PS=1, RW=1, P=0
            }
        } else {
            page_directory[i] = 0;
        }
    }

    // 5. Load CR3 and Enable Paging
    const pd_addr = @intFromPtr(&page_directory);
    var cr0_val: u32 = undefined;
    asm volatile (
        \\wbinvd
        \\mov %[pd], %%cr3
        \\mov %%cr0, %[cr0_val]
        \\or $0x80000000, %[cr0_val]
        \\mov %[cr0_val], %%cr0
        \\jmp 1f
        \\1:
        : [cr0_val] "=&r" (cr0_val),
        : [pd] "r" (pd_addr),
        : "memory");

    // 6. Restore Interrupts
    asm volatile ("sti");
}

/// create_page_table ensures a page table exists for a directory entry.
/// It MUST only be called if we are sure it won't trigger a recursive fault,
/// or if it allocates from an already identity-mapped region.
fn create_page_table(pd_idx: u32) ?*PageTable {
    if (pd_idx >= 1024) return null;
    if (page_tables[pd_idx]) |pt| return pt;

    // Use static tables for the critical first 16MB (Indices 0-3)
    if (pd_idx < 4) {
        const pt = &first_16mb_pts[pd_idx];
        page_tables[pd_idx] = pt;
        page_directory[pd_idx] = @as(u32, @intCast(@intFromPtr(pt))) | 0x3;
        return pt;
    }

    // Allocate physical frame
    if (pmm.alloc_page()) |pt_addr| {
        const pt = @as(*PageTable, @ptrFromInt(pt_addr));
        for (pt) |*entry| entry.* = 0;

        page_tables[pd_idx] = pt;
        page_directory[pd_idx] = @as(u32, @intCast(pt_addr)) | 0x3;
        return pt;
    }
    return null;
}

/// map_page handles demand paging and discovery of high-memory tables (ACPI, BIOS, MMIO).
pub fn map_page(vaddr: usize) bool {
    const pd_idx = vaddr >> 22;
    const pt_idx = (vaddr >> 12) & 0x3FF;

    if (pd_idx >= 1024) return false;

    // Address 0x0 and Poison addresses are protected
    if (vaddr < 4096) return false;
    if (vaddr >= 0xDEAD0000 and vaddr <= 0xDEADFFFF) return false;

    // Check for HUGE PAGE (Bit 7)
    const pde = &page_directory[pd_idx];
    if ((pde.* & 0x80) != 0) {
        if ((pde.* & 1) == 0) {
            pde.* |= 1; // Mark Present
            asm volatile ("invlpg (%[vaddr])"
                :
                : [vaddr] "r" (vaddr),
                : "memory");
            pf_count += 1;
        }
        return true;
    }

    const pt = create_page_table(@as(u32, @intCast(pd_idx))) orelse return false;
    const pte = &pt[pt_idx];

    // If not present
    if ((pte.* & 1) == 0) {
        var paddr: usize = 0;

        if ((pte.* & 0xFFFFF000) != 0) {
            // Use pre-assigned physical address (for 32MB - RAM range)
            paddr = pte.* & 0xFFFFF000;
        } else {
            // Identity map for discovery (BIOS, ACPI, MMIO)
            paddr = vaddr & 0xFFFFF000;
        }

        // Mark as busy if it's in our RAM range
        if (paddr < MAX_MEMORY) {
            set_page_busy(@as(u32, @intCast(paddr / PAGE_SIZE)));
        }

        pte.* = @as(u32, @intCast(paddr)) | 0x3; // P=1, RW=1
        asm volatile ("invlpg (%[vaddr])"
            :
            : [vaddr] "r" (vaddr),
            : "memory");

        pf_count += 1;
        return true;
    }
    return false;
}

pub fn map_range(vaddr: usize, size: usize) void {
    var addr = vaddr & 0xFFFFF000;
    const end = vaddr + size;
    while (addr < end) {
        const pd_idx = addr >> 22;
        if ((page_directory[pd_idx] & 0x80) != 0) {
            // Huge page: map it and jump to next 4MB
            _ = map_page(addr);
            addr = (addr + 0x400000) & 0xFFC00000;
        } else {
            _ = map_page(addr);
            addr += PAGE_SIZE;
        }
    }
}

/// --- Linked List Heap Allocator ---
const BlockHeader = struct {
    size: usize,
    is_free: bool,
    next: ?*BlockHeader,
};

var first_block: ?*BlockHeader = null;

pub const heap = struct {
    pub fn init() void {
        if (pmm.alloc_page()) |addr| {
            first_block = @as(*BlockHeader, @ptrFromInt(addr));
            first_block.?.* = .{
                .size = PAGE_SIZE - @sizeOf(BlockHeader),
                .is_free = true,
                .next = null,
            };
        }
    }

    pub fn alloc(size: usize) ?[*]u8 {
        // Align to 8 bytes
        const aligned_size = (size + 7) & ~@as(usize, 7);

        while (true) {
            var current = first_block;

            // 1. Search for a free block
            while (current) |block| : (current = block.next) {
                if (block.is_free and block.size >= aligned_size) {
                    // If the block is significantly larger, split it
                    if (block.size > aligned_size + @sizeOf(BlockHeader) + 16) {
                        const next_ptr = @intFromPtr(block) + @sizeOf(BlockHeader) + aligned_size;
                        const new_block = @as(*BlockHeader, @ptrFromInt(next_ptr));
                        new_block.* = .{
                            .size = block.size - aligned_size - @sizeOf(BlockHeader),
                            .is_free = true,
                            .next = block.next,
                        };
                        block.size = aligned_size;
                        block.next = new_block;
                    }
                    block.is_free = false;
                    return @as([*]u8, @ptrFromInt(@intFromPtr(block) + @sizeOf(BlockHeader)));
                }
            }

            // 2. Not found? Try to get more pages and link them
            if (pmm.alloc_page()) |addr| {
                const new_block = @as(*BlockHeader, @ptrFromInt(addr));
                new_block.* = .{
                    .size = PAGE_SIZE - @sizeOf(BlockHeader),
                    .is_free = true,
                    .next = null,
                };

                // Link to the end of the chain
                var last = first_block;
                if (last != null) {
                    while (last.?.next) |n| {
                        last = n;
                    }
                    last.?.next = new_block;
                } else {
                    first_block = new_block;
                }

                // Coalesce immediately to merge with previous block if contiguous
                coalesce();

                // Continue loop to check if we now have enough space
            } else {
                return null; // Out of memory
            }
        }
    }

    pub fn free(ptr: [*]u8) void {
        const header_ptr = @intFromPtr(ptr) - @sizeOf(BlockHeader);
        const header = @as(*BlockHeader, @ptrFromInt(header_ptr));
        header.is_free = true;

        // Simple immediate coalescing with next block
        coalesce();
    }

    /// Garbage Collector / Memory Cleaner
    /// Merges adjacent free blocks to prevent fragmentation
    pub fn garbage_collect() void {
        if (!config.USE_GARBAGE_COLLECTOR) return;

        common.printZ("GC: Running memory cleanup...\n");
        coalesce();
    }

    fn coalesce() void {
        var current = first_block;
        while (current) |block| {
            if (block.is_free) {
                if (block.next) |next_block| {
                    if (next_block.is_free) {
                        // Check if they are physically adjacent
                        const current_end = @intFromPtr(block) + @sizeOf(BlockHeader) + block.size;
                        if (current_end == @intFromPtr(next_block)) {
                            block.size += @sizeOf(BlockHeader) + next_block.size;
                            block.next = next_block.next;
                            // Don't move to next yet, might need to coalesce more
                            continue;
                        }
                    }
                }
            }
            current = block.next;
        }
    }
};
