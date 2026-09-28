// Stub exposing `config` and `logger` for host-testing gdt.zig.
pub const ENABLE_WX_SEPARATION = false;

pub fn trace(msg: []const u8) void { _ = msg; }
