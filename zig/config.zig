// NovumOS Global Configuration
pub const USE_GARBAGE_COLLECTOR = false; // Build-time toggle for GC
pub const HEAP_INITIAL_SIZE = 1024 * 1024; // 1MB initial kernel heap
pub const HISTORY_SIZE = 50; // Default history size
pub const ENABLE_DEBUG_CRASH_COMMANDS = true;
pub const ENABLE_DEBUG_COMMANDS = true;
pub const ENABLE_EARLY_LFB_DEBUG = false; // Print pattern to LFB at boot (from Multiboot2 fb)
pub const ENABLE_SERIAL_DEBUG = false; // Serial debug output (DKPCG...)
pub const ENABLE_IDT_WATCHDOG = true; // Watchdog to check IDT integrity periodically
pub const ENABLE_RSOD_REBOOT = true;
pub const ENABLE_EMBEDDED_ELFS = false;
pub const ENABLE_KERNEL_LOGGING = false; // Toggle for informative kernel logs

// Computetime randomization for watchdog timing (obfuscated)
pub const BUILD_HASH = 0xDEADC0DE ^ 0xCAFEBABE ^ 0x12345678;
pub const WATCHDOG_INTERVAL_TICKS = 1000 + (BUILD_HASH % 500); // 1000-1500
pub const WATCHDOG_CHANCE_ALLOC = 1 + (BUILD_HASH % 16); // 1-16
pub const WATCHDOG_CHANCE_SCHED = 1 + (BUILD_HASH % 32); // 1-32
pub const WATCHDOG_CHANCE_TIMER = 1 + (BUILD_HASH % 8); // 1-8

// PC Speaker configuration
pub const ENABLE_SPEAKER = true;
pub const ENABLE_BOOT_BEEP = true;
pub const ENABLE_ERROR_BEEP = true;
pub const ENABLE_NOTIFICATION_BEEP = true;

// Nova (CVE-2026-40573 mitigation)
pub const NOVA_PATH_POLICY_ENABLED = true; // Kill-switch for path policy
pub const NOVA_DEBUG = false; // Nova debug logging
