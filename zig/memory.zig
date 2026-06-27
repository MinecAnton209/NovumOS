const common = @import("commands/common.zig");
const config = @import("config.zig");
const logger = @import("logger.zig");

pub const PAGE_SIZE = 4096;
pub var MAX_MEMORY: usize = 128 * 1024 * 1024; // Default to 128MB, updated at boot
pub var DETECTED_MEMORY: u64 = 128 * 1024 * 1024;
pub var TOTAL_PAGES: usize = 0;
pub var BITMAP_SIZE: usize = 0;

extern const ebss: anyopaque;
extern const _code_start: anyopaque;
extern const _code_end: anyopaque;
extern const _rodata_start: anyopaque;
extern const _rodata_end: anyopaque;
extern const _data_start: anyopaque;
extern const _data_end: anyopaque;
extern const _system_start: anyopaque;
extern const _system_end: anyopaque;
pub extern const idt_start: anyopaque;

// We'll allocate a fixed-size bitmap for up to 4GB (128KB bitmap)
var bitmap: [131072]u8 align(4096) linksection(".system") = [_]u8{0} ** 131072;
var last_free_page: u32 = 0;
var pmm_lock: u32 = 0;
var paging_lock: u32 = 0;
const smp = @import("smp.zig");

/// Public alias to the kernel's BSS end symbol (used by user.zig for kernel_end)
pub const ebss_sym: *const anyopaque = &ebss;

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
        while (i < reserved_pages) : (i += 1) _ = set_page_busy(i);
    }

    pub fn alloc_page() ?usize {
        const eflags = interrupts_save();
        smp.spin_lock(&pmm_lock);
        defer {
            smp.spin_unlock(&pmm_lock);
            interrupts_restore(eflags);
        }

        var i = last_free_page;
        while (i < TOTAL_PAGES) : (i += 1) {
            if (!is_page_busy(i)) {
                _ = set_page_busy(i);
                last_free_page = i;
                return i * PAGE_SIZE;
            }
        }
        return null; // OOM
    }

    pub fn free_page(addr: usize) void {
        const eflags = interrupts_save();
        smp.spin_lock(&pmm_lock);
        defer {
            smp.spin_unlock(&pmm_lock);
            interrupts_restore(eflags);
        }

        const idx = @as(u32, @intCast(addr / PAGE_SIZE));
        clear_page_busy(idx);
        if (idx < last_free_page) last_free_page = idx;
    }
};

pub fn set_page_busy(idx: u32) bool {
    if (idx >= TOTAL_PAGES) {
        logger.security("PMM: set_page_busy - index out of bounds");
        return false;
    }
    const bit_idx: u3 = @intCast(idx % 8);
    const mask = @as(u8, 1) << bit_idx;
    _ = @atomicRmw(u8, &bitmap[idx / 8], .Or, mask, .seq_cst);
    return true;
}

pub fn clear_page_busy(idx: u32) bool {
    if (idx >= TOTAL_PAGES) {
        logger.security("PMM: clear_page_busy - index out of bounds");
        return false;
    }
    const bit_idx: u3 = @intCast(idx % 8);
    const mask = ~(@as(u8, 1) << bit_idx);
    _ = @atomicRmw(u8, &bitmap[idx / 8], .And, mask, .seq_cst);
    return true;
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

fn is_page_busy(idx: u32) bool {
    if (idx >= TOTAL_PAGES) return true;
    return (@atomicLoad(u8, &bitmap[idx / 8], .seq_cst) & (@as(u8, 1) << @as(u3, @intCast(idx % 8)))) != 0;
}

// Paging structures
pub const PageDirectory = [1024]u32;
pub const PageTable = [1024]u32;

// Paging structures - MUST be 4096-byte aligned for the CPU
pub var page_directory: PageDirectory align(4096) linksection(".system") = [_]u32{0} ** 1024;
pub var page_tables: [1024]?*PageTable linksection(".system") = [_]?*PageTable{null} ** 1024;

inline fn interrupts_save() u32 {
    var eflags: u32 = undefined;
    asm volatile (
        \\pushfl
        \\popl %[eflags]
        : [eflags] "=r" (eflags),
    );
    // CLI is a privileged instruction — only execute it in Ring 0 (CPL=0).
    // In Ring 3 the spinlock is sufficient for concurrency (no local IRQ masking).
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 0) {
        asm volatile ("cli");
    }
    return eflags;
}

