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
const sysenter = @import("../arch/mod.zig").sysenter;
const idt_watchdog = @import("../arch/mod.zig").idt_watchdog;
const ata = @import("../drivers/ata.zig");
const fat = @import("../drivers/fat.zig");
const speaker = @import("../drivers/speaker.zig");
const mouse = @import("mouse.zig");
const quantum = @import("quantum.zig");
const config = @import("../config.zig");

// NovumOS Kernel - Main Zig Module
// Entry point for the Zig portion of the kernel and panic handler.

// Ensure all modules are included in the compilation
comptime {
    _ = shell_cmds;
    _ = keyboard_isr;
    if (config.ENABLE_NOVA) {
        _ = nova;
    }
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
    if (config.ENABLE_QUANTUM) {
        _ = quantum;
    }
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
    const Announce = struct {
        var done = false;
    };
    if (!Announce.done) {
        Announce.done = true;
        logger.trace("boot: shell ready");
    }
    while (true) {
        read_command();
        execute_command();
        vga.vga_flush();
    }
}

fn init_memory() void {
    memory.pmm.init();
    logger.trace("boot: PMM ready");
    memory.heap.init();
    logger.trace("boot: kernel heap ready");
    memory.init_paging();
    logger.trace("boot: demand paging ready");
}

fn init_display() void {
    timer.init();
    logger.trace("boot: PIT timer ready");
    lfb.init();
    logger.trace("boot: framebuffer ready");
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
    logger.trace("boot: probing ATA disks");
    while (boot_elapsed < 2000) {
        const now = timer.get_ticks();
        if (now - boot_last >= 10) {
            boot_last = now;
            common.print_char(boot_spinner[(boot_elapsed / 100) % 4]);
            common.print_char(8);
        }

        if (!slave_probed and ata.identify(.Slave) > 0) {
            slave_probed = true;
            logger.trace("boot: slave ATA disk found");
            if (fat.read_bpb(.Slave) != null) {
                common.selected_disk = 1;
                logger.trace("boot: slave filesystem selected");
                break;
            }
        }
        if (!master_probed and ata.identify(.Master) > 0) {
            master_probed = true;
            logger.trace("boot: master ATA disk found");
            if (fat.read_bpb(.Master) != null) {
                common.selected_disk = 0;
                logger.trace("boot: master filesystem selected");
                break;
            }
        }
        if (slave_probed and master_probed) break;
        timer.sleep(10);
        boot_elapsed += 10;
    }
    if (common.selected_disk < 0) {
        logger.trace("boot: no boot disk, RAM filesystem only");
    }
    common.fs_init();
    logger.trace("boot: fs layer ready");

    common.print_char(8);
    common.print_char(' ');
    common.print_char(8);
    vga.set_color(10, 0);
    common.printZ(" OK\n");
}

fn init_scheduler() void {
    scheduler.init();
    logger.trace("boot: scheduler ready");
    var current_esp: u32 = undefined;
    asm volatile ("mov %%esp, %[esp]"
        : [esp] "=r" (current_esp),
    );
    scheduler.bootstrap(current_esp);
}

fn init_peripherals() void {
    if (config.ENABLE_SPEAKER) {
        speaker.init();
        timer.set_tick_callback(&speaker.beep_async_tick);
        logger.trace("boot: speaker ready");
        if (config.ENABLE_BOOT_BEEP) speaker.beep(1000, 100);
    }
    if (config.ENABLE_MOUSE) {
        mouse.init();
        logger.trace("boot: mouse ready");
    }
    if (config.ENABLE_QUANTUM) {
        quantum.init();
        logger.trace("boot: quantum ready");
    }
}

/// Kernel entry point.
export fn kmain() void {
    // 1. Memory (paging, heap, PMM)
    init_memory();
    init_display();
    logger.trace("boot: display ready");

    // Fast syscalls (SYSENTER MSRs) before any Ring 3 entry
    sysenter.init_bsp();
    logger.trace("boot: sysenter MSRs programmed");

    // 2. Drivers
    common.printZ("Checking PMM: ");
    vga.set_color(10, 0);
    common.printZ("OK\n");
    if (config.ENABLE_ACPI) {
        if (acpi.init()) {
            logger.trace("boot: ACPI ready");
        } else {
            logger.trace("boot: ACPI unavailable, using defaults");
        }
    }
    init_drivers_spinner();

    // 3. File System + disk check
    if (config.ENABLE_ATA) {
        init_disk_check();
        logger.trace("boot: disks probed");
    }

    // 4. Display dimensions + welcome
    vga.init_dimensions();
    vga.clear_screen();
    vga.vga_flush();
    messages.print_welcome();
    logger.trace("boot: console ready");

    // 5. Scheduler + multicore
    init_scheduler();
    logger.trace("boot: scheduler bootstrapped");
    if (config.ENABLE_SMP) {
        smp.init();
        logger.trace("boot: SMP online");
    }
    if (config.ENABLE_IDT_WATCHDOG_SNAPSHOT) {
        idt_watchdog.save_snapshot();
        logger.trace("boot: IDT snapshot saved");
    }

    // 6. Peripherals + user mode
    init_peripherals();
    logger.trace("boot: peripherals ready");
    logger.trace("boot: entering Ring 3 shell");
    user.jump_to_user_mode_with_entry(@intFromPtr(&kernel_loop), true);
}
