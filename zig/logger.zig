// NovumOS Kernel Logger
// Provides colored, formatted, and toggleable logging for system events.

const common = @import("commands/common.zig");
const vga = @import("drivers/vga.zig");
const config = @import("config.zig");

pub const Level = enum {
    INFO,
    SUCCESS,
    WARN,
    ERROR,
    DEBUG,
};

/// Internal shared printing function
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
