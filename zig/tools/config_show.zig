// `zig build config` — print resolved kernel configuration.
const std = @import("std");
const schema = @import("config_schema").schema;
const config = @import("build_config");
const kconfig = @import("kconfig");

const Resolved = union(enum) { bool_val: bool, int_val: u32, str_val: []const u8 };

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var stdout_buf: [1024]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &stdout_buf);
    const stdout = &writer.interface;
    const cfg = config.config_text;

    if (kconfig.validate(&schema, cfg)) |diag| {
        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "invalid config: line {d}: {s} key '{s}' detail '{s}'\n",
            .{ diag.line, @tagName(diag.kind), diag.key, diag.detail });
        try stdout.writeAll(msg);
        return;
    }

    for (schema) |f| {
        var key_buf: [128]u8 = undefined;
        const full_key = try std.fmt.bufPrint(&key_buf, "CONFIG_{s}", .{f.name});
        const val = resolveValue(f, cfg, full_key);
        try stdout.print("{s}=", .{full_key});
        const line = try fmtLine(val, std.heap.page_allocator);
        try stdout.print("{s}  # {s}\n", .{ line, f.help });
    }
}

fn resolveValue(f: kconfig.Field, cfg: []const u8, full_key: []const u8) Resolved {
    var line_it = std.mem.splitScalar(u8, cfg, '\n');
    while (line_it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t\r");
        if (!std.mem.eql(u8, key, full_key)) continue;
        const val = std.mem.trim(u8, line[eq + 1 ..], " \t\r");
        return parseValue(f.default, val);
    }
    return parseDefault(f);
}

fn parseValue(default: kconfig.Option, val: []const u8) Resolved {
    return switch (default) {
        .bool => .{ .bool_val = std.mem.eql(u8, val, "y") },
        .int => .{ .int_val = std.fmt.parseInt(u32, val, 10) catch 0 },
        .str => .{ .str_val = val },
    };
}

fn parseDefault(f: kconfig.Field) Resolved {
    return switch (f.default) {
        .bool => |b| .{ .bool_val = b },
        .int => |v| .{ .int_val = v },
        .str => |s| .{ .str_val = s },
    };
}

fn fmtLine(r: Resolved, allocator: std.mem.Allocator) ![]const u8 {
    return switch (r) {
        .bool_val => |b| if (b) "y" else "n",
        .int_val => |v| try std.fmt.allocPrint(allocator, "{}", .{v}),
        .str_val => |s| s,
    };
}
