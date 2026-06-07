// compat: VGA stubs (not needed from Ring 3)
pub var current_color: u16 = 0x07;
pub fn zig_set_cursor(_: u8, _: u8) void {}
pub fn zig_get_cursor_row() u8 { return 0; }
pub fn zig_get_cursor_col() u8 { return 0; }
pub fn clear_screen() void {}
