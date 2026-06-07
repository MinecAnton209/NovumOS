const common = @import("commands/common.zig");
const exceptions = @import("exceptions.zig");
const smp = @import("smp.zig");
const keyboard = @import("keyboard_isr.zig");
const vga = @import("drivers/vga.zig");
const timer = @import("drivers/timer.zig");
const memory = @import("memory.zig");
const logger = @import("logger.zig");
const ata = @import("drivers/ata.zig");
const rtc = @import("drivers/time/time.zig");
const config = @import("config.zig");
const speaker = @import("drivers/speaker.zig");
const syscalls = @import("syscalls/mod.zig");

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

// (is_user_mode now stored in smp.cores[id])
pub fn get_is_user_mode() bool {
    return smp.cores[exceptions.get_core_index()].is_user_mode;
}

pub fn set_is_user_mode(val: bool) void {
    smp.cores[exceptions.get_core_index()].is_user_mode = val;
}

pub fn get_is_privileged() bool {
    return smp.cores[exceptions.get_core_index()].is_privileged;
}

pub fn set_is_privileged(val: bool) void {
    smp.cores[exceptions.get_core_index()].is_privileged = val;
}

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

pub fn checkPrivilege(regs: *Registers, action: []const u8) bool {
    _ = regs;
    if (!get_is_privileged()) {
        logger.security(action); // Log the unauthorized action
        return false;
    }
    return true;
}

// System call handler exported for linker
export fn handle_syscall_zig(regs: *Registers) void {
    syscalls.dispatch(regs);
}

/// Thread-safe and ISR-safe malloc for User and Kernel mode.
/// If in Ring 3, it performs a syscall to transition to Ring 0.
pub fn user_malloc(size: usize) ?[*]u8 {
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 0) return memory.heap.alloc(size); // Already in Ring 0

    var res: usize = 0;
    asm volatile ("int $0x80"
        : [ret] "={eax}" (res),
        : [sys] "{eax}" (@as(u32, 30)),
          [arg1] "{ebx}" (size),
        : .{ .memory = true });
    if (res == 0) return null;
    return @ptrFromInt(res);
}

/// Thread-safe and ISR-safe free for User and Kernel mode.
pub fn user_free(ptr: ?[*]u8) void {
    const p = ptr orelse return;
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 0) {
        memory.heap.free(p);
        return;
    }

    asm volatile ("int $0x80"
        :
        : [sys] "{eax}" (@as(u32, 31)),
          [arg1] "{ebx}" (@intFromPtr(p)),
        : .{ .memory = true });
}

// Link to the assembly implementation
extern fn jump_to_ring3_entry(entry: usize, stack: usize, eflags: u32) noreturn;

pub fn jump_to_user_mode() noreturn {
    jump_to_user_mode_with_entry(@intFromPtr(&kernel_loop), true);
}

pub fn jump_to_user_mode_with_entry(entry: usize, privileged: bool) noreturn {
    set_is_user_mode(true);
    set_is_privileged(privileged);

    // Ensure current core's TSS is ready for interrupts coming from user-space
    const core_idx = exceptions.get_core_index();
    const tss = &exceptions.cores_tss[core_idx];
    tss.ss0 = 0x10;

    // BSP uses 0x500000, APs use their respective allocated stacks
    if (core_idx == 0) {
        tss.esp0 = 0x500000;
    } else {
        const smp_mod = @import("smp.zig");
        tss.esp0 = @intFromPtr(&smp_mod.ap_stacks[core_idx - 1]) + 8192;
    }

    // Check if we are already in Ring 3
    var cs_reg: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs_reg),
    );
    if ((cs_reg & 3) == 3) {
        // Use syscall 12 to jump to a new entry point
        asm volatile ("int $0x80"
            :
            : [sys] "{eax}" (@as(u32, 12)),
              [ent] "{ebx}" (entry),
        );
        unreachable;
    }

    // --- Dynamic User Stack Allocation ---
    // We'll use 0x3FF000 as the virtual base for the stack page
    const stack_vaddr = 0x3FF000;
    const pd_idx = stack_vaddr >> 22;
    const pt_idx = (stack_vaddr >> 12) & 0x3FF;

    var stack_paddr: usize = 0;
    if (memory.page_tables[pd_idx]) |pt| {
        if ((pt[pt_idx] & 1) != 0) {
            stack_paddr = pt[pt_idx] & 0xFFFFF000;
        }
    }

    if (stack_paddr == 0) {
        stack_paddr = memory.pmm.alloc_page() orelse @panic("OOM: Failed to allocate user stack page");
        _ = memory.map_page_at(stack_vaddr, stack_paddr, true);
    }

    // Zero out the stack to avoid artifacts from previous runs
    @memset(@as([*]u8, @ptrFromInt(stack_vaddr))[0..memory.PAGE_SIZE], 0);

    // Top of stack (16-byte aligned for entry point)
    const user_esp = stack_vaddr + memory.PAGE_SIZE - 16;

    // Call the stable assembly transition with entry, stack and eflags
    // Privileged processes get IOPL=3 (0x3000)
    const eflags: u32 = if (privileged) 0x3202 else 0x0202;
    jump_to_ring3_entry(entry, user_esp, eflags);
}
