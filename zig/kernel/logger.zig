const common = @import("../commands/common.zig");
const vga = @import("../drivers/vga.zig");
const config = @import("../config.zig");

// NovumOS Kernel Logger
// Provides colored, formatted, and toggleable logging for system events.

pub const Level = enum {
    INFO,
    SUCCESS,
    WARN,
    ERROR,
    DEBUG,
};

/// Internal shared printing function
///
/// INTERRUPT-SAFE INVARIANT: logging is reachable from schedule()
/// (timer ISR) through heap/pmm error paths. Nothing here may do sti,
/// sleep, vsync or otherwise wait on interrupts — printZ must keep
/// going through the flush-free zig_print_char, and ISR-reachable log
/// calls must stay minimal: the vga_lock spin self-deadlocks if the
/// ISR interrupts a ring 3 print that already holds it (ring 3 prints
/// do not cli).
fn internal_log(level: Level, prefix: []const u8, msg: []const u8) void {
    if (!config.ENABLE_KERNEL_LOGGING) return;

    // Set color based on level
    const original_color = vga.current_color;
    switch (level) {
        .INFO => vga.set_color(11, 0), // Light Cyan
        .SUCCESS => vga.set_color(10, 0), // Light Green
        .WARN => vga.set_color(14, 0), // Yellow
        .ERROR => vga.set_color(12, 0), // Light Red
        .DEBUG => vga.set_color(13, 0), // Light Magenta
    }

    common.printZ(prefix);
    vga.set_color(15, 0); // Reset to White for the message
    common.printZ(msg);
    common.printZ("\n");

    // Restore original color
    vga.set_color(@intCast((original_color >> 8) & 0x0F), @intCast((original_color >> 12) & 0x0F));
}

pub fn info(msg: []const u8) void {
    internal_log(.INFO, "[ Kernel ] ", msg);
}

pub fn success(msg: []const u8) void {
    internal_log(.SUCCESS, "[   OK   ] ", msg);
}

pub fn warn(msg: []const u8) void {
    internal_log(.WARN, "[  WARN  ] ", msg);
}

pub fn err(msg: []const u8) void {
    internal_log(.ERROR, "[ ERROR  ] ", msg);
}

/// Same interrupt-safety invariant as internal_log: reachable from the
/// timer ISR via heap/pmm error paths — no sti, sleep or vsync here.
pub fn security(msg: []const u8) void {
    if (!config.ENABLE_KERNEL_LOGGING) return;
    vga.set_color(12, 0);
    common.printZ("[SECURITY] ");
    vga.set_color(15, 0);
    common.printZ(msg);
    common.printZ("\n");
}

pub fn debug(msg: []const u8) void {
    if (config.ENABLE_DEBUG_COMMANDS) {
        internal_log(.DEBUG, "[ DEBUG  ] ", msg);
    }
}
