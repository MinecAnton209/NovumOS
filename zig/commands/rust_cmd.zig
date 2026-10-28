const rust_bridge = @import("../kernel/rust_bridge.zig");

pub fn execute() void {
    rust_bridge.hello();
}
