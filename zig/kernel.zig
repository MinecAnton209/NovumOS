// NovumOS Kernel - Main Zig Module
// Entry point for the Zig portion of the kernel and panic handler.

const shell_cmds = @import("shell_cmds.zig");
const keyboard_isr = @import("keyboard_isr.zig");
const nova = @import("nova.zig");
const common = @import("commands/common.zig");
const shell = @import("shell.zig");
const messages = @import("messages.zig");
const timer = @import("drivers/timer.zig");
const acpi = @import("drivers/acpi.zig");
const memory = @import("memory.zig");
const exceptions = @import("exceptions.zig");
const smp = @import("smp.zig");

// Ensure all modules are included in the compilation
comptime {
    _ = shell_cmds;
    _ = keyboard_isr;
    _ = nova;
    _ = shell;
    _ = messages;
    _ = timer;
    _ = acpi;
    _ = memory;
    _ = exceptions;
    _ = smp;
    _ = @import("drivers/vga.zig");
}

// External shell functions (exported by shell.zig)
extern fn read_command() void;
extern fn execute_command() void;

/// Kernel Panic Handler (exported for ASM use)
export fn kernel_panic(msg_ptr: [*]const u8, msg_len: usize) noreturn {
    exceptions.panic(msg_ptr[0..msg_len]);
}

/// Main Panic Handler - Stops execution and displays an error message
pub fn panic(msg: []const u8) noreturn {
    exceptions.panic(msg);
}

// --- Kernel Entry Point ---
export fn kmain() void {
    // 1. Initialize PMM & Heap
    memory.pmm.init();
    memory.heap.init();
    memory.init_paging();

    // 2. Initialize timer and interrupt controllers
    // Initialize file system
    shell_cmds.zig_init();

    // Initialize system timer
    timer.init();

    // Initialize ACPI (for proper shutdown)
    _ = acpi.init();

    // Initialize Dumb SMP (Kick Core 1)
    smp.init();

    // Main Shell loop
    while (true) {
        read_command();
        execute_command();
    }
}
