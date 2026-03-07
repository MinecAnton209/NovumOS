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
    const pd_idx = addr >> 22;
    const pt_idx = (addr >> 12) & 0x3FF;

    // Check Page Directory Entry (PDE)
    const pde = memory.page_directory[pd_idx];
    if ((pde & 0x01) == 0) return false; // Not present
    if ((pde & 0x04) == 0) return false; // User bit must be set

    // If it's a huge page (4MB), we are done (USER bit already checked in PDE)
    if ((pde & 0x80) != 0) return true;

    // Check Page Table Entry (PTE)
    if (memory.page_tables[pd_idx]) |pt| {
        const pte = pt[pt_idx];
        return (pte & 0x01) != 0 and (pte & 0x04) != 0; // Must be present AND user
    }

    return false;
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
            jump_to_ring3_entry(regs.ebx);
        },
        13 => { // Shutdown
            common.shutdown();
        },
        14 => { // Reboot
            common.reboot();
        },
        15 => { // MemoryMapRange(EBX=addr, ECX=size)
            memory.map_range(regs.ebx, regs.ecx, true);
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
extern fn jump_to_ring3_entry(entry: usize) noreturn;
extern fn jump_to_ring3() noreturn;

pub fn jump_to_user_mode() noreturn {
    is_user_mode = true;
    exceptions.main_tss.ss0 = 0x10;
    exceptions.main_tss.esp0 = 0x500000;

    // Detect if we are already in Ring 3
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 3) {
        // Already in Ring 3, just return to loop via syscall or jump
        // For jump_to_user_mode (no entry), we can't easily jump to "nothing".
        asm volatile ("int $0x80"
            :
            : [sys] "{eax}" (@as(u32, 12)),
              [ent] "{ebx}" (@intFromPtr(&kernel_loop)),
        );
        unreachable;
    }

    jump_to_ring3();
}

pub fn jump_to_user_mode_with_entry(entry: usize) noreturn {
    is_user_mode = true;

    // Ensure TSS is ready for interrupts coming from Ring 3
    exceptions.main_tss.ss0 = 0x10;
    exceptions.main_tss.esp0 = 0x500000;

    // Detect if we are already in Ring 3
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 3) {
        // We are in Ring 3. Use syscall 12 to jump to a new entry point
        asm volatile ("int $0x80"
            :
            : [sys] "{eax}" (@as(u32, 12)),
              [ent] "{ebx}" (entry),
        );
        unreachable;
    }

    // Call the stable assembly transition
    jump_to_ring3_entry(entry);
}
