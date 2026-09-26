const std = @import("std");
const testing = std.testing;
const schema_mod = @import("config_schema");
const kconfig = schema_mod.k;

const mini = [_]kconfig.Field{
    .{ .name = "ENABLE_SERIAL_DEBUG", .default = .{ .bool = false }, .help = "serial" },
    .{ .name = "HEAP_INITIAL_SIZE", .default = .{ .int = 1024 * 1024 }, .help = "heap" },
    .{ .name = "ENABLE_TEST_DEFAULT_ON", .default = .{ .bool = true }, .help = "default on" },
};

test "replace in place keeps comments and order, missing keys appended" {
    const original =
        \\# header
        \\CONFIG_ENABLE_SERIAL_DEBUG=n
        \\
        \\CONFIG_HEAP_INITIAL_SIZE=1048576
        \\
    ;
    const values = [_]kconfig.Option{ .{ .bool = true }, .{ .int = 2097152 }, .{ .bool = true } };
    const out = try merge(testing.allocator, &mini, original, &values);
    defer testing.allocator.free(out);
    try testing.expectEqualStrings(
        \\# header
        \\CONFIG_ENABLE_SERIAL_DEBUG=y
        \\
        \\CONFIG_HEAP_INITIAL_SIZE=2097152
        \\CONFIG_ENABLE_TEST_DEFAULT_ON=y
        \\
    , out);
}

test "empty original appends every key with LF and no leading separator" {
    const values = [_]kconfig.Option{ .{ .bool = false }, .{ .int = 4096 }, .{ .bool = true } };
    const out = try merge(testing.allocator, &mini, "", &values);
    defer testing.allocator.free(out);
    try testing.expectEqualStrings(
        \\CONFIG_ENABLE_SERIAL_DEBUG=n
        \\CONFIG_HEAP_INITIAL_SIZE=4096
        \\CONFIG_ENABLE_TEST_DEFAULT_ON=y
        \\
    , out);
}

test "unchanged lines stay byte-identical, changed lines swap the value only" {
    const original = "CONFIG_ENABLE_SERIAL_DEBUG = y\nCONFIG_HEAP_INITIAL_SIZE=1\n";
    const values = [_]kconfig.Option{ .{ .bool = false }, .{ .int = 1 }, .{ .bool = true } };
    const out = try merge(testing.allocator, &mini, original, &values);
    defer testing.allocator.free(out);
    try testing.expectEqualStrings(
        "CONFIG_ENABLE_SERIAL_DEBUG = n\nCONFIG_HEAP_INITIAL_SIZE=1\nCONFIG_ENABLE_TEST_DEFAULT_ON=y\n",
        out,
    );
}

test "merged output validates against the schema" {
    const original = "# c\nCONFIG_ENABLE_SERIAL_DEBUG=y\n";
    const values = [_]kconfig.Option{ .{ .bool = false }, .{ .int = 77 }, .{ .bool = false } };
    const out = try merge(testing.allocator, &mini, original, &values);
    defer testing.allocator.free(out);
    try testing.expect(kconfig.validate(&mini, out) == null);
}

test "real schema round-trip: values from get survive merge and read back" {
    const schema = &schema_mod.schema;
    const original = "CONFIG_ENABLE_SERIAL_DEBUG=y\nCONFIG_HEAP_INITIAL_SIZE=2097152\n";
    var values: [schema.len]kconfig.Option = undefined;
    inline for (schema, 0..) |f, i| {
        values[i] = switch (f.default) {
            .bool => .{ .bool = kconfig.flag(schema, original, f.name) },
            .int => .{ .int = kconfig.get(u32, schema, original, f.name) orelse f.default.int },
            .str => .{ .str = kconfig.get([]const u8, schema, original, f.name) orelse f.default.str },
        };
    }
    values[1] = .{ .int = 4096 }; // HEAP_INITIAL_SIZE is schema index 1
    const out = try merge(testing.allocator, schema, original, &values);
    defer testing.allocator.free(out);
    try testing.expect(kconfig.validate(schema, out) == null);
    inline for (schema, 0..) |f, i| {
        switch (f.default) {
            .bool => try testing.expectEqual(values[i].bool, kconfig.flag(schema, out, f.name)),
            .int => |d| try testing.expectEqual(values[i].int, kconfig.get(u32, schema, out, f.name) orelse d),
            .str => |d| try testing.expectEqualStrings(values[i].str, kconfig.get([]const u8, schema, out, f.name) orelse d),
        }
    }
}

test "CRLF original stays CRLF after replacement and append" {
    const original = "# h\r\nCONFIG_ENABLE_SERIAL_DEBUG=n\r\n";
    const values = [_]kconfig.Option{ .{ .bool = true }, .{ .int = 1048576 }, .{ .bool = true } };
    const out = try merge(testing.allocator, &mini, original, &values);
    defer testing.allocator.free(out);
    try testing.expectEqualStrings(
        "# h\r\nCONFIG_ENABLE_SERIAL_DEBUG=y\r\nCONFIG_HEAP_INITIAL_SIZE=1048576\r\nCONFIG_ENABLE_TEST_DEFAULT_ON=y\r\n",
        out,
    );
}

