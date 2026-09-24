// zig/path_policy.zig
// Path whitelist/blocklist for untrusted ELFs (Nova in Ring 3).
// When NOVA_PATH_POLICY_ENABLED, blocks access to sensitive paths.
// Gated by config.NOVA_PATH_POLICY_ENABLED kill-switch.

const config = @import("../config.zig");
const logger = @import("logger.zig");
const common = @import("../commands/common.zig");

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

/// Canonicalize the way drivers/fat resolve_path does: `\` is a
/// separator, repeated separators collapse, `.` components vanish.
/// `..` is rejected outright — resolve pops it, so a raw prefix match
/// on "foo/../.SYSTEM/" would never see the blocked prefix. Returns
/// null when the path cannot be represented (fail closed).
fn canonicalize(path: []const u8, out: []u8) ?[]const u8 {
    var len: usize = 0;
    var i: usize = 0;

    const rooted = path.len > 0 and (path[0] == '/' or path[0] == '\\');
    if (rooted) {
        out[0] = '/';
        len = 1;
    }

    while (i < path.len) {
        while (i < path.len and (path[i] == '/' or path[i] == '\\')) : (i += 1) {}
        if (i >= path.len) break;

        const start = i;
        while (i < path.len and path[i] != '/' and path[i] != '\\') : (i += 1) {}
        const comp = path[start..i];

        if (common.std_mem_eql(comp, ".")) continue;
        if (common.std_mem_eql(comp, "..")) return null;

        if (len > 0 and out[len - 1] != '/') {
            if (len >= out.len) return null;
            out[len] = '/';
            len += 1;
        }
        if (len + comp.len > out.len) return null;
        @memcpy(out[len..len + comp.len], comp);
        len += comp.len;
    }

    return out[0..len];
}

/// Returns true if the path is allowed (not blocked), false if blocked.
/// When NOVA_PATH_POLICY_ENABLED is false, always returns true (kill-switch).
pub fn is_path_allowed(path: []const u8) bool {
    if (!config.NOVA_PATH_POLICY_ENABLED) return true;

    var canon_buf: [256]u8 = undefined;
    const canon = canonicalize(path, &canon_buf) orelse {
        logger.security("Path policy: unresolvable path");
        return false;
    };

    for (BLOCKED_EXACT) |blocked| {
        if (common.std_mem_eql(canon, blocked)) {
            logger.security("Path policy: blocked exact path");
            return false;
        }
    }

    for (BLOCKED_PREFIXES) |prefix| {
        if (common.startsWith(canon, prefix)) {
            logger.security("Path policy: blocked prefix path");
            return false;
        }
    }

    return true;
}
