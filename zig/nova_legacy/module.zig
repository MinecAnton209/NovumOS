// Nova Language - Module Resolver
const common = @import("common.zig");
const hash_table = @import("hash_table.zig");
const memory = @import("../memory.zig");

pub const ModuleCache = struct {
    loaded: hash_table.HashTable,

    pub fn init() ModuleCache {
        return .{
            .loaded = hash_table.HashTable.init(8),
        };
    }

    pub fn isLoaded(self: *ModuleCache, path: []const u8) bool {
        return self.loaded.get(path) != null;
    }

    pub fn markLoaded(self: *ModuleCache, path: []const u8) void {
        self.loaded.put(path, .{ .vtype = .int, .int_val = 1 });
    }

    pub fn resolvePath(current_path: []const u8, import_path: []const u8, out_buf: []u8) []const u8 {
        // Simple resolver
        // If import_path starts with /, it's absolute
        // Otherwise relative to current_path directory

        if (import_path.len > 0 and import_path[0] == '/') {
            common.copy(out_buf, import_path);
            var len = import_path.len;
            if (!common.startsWith(import_path, ".nv") and len + 3 <= out_buf.len) {
                common.copy(out_buf[len..], ".nv");
                len += 3;
            }
            return out_buf[0..len];
        }

        // Find directory of current_path
        var last_slash: usize = 0;
        var found = false;
        for (current_path, 0..) |c, i| {
            if (c == '/') {
                last_slash = i;
                found = true;
            }
        }

        var pos: usize = 0;
        if (found) {
            const dir = current_path[0 .. last_slash + 1];
            common.copy(out_buf[0..], dir);
            pos = dir.len;
        } else {
            // Default to /sys/nova/ if no path
            const base = "/sys/nova/";
            common.copy(out_buf[0..], base);
            pos = base.len;
        }

        common.copy(out_buf[pos..], import_path);
        pos += import_path.len;

        if (!common.startsWith(import_path, ".nv") and pos + 3 <= out_buf.len) {
            common.copy(out_buf[pos..], ".nv");
            pos += 3;
        }

        return out_buf[0..pos];
    }
};
