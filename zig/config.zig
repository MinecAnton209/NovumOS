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
pub const ENABLE_DEBUG_CRASH_COMMANDS = value(bool, "ENABLE_DEBUG_CRASH_COMMANDS");
pub const ENABLE_DEBUG_COMMANDS = value(bool, "ENABLE_DEBUG_COMMANDS");
pub const ENABLE_EARLY_LFB_DEBUG = value(bool, "ENABLE_EARLY_LFB_DEBUG");
pub const ENABLE_SERIAL_DEBUG = value(bool, "ENABLE_SERIAL_DEBUG");
pub const ENABLE_IDT_WATCHDOG = value(bool, "ENABLE_IDT_WATCHDOG");
pub const ENABLE_RSOD_REBOOT = value(bool, "ENABLE_RSOD_REBOOT");
pub const ENABLE_EMBEDDED_ELFS = value(bool, "ENABLE_EMBEDDED_ELFS");
pub const ENABLE_FAT_DEBUG = value(bool, "ENABLE_FAT_DEBUG");
pub const ENABLE_KERNEL_LOGGING = value(bool, "ENABLE_KERNEL_LOGGING");
pub const ENABLE_SPEAKER = value(bool, "ENABLE_SPEAKER");
pub const ENABLE_BOOT_BEEP = value(bool, "ENABLE_BOOT_BEEP");
pub const ENABLE_ERROR_BEEP = value(bool, "ENABLE_ERROR_BEEP");
pub const NOVA_PATH_POLICY_ENABLED = value(bool, "NOVA_PATH_POLICY_ENABLED");
pub const NOVA_DEBUG = value(bool, "NOVA_DEBUG");
pub const MOUSE_DEBUG = value(bool, "MOUSE_DEBUG");

pub const BUILD_HASH = 0xDEADC0DE ^ 0xCAFEBABE ^ 0x12345678;
pub const WATCHDOG_INTERVAL_TICKS = 1000 + (BUILD_HASH % 500);
pub const WATCHDOG_CHANCE_ALLOC = 1 + (BUILD_HASH % 16);
pub const WATCHDOG_CHANCE_SCHED = 1 + (BUILD_HASH % 32);
pub const WATCHDOG_CHANCE_TIMER = 1 + (BUILD_HASH % 8);
