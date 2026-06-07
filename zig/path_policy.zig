// zig/path_policy.zig
// Path whitelist/blocklist for untrusted ELFs (Nova in Ring 3).
// When NOVA_PATH_POLICY_ENABLED, blocks access to sensitive paths.
// Gated by config.NOVA_PATH_POLICY_ENABLED kill-switch.

const config = @import("config.zig");
const logger = @import("logger.zig");
const common = @import("commands/common.zig");

/// Prefixes that are always blocked for untrusted processes
const BLOCKED_PREFIXES = [_][]const u8{
    "/boot/",
    "/.SYSTEM/",
    "/EFI/",
    "/initrd/",
    "/zig/",
};

/// Exact paths (filenames) that are always blocked regardless of prefix
const BLOCKED_EXACT = [_][]const u8{
    "/kernel.zig",
    "/user.zig",
    "/shell.zig",
    "/memory.zig",
    "/elf.zig",
    "/kernel.bin",
    "/novum.bin",
};

/// Returns true if the path is allowed (not blocked), false if blocked.
/// When NOVA_PATH_POLICY_ENABLED is false, always returns true (kill-switch).
pub fn is_path_allowed(path: []const u8) bool {
    if (!config.NOVA_PATH_POLICY_ENABLED) return true;

    for (BLOCKED_EXACT) |blocked| {
        if (common.std_mem_eql(path, blocked)) {
            logger.security("Path policy: blocked exact path");
            return false;
        }
    }

    for (BLOCKED_PREFIXES) |prefix| {
        if (common.startsWith(path, prefix)) {
            logger.security("Path policy: blocked prefix path");
            return false;
        }
    }

    return true;
}
