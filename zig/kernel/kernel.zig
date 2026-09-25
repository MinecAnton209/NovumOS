// NovumOS Kernel - Main Zig Module
// Entry point for the Zig portion of the kernel and panic handler.

const shell_cmds = @import("../shell/shell_cmds.zig");
const keyboard_isr = @import("../arch/mod.zig").keyboard_isr;
const nova = @import("nova.zig");
const common = @import("../commands/common.zig");
const shell = @import("../shell/shell.zig");
const messages = @import("messages.zig");
const timer = @import("../drivers/timer.zig");
const acpi = @import("../drivers/acpi.zig");
const memory = @import("memory.zig");
const lfb = @import("../drivers/lfb.zig");
const vga = @import("../drivers/vga.zig");
const exceptions = @import("../arch/mod.zig").exceptions;
const smp = @import("../arch/mod.zig").smp;
const libc_stubs = @import("libc_stubs.zig");
const logger = @import("logger.zig");
const user = @import("../arch/mod.zig").user;
const idt_watchdog = @import("../arch/mod.zig").idt_watchdog;
const ata = @import("../drivers/ata.zig");
const fat = @import("../drivers/fat.zig");
const speaker = @import("../drivers/speaker.zig");
const mouse = @import("mouse.zig");
const quantum = @import("quantum.zig");
const config = @import("../config.zig");

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
    _ = @import("../arch/mod.zig").user;
    _ = @import("../drivers/vga.zig");
    _ = speaker;
    _ = mouse;
    _ = quantum;
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

/// Main Kernel Loop - Exported for re-entry from User Mode
pub export fn kernel_loop() noreturn {
    while (true) {
        read_command();
        execute_command();
        vga.vga_flush();
    }
}

fn init_memory() void {
    memory.pmm.init();
    memory.heap.init();
    memory.init_paging();
}

fn init_display() void {
    timer.init();
    lfb.init();
    vga.clear_screen();
    vga.set_color(11, 0);
    common.printZ("\nInitializing NovumOS Kernel...\n\n");
}

fn init_drivers_spinner() void {
    vga.set_color(15, 0);
    common.printZ("Loading drivers:");
    vga.set_color(10, 0);
    vga.vga_flush();
    const spinner = [_]u8{ '|', '/', '-', '\\' };
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        common.set_cursor(2, 17);
        common.print_char(spinner[i % 4]);
    }
}

fn init_disk_check() void {
    vga.set_color(15, 0);
    common.printZ("Checking disks: ");
    vga.vga_flush();

    const boot_spinner = [_]u8{ '|', '/', '-', '\\' };
    var boot_elapsed: usize = 0;
    var boot_last: usize = 0;

    // Probe both Master and Slave in a short loop (≤2s).
    // Select whichever has a valid BPB; prefer Slave to match legacy behavior.
    var master_probed = false;
    var slave_probed = false;
    while (boot_elapsed < 2000) {
        const now = timer.get_ticks();
        if (now - boot_last >= 10) {
            boot_last = now;
            common.print_char(boot_spinner[(boot_elapsed / 100) % 4]);
            common.print_char(8);
        }

        if (!slave_probed and ata.identify(.Slave) > 0) {
            slave_probed = true;
            if (fat.read_bpb(.Slave) != null) {
                common.selected_disk = 1;
                break;
            }
        }
        if (!master_probed and ata.identify(.Master) > 0) {
            master_probed = true;
            if (fat.read_bpb(.Master) != null) {
                common.selected_disk = 0;
                break;
            }
        }
        if (slave_probed and master_probed) break;
        timer.sleep(10);
        boot_elapsed += 10;
    }
    common.fs_init();

    common.print_char(8);
    common.print_char(' ');
    common.print_char(8);
    vga.set_color(10, 0);
    common.printZ(" OK\n");
}

fn init_scheduler() void {
    scheduler.init();
    var current_esp: u32 = undefined;
    asm volatile ("mov %%esp, %[esp]"
        : [esp] "=r" (current_esp),
    );
    scheduler.bootstrap(current_esp);
}

fn init_peripherals() void {
    speaker.init();
    timer.set_tick_callback(&speaker.beep_async_tick);
    if (config.ENABLE_BOOT_BEEP) speaker.beep(1000, 100);
    mouse.init();
    quantum.init();
}

/// Kernel entry point.
export fn kmain() void {
    // 1. Memory (paging, heap, PMM)
    init_memory();
    init_display();

    // 2. Drivers
    common.printZ("Checking PMM: ");
    vga.set_color(10, 0);
    common.printZ("OK\n");
    _ = acpi.init();
    init_drivers_spinner();

    // 3. File System + disk check
    init_disk_check();

    // 4. Display dimensions + welcome
    vga.init_dimensions();
    vga.clear_screen();
    vga.vga_flush();
    messages.print_welcome();

    // 5. Scheduler + multicore
    init_scheduler();
    smp.init();
    idt_watchdog.save_snapshot();

    // 6. Peripherals + user mode
    init_peripherals();
    user.jump_to_user_mode_with_entry(@intFromPtr(&kernel_loop), true);
}
