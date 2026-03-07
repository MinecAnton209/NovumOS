const common = @import("commands/common.zig");
const exceptions = @import("exceptions.zig");
const keyboard = @import("keyboard_isr.zig");
const vga = @import("drivers/vga.zig");
const timer = @import("drivers/timer.zig");
const memory = @import("memory.zig");
const ata = @import("drivers/ata.zig");
const rtc = @import("drivers/rtc.zig");

// External jump target to return to kernel shell
extern fn kernel_loop() noreturn;

// Register state passed from assembly (matches stack layout)
pub const Registers = extern struct {
    edi: u32,
    esi: u32,
    ebp: u32,
    esp_dummy: u32,
    ebx: u32,
    edx: u32,
    ecx: u32,
    eax: u32,
    ds: u32,
    es: u32,
    fs: u32,
    gs: u32,
};

// Global flag to indicate if we are in user mode (for shared code)
pub var is_user_mode: bool = false;

// Constant for maximum allowed string length in syscalls
pub const MAX_SYSCALL_STR_LEN = 4096;

/// Helper function to check if a memory address is user-accessible in the current page table
fn is_user_ptr(addr: usize) bool {
    return memory.is_user_ptr(addr);
}

/// Safely scans a user-provided string for its length, checking page permissions along the way
fn safe_strlen_user(ptr: [*]const u8, max_len: usize) ?usize {
    var i: usize = 0;
    while (i < max_len) {
        const addr = @intFromPtr(ptr) + i;
        // Optimization: check page permissions only on start and at page boundaries
        if (i == 0 or (addr & 0xFFF) == 0) {
            if (!is_user_ptr(addr)) return null;
        }
        if (ptr[i] == 0) return i;
        i += 1;
    }
    return null; // Too long or not null-terminated within bounds
}

// Export strlen as it might be needed by the kernel for strings passed from Ring 3
export fn strlen(s: [*]const u8) usize {
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {}
    return i;
}

/// Validates if a user-mode process is allowed to access a specific I/O port.
/// Returns false for sensitive system ports.
fn is_io_port_allowed(port: u16) bool {
    // Whitelist approach: only allow safe ports if any.
    // For now, we block most sensitive system ports.

    // Blocking Programmable Interrupt Controller (PIC)
    if (port == 0x20 or port == 0x21 or port == 0xA0 or port == 0xA1) return false;

    // Blocking Programmable Interval Timer (PIT)
    if (port >= 0x40 and port <= 0x43) return false;

    // Blocking PS/2 Keyboard Controller
    if (port == 0x60 or port == 0x64) return false;

    // Blocking CMOS / RTC
    if (port == 0x70 or port == 0x71) return false;

    // Blocking DMA Controllers
    if (port <= 0x1F or (port >= 0xC0 and port <= 0xDF)) return false;

    // Blocking Primary/Secondary ATA (Hard Disk)
    if (port >= 0x1F0 and port <= 0x1F7) return false;
    if (port == 0x3F6) return false;

    // Blocking PCI Configuration Ports
    if (port == 0xCF8 or port == 0xCFC) return false;

    // Blocking ACPI PM Ports (usually dynamic, but typical values)

    // Allow everything else (VGA, Serial COM1/COM2 if not blocked)
    // Note: In a production kernel, we would use a bitmap or a very strict whitelist.
    return true;
}

