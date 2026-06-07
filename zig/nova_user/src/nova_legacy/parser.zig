// Nova Language - Parser
const common = @import("common.zig");

pub const Statement = struct {
    cmd_type: CmdType,
    arg_start: usize,
    arg_len: usize,
};

pub const CmdType = enum {
    print,
    set_string,
    set_int,
    exit,
    reboot,
    shutdown,
    sleep,
    // File operations
    fs_delete,
    fs_rename,
    fs_copy,
    fs_mkdir,
    fs_write,
    fs_create,
    // Control Flow
    if_stmt,
    else_stmt,
    while_stmt,
    end_block,
    shell_exec,
    unknown,
    empty,
};

// Parse a statement from buffer starting at pos
pub fn parseStatement(buffer: []const u8, start: usize) Statement {
    var pos = start;

    // Skip leading spaces, newlines, tabs, and comments
    while (pos < buffer.len) {
        if (buffer[pos] == ' ' or buffer[pos] == '\t' or buffer[pos] == '\n' or buffer[pos] == '\r') {
            pos += 1;
            continue;
        }
        if (pos + 1 < buffer.len and buffer[pos] == '/' and buffer[pos + 1] == '/') {
            while (pos < buffer.len and buffer[pos] != '\n') {
                pos += 1;
            }
            continue;
        }
        break;
    }

    // End of buffer
    if (pos >= buffer.len or buffer[pos] == 0) {
        return .{ .cmd_type = .empty, .arg_start = 0, .arg_len = 0 };
    }

    // Check for exit()
    if (common.startsWith(buffer[pos..], "exit();") or common.startsWith(buffer[pos..], "exit()")) {
        return .{ .cmd_type = .exit, .arg_start = 0, .arg_len = 0 };
    }

    // Check for reboot();
    if (common.startsWith(buffer[pos..], "reboot();")) {
        return .{ .cmd_type = .reboot, .arg_start = 0, .arg_len = 0 };
    }

    // Check for shutdown();
    if (common.startsWith(buffer[pos..], "shutdown();")) {
        return .{ .cmd_type = .shutdown, .arg_start = 0, .arg_len = 0 };
    }

    // Check for sleep(
    if (common.startsWith(buffer[pos..], "sleep(")) {
        return .{ .cmd_type = .sleep, .arg_start = pos + 6, .arg_len = findParensContent(buffer, pos + 6) };
    }

    // Check for set string
    // Format: set string <name> = <expr>;
    if (common.startsWith(buffer[pos..], "set string ")) {
        const arg_start = pos + 11; // "set string " len is 11
        var arg_end = arg_start;

        // Find semicolon
        while (arg_end < buffer.len and buffer[arg_end] != ';' and buffer[arg_end] != 0) {
            arg_end += 1;
        }

        return .{ .cmd_type = .set_string, .arg_start = arg_start, .arg_len = arg_end - arg_start };
    }

    // Check for set int
    // Format: set int <name> = <expr>;
    if (common.startsWith(buffer[pos..], "set int ")) {
        const arg_start = pos + 8; // "set int " len is 8
        var arg_end = arg_start;

        // Find semicolon
        while (arg_end < buffer.len and buffer[arg_end] != ';' and buffer[arg_end] != 0) {
            arg_end += 1;
        }

        return .{ .cmd_type = .set_int, .arg_start = arg_start, .arg_len = arg_end - arg_start };
    }

    // Check for print(
    if (common.startsWith(buffer[pos..], "print(")) {
        const arg_start = pos + 6; // After print(
        var arg_end = arg_start;

        // Find closing );
        // We look for ); specifically to be safe, or just )
        // Example: print(1);
        while (arg_end < buffer.len and buffer[arg_end] != 0) {
            if (buffer[arg_end] == ')' and arg_end + 1 < buffer.len and buffer[arg_end + 1] == ';') {
                break;
            }
            arg_end += 1;
        }

        return .{ .cmd_type = .print, .arg_start = arg_start, .arg_len = arg_end - arg_start };
    }

    // File operations
    if (common.startsWith(buffer[pos..], "delete(")) {
        return .{ .cmd_type = .fs_delete, .arg_start = pos + 7, .arg_len = findParensContent(buffer, pos + 7) };
    }
    if (common.startsWith(buffer[pos..], "rename(")) {
        return .{ .cmd_type = .fs_rename, .arg_start = pos + 7, .arg_len = findParensContent(buffer, pos + 7) };
    }
    if (common.startsWith(buffer[pos..], "copy(")) {
        return .{ .cmd_type = .fs_copy, .arg_start = pos + 5, .arg_len = findParensContent(buffer, pos + 5) };
    }
    if (common.startsWith(buffer[pos..], "mkdir(")) {
        return .{ .cmd_type = .fs_mkdir, .arg_start = pos + 6, .arg_len = findParensContent(buffer, pos + 6) };
    }
    if (common.startsWith(buffer[pos..], "write_file(")) {
        return .{ .cmd_type = .fs_write, .arg_start = pos + 11, .arg_len = findParensContent(buffer, pos + 11) };
    }
    if (common.startsWith(buffer[pos..], "create_file(")) {
        return .{ .cmd_type = .fs_create, .arg_start = pos + 12, .arg_len = findParensContent(buffer, pos + 12) };
    }

    // Control Flow
    if (common.startsWith(buffer[pos..], "if ")) {
        return .{ .cmd_type = .if_stmt, .arg_start = pos + 3, .arg_len = findBlockCondition(buffer, pos + 3) };
    }
    if (common.startsWith(buffer[pos..], "while ")) {
        return .{ .cmd_type = .while_stmt, .arg_start = pos + 6, .arg_len = findBlockCondition(buffer, pos + 6) };
    }
    if (common.startsWith(buffer[pos..], "else")) {
        return .{ .cmd_type = .else_stmt, .arg_start = 0, .arg_len = 0 };
    }
    if (common.startsWith(buffer[pos..], "}")) {
        return .{ .cmd_type = .end_block, .arg_start = 0, .arg_len = 0 };
    }
    if (common.startsWith(buffer[pos..], "shell(")) {
        return .{ .cmd_type = .shell_exec, .arg_start = pos + 6, .arg_len = findParensContent(buffer, pos + 6) };
    }

    return .{ .cmd_type = .unknown, .arg_start = 0, .arg_len = 0 };
}

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
