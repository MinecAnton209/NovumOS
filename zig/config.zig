const std = @import("std");
const kconfig = @import("kconfig.zig");
const build_config = @import("build_config");

pub const schema = @import("config_schema.zig").schema;

const config_text: []const u8 = build_config.config_text;

fn value(comptime T: type, comptime name: []const u8) T {
    return kconfig.value(T, &schema, config_text, name);
}

pub const USE_GARBAGE_COLLECTOR = value(bool, "USE_GARBAGE_COLLECTOR");
pub const HEAP_INITIAL_SIZE = value(u32, "HEAP_INITIAL_SIZE");
pub const HISTORY_SIZE = value(u32, "HISTORY_SIZE");
pub const ENABLE_DISK_HISTORY = value(bool, "ENABLE_DISK_HISTORY");
pub const ENABLE_DEBUG_CRASH_COMMANDS = value(bool, "ENABLE_DEBUG_CRASH_COMMANDS");
pub const ENABLE_DEBUG_COMMANDS = value(bool, "ENABLE_DEBUG_COMMANDS");
pub const ENABLE_EARLY_LFB_DEBUG = value(bool, "ENABLE_EARLY_LFB_DEBUG");
pub const ENABLE_SERIAL_DEBUG = value(bool, "ENABLE_SERIAL_DEBUG");
pub const ENABLE_IDT_WATCHDOG = value(bool, "ENABLE_IDT_WATCHDOG");
pub const ENABLE_IDT_WATCHDOG_SNAPSHOT = value(bool, "ENABLE_IDT_WATCHDOG_SNAPSHOT");
pub const ENABLE_RSOD_REBOOT = value(bool, "ENABLE_RSOD_REBOOT");
pub const ENABLE_EMBEDDED_ELFS = value(bool, "ENABLE_EMBEDDED_ELFS");
pub const ENABLE_FAT_DEBUG = value(bool, "ENABLE_FAT_DEBUG");
pub const ENABLE_KERNEL_LOGGING = value(bool, "ENABLE_KERNEL_LOGGING");
pub const ENABLE_BOOT_TRACE = value(bool, "ENABLE_BOOT_TRACE");
pub const ENABLE_SYSCALL_TRACE = value(bool, "ENABLE_SYSCALL_TRACE");
pub const ENABLE_SPEAKER = value(bool, "ENABLE_SPEAKER");
pub const ENABLE_BOOT_BEEP = value(bool, "ENABLE_BOOT_BEEP");
pub const ENABLE_ERROR_BEEP = value(bool, "ENABLE_ERROR_BEEP");
pub const NOVA_PATH_POLICY_ENABLED = value(bool, "NOVA_PATH_POLICY_ENABLED");
pub const NOVA_DEBUG = value(bool, "NOVA_DEBUG");
pub const MOUSE_DEBUG = value(bool, "MOUSE_DEBUG");

pub const ENABLE_QUANTUM = value(bool, "ENABLE_QUANTUM");
pub const ENABLE_DOOMFIRE = value(bool, "ENABLE_DOOMFIRE");
pub const ENABLE_MATRIX = value(bool, "ENABLE_MATRIX");
pub const ENABLE_BUILTIN_SCRIPTS = value(bool, "ENABLE_BUILTIN_SCRIPTS");
pub const ENABLE_MOUSE = value(bool, "ENABLE_MOUSE");
pub const ENABLE_SMP = value(bool, "ENABLE_SMP");
pub const ENABLE_NOVA = value(bool, "ENABLE_NOVA");
pub const ENABLE_FAT12 = value(bool, "ENABLE_FAT12");
pub const ENABLE_FAT16 = value(bool, "ENABLE_FAT16");
pub const ENABLE_FAT32 = value(bool, "ENABLE_FAT32");
pub const ENABLE_LFN = value(bool, "ENABLE_LFN");
pub const ENABLE_SERIAL_INPUT = value(bool, "ENABLE_SERIAL_INPUT");
pub const ENABLE_VGA_TEXT = value(bool, "ENABLE_VGA_TEXT");
pub const ENABLE_ACPI = value(bool, "ENABLE_ACPI");
pub const ENABLE_PCI = value(bool, "ENABLE_PCI");
pub const ENABLE_ATA = value(bool, "ENABLE_ATA");
pub const ENABLE_CLOCK_IN_PROMPT = value(bool, "ENABLE_CLOCK_IN_PROMPT");
pub const ENABLE_STATUS_INDICATORS = value(bool, "ENABLE_STATUS_INDICATORS");
pub const ENABLE_WELCOME_MESSAGE = value(bool, "ENABLE_WELCOME_MESSAGE");
pub const ENABLE_BOOT_SPINNER = value(bool, "ENABLE_BOOT_SPINNER");
pub const ENABLE_ASLR = value(bool, "ENABLE_ASLR");
pub const ENABLE_WX_SEPARATION = value(bool, "ENABLE_WX_SEPARATION");
pub const BUILD_HASH_SEED = value([]const u8, "BUILD_HASH_SEED");

/// Cryptographically random build-time seed injected by build.zig via
/// std.Io.randomSecure(). Used for watchdog scatter checks.
pub const BUILD_HASH = build_config.build_hash;
pub const WATCHDOG_INTERVAL_TICKS = 1000 + (BUILD_HASH % 500);
pub const WATCHDOG_CHANCE_ALLOC = 1 + (BUILD_HASH % 16);
pub const WATCHDOG_CHANCE_SCHED = 1 + (BUILD_HASH % 32);
pub const WATCHDOG_CHANCE_TIMER = 1 + (BUILD_HASH % 8);

test "config_text overrides schema default" {
    try std.testing.expectEqual(@as(u32, 7), HISTORY_SIZE);
}

test "field absent from config_text uses schema default" {
    try std.testing.expectEqual(false, ENABLE_SERIAL_DEBUG);
}