// System call handler exported for linker
export fn handle_syscall_zig(regs: *Registers) void {
    switch (regs.eax) {
        0 => { // Exit
            common.printZ("[Kernel] User mode process exited. Returning to Shell...\n");
            jump_to_user_mode_with_entry(@intFromPtr(&kernel_loop));
        },
        1 => { // PrintZ(EBX = string_ptr)
            const ptr = @as([*]const u8, @ptrFromInt(regs.ebx));
            if (safe_strlen_user(ptr, MAX_SYSCALL_STR_LEN)) |len| {
                common.printZ(ptr[0..len]);
            } else {
                common.printError("[Security Fault] Invalid user string provided in syscall 1\n");
            }
        },
        2 => { // GetChar() -> EAX
            regs.eax = keyboard.keyboard_wait_char();
        },
        3 => { // SetCursor(EBX = row, ECX = col)
            vga.zig_set_cursor(@intCast(regs.ebx), @intCast(regs.ecx));
        },
        4 => { // GetCursor() -> EAX (row << 8 | col)
            const row = vga.zig_get_cursor_row();
            const col = vga.zig_get_cursor_col();
            regs.eax = (@as(u32, row) << 8) | col;
        },
        5 => { // ClearScreen()
            vga.clear_screen();
        },
        6 => { // InB(EBX = port) -> EAX
            const port: u16 = @intCast(regs.ebx);
            if (is_io_port_allowed(port)) {
                regs.eax = common.inb(port);
            } else {
                common.printError("[Security Fault] Unauthorized InB to port ");
                common.printHex(port);
                common.printZ("\n");
                regs.eax = 0xFF;
            }
        },
        7 => { // OutB(EBX = port, ECX = val)
            const port: u16 = @intCast(regs.ebx);
            if (is_io_port_allowed(port)) {
                common.outb(port, @intCast(regs.ecx));
            } else {
                common.printError("[Security Fault] Unauthorized OutB to port ");
                common.printHex(port);
                common.printZ("\n");
            }
        },
        8 => { // InW(EBX = port) -> EAX
            const port: u16 = @intCast(regs.ebx);
            if (is_io_port_allowed(port)) {
                regs.eax = common.inw(port);
            } else {
                common.printError("[Security Fault] Unauthorized InW to port ");
                common.printHex(port);
                common.printZ("\n");
                regs.eax = 0xFFFF;
            }
        },
        9 => { // OutW(EBX = port, ECX = val)
            const port: u16 = @intCast(regs.ebx);
            if (is_io_port_allowed(port)) {
                common.outw(port, @intCast(regs.ecx));
            } else {
                common.printError("[Security Fault] Unauthorized OutW to port ");
                common.printHex(port);
                common.printZ("\n");
            }
        },
        10 => { // Sleep(EBX = ms)
            common.sleep(@intCast(regs.ebx));
        },
        11 => { // GetTicks() -> EAX
            regs.eax = @intCast(timer.get_ticks());
        },
        12 => { // JumpToUser(EBX = entry)
            // Reset to the standard user stack location
            const user_esp = 0x3FF000 + 4096 - 16;
            jump_to_ring3_entry(regs.ebx, user_esp);
        },
        13 => { // Shutdown
            common.shutdown();
        },
        14 => { // Reboot
            common.reboot();
        },
        15 => { // MemoryMapRange(EBX=vaddr, ECX=size)
            // Security: Do NOT identity-map user requests.
            // Instead, allocate fresh physical frames from the PMM so the user
            // cannot target a specific physical address (prevents cross-process
            // frame snooping in future multi-process scenarios).
            const vaddr = regs.ebx;
            const size = regs.ecx;
            const kernel_end = @intFromPtr(&memory.ebss_sym);
            // Validate virtual address range
            if (vaddr < kernel_end or size == 0 or size > 64 * 1024 * 1024) {
                common.printError("[Security] Invalid MemoryMapRange request\n");
            } else {
                var addr = vaddr & 0xFFFFF000;
                const end = vaddr + size;
                while (addr < end) : (addr += memory.PAGE_SIZE) {
                    const pd_idx = addr >> 22;
                    const pt_idx = (addr >> 12) & 0x3FF;
                    if (memory.page_tables[pd_idx]) |pt| {
                        if ((pt[pt_idx] & 1) == 0) {
                            // Allocate a fresh physical frame
                            if (memory.pmm.alloc_page()) |paddr| {
                                pt[pt_idx] = @as(u32, @intCast(paddr)) | 0x7; // P=1, RW=1, USER=1
                                memory.page_directory[pd_idx] |= 0x04; // ensure USER bit in PDE
                                asm volatile ("invlpg (%[v])"
                                    :
                                    : [v] "r" (addr),
                                    : "memory");
                            }
                        }
                    } else {
                        _ = memory.map_page(addr, true);
                    }
                }
            }
        },
        16 => { // InL(EBX = port) -> EAX
            const port: u16 = @intCast(regs.ebx);
            if (is_io_port_allowed(port)) {
                regs.eax = common.inl(port);
            } else {
                common.printError("[Security Fault] Unauthorized InL to port ");
                common.printHex(port);
                common.printZ("\n");
                regs.eax = 0xFFFFFFFF;
            }
        },
        17 => { // OutL(EBX = port, ECX = val)
            const port: u16 = @intCast(regs.ebx);
            if (is_io_port_allowed(port)) {
                common.outl(port, regs.ecx);
            } else {
                common.printError("[Security Fault] Unauthorized OutL to port ");
                common.printHex(port);
                common.printZ("\n");
            }
        },
        18 => { // DrawCharAt(EBX=row, ECX=col, EDX=char, ESI=attr)
            const old_color = vga.current_color;
            vga.current_color = @intCast(regs.esi);
            vga.zig_draw_char_at(@intCast(regs.ebx), @intCast(regs.ecx), @intCast(regs.edx));
            vga.current_color = old_color;
        },
        19 => { // GetDateTime(EBX = ptr to DateTime)
            const dt_ptr = @as(*rtc.DateTime, @ptrFromInt(regs.ebx));
            if (is_user_ptr(regs.ebx) and is_user_ptr(regs.ebx + @sizeOf(rtc.DateTime) - 1)) {
                dt_ptr.* = rtc.get_datetime();
            } else {
                common.printError("[Security Fault] Invalid DateTime pointer for GetDateTime\n");
            }
        },
        20 => { // ATA_IDENTIFY(EBX = drive) -> EAX
            const drive: ata.Drive = @enumFromInt(@as(u1, @intCast(regs.ebx & 1)));
            regs.eax = ata.identify(drive);
        },
        21 => { // ATA_READ_SECTOR(EBX = drive, ECX = lba, EDX = buf)
            const drive: ata.Drive = @enumFromInt(@as(u1, @intCast(regs.ebx & 1)));
            const lba: u32 = regs.ecx;
            const ptr = @as([*]u8, @ptrFromInt(regs.edx));
            // Validate user pointer (sector is 512 bytes)
            if (is_user_ptr(regs.edx) and is_user_ptr(regs.edx + 511)) {
                ata.read_sector(drive, lba, ptr);
            } else {
                common.printError("[Security Fault] Invalid buffer pointer for ATA Read\n");
            }
        },
        22 => { // ATA_WRITE_SECTOR(EBX = drive, ECX = lba, EDX = data)
            const drive: ata.Drive = @enumFromInt(@as(u1, @intCast(regs.ebx & 1)));
            const lba: u32 = regs.ecx;
            const ptr = @as([*]const u8, @ptrFromInt(regs.edx));
            // Validate user pointer (sector is 512 bytes)
            if (is_user_ptr(regs.edx) and is_user_ptr(regs.edx + 511)) {
                ata.write_sector(drive, lba, ptr);
            } else {
                common.printError("[Security Fault] Invalid data pointer for ATA Write\n");
            }
        },
        else => {
            common.printZ("Unknown syscall from user mode\n");
        },
    }
}

