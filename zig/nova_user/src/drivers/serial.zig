// compat: serial stubs (not available from Ring 3)
pub fn serial_hide_cursor() void {}
pub fn serial_set_cursor(_: u8, _: u8) void {}
pub fn serial_print_str(_: []const u8) void {}
pub fn serial_clear_line() void {}
pub fn serial_show_cursor() void {}