inline fn interrupts_restore(eflags: u32) void {
    // Only restore IF via popfl in Ring 0; in Ring 3 it's a no-op.
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 0) {
        asm volatile (
            \\pushl %[eflags]
            \\popfl
            :
            : [eflags] "r" (eflags),
            : .{ .memory = true });
    }
}

// Statically allocate enough page tables to safely cover the first 16MB (Kernel, stack, IDT)
var first_16mb_pts: [4]PageTable align(4096) linksection(".system") = [_]PageTable{[_]u32{0} ** 1024} ** 4;

pub var pf_count: usize = 0;

// Whitelisted MMIO regions for User-mode (e.g., LFB)
pub var user_mmio_start: usize = 0;
pub var user_mmio_end: usize = 0;

pub fn init_paging() void {
    // 1. Disable Interrupts during this transition
    asm volatile ("cli");

    // 2. Enable PSE (Page Size Extension) in CR4
    asm volatile (
        \\mov %%cr4, %%eax
        \\or $0x00000010, %%eax
        \\mov %%eax, %%cr4
        ::: .{ .eax = true });

    const code_start = @intFromPtr(&_code_start);
    const code_end = @intFromPtr(&_code_end);
    const rodata_start = @intFromPtr(&_rodata_start);
    const rodata_end = @intFromPtr(&_rodata_end);
    const data_start = @intFromPtr(&_data_start);
    const system_start = @intFromPtr(&_system_start);
    const system_end = @intFromPtr(&_system_end);
    const idt_addr = @intFromPtr(&idt_start);

    // 3. Setup Page Directory Index 0-3 (0-16MB) using 4KB pages
    var pd_idx: u32 = 0;
    while (pd_idx < 4) : (pd_idx += 1) {
        if (create_page_table(pd_idx)) |pt| {
            for (0..1024) |j| {
                const addr = (pd_idx * 1024 * PAGE_SIZE) + (j * PAGE_SIZE);

                if (addr == 0) {
                    pt[j] = 0x0 | 0x2; // NULL protection (P=0)
                }
                // Critical System Structures (PD/PMM/PT) and IDT
                // MUST NOT be user-accessible to prevent privilege escalation.
                else if ((addr >= system_start and addr < system_end) or
                    (addr >= (idt_addr & 0xFFFFF000) and addr < (idt_addr & 0xFFFFF000) + 4096))
                {
                    pt[j] = @as(u32, @intCast(addr)) | 0x3; // P=1, RW=1, USER=0 (Supervisor Only)
                }
                // All kernel code - User Read/Execute Only
                // NOTE: Ring 3 needs this because Nova/Shell runs inside the kernel binary.
                // The .system section above protects the most critical structures.
                else if (addr >= code_start and addr < code_end) {
                    pt[j] = @as(u32, @intCast(addr)) | 0x5; // P=1, RW=0, USER=1
                }
                // Read-Only Data (constants, strings)
                else if (addr >= rodata_start and addr < rodata_end) {
                    pt[j] = @as(u32, @intCast(addr)) | 0x5; // P=1, RW=0, USER=1
                }
                // Kernel Data and BSS - User Read-Write
                // Nova interpreter and Shell store state here
                else if (addr >= data_start and addr < @intFromPtr(&ebss)) {
                    pt[j] = @as(u32, @intCast(addr)) | 0x7; // P=1, RW=1, USER=1
                }
                // (Static User Stack Area removed to support dynamic per-process stacks)
                // Everything else (BIOS, Heap, hardware areas)
                // We keep VGA buffer user-accessible for the shell, but protect BIOS/Hardware areas.
                else {
                    const is_vga = (addr >= 0xB8000 and addr < 0xC0000);
                    // The shell and Nova need access to the heap (shared for simplicity for now)
                    const is_heap = (addr >= @intFromPtr(&ebss_sym) and addr < 16 * 1024 * 1024);

                    if (is_vga or is_heap) {
                        pt[j] = @as(u32, @intCast(addr)) | 0x7; // P=1, RW=1, USER=1
                    } else {
                        pt[j] = @as(u32, @intCast(addr)) | 0x3; // P=1, RW=1, USER=0 (Supervisor)
                    }
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
                // Identity map physical RAM to kernel as Supervisor
                page_directory[i] = addr | 0x83; // PS=1, RW=1, P=1, USER=0 (Supervisor Only)
            } else {
                // Demand paging for the rest of physical memory
                page_directory[i] = addr | 0x82; // PS=1, RW=1, P=0, USER=0 (Supervisor Only)
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
        \\or $0x80010000, %[cr0_val]
        \\mov %[cr0_val], %%cr0
        \\jmp 1f
        \\1:
        : [cr0_val] "=&r" (cr0_val),
        : [pd] "r" (pd_addr),
        : .{ .memory = true });

    // 6. Restore Interrupts
    asm volatile ("sti");
}

pub fn enable_paging_on_current_core() void {
    const pd_addr = @intFromPtr(&page_directory);

    asm volatile (
        \\mov %%cr4, %%eax
        \\or $0x10, %%eax
        \\mov %%eax, %%cr4
        \\wbinvd
        \\mov %[pd], %%cr3
        \\mov %%cr0, %%eax
        \\or $0x80010000, %%eax
        \\mov %%eax, %%cr0
        \\jmp 1f
        \\1:
        :
        : [pd] "r" (pd_addr),
    );
}

/// create_page_table ensures a page table exists for a directory entry.
/// It MUST only be called if we are sure it won't trigger a recursive fault,
/// or if it allocates from an already identity-mapped region.
fn create_page_table(pd_idx: u32) ?*PageTable {
    if (pd_idx >= 1024) return null;
    if (page_tables[pd_idx]) |pt| return pt;

    // Use static tables for the first 16MB (Indices 0-3)
    if (pd_idx < 4) {
        const pt = &first_16mb_pts[pd_idx];
        page_tables[pd_idx] = pt;
        // The first 16MB (indices 0-3) MUST have USER bit set in PDE to allow user access to kernel binary (Nova/Shell).
        // For higher indices, we keep them as Supervisor-only; map_page will upgrade if needed.
        const attr: u32 = if (pd_idx < 4) 0x7 else 0x3;
        page_directory[pd_idx] = @as(u32, @intCast(@intFromPtr(pt))) | attr;
        return pt;
    }

    // Allocate physical frame
    if (pmm.alloc_page()) |pt_addr| {
        const pt = @as(*PageTable, @ptrFromInt(pt_addr));
        for (pt) |*entry| entry.* = 0;

        page_tables[pd_idx] = pt;
        // Start as Supervisor; map_page will upgrade to USER if needed
        page_directory[pd_idx] = @as(u32, @intCast(pt_addr)) | 0x3;
        return pt;
    }
    return null;
}

/// map_page handles demand paging and discovery of high-memory tables (ACPI, BIOS, MMIO).
/// If is_user is true, it verifies that the address is within allowed user-mode memory boundaries.
pub fn map_page(vaddr: usize, is_user: bool) bool {
    // Address 0x0 and Poison addresses are protected
    if (vaddr < 4096) return false;
    if (vaddr >= 0xDEAD0000 and vaddr <= 0xDEADFFFF) return false;

    const pd_idx = vaddr >> 22;

    // --- Restore Huge Page (4MB) Activation ---
    const pde = &page_directory[pd_idx];
    if ((pde.* & 0x80) != 0) {
        // If not present or (if user request) user bit missing
        if ((pde.* & 1) == 0 or (is_user and (pde.* & 4) == 0)) {
            pde.* |= 0x1; // Mark Present
            if (is_user) pde.* |= 0x4; // User-mode access

            asm volatile ("invlpg (%[vaddr])"
                :
                : [vaddr] "r" (vaddr),
                : .{ .memory = true });
            pf_count += 1;
            return true;
        }
        return true; // Already present
    }

    // Security check for User Mode requests
    if (is_user) {
        // User Mode can only map:
        // 1. RAM within [kernel_end, MAX_MEMORY)
        // 2. Whitelisted MMIO (like LFB)
        // 3. Legacy VGA text buffer (0xB8000)
        const kernel_end = @intFromPtr(&ebss);

        const is_vga = (vaddr >= 0xB8000 and vaddr < 0xC0000);
        const is_kernel_code = (vaddr >= @intFromPtr(&_code_start) and vaddr < @intFromPtr(&_code_end));
        const is_rodata = (vaddr >= @intFromPtr(&_rodata_start) and vaddr < @intFromPtr(&_rodata_end));
        const is_data = (vaddr >= @intFromPtr(&_data_start) and vaddr < @intFromPtr(&ebss));
        const is_system_area = (vaddr >= @intFromPtr(&_system_start) and vaddr < @intFromPtr(&_system_end));

        const is_allowed_mmio = (user_mmio_start != 0 and vaddr >= user_mmio_start and vaddr < user_mmio_end);

        // For general demand paging (identity mapping), we check boundaries.
        const is_kernel_image = is_kernel_code or is_rodata or is_data or is_system_area;
        if (!is_vga and !is_allowed_mmio and !is_kernel_image) {
            if (vaddr < kernel_end or vaddr >= MAX_MEMORY) {
                logger.security("User-mode unauthorized memory map attempt");
                var buf: [16]u8 = undefined;
                logger.debug(common.intToHex(@intCast(vaddr), &buf));
                return false;
            }
        }
    }

    const eflags = interrupts_save();
    smp.spin_lock(&paging_lock);
    defer {
        smp.spin_unlock(&paging_lock);
        interrupts_restore(eflags);
    }

    return map_page_at(vaddr, vaddr & 0xFFFFF000, is_user);
}

/// map_page_at maps a specific virtual address to a specific physical address with requested permissions.
pub fn map_page_at(vaddr: usize, paddr_in: usize, is_user: bool) bool {
    const pd_idx = vaddr >> 22;
    const pt_idx = (vaddr >> 12) & 0x3FF;

    if (pd_idx >= 1024) return false;

    // Address 0x0 and Poison addresses are protected from mapping (except maybe kernel?)
    if (vaddr < 4096) return false;

    // Check for HUGE PAGE (Bit 7) in the directory
    if ((page_directory[pd_idx] & 0x80) != 0) {
        // If it's a huge page, ensure it has the requested permissions
        var huge_attr: u32 = 0x81; // P=1, PS=1
        if (is_user) {
            huge_attr |= 0x06; // RW=1, US=1
        } else {
            huge_attr |= 0x02; // RW=1
        }

        page_directory[pd_idx] |= huge_attr;

        // Invalidate TLB for this range
        asm volatile ("invlpg (%[vaddr])"
            :
            : [vaddr] "r" (vaddr),
            : .{ .memory = true });
        return true;
    }

    const pt = create_page_table(@as(u32, @intCast(pd_idx))) orelse return false;

    // Ensure the PDE has USER and RW bits set if this is a user-mode request
    if (is_user) {
        page_directory[pd_idx] |= 0x06; // USER=1, RW=1
    }

    const pte = &pt[pt_idx];
    const target_attr: u32 = if (is_user) 0x07 else 0x03; // P+RW(+US)

    // If not present or if permissions are insufficient (missing USER or RW)
    if ((pte.* & 1) == 0 or (pte.* & target_attr) != target_attr) {
        var paddr: usize = paddr_in;

        // If a physical address was pre-assigned in the PTE, use it.
        if ((pte.* & 0xFFFFF000) != 0) {
            paddr = pte.* & 0xFFFFF000;
        }

        // Mark as busy if it's in our RAM range
        if (paddr < MAX_MEMORY) {
            _ = set_page_busy(@as(u32, @intCast(paddr / PAGE_SIZE)));
        }

        // Set attributes based on requester and region
        var attr: u32 = if (is_user) 0x7 else 0x3;

        // Security: Restrict permissions for specific regions
        if (vaddr >= @intFromPtr(&_code_start) and vaddr < @intFromPtr(&_code_end)) {
            attr = if (is_user) 0x5 else 0x1; // Code is Read/Execute
        } else if (vaddr >= @intFromPtr(&_rodata_start) and vaddr < @intFromPtr(&_rodata_end)) {
            attr = if (is_user) 0x5 else 0x1; // RoData is Read-only
        } else if (vaddr >= @intFromPtr(&_system_start) and vaddr < @intFromPtr(&_system_end)) {
            attr = 0x7; // Allowed for shell/nova for now
        }

        // Apply new attributes while keeping the physical address
        pte.* = @as(u32, @intCast(paddr)) | attr;

        // Invalidate TLB
        asm volatile ("invlpg (%[vaddr])"
            :
            : [vaddr] "r" (vaddr),
            : .{ .memory = true });

        pf_count += 1;
        return true;
    }
    return false;
}

/// Helper to check if an address is mapped and present in the page directory/tables.
pub fn is_ptr_present(addr: usize) bool {
    const pd_idx = addr >> 22;
    const pt_idx = (addr >> 12) & 0x3FF;

    const pde = page_directory[pd_idx];
    if ((pde & 0x01) == 0) return false;
    if ((pde & 0x80) != 0) return true; // Huge page is present

    if (page_tables[pd_idx]) |pt| {
        return (pt[pt_idx] & 0x01) != 0;
    }
    return false;
}

/// Helper to check if an address is mapped for User-mode (P=1 and USER=1)
pub fn is_user_ptr(addr: usize) bool {
    const pd_idx = addr >> 22;
    const pt_idx = (addr >> 12) & 0x3FF;

    const pde = page_directory[pd_idx];
    if ((pde & 0x01) == 0 or (pde & 0x04) == 0) return false;
    if ((pde & 0x80) != 0) return true; // Huge page is present and user

    if (page_tables[pd_idx]) |pt| {
        const pte = pt[pt_idx];
        return (pte & 0x01) != 0 and (pte & 0x04) != 0;
    }
    return false;
}

pub fn map_range(vaddr: usize, size: usize, is_user: bool) void {
    if (size == 0) return;

    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 3) {
        // Redirect to syscall if called from user-mode code directly.
        // Must NOT hold paging_lock here — the syscall handler runs in Ring 0
        // and the return would skip the defer block, leaking the lock.
        asm volatile ("int $0x80"
            :
            : [sys] "{eax}" (@as(u32, 15)),
              [v] "{ebx}" (vaddr),
              [s] "{ecx}" (size),
        );
        return;
    }

    const eflags = interrupts_save();
    smp.spin_lock(&paging_lock);
    defer {
        smp.spin_unlock(&paging_lock);
        interrupts_restore(eflags);
    }

    const end_aligned = (vaddr + (size - 1)) & 0xFFFFF000;
    var addr = vaddr & 0xFFFFF000;

    while (true) {
        const pd_idx = addr >> 22;
        if ((page_directory[pd_idx] & 0x80) != 0) {
            // Huge page: map it and jump to next 4MB
            _ = map_page_at(addr, addr & 0xFFC00000, is_user);
            const res = @addWithOverflow(addr & 0xFFC00000, @as(usize, 0x400000));
            if (res[1] != 0 or res[0] > end_aligned) break;
            addr = res[0];
        } else {
            _ = map_page_at(addr, addr & 0xFFFFF000, is_user);
            if (addr >= end_aligned) break;
            const res = @addWithOverflow(addr, @as(usize, PAGE_SIZE));
            if (res[1] != 0) break;
            addr = res[0];
        }
    }
}

/// --- Segregated Explicit Free List with Boundary Tags ---
const HEAP_MAGIC = 0x48454150;
const END_CANARY = 0xCAFEBABE;
const CANARY_BYTE = 0xCB;
const POISON_ALLOC: u8 = 0xAA;
const POISON_FREE: u8 = 0xDF;
const CANARY_SIZE = 4;
const MAX_ALLOC_SIZE = 16 * 1024 * 1024;
const MIN_BIN_SHIFT: u32 = 5;
const BIN_COUNT: u32 = 27;

const BlockHeader = struct {
    magic: u32,
    size: u32,
    is_free: bool,
    requested: u32,
};

const BlockFooter = struct {
    size: u32,
};

const HEADER_SIZE: u32 = @sizeOf(BlockHeader);
const FOOTER_SIZE: u32 = @sizeOf(BlockFooter);
const MIN_BLOCK_SIZE: u32 = @max(
    (HEADER_SIZE + 8 + FOOTER_SIZE + 7) & ~@as(u32, 7),
    32,
);

pub const heap = struct {
    var bins: [BIN_COUNT]?*BlockHeader = .{null} ** BIN_COUNT;
    var heap_base: usize = 0;
    var heap_lock: u32 = 0;

    pub fn init() void {
        const addr = pmm.alloc_page() orelse return;
        heap_base = addr;
        const block = @as(*BlockHeader, @ptrFromInt(addr));
        block.magic = HEAP_MAGIC;
        block.size = @as(u32, @intCast(PAGE_SIZE));
        block.is_free = true;
        block.requested = 0;
        writeFooter(block);
        binPush(block);
    }

    pub fn alloc(size: usize) ?[*]u8 {
        if (size > MAX_ALLOC_SIZE) {
            logger.security("Heap alloc: requested size exceeds maximum (16MB)");
            return null;
        }

        const eflags = interrupts_save();
        smp.spin_lock(&heap_lock);
        defer {
            smp.spin_unlock(&heap_lock);
            interrupts_restore(eflags);
        }

        const size32 = @as(u32, @intCast(size));
        const aligned: u32 = (size32 + 7) & ~@as(u32, 7);
        const need_block = @max(
            HEADER_SIZE + aligned + CANARY_SIZE + FOOTER_SIZE,
            MIN_BLOCK_SIZE,
        );

        while (true) {
            var bin_idx = binIndex(need_block);
            while (bin_idx < BIN_COUNT) : (bin_idx += 1) {
                var block = bins[bin_idx];
                while (block) |blk| : (block = nextFree(blk)) {
                    if (blk.size >= need_block) {
                        binRemove(blk);

                        const remaining = blk.size - need_block;
                        if (remaining >= MIN_BLOCK_SIZE) {
                            const next_addr = @intFromPtr(blk) + need_block;
                            const new_block = @as(*BlockHeader, @ptrFromInt(next_addr));
                            new_block.magic = HEAP_MAGIC;
                            new_block.size = remaining;
                            new_block.is_free = true;
                            new_block.requested = 0;
                            writeFooter(new_block);
                            binPush(new_block);
                            blk.size = need_block;
                        }

                        writeFooter(blk);
                        blk.is_free = false;
                        blk.requested = @as(u32, @intCast(size));

                        const data_ptr = dataPtr(blk);
                        @memset(data_ptr[0..size], POISON_ALLOC);

                        const canary_off = HEADER_SIZE + aligned;
                        @as(*align(1) u32, @ptrFromInt(@intFromPtr(blk) + canary_off)).* = END_CANARY;

                        if (aligned > size32) {
                            @memset(data_ptr[size..@as(usize, aligned)], CANARY_BYTE);
                        }
                        return data_ptr;
                    }
                }
            }

            const page_addr = pmm.alloc_page() orelse return null;
            const new_block = @as(*BlockHeader, @ptrFromInt(page_addr));
            new_block.magic = HEAP_MAGIC;
            new_block.size = @as(u32, @intCast(PAGE_SIZE));
            new_block.is_free = true;
            new_block.requested = 0;
            writeFooter(new_block);
            binPush(tryCoalesce(new_block));
        }
    }

    pub fn free(ptr: [*]u8) void {
        if (!free_internal(ptr, false)) {
            @panic("Heap: Internal free failed (bad pointer, magic or double-free)");
        }
    }

    pub fn free_safe(ptr: [*]u8) bool {
        return free_internal(ptr, true);
    }

    fn free_internal(ptr: [*]u8, safe: bool) bool {
        const addr = @intFromPtr(ptr);
        if (addr < 0x1000 or (addr & 3) != 0) {
            if (safe) logger.security("Free: Invalid or unaligned pointer from User Mode");
            return false;
        }

        const eflags = interrupts_save();
        smp.spin_lock(&heap_lock);
        defer {
            smp.spin_unlock(&heap_lock);
            interrupts_restore(eflags);
        }

        const header = @as(*BlockHeader, @ptrFromInt(addr - HEADER_SIZE));
        if (header.magic != HEAP_MAGIC) {
            if (safe) logger.security("Free: corruption (invalid magic)");
            return false;
        }
        if (header.is_free) {
            if (safe) logger.security("Free: double-free attempt from User Mode");
            return false;
        }

        const block_size = header.size;
        const aligned: u32 = (header.requested + 7) & ~@as(u32, 7);
        const canary_off: u32 = HEADER_SIZE + aligned;
        const stored = @as(*align(1) const u32, @ptrFromInt(@intFromPtr(header) + canary_off)).*;
        if (stored != END_CANARY) {
            if (safe) logger.security("Free: buffer overflow (END_CANARY corrupted)");
            return false;
        }

        if (aligned > header.requested) {
            const data_ptr = @as([*]u8, @ptrFromInt(addr));
            for (header.requested..aligned) |i| {
                if (data_ptr[i] != CANARY_BYTE) {
                    if (safe) logger.security("Free: small buffer overflow (padding corrupted)");
                    return false;
                }
            }
        }

        if (block_size > 128 * 1024 * 1024) {
            if (safe) logger.security("Free: implausible block size");
            return false;
        }

        const poison_len = block_size - HEADER_SIZE - FOOTER_SIZE;
        @memset(@as([*]u8, @ptrFromInt(addr))[0..@as(usize, poison_len)], POISON_FREE);

        header.is_free = true;
        header.requested = 0;

        const merged = tryCoalesce(header);
        binPush(merged);
        return true;
    }

    pub fn garbage_collect() void {
        const eflags = interrupts_save();
        smp.spin_lock(&heap_lock);
        defer {
            smp.spin_unlock(&heap_lock);
            interrupts_restore(eflags);
        }
        if (!config.USE_GARBAGE_COLLECTOR) return;
        logger.info("GC: coalescing free blocks...");
    }
};

fn dataPtr(block: *BlockHeader) [*]u8 {
    return @as([*]u8, @ptrFromInt(@intFromPtr(block) + HEADER_SIZE));
}

fn writeFooter(block: *BlockHeader) void {
    const ftr = @as(*BlockFooter, @ptrFromInt(@intFromPtr(block) + block.size - FOOTER_SIZE));
    ftr.size = block.size;
}

fn nextFree(block: *BlockHeader) ?*BlockHeader {
    return @as(*?*BlockHeader, @ptrFromInt(@intFromPtr(block) + HEADER_SIZE)).*;
}

fn setNextFree(block: *BlockHeader, next: ?*BlockHeader) void {
    @as(*?*BlockHeader, @ptrFromInt(@intFromPtr(block) + HEADER_SIZE)).* = next;
}

fn prevFree(block: *BlockHeader) ?*BlockHeader {
    return @as(*?*BlockHeader, @ptrFromInt(@intFromPtr(block) + HEADER_SIZE + @sizeOf(?*BlockHeader))).*;
}

fn setPrevFree(block: *BlockHeader, prev: ?*BlockHeader) void {
    @as(*?*BlockHeader, @ptrFromInt(@intFromPtr(block) + HEADER_SIZE + @sizeOf(?*BlockHeader))).* = prev;
}

fn binIndex(size: u32) u32 {
    if (size <= (@as(u32, 1) << MIN_BIN_SHIFT)) return 0;
    const bits = @bitSizeOf(u32) - @clz(size) - 1;
    const idx = bits - MIN_BIN_SHIFT;
    return if (idx >= BIN_COUNT) BIN_COUNT - 1 else idx;
}

fn binPush(block: *BlockHeader) void {
    const idx = binIndex(block.size);
    setNextFree(block, heap.bins[idx]);
    setPrevFree(block, null);
    if (heap.bins[idx]) |head| setPrevFree(head, block);
    heap.bins[idx] = block;
}

fn binRemove(block: *BlockHeader) void {
    const prev = prevFree(block);
    const next = nextFree(block);
    if (prev) |p| {
        setNextFree(p, next);
    } else {
        const idx = binIndex(block.size);
        if (heap.bins[idx] == block) heap.bins[idx] = next;
    }
    if (next) |n| setPrevFree(n, prev);
}

fn tryCoalesce(block: *BlockHeader) *BlockHeader {
    var cur = block;
    const block_addr = @intFromPtr(block);

    if (block_addr > heap.heap_base) {
        const prev_footer = @as(*BlockFooter, @ptrFromInt(block_addr - FOOTER_SIZE));
        const prev_size = prev_footer.size;
        if (prev_size >= MIN_BLOCK_SIZE and prev_size <= MAX_ALLOC_SIZE) {
            const prev_addr = block_addr - prev_size;
            if (prev_addr >= heap.heap_base and prev_addr + prev_size == block_addr) {
                const prev_block = @as(*BlockHeader, @ptrFromInt(prev_addr));
                if (prev_block.magic == HEAP_MAGIC and prev_block.is_free) {
                    binRemove(prev_block);
                    prev_block.size += cur.size;
                    writeFooter(prev_block);
                    cur = prev_block;
                }
            }
        }
    }

    const next_addr = @intFromPtr(cur) + cur.size;
    if (next_addr < @intFromPtr(cur) + MAX_ALLOC_SIZE * 2) {
        const next_block = @as(*BlockHeader, @ptrFromInt(next_addr));
        if (next_block.magic == HEAP_MAGIC and next_block.is_free) {
            binRemove(next_block);
            cur.size += next_block.size;
            writeFooter(cur);
        }
    }

    return cur;
}

pub fn get_free_memory() usize {
    var free: usize = 0;
    var i: u32 = 0;
    while (i < TOTAL_PAGES) : (i += 1) {
        if (!is_page_busy(i)) free += PAGE_SIZE;
    }
    return free;
}

pub fn get_used_memory() usize {
    return MAX_MEMORY - get_free_memory();
}

pub fn get_current_pd() u32 {
    return asm volatile ("mov %%cr3, %[ret]"
        : [ret] "=r" (-> u32),
    );
}

pub fn switch_page_directory(pd_addr: u32) void {
    asm volatile ("mov %[pd], %%cr3"
        :
        : [pd] "r" (pd_addr),
        : .{ .memory = true });
}
