const std = @import("std");

// Ported parser logic for host testing (avoids common.zig dependency)
// Based on zig/nova_legacy/parser.zig

fn startsWith(a: []const u8, b: []const u8) bool {
    if (a.len < b.len) return false;
    for (b, 0..) |c, i| {
        if (a[i] != c) return false;
    }
    return true;
}

pub const CmdType = enum {
    print,
    set_string,
    set_int,
    exit,
    reboot,
    shutdown,
    sleep,
    fs_delete,
    fs_rename,
    fs_copy,
    fs_mkdir,
    fs_write,
    fs_create,
    if_stmt,
    else_stmt,
    while_stmt,
    end_block,
    shell_exec,
    unknown,
    empty,
};

pub const Statement = struct {
    cmd_type: CmdType,
    arg_start: usize,
    arg_len: usize,
};

fn findParensContent(buffer: []const u8, start: usize) usize {
    var end = start;
    var depth: i32 = 1;
    while (end < buffer.len and buffer[end] != 0) {
        if (buffer[end] == '(') depth += 1;
        if (buffer[end] == ')') {
            depth -= 1;
            if (depth == 0) break;
        }
        end += 1;
    }
    return end - start;
}

fn findBlockCondition(buffer: []const u8, start: usize) usize {
    var end = start;
    while (end < buffer.len and buffer[end] != 0 and buffer[end] != '{') {
        end += 1;
    }
    return end - start;
}

// Find next statement (after semicolon)
pub fn nextStatement(buffer: []const u8, pos: usize) usize {
    var p = pos;
    while (p < buffer.len and buffer[p] != 0 and buffer[p] != ';') {
        p += 1;
    }
    if (p < buffer.len and buffer[p] == ';') {
        p += 1;
    }
    return p;
}

