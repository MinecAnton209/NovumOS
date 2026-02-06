// System Messages Module
const common = @import("commands/common.zig");
const versioning = @import("versioning.zig");

/// Print welcome banner
pub export fn print_welcome() void {
    common.printZ("=== NovumOS v" ++ versioning.NOVUMOS_VERSION ++ " 32-bit Console ===\n");
    common.printZ("Type \"help\" for commands\n\n");
}
