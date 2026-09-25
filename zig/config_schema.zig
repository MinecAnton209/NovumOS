const kconfig = @import("kconfig.zig");

pub const schema = [_]kconfig.Field{
    .{ .name = "USE_GARBAGE_COLLECTOR", .default = .{ .bool = false }, .help = "Build-time toggle for GC" },
    .{ .name = "HEAP_INITIAL_SIZE", .default = .{ .int = 1024 * 1024 }, .help = "Initial kernel heap bytes" },
    .{ .name = "HISTORY_SIZE", .default = .{ .int = 50 }, .help = "Default history size" },
    .{ .name = "ENABLE_DEBUG_CRASH_COMMANDS", .default = .{ .bool = true }, .help = "Debug crash commands" },
    .{ .name = "ENABLE_DEBUG_COMMANDS", .default = .{ .bool = true }, .help = "Debug shell commands" },
    .{ .name = "ENABLE_EARLY_LFB_DEBUG", .default = .{ .bool = false }, .help = "Print pattern to LFB at boot (from Multiboot2 fb)" },
    .{ .name = "ENABLE_SERIAL_DEBUG", .default = .{ .bool = false }, .help = "Serial debug output (DKPCG...)" },
    .{ .name = "ENABLE_IDT_WATCHDOG", .default = .{ .bool = true }, .help = "Watchdog to check IDT integrity periodically" },
    .{ .name = "ENABLE_RSOD_REBOOT", .default = .{ .bool = true }, .help = "Reboot after red screen of death" },
    .{ .name = "ENABLE_EMBEDDED_ELFS", .default = .{ .bool = false }, .help = "Embed user ELFs in the kernel" },
    .{ .name = "ENABLE_FAT_DEBUG", .default = .{ .bool = false }, .help = "FAT driver debug prints (read_bpb/wfl/add_dir)" },
    .{ .name = "ENABLE_KERNEL_LOGGING", .default = .{ .bool = false }, .help = "Toggle for informative kernel logs" },
    .{ .name = "ENABLE_SPEAKER", .default = .{ .bool = true }, .help = "PC speaker support" },
    .{ .name = "ENABLE_BOOT_BEEP", .default = .{ .bool = true }, .help = "Beep on boot" },
    .{ .name = "ENABLE_ERROR_BEEP", .default = .{ .bool = true }, .help = "Beep on error" },
    .{ .name = "NOVA_PATH_POLICY_ENABLED", .default = .{ .bool = true }, .help = "Kill-switch for path policy (CVE-2026-40573 mitigation)" },
    .{ .name = "NOVA_DEBUG", .default = .{ .bool = true }, .help = "Nova debug logging" },
    .{ .name = "MOUSE_DEBUG", .default = .{ .bool = true }, .help = "Enable mouse debug output during init" },
};