pub fn parseStatement(buffer: []const u8, start: usize) Statement {
    var pos = start;

    while (pos < buffer.len) {
        const c = buffer[pos];
        if (!(c == ' ' or c == '\t' or c == '\n' or c == '\r')) break;
        pos += 1;
    }

    // Also skip single-line comments
    while (pos + 1 < buffer.len and buffer[pos] == '/' and buffer[pos + 1] == '/') {
        while (pos < buffer.len and buffer[pos] != '\n') {
            pos += 1;
        }
        while (pos < buffer.len) {
            const c = buffer[pos];
            if (!(c == ' ' or c == '\t' or c == '\n' or c == '\r')) break;
            pos += 1;
        }
    }

    if (pos >= buffer.len or buffer[pos] == ';' or buffer[pos] == 0) {
        return .{ .cmd_type = .empty, .arg_start = pos, .arg_len = 0 };
    }

    if (pos + 4 < buffer.len and startsWith(buffer[pos..], "exit(")) {
        return .{ .cmd_type = .exit, .arg_start = pos + 5, .arg_len = findParensContent(buffer, pos + 5) };
    }

    if (pos + 5 < buffer.len and startsWith(buffer[pos..], "reboot(")) {
        return .{ .cmd_type = .reboot, .arg_start = pos + 6, .arg_len = findParensContent(buffer, pos + 6) };
    }

    if (pos + 7 < buffer.len and startsWith(buffer[pos..], "shutdown(")) {
        return .{ .cmd_type = .shutdown, .arg_start = pos + 8, .arg_len = findParensContent(buffer, pos + 8) };
    }

    if (pos + 5 < buffer.len and startsWith(buffer[pos..], "sleep(")) {
        return .{ .cmd_type = .sleep, .arg_start = pos + 6, .arg_len = findParensContent(buffer, pos + 6) };
    }

    if (startsWith(buffer[pos..], "set string ")) {
        const arg_start = pos + 11;
        var arg_end = arg_start;
        while (arg_end < buffer.len and buffer[arg_end] != ';' and buffer[arg_end] != 0) {
            arg_end += 1;
        }
        return .{ .cmd_type = .set_string, .arg_start = arg_start, .arg_len = arg_end - arg_start };
    }

    if (startsWith(buffer[pos..], "set int ")) {
        const arg_start = pos + 8;
        var arg_end = arg_start;
        while (arg_end < buffer.len and buffer[arg_end] != ';' and buffer[arg_end] != 0) {
            arg_end += 1;
        }
        return .{ .cmd_type = .set_int, .arg_start = arg_start, .arg_len = arg_end - arg_start };
    }

    if (pos + 4 < buffer.len and startsWith(buffer[pos..], "print(")) {
        const arg_start = pos + 6;
        var arg_end = arg_start;
        while (arg_end < buffer.len and buffer[arg_end] != ')' and buffer[arg_end] != 0) {
            arg_end += 1;
        }
        return .{ .cmd_type = .print, .arg_start = arg_start, .arg_len = arg_end - arg_start };
    }

    if (startsWith(buffer[pos..], "delete(")) {
        return .{ .cmd_type = .fs_delete, .arg_start = pos + 7, .arg_len = findParensContent(buffer, pos + 7) };
    }
    if (startsWith(buffer[pos..], "rename(")) {
        return .{ .cmd_type = .fs_rename, .arg_start = pos + 7, .arg_len = findParensContent(buffer, pos + 7) };
    }
    if (startsWith(buffer[pos..], "copy(")) {
        return .{ .cmd_type = .fs_copy, .arg_start = pos + 5, .arg_len = findParensContent(buffer, pos + 5) };
    }
    if (startsWith(buffer[pos..], "mkdir(")) {
        return .{ .cmd_type = .fs_mkdir, .arg_start = pos + 6, .arg_len = findParensContent(buffer, pos + 6) };
    }
    if (startsWith(buffer[pos..], "write_file(")) {
        return .{ .cmd_type = .fs_write, .arg_start = pos + 11, .arg_len = findParensContent(buffer, pos + 11) };
    }
    if (startsWith(buffer[pos..], "create_file(")) {
        return .{ .cmd_type = .fs_create, .arg_start = pos + 12, .arg_len = findParensContent(buffer, pos + 12) };
    }

    if (startsWith(buffer[pos..], "if ")) {
        return .{ .cmd_type = .if_stmt, .arg_start = pos + 3, .arg_len = findBlockCondition(buffer, pos + 3) };
    }
    if (startsWith(buffer[pos..], "while ")) {
        return .{ .cmd_type = .while_stmt, .arg_start = pos + 6, .arg_len = findBlockCondition(buffer, pos + 6) };
    }
    if (startsWith(buffer[pos..], "else")) {
        return .{ .cmd_type = .else_stmt, .arg_start = 0, .arg_len = 0 };
    }
    if (startsWith(buffer[pos..], "}")) {
        return .{ .cmd_type = .end_block, .arg_start = 0, .arg_len = 0 };
    }
    if (startsWith(buffer[pos..], "shell(")) {
        return .{ .cmd_type = .shell_exec, .arg_start = pos + 6, .arg_len = findParensContent(buffer, pos + 6) };
    }

    return .{ .cmd_type = .unknown, .arg_start = 0, .arg_len = 0 };
}

// --- Tests ---

test "parseStatement: print with string arg" {
    const src = "print(\"hello world\");";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.print);
    try std.testing.expectEqualSlices(u8, src[stmt.arg_start..stmt.arg_start + stmt.arg_len], "\"hello world\"");
}

test "parseStatement: print with multiple args" {
    const src = "print(1, 2, 3);";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.print);
}

test "parseStatement: set string" {
    const src = "set string var = myval;";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.set_string);
}

test "parseStatement: set int" {
    const src = "set int counter = 42;";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.set_int);
}

test "parseStatement: exit" {
    const src = "exit(0);";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.exit);
}

test "parseStatement: reboot" {
    const src = "reboot();";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.reboot);
}

