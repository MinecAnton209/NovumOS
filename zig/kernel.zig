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
const lfb = @import("drivers/lfb.zig");
const vga = @import("drivers/vga.zig");
const exceptions = @import("exceptions.zig");
const smp = @import("smp.zig");
const libc_stubs = @import("libc_stubs.zig");
const logger = @import("logger.zig");
const user = @import("user.zig");
const idt_watchdog = @import("idt_watchdog.zig");
const ata = @import("drivers/ata.zig");
const fat = @import("drivers/fat.zig");
const speaker = @import("drivers/speaker.zig");
const mouse = @import("mouse.zig");
const config = @import("config.zig");

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
    _ = @import("user.zig");
    _ = @import("drivers/vga.zig");
    _ = speaker;
    _ = mouse;
    _ = libc_stubs;
}

// External shell functions (exported by shell.zig)
extern fn read_command() void;
extern fn execute_command() void;

/// Kernel Panic Handler (exported for ASM use)
export fn kernel_panic(msg_ptr: [*]const u8, msg_len: usize) noreturn {
    exceptions.panic(msg_ptr[0..msg_len]);
}

/// Main Panic Handler - Stops execution and displays an error message
pub fn panic(msg: []const u8, _: ?*@import("std").builtin.StackTrace, _: ?usize) noreturn {
    exceptions.panic(msg);
}
const scheduler = @import("scheduler.zig");

// --- Kernel Entry Point ---
export fn kmain() void {
    // 1. Initialize Memory first so we can use paging, heap and LFB mapping
    memory.pmm.init();
    memory.heap.init();
    memory.init_paging();

    // 2. Initialize timer early so we can do small delays for animation
    timer.init();

    // 3. Initialize display so we can show boot progress
    lfb.init();
    vga.clear_screen();

    vga.set_color(11, 0); // Light Cyan
    common.printZ("\nInitializing NovumOS Kernel...\n\n");

    // Step 1: Memory
    vga.set_color(15, 0);
    common.printZ("Checking PMM: ");
    vga.set_color(10, 0);
    common.printZ("OK\n");

    // Step 2: Drivers
    vga.set_color(15, 0);
    common.printZ("Loading drivers:");
    vga.vga_flush();

    // Actual drivers init
    _ = acpi.init();
    const spinner = [_]u8{ '|', '/', '-', '\\' };
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        common.set_cursor(2, 17);
        common.print_char(spinner[i % 4]);
    }
    common.set_cursor(2, 17);
    vga.set_color(10, 0);
    common.printZ("OK\n");

    // Step 3: File System
    vga.set_color(15, 0);
    common.printZ("Checking disks: ");
    vga.vga_flush();

    // Boot spinner + disk check
    const boot_spinner = [_]u8{ '|', '/', '-', '\\' };
    var boot_elapsed: usize = 0;
    var boot_last: usize = 0;
    var disk_found = false;

    while (boot_elapsed < 2000) {
        const now = timer.get_ticks();
        if (now - boot_last >= 10) {
            boot_last = now;
            common.print_char(boot_spinner[(boot_elapsed / 100) % 4]);
            common.print_char(8);
        }

        const size = ata.identify(.Slave);
        if (size > 0) {
            disk_found = true;
            break;
        }
        timer.sleep(10);
        boot_elapsed += 10;
    }

    if (disk_found) {
        if (fat.read_bpb(.Slave) != null) {
            common.selected_disk = 1;
        }
    }
    common.fs_init();

    // Clear spinner and show OK
    common.print_char(8);
    common.print_char(' ');
    common.print_char(8);
    vga.set_color(10, 0);
    common.printZ(" OK\n");

    // Now init LFB dimensions
    vga.init_dimensions();

    vga.clear_screen();
    vga.vga_flush();

    // Print welcome banner in LFB
    messages.print_welcome();

    // Initialize Scheduler
    scheduler.init();
    // Get current ESP to bootstrap
    var current_esp: u32 = undefined;
    asm volatile ("mov %%esp, %[esp]"
        : [esp] "=r" (current_esp),
    );
    scheduler.bootstrap(current_esp);

    // Initialize Dumb SMP (Kick Core 1)
    smp.init();

    // Save IDT snapshot for watchdog (after all IDT setup is complete)
    idt_watchdog.save_snapshot();

    speaker.init();
    timer.set_tick_callback(&speaker.beep_async_tick);
    if (config.ENABLE_BOOT_BEEP) {
        speaker.beep(1000, 100);
    }

    // Initialize PS/2 mouse
    mouse.init();

    // Jump to Shell in Ring 3 (User Mode)
    user.jump_to_user_mode_with_entry(@intFromPtr(&kernel_loop), true);
}

/// Main Kernel Loop - Exported for re-entry from User Mode
pub export fn kernel_loop() noreturn {
    // Reset any potentially corrupted state here if needed
    // For now, just enter the shell loop
    while (true) {
        read_command();
        execute_command();
        vga.vga_flush();
    }
}
