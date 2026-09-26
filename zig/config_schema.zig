const kconfig = @import("kconfig.zig");

pub const k = kconfig;

pub const schema = [_]kconfig.Field{
    .{
        .name = "USE_GARBAGE_COLLECTOR",
        .default = .{ .bool = false },
        .help = "Build-time garbage collector support",
        .desc = "Enables automated garbage collection for kernel heap allocations. When enabled, dynamic memory uses tracking and collection passes to automatically reclaim unused allocations.",
    },
    .{
        .name = "HEAP_INITIAL_SIZE",
        .default = .{ .int = 1024 * 1024 },
        .help = "Initial kernel heap size (bytes)",
        .desc = "Specifies the initial contiguous physical memory size reserved for the kernel heap allocator at boot time. Default is 1048576 bytes (1 MiB). Increase this if memory allocations fail during early initialization.",
    },
    .{
        .name = "HISTORY_SIZE",
        .default = .{ .int = 50 },
        .help = "Shell command history buffer capacity",
        .desc = "Defines the maximum number of previously executed command lines stored in the interactive shell scrollback history buffer. Accessible via Up/Down arrow keys.",
    },
    .{
        .name = "ENABLE_DEBUG_CRASH_COMMANDS",
        .default = .{ .bool = true },
        .help = "Kernel crash test commands (panic, div0, pf)",
        .desc = "Enables intentional crash commands in the interactive shell (such as panic, div0, and pagefault) to test fault handling, stack unwinding, and kernel recovery routines.",
    },
    .{
        .name = "ENABLE_DEBUG_COMMANDS",
        .default = .{ .bool = true },
        .help = "Kernel inspection & debug shell commands",
        .desc = "Enables diagnostic shell utilities for inspecting CPU registers, memory mappings, GDT/IDT descriptors, and process execution state.",
    },
    .{
        .name = "ENABLE_EARLY_LFB_DEBUG",
        .default = .{ .bool = false },
        .help = "Early Linear Framebuffer (LFB) boot test pattern",
        .desc = "Draws a diagnostic color test pattern on the linear framebuffer immediately after Multiboot2 video info is obtained, verifying graphics mode switching before full console initialization.",
    },
    .{
        .name = "ENABLE_SERIAL_DEBUG",
        .default = .{ .bool = false },
        .help = "COM1 serial port logging (115200 8N1)",
        .desc = "Directs all low-level kernel log messages and register dumps to the primary serial port COM1 (0x3F8). Recommended when running inside QEMU with -serial stdio.",
    },
    .{
        .name = "ENABLE_IDT_WATCHDOG",
        .default = .{ .bool = true },
        .help = "Interrupt Descriptor Table (IDT) integrity watchdog",
        .desc = "Periodically validates the hardware IDT gates and descriptor addresses to detect stack corruptions or unauthorized descriptor modifications.",
    },
    .{
        .name = "ENABLE_RSOD_REBOOT",
        .default = .{ .bool = true },
        .help = "Automatic reboot after Red Screen of Death",
        .desc = "Enables automatic system reset after a kernel panic / Red Screen of Death crash screen is displayed. If disabled, the system will halt and remain on the crash screen.",
    },
    .{
        .name = "ENABLE_EMBEDDED_ELFS",
        .default = .{ .bool = false },
        .help = "Embed user-mode ELF binaries in kernel image",
        .desc = "Embeds precompiled static user ELF binaries directly into kernel read-only data sections so they can be launched without requiring an underlying disk filesystem.",
    },
    .{
        .name = "ENABLE_FAT_DEBUG",
        .default = .{ .bool = false },
        .help = "FAT12/16/32 filesystem debug logging",
        .desc = "Enables verbose diagnostic output during BPB parsing, FAT cluster traversal, directory entry lookups, and file read operations.",
    },
    .{
        .name = "ENABLE_KERNEL_LOGGING",
        .default = .{ .bool = false },
        .help = "Informational kernel ring buffer logging",
        .desc = "Enables the in-memory circular log ring buffer and formatted log levels (INFO, WARN, ERROR, DEBUG) for runtime inspection.",
    },
    .{
        .name = "ENABLE_SPEAKER",
        .default = .{ .bool = true },
        .help = "PC speaker audio hardware support",
        .desc = "Enables the motherboard PC speaker driver via PIT channel 2 (port 0x61/0x42) for acoustic tones and sound effects.",
    },
    .{
        .name = "ENABLE_BOOT_BEEP",
        .default = .{ .bool = true },
        .help = "Audible confirmation tone on boot",
        .desc = "Plays a short confirmation beep through the PC speaker when the kernel completes fundamental subsystem initialization.",
    },
    .{
        .name = "ENABLE_ERROR_BEEP",
        .default = .{ .bool = true },
        .help = "Audible alarm tone on kernel panics & errors",
        .desc = "Plays an acoustic warning pattern via the PC speaker when an unhandled exception, assertion failure, or kernel panic occurs.",
    },
    .{
        .name = "NOVA_PATH_POLICY_ENABLED",
        .default = .{ .bool = true },
        .help = "Nova path policy validation (CVE-2026-40573)",
        .desc = "Enforces strict canonical path checks and directory traversal mitigations in the Nova runtime to prevent CVE-2026-40573 security bypasses.",
    },
    .{
        .name = "NOVA_DEBUG",
        .default = .{ .bool = true },
        .help = "Nova VM & bytecode execution tracing",
        .desc = "Enables detailed instruction-level tracing, AST evaluation logs, and runtime memory allocation dumps for Nova language scripts.",
    },
    .{
        .name = "MOUSE_DEBUG",
        .default = .{ .bool = true },
        .help = "PS/2 mouse initialization & packet logs",
        .desc = "Prints raw byte packets, acknowledge responses, and IRQ12 interrupt delivery events during PS/2 auxiliary mouse setup.",
    },
    .{
        .name = "ENABLE_QUANTUM",
        .default = .{ .bool = true },
        .help = "Kernel quantum circuit simulation engine",
        .desc = "Enables the in-kernel quantum state vector simulator and quantum shell commands (qrun, qstate, qgate) for running quantum algorithms.",
    },
    .{
        .name = "ENABLE_DOOMFIRE",
        .default = .{ .bool = true },
        .help = "DOOM procedural fire visual demo command",
        .desc = "Enables the classic DOOM PSX procedural fire particle simulation effect in the graphical terminal console.",
    },
    .{
        .name = "ENABLE_BUILTIN_SCRIPTS",
        .default = .{ .bool = true },
        .help = "Embedded Nova scripts (hello, syscheck)",
        .desc = "Includes built-in diagnostic and demo Nova scripts directly in the kernel image, accessible via the shell without mounting a disk.",
    },
    .{
        .name = "ENABLE_MOUSE",
        .default = .{ .bool = true },
        .help = "PS/2 mouse driver & cursor subsystem",
        .desc = "Enables the PS/2 mouse hardware driver, interrupt handler (IRQ12), coordinate tracking, and visual mouse cursor rendering.",
    },
    .{
        .name = "ENABLE_SMP",
        .default = .{ .bool = true },
        .help = "Symmetric Multiprocessing (SMP) multicore support",
        .desc = "Enables MADT table parsing, Local APIC setup, AP trampoline startup, inter-processor interrupts (IPIs), and multicore execution.",
    },
    .{
        .name = "ENABLE_NOVA",
        .default = .{ .bool = true },
        .help = "Nova programming language runtime environment",
        .desc = "Enables the core Nova language interpreter, memory runtime, embedded userspace ELF loader, and interactive scripting engine.",
    },
};
