// Host-test stub for zig/drivers/vga.zig: colors have no effect on host tests.
pub fn set_color(fg: u8, bg: u8) void {
    _ = fg;
    _ = bg;
}

pub fn reset_color() void {}
