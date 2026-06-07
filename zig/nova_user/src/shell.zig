// compat (stub) — shell_execute_literal not available from Ring 3
pub fn shell_execute_literal(cmd: []const u8) void {
    _ = cmd;
}