test "missing trailing newline gets separator before appended key" {
    const original = "CONFIG_ENABLE_SERIAL_DEBUG=y";
    const values = [_]kconfig.Option{ .{ .bool = true }, .{ .int = 1048576 }, .{ .bool = true } };
    const out = try merge(testing.allocator, &mini, original, &values);
    defer testing.allocator.free(out);
    try testing.expectEqualStrings(
        "CONFIG_ENABLE_SERIAL_DEBUG=y\nCONFIG_HEAP_INITIAL_SIZE=1048576\nCONFIG_ENABLE_TEST_DEFAULT_ON=y\n",
        out,
    );
}

pub fn merge(
    gpa: std.mem.Allocator,
    comptime schema: []const kconfig.Field,
    original: []const u8,
    values: []const kconfig.Option,
) std.mem.Allocator.Error![]u8 {
    std.debug.assert(values.len == schema.len);

    const eol: []const u8 = blk: {
        if (std.mem.indexOfScalar(u8, original, '\n')) |i| {
            break :blk if (i > 0 and original[i - 1] == '\r') "\r\n" else "\n";
        }
        break :blk "\n";
    };

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);

    var seen = [_]bool{false} ** schema.len;

    var rest: []const u8 = original;
    while (true) {
        const nl = std.mem.indexOfScalar(u8, rest, '\n');
        const raw = if (nl) |i| rest[0..i] else rest;
        const had_nl = nl != null;

        var line = raw;
        var crlf = false;
        if (line.len > 0 and line[line.len - 1] == '\r') {
            line = line[0 .. line.len - 1];
            crlf = true;
        }

        if (findKey(schema, line)) |found| {
            seen[found.index] = true;
            const old = trim(line[found.eq + 1 ..]);
            var val_buf: [64]u8 = undefined;
            const new_val = formatValue(&val_buf, values[found.index]);
            if (std.mem.eql(u8, old, new_val)) {
                try out.appendSlice(gpa, raw);
            } else {
                var vstart = found.eq + 1;
                while (vstart < line.len and (line[vstart] == ' ' or line[vstart] == '\t')) vstart += 1;
                try out.appendSlice(gpa, line[0..vstart]);
                try out.appendSlice(gpa, new_val);
                if (crlf) try out.appendSlice(gpa, "\r");
            }
        } else {
            try out.appendSlice(gpa, raw);
        }
        if (had_nl) try out.appendSlice(gpa, "\n");

        if (!had_nl) break;
        rest = rest[nl.? + 1 ..];
    }

    for (schema, 0..) |f, i| {
        if (seen[i]) continue;
        if (out.items.len > 0 and out.items[out.items.len - 1] != '\n') {
            try out.appendSlice(gpa, eol);
        }
        var val_buf: [64]u8 = undefined;
        const val = formatValue(&val_buf, values[i]);
        try out.appendSlice(gpa, "CONFIG_");
        try out.appendSlice(gpa, f.name);
        try out.appendSlice(gpa, "=");
        try out.appendSlice(gpa, val);
        try out.appendSlice(gpa, eol);
    }

    return out.toOwnedSlice(gpa);
}

const Found = struct { index: usize, eq: usize };

fn findKey(comptime schema: []const kconfig.Field, line: []const u8) ?Found {
    var s = line;
    while (s.len > 0 and (s[0] == ' ' or s[0] == '\t')) s = s[1..];
    if (s.len == 0 or s[0] == '#') return null;
    const eq_s = std.mem.indexOfScalar(u8, s, '=') orelse return null;
    const offset = line.len - s.len;
    const key = trim(s[0..eq_s]);
    if (!std.mem.startsWith(u8, key, "CONFIG_")) return null;
    const bare = key["CONFIG_".len..];
    for (schema, 0..) |f, i| {
        if (std.mem.eql(u8, f.name, bare)) return .{ .index = i, .eq = offset + eq_s };
    }
    return null;
}

fn trim(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and (s[start] == ' ' or s[start] == '\t')) start += 1;
    var end: usize = s.len;
    while (end > start and (s[end - 1] == ' ' or s[end - 1] == '\t')) end -= 1;
    return s[start..end];
}

fn formatValue(buf: []u8, v: kconfig.Option) []const u8 {
    return switch (v) {
        .bool => |b| if (b) "y" else "n",
        .int => |n| std.fmt.bufPrint(buf, "{d}", .{n}) catch unreachable,
        .str => |s| std.fmt.bufPrint(buf, "\"{s}\"", .{s}) catch unreachable,
    };
}