// Link to the assembly implementation
extern fn jump_to_ring3_entry(entry: usize, stack: usize) noreturn;

pub fn jump_to_user_mode() noreturn {
    jump_to_user_mode_with_entry(@intFromPtr(&kernel_loop));
}

pub fn jump_to_user_mode_with_entry(entry: usize) noreturn {
    is_user_mode = true;

    // Ensure TSS is ready for interrupts coming from Ring 3
    exceptions.main_tss.ss0 = 0x10;
    exceptions.main_tss.esp0 = 0x500000;

    // Check if we are already in Ring 3
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 3) {
        // Use syscall 12 to jump to a new entry point
        asm volatile ("int $0x80"
            :
            : [sys] "{eax}" (@as(u32, 12)),
              [ent] "{ebx}" (entry),
        );
        unreachable;
    }

    // --- Dynamic User Stack Allocation ---
    // Instead of a shared 0x3FFFF0, we allocate a fresh physical page
    // and map it to a specific virtual address per transition.
    const stack_paddr = memory.pmm.alloc_page() orelse @panic("OOM: Failed to allocate user stack page");
    // We'll use 0x3FF000 as the virtual base for the stack page
    const stack_vaddr = 0x3FF000;
    _ = memory.map_page_at(stack_vaddr, stack_paddr, true);

    // Top of stack (16-byte aligned for entry point)
    const user_esp = stack_vaddr + memory.PAGE_SIZE - 16;

    // Call the stable assembly transition with entry and stack
    jump_to_ring3_entry(entry, user_esp);
}