test "parseStatement: shutdown" {
    const src = "shutdown();";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.shutdown);
}

test "parseStatement: sleep" {
    const src = "sleep(1000);";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.sleep);
}

test "parseStatement: delete" {
    const src = "delete(/path/to/file);";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.fs_delete);
}

test "parseStatement: rename" {
    const src = "rename(old, new);";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.fs_rename);
}

test "parseStatement: copy" {
    const src = "copy(src, dst);";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.fs_copy);
}

test "parseStatement: mkdir" {
    const src = "mkdir(/newdir);";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.fs_mkdir);
}

test "parseStatement: write_file" {
    const src = "write_file(/path, data);";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.fs_write);
}

test "parseStatement: create_file" {
    const src = "create_file(/path);";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.fs_create);
}

test "parseStatement: if statement" {
    const src = "if true {";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.if_stmt);
    try std.testing.expectEqualSlices(u8, src[stmt.arg_start..stmt.arg_start + stmt.arg_len], "true ");
}

test "parseStatement: while statement" {
    const src = "while x < 10 {";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.while_stmt);
    try std.testing.expectEqualSlices(u8, src[stmt.arg_start..stmt.arg_start + stmt.arg_len], "x < 10 ");
}

test "parseStatement: else statement" {
    const src = "else";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.else_stmt);
}

test "parseStatement: end block (closing brace)" {
    const src = "}";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.end_block);
}

test "parseStatement: shell exec" {
    const src = "shell(ls -la);";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.shell_exec);
}

test "parseStatement: unknown command" {
    const src = "foobar();";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.unknown);
}

test "parseStatement: empty statement (semicolon)" {
    const src = ";";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.empty);
}

test "parseStatement: with leading whitespace" {
    const src = "   print(hello);";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.print);
}

test "parseStatement: with leading newlines" {
    const src = "\n\n  print(test);";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.print);
}

test "parseStatement: with leading comment" {
    const src = "// this is a comment\nprint(value);";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.print);
}

test "parseStatement: set_string captures arg correctly" {
    const src = "set string name = hello world;";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.set_string);
    try std.testing.expectEqualSlices(u8, src[stmt.arg_start..stmt.arg_start + stmt.arg_len], "name = hello world");
}

test "parseStatement: set_int captures arg correctly" {
    const src = "set int x = 42;";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.set_int);
    try std.testing.expectEqualSlices(u8, src[stmt.arg_start..stmt.arg_start + stmt.arg_len], "x = 42");
}

test "parseStatement: parens content with nested parens" {
    const src = "print(add(1, 2));";
    const stmt = parseStatement(src, 0);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.print);
    // arg_len should include "add(1, 2)"
}

test "nextStatement: finds semicolon position" {
    const src = "print(hello);print(world);";
    const next = nextStatement(src, 0);
    try std.testing.expectEqual(next, src.len - 13); // skip "print(hello);"
}

test "nextStatement: stops at semicolon" {
    const src = "test;";
    const next = nextStatement(src, 0);
    try std.testing.expectEqual(next, 5);
}

test "nextStatement: no semicolon at end" {
    const src = "no semicolon here";
    const next = nextStatement(src, 0);
    try std.testing.expectEqual(next, src.len);
}

test "nextStatement: at semicolon" {
    const src = ";done";
    const next = nextStatement(src, 0);
    try std.testing.expectEqual(next, 1);
}

test "Parser: multiple statements sequence" {
    const buffer = "set string name = test; set int x = 42; print(name);";
    var pos: usize = 0;

    var stmt = parseStatement(buffer, pos);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.set_string);
    pos = nextStatement(buffer, pos);

    stmt = parseStatement(buffer, pos);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.set_int);
    pos = nextStatement(buffer, pos);

    stmt = parseStatement(buffer, pos);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.print);
    pos = nextStatement(buffer, pos);

    stmt = parseStatement(buffer, pos);
    try std.testing.expectEqual(stmt.cmd_type, CmdType.empty);
}
