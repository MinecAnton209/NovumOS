const std = @import("std");
const testing = std.testing;

pub const Option = union(enum) { bool: bool, int: u32, str: []const u8 };

pub const Field = struct {
    name: []const u8,
    default: Option,
    help: []const u8,
};

pub const ErrorKind = enum {
    missing_prefix,
    unknown_key,
    duplicate_key,
    missing_equals,
    bad_bool,
    bad_int,
    unmatched_quotes,
};

pub const Diagnostic = struct {
    kind: ErrorKind,
    line: usize,
    key: []const u8,
    detail: []const u8 = "",
    first_line: ?usize = null,
};

test "valid file validates clean" {
    try testing.expect(validate(&test_schema,
        \\CONFIG_ENABLE_SERIAL_DEBUG=y
        \\CONFIG_HEAP_INITIAL_SIZE=2097152
    ) == null);
}

test "trims whitespace and crlf" {
    try testing.expect(validate(&test_schema, "CONFIG_HEAP_INITIAL_SIZE = 2097152 \r\n") == null);
    try testing.expect(validate(&test_schema, "  CONFIG_ENABLE_SERIAL_DEBUG\t=\ty\r") == null);
}

test "validate scans the whole file" {
    const d = validate(&test_schema,
        \\CONFIG_ENABLE_SERIAL_DEBUG=y
        \\CONFIG_HEAP_INITIAL_SIZE=2097152
        \\CONFIG_ENABBLE_SERIAL_DEBUG=y
    ).?;
    try testing.expect(d.kind == .unknown_key);
    try testing.expect(d.line == 3);
    try testing.expectEqualStrings("ENABBLE_SERIAL_DEBUG", d.key);
}

test "missing CONFIG_ prefix names the line" {
    const d = validate(&test_schema, "CONFIG_ENABLE_SERIAL_DEBUG=y\nENABLE_SERIAL_DEBUG=n\n").?;
    try testing.expect(d.kind == .missing_prefix);
    try testing.expect(d.line == 2);
}

test "duplicate names second line and first occurrence" {
    const d = validate(&test_schema,
        \\CONFIG_ENABLE_SERIAL_DEBUG=y
        \\CONFIG_ENABLE_SERIAL_DEBUG=n
    ).?;
    try testing.expect(d.kind == .duplicate_key);
    try testing.expect(d.line == 2);
    try testing.expect(d.first_line.? == 1);
    try testing.expectEqualStrings("ENABLE_SERIAL_DEBUG", d.key);
}

test "bad bool and bad int" {
    const d1 = validate(&test_schema, "CONFIG_ENABLE_SERIAL_DEBUG=maybe\n").?;
    try testing.expect(d1.kind == .bad_bool);
    const d2 = validate(&test_schema, "CONFIG_HEAP_INITIAL_SIZE=abc\n").?;
    try testing.expect(d2.kind == .bad_int);
}

test "unmatched quotes rejected, paired and empty accepted" {
    const d = validate(&test_schema, "CONFIG_TARGET_NAME=\"hello\n").?;
    try testing.expect(d.kind == .unmatched_quotes);
    try testing.expect(validate(&test_schema, "CONFIG_TARGET_NAME=\"hello\"\n") == null);
    try testing.expect(validate(&test_schema, "CONFIG_TARGET_NAME=\"\"\n") == null);
    try testing.expect(validate(&test_schema, "CONFIG_TARGET_NAME=\"\"\r\n") == null);
}

test "comments and is-not-set lines skipped" {
    try testing.expect(validate(&test_schema,
        \\# CONFIG_ENABLE_SERIAL_DEBUG is not set
        \\#   CONFIG_FOO is not set
        \\
        \\CONFIG_HEAP_INITIAL_SIZE=1
    ) == null);
}

test "first offending line wins" {
    const d = validate(&test_schema,
        \\CONFIG_TYPO=1
        \\CONFIG_ENABLE_SERIAL_DEBUG=maybe
    ).?;
    try testing.expect(d.kind == .unknown_key);
    try testing.expect(d.line == 1);
}

test "line without equals" {
    const d = validate(&test_schema, "CONFIG_BROKEN\n").?;
    try testing.expect(d.kind == .missing_equals);
}

test "value returns override and default" {
    try testing.expect(value(bool, &test_schema, "CONFIG_ENABLE_SERIAL_DEBUG=y", "ENABLE_SERIAL_DEBUG"));
    try testing.expect(!value(bool, &test_schema, "", "ENABLE_SERIAL_DEBUG"));
    try testing.expectEqual(@as(u32, 1024 * 1024), value(u32, &test_schema, "", "HEAP_INITIAL_SIZE"));
    try testing.expectEqual(@as(u32, 2097152), value(u32, &test_schema, "CONFIG_HEAP_INITIAL_SIZE=2097152", "HEAP_INITIAL_SIZE"));
}

test "value unquotes str and falls back" {
    try testing.expectEqualStrings("hello", value([]const u8, &test_schema, "CONFIG_TARGET_NAME=\"hello\"", "TARGET_NAME"));
    try testing.expectEqualStrings("x86", value([]const u8, &test_schema, "", "TARGET_NAME"));
}

test "nasmDefine formats fragments" {
    var buf1: [64]u8 = undefined;
    try testing.expectEqualStrings("ENABLE_SERIAL_DEBUG=1", nasmDefine(&buf1, &test_schema, "CONFIG_ENABLE_SERIAL_DEBUG=y", "ENABLE_SERIAL_DEBUG"));
    var buf2: [64]u8 = undefined;
    try testing.expectEqualStrings("ENABLE_SERIAL_DEBUG=0", nasmDefine(&buf2, &test_schema, "", "ENABLE_SERIAL_DEBUG"));
}

