// Stub logger module for host testing path_policy.zig
// path_policy.zig calls logger.security() for blocked path logs.
pub fn security(msg: []const u8) void {
    _ = msg;
}