const test_schema = [_]Field{
    .{ .name = "ENABLE_SERIAL_DEBUG", .default = .{ .bool = false }, .help = "serial" },
    .{ .name = "HEAP_INITIAL_SIZE", .default = .{ .int = 1024 * 1024 }, .help = "heap" },
    .{ .name = "TARGET_NAME", .default = .{ .str = "x86" }, .help = "str field" },
};

fn trim(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and (s[start] == ' ' or s[start] == '\t' or s[start] == '\r')) start += 1;
    var end: usize = s.len;
    while (end > start and (s[end - 1] == ' ' or s[end - 1] == '\t' or s[end - 1] == '\r')) end -= 1;
    return s[start..end];
}

fn findField(comptime schema: []const Field, name: []const u8) ?Field {
    for (schema) |f| {
        if (std.mem.eql(u8, f.name, name)) return f;
    }
    return null;
}

pub fn validate(comptime schema: []const Field, text: []const u8) ?Diagnostic {
    var line_no: usize = 1;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw| : (line_no += 1) {
        const line = trim(raw);
        if (line.len == 0 or line[0] == '#') continue;
        const eq = std.mem.indexOfScalar(u8, line, '=');
        if (eq == null) {
            return .{ .kind = .missing_equals, .line = line_no, .key = "", .detail = line };
        }
        const key = trim(line[0..eq.?]);
        const val = trim(line[eq.? + 1 ..]);
        if (!std.mem.startsWith(u8, key, "CONFIG_")) {
            return .{ .kind = .missing_prefix, .line = line_no, .key = key, .detail = line };
        }
        const bare = key["CONFIG_".len ..];
        const field = findField(schema, bare) orelse
            return .{ .kind = .unknown_key, .line = line_no, .key = bare, .detail = val };
        if (earlierKeyLine(text, key, line_no)) |first| {
            return .{ .kind = .duplicate_key, .line = line_no, .key = bare, .first_line = first };
        }
        if (checkValue(field.default, val)) |bad| {
            return .{ .kind = bad, .line = line_no, .key = bare, .detail = val };
        }
    }
    return null;
}

fn earlierKeyLine(text: []const u8, key: []const u8, stop_line: usize) ?usize {
    var line_no: usize = 1;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw| : (line_no += 1) {
        if (line_no >= stop_line) return null;
        const line = trim(raw);
        if (line.len == 0 or line[0] == '#') continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        if (std.mem.eql(u8, trim(line[0..eq]), key)) return line_no;
    }
    return null;
}

fn asBool(val: []const u8) ?bool {
    if (std.mem.eql(u8, val, "y")) return true;
    if (std.mem.eql(u8, val, "n")) return false;
    return null;
}

fn asInt(val: []const u8) ?u32 {
    return std.fmt.parseInt(u32, val, 10) catch null;
}

fn unquote(val: []const u8) error{UnmatchedQuotes}![]const u8 {
    if (val.len >= 1 and (val[0] == '"' or val[val.len - 1] == '"')) {
        if (val.len >= 2 and val[0] == '"' and val[val.len - 1] == '"') {
            return val[1 .. val.len - 1];
        }
        return error.UnmatchedQuotes;
    }
    return val;
}

fn checkValue(expected: Option, val: []const u8) ?ErrorKind {
    switch (expected) {
        .bool => if (asBool(val) == null) return .bad_bool,
        .int => if (asInt(val) == null) return .bad_int,
        .str => {
            _ = unquote(val) catch return .unmatched_quotes;
        },
    }
    return null;
}

fn get(comptime T: type, comptime schema: []const Field, text: []const u8, comptime name: []const u8) ?T {
    _ = schema;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw| {
        const line = trim(raw);
        if (line.len == 0 or line[0] == '#') continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = trim(line[0..eq]);
        const wanted = "CONFIG_" ++ name;
        if (!std.mem.eql(u8, key, wanted)) continue;
        const val = trim(line[eq + 1 ..]);
        return switch (T) {
            bool => asBool(val).?,
            u32 => asInt(val).?,
            []const u8 => unquote(val) catch unreachable,
            else => @compileError("unsupported config type " ++ @typeName(T)),
        };
    }
    return null;
}

pub fn value(comptime T: type, comptime schema: []const Field, comptime text: []const u8, comptime name: []const u8) T {
    return comptime blk: {
        if (validate(schema, text)) |d| {
            @compileError(std.fmt.comptimePrint(
                "invalid .config: line {d}: {s} key '{s}' detail '{s}'",
                .{ d.line, @tagName(d.kind), d.key, d.detail },
            ));
        }
        const field = findField(schema, name) orelse
            @compileError("kconfig.value: no schema field named " ++ name);
        switch (T) {
            bool => switch (field.default) { .bool => {}, else => @compileError("schema type mismatch for " ++ name) },
            u32 => switch (field.default) { .int => {}, else => @compileError("schema type mismatch for " ++ name) },
            []const u8 => switch (field.default) { .str => {}, else => @compileError("schema type mismatch for " ++ name) },
            else => @compileError("unsupported config type " ++ @typeName(T)),
        }
        if (get(T, schema, text, name)) |v| break :blk v;
        break :blk switch (T) {
            bool => field.default.bool,
            u32 => field.default.int,
            []const u8 => field.default.str,
            else => unreachable,
        };
    };
}

pub fn nasmDefine(buf: []u8, comptime schema: []const Field, text: []const u8, comptime name: []const u8) []const u8 {
    const field = comptime findField(schema, name) orelse
        @compileError("kconfig.nasmDefine: no schema field named " ++ name);
    const v = get(bool, schema, text, name) orelse field.default.bool;
    return std.fmt.bufPrint(buf, "{s}={d}", .{ name, @intFromBool(v) }) catch unreachable;
}
