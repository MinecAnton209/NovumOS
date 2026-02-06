// Nova Language - Main interpreter REPL
// This module handles input buffering and execution of Nova commands.

const common = @import("common.zig");
const parser = @import("parser.zig");
const commands = @import("commands.zig");
const keyboard = @import("../keyboard_isr.zig");
const versioning = @import("../versioning.zig");
const vga = @import("../drivers/vga.zig");
const serial = @import("../drivers/serial.zig");
const global_common = @import("../commands/common.zig");
const fat = @import("../drivers/fat.zig");
const ata = @import("../drivers/ata.zig");
const shell = @import("../shell.zig");

const BUFFER_SIZE: usize = 128;
const HISTORY_SIZE: usize = 10;

const NOVA_KEYWORDS = [_][]const u8{
    "print(",       "set string ", "set int ", "exit()", "reboot()", "shutdown()",
    "input(",       "delete(",     "rename(",  "copy(",  "mkdir(",   "write_file(",
    "create_file(", "if ",         "else",     "while ", "sleep(",   "shell(",
    "read(",        "random(",     "min(",     "max(",   "abs(",     "sin(",
    "cos(",         "tan(",        "atan(",
};

// Interpreter state
var buffer: [BUFFER_SIZE]u8 = [_]u8{0} ** BUFFER_SIZE;
var buf_len: u16 = 0;
var buf_pos: u16 = 0;
var insert_mode: bool = true;
var prompt_row: u8 = 0;
var prompt_col: u8 = 0;
var exit_flag: bool = false;

// History state
var history: [HISTORY_SIZE][BUFFER_SIZE]u8 = [_][BUFFER_SIZE]u8{[_]u8{0} ** BUFFER_SIZE} ** HISTORY_SIZE;
var history_lens: [HISTORY_SIZE]u16 = [_]u16{0} ** HISTORY_SIZE;
var history_count: u8 = 0;
var history_index: u8 = 0;

// Autocomplete state
var auto_cycling: bool = false;
var auto_prefix: [64]u8 = [_]u8{0} ** 64;
var auto_prefix_len: usize = 0;
var auto_match_index: usize = 0;
var auto_start_pos: u16 = 0;

/// Read a simple line of input into the provided buffer
pub fn readInput(buf: []u8) usize {
    var length: usize = 0;
    while (length < buf.len - 1) {
        const key = keyboard.keyboard_wait_char();
        if (key == 10 or key == 13) { // Enter
            common.print_char('\n');
            break;
        } else if (key == 8 or key == 127) { // Backspace
            if (length > 0) {
                length -= 1;
                buf[length] = 0;
                // Visually backspace
                const cur_row = vga.zig_get_cursor_row();
                const cur_col = vga.zig_get_cursor_col();
                if (cur_col > 0) {
                    vga.zig_set_cursor(cur_row, cur_col - 1);
                    vga.zig_print_char(' ');
                    vga.zig_set_cursor(cur_row, cur_col - 1);
                }
            }
        } else if (key >= 32 and key <= 126) {
            buf[length] = key;
            length += 1;
            common.print_char(key);
        }
    }
    return length;
}

/// Start the Nova interpreter environment
pub fn start(script_path: ?[]const u8) void {
    exit_flag = false;
    global_common.seed_random_with_tsc();

    if (script_path) |path| {
        runScript(path);
    } else {
        // Welcome message
        common.printZ("Nova Language v" ++ versioning.NOVA_VERSION ++ "\n" ++
            "Commands: print(\"text\"); exit();\n");

        // Main REPL loop (Read-Eval-Print Loop)
        while (!exit_flag) {
            common.printZ("nova> ");
            readLine();
            if (exit_flag) break;
            executeLine();
        }
    }
}

pub fn runScript(path: []const u8) void {
    const drive = if (global_common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
    if (global_common.selected_disk < 0) {
        global_common.printError("Error: No disk mounted. Please use 'mount 0' first.\n");
        return;
    }

    if (fat.read_bpb(drive)) |bpb| {
        if (fat.find_entry(drive, bpb, global_common.current_dir_cluster, path)) |entry| {
            if ((entry.attr & 0x10) != 0) {
                global_common.printError("Error: Path is a directory\n");
                return;
            }

            // Allocate a temporary buffer for the script
            // For now, use a fixed size. We can improve this later.
            var script_buffer: [4096]u8 = [_]u8{0} ** 4096;
            const bytes_read = fat.read_file(drive, bpb, global_common.current_dir_cluster, path, &script_buffer);

            if (bytes_read > 0) {
                const script = script_buffer[0..@intCast(bytes_read)];
                runScriptSource(script);
            } else {
                global_common.printError("Error: Empty file or read error\n");
            }
        } else {
            global_common.printError("Error: Script not found: ");
            global_common.printError(path);
            global_common.printError("\n");
        }
    }
}

pub fn runScriptSource(script: []const u8) void {
    // VALIDATE SYNTAX BEFORE EXECUTION
    if (!validateScript(script)) {
        global_common.printError("Script validation failed. Execution aborted.\n");
        return;
    }

    // Reset state before run
    exit_flag = false;
    executeScript(script);
}

fn validateScript(script: []const u8) bool {
    var brace_depth: i32 = 0;
    var paren_depth: i32 = 0;
    var in_quotes: bool = false;
    var line_num: u32 = 1;
    var has_errors: bool = false;

    var i: usize = 0;
    while (i < script.len) : (i += 1) {
        const c = script[i];

        if (c == '\n') {
            line_num += 1;
            if (in_quotes) {
                global_common.printError("Error: Unclosed quote on line ");
                global_common.printNum(@intCast(line_num - 1));
                global_common.printError("\n");
                has_errors = true;
                in_quotes = false;
            }
            continue;
        }

        if (c == '"') {
            in_quotes = !in_quotes;
            continue;
        }

        if (in_quotes) continue;

        if (c == '{') brace_depth += 1;
        if (c == '}') {
            brace_depth -= 1;
            if (brace_depth < 0) {
                global_common.printError("Error: Unmatched '}' on line ");
                global_common.printNum(@intCast(line_num));
                global_common.printError("\n");
                has_errors = true;
                brace_depth = 0;
            }
        }

        if (c == '(') paren_depth += 1;
        if (c == ')') {
            paren_depth -= 1;
            if (paren_depth < 0) {
                global_common.printError("Error: Unmatched ')' on line ");
                global_common.printNum(@intCast(line_num));
                global_common.printError("\n");
                has_errors = true;
                paren_depth = 0;
            }
        }
    }

    if (brace_depth != 0) {
        global_common.printError("Error: Unclosed '{' - missing ");
        global_common.printNum(@intCast(brace_depth));
        global_common.printError(" closing brace(s)\n");
        has_errors = true;
    }

    if (paren_depth != 0) {
        global_common.printError("Error: Unclosed '(' - missing ");
        global_common.printNum(@intCast(paren_depth));
        global_common.printError(" closing parenthesis\n");
        has_errors = true;
    }

    if (in_quotes) {
        global_common.printError("Error: Unclosed quote at end of file\n");
        has_errors = true;
    }

    return !has_errors;
}

fn executeScript(script: []const u8) void {
    var pos: usize = 0;
    while (!exit_flag) {
        if (keyboard.check_ctrl_c()) {
            common.printZ("\nScript interrupted by user\n");
            exit_flag = true;
            return;
        }
        // Skip whitespace and empty lines
        while (pos < script.len and (script[pos] == ' ' or script[pos] == '\n' or script[pos] == '\r')) : (pos += 1) {}
        if (pos >= script.len) break;

        const stmt = parser.parseStatement(script, pos);

        if (stmt.cmd_type == .empty) {
            pos = parser.nextStatement(script, pos);
            continue;
        }

        if (stmt.cmd_type == .if_stmt) {
            const cond = commands.evaluateCondition(script, stmt);

            // Find opening brace {
            var brace_pos = stmt.arg_start + stmt.arg_len;
            while (brace_pos < script.len and script[brace_pos] != '{') : (brace_pos += 1) {}

            if (brace_pos >= script.len) {
                global_common.printError("Error: Missing { for if\n");
                break;
            }

            const end_brace = findMatchingBrace(script, brace_pos + 1);

            if (cond) {
                executeScript(script[brace_pos + 1 .. end_brace]);
                pos = end_brace + 1;
                // SKIP any following else block
                while (pos < script.len and (script[pos] == ' ' or script[pos] == '\n' or script[pos] == '\r' or script[pos] == ';')) : (pos += 1) {}
                if (pos + 4 <= script.len and common.startsWith(script[pos..], "else")) {
                    pos += 4;
                    while (pos < script.len and (script[pos] == ' ' or script[pos] == '\n' or script[pos] == '\r')) : (pos += 1) {}
                    if (pos < script.len and script[pos] == '{') {
                        pos = findMatchingBrace(script, pos + 1) + 1;
                    }
                }
            } else {
                // Check if an else block follows
                var next_pos = end_brace + 1;
                while (next_pos < script.len and (script[next_pos] == ' ' or script[next_pos] == '\n' or script[next_pos] == '\r' or script[next_pos] == ';')) : (next_pos += 1) {}
                if (next_pos + 4 <= script.len and common.startsWith(script[next_pos..], "else")) {
                    var else_brace_pos = next_pos + 4;
                    while (else_brace_pos < script.len and script[else_brace_pos] != '{') : (else_brace_pos += 1) {}
                    if (else_brace_pos < script.len) {
                        const else_end_brace = findMatchingBrace(script, else_brace_pos + 1);
                        executeScript(script[else_brace_pos + 1 .. else_end_brace]);
                        pos = else_end_brace + 1;
                    } else {
                        pos = next_pos + 4;
                    }
                } else {
                    pos = end_brace + 1;
                }
            }
        } else if (stmt.cmd_type == .while_stmt) {
            var brace_pos = stmt.arg_start + stmt.arg_len;
            while (brace_pos < script.len and script[brace_pos] != '{') : (brace_pos += 1) {}
            if (brace_pos >= script.len) {
                break;
            }

            const end_brace = findMatchingBrace(script, brace_pos + 1);
            const block_content = script[brace_pos + 1 .. end_brace];

            while (commands.evaluateCondition(script, stmt) and !exit_flag) {
                executeScript(block_content);
            }
            pos = end_brace + 1;
        } else {
            // Normal command
            commands.execute(script, stmt, &exit_flag);
            pos = parser.nextStatement(script, pos);
        }
    }
}

fn findMatchingBrace(script: []const u8, start_idx: usize) usize {
    var depth: i32 = 1;
    var i = start_idx;
    while (i < script.len) : (i += 1) {
        if (script[i] == '{') depth += 1;
        if (script[i] == '}') {
            depth -= 1;
            if (depth == 0) return i;
        }
    }
    return i;
}

/// Read a single line of input from the keyboard
fn readLine() void {
    buf_len = 0;
    buf_pos = 0;
    for (&buffer) |*b| b.* = 0;
    history_index = history_count;

    prompt_row = vga.zig_get_cursor_row();
    prompt_col = vga.zig_get_cursor_col();
    refreshLine(); // Initial draw of status bar

    while (true) {
        const key = keyboard.keyboard_wait_char();

        if (key == 3) {
            common.printZ("^C\n");
            buf_len = 0;
            buf_pos = 0;
            return;
        }

        if (key != 9) auto_cycling = false;

        if (key == 10 or key == 13) { // Enter
            if (buf_len > 0) {
                saveToHistory();
            }
            common.print_char('\n');
            return;
        } else if (key == 8 or key == 127) { // Backspace
            if (buf_pos > 0) {
                var i: usize = buf_pos - 1;
                while (i < buf_len - 1) : (i += 1) {
                    buffer[i] = buffer[i + 1];
                }
                buffer[buf_len - 1] = 0;
                buf_pos -= 1;
                buf_len -= 1;
                refreshLine();
            }
        } else if (key == keyboard.KEY_LEFT) {
            if (buf_pos > 0) {
                buf_pos -= 1;
                moveScreenCursor();
            }
        } else if (key == keyboard.KEY_RIGHT) {
            if (buf_pos < buf_len) {
                buf_pos += 1;
                moveScreenCursor();
            }
        } else if (key == keyboard.KEY_HOME) {
            buf_pos = 0;
            moveScreenCursor();
        } else if (key == keyboard.KEY_END) {
            buf_pos = buf_len;
            moveScreenCursor();
        } else if (key == keyboard.KEY_UP) {
            if (history_count > 0 and history_index > 0) {
                history_index -= 1;
                loadHistory();
            }
        } else if (key == keyboard.KEY_DOWN) {
            if (history_index < history_count) {
                history_index += 1;
                if (history_index == history_count) {
                    buf_len = 0;
                    buf_pos = 0;
                    for (&buffer) |*b| b.* = 0;
                    refreshLine();
                } else {
                    loadHistory();
                }
            }
        } else if (key == keyboard.KEY_DELETE) {
            if (buf_pos < buf_len) {
                var i: usize = buf_pos;
                while (i < buf_len - 1) : (i += 1) {
                    buffer[i] = buffer[i + 1];
                }
                buffer[buf_len - 1] = 0;
                buf_len -= 1;
                refreshLine();
            }
        } else if (key == keyboard.KEY_INSERT) {
            insert_mode = !insert_mode;
            refreshLine();
        } else if (key == keyboard.KEY_CAPS or key == keyboard.KEY_NUM) {
            refreshLine();
        } else if (key == 9) { // Tab
            if (auto_cycling) {
                auto_match_index += 1;
            }
            autocomplete();
            refreshLine();
        } else if (key >= 32 and key <= 126) { // Printable characters
            if (buf_len < BUFFER_SIZE - 1) {
                if (insert_mode) {
                    var i: usize = buf_len;
                    while (i > buf_pos) : (i -= 1) {
                        buffer[i] = buffer[i - 1];
                    }
                    buffer[buf_pos] = key;
                    buf_len += 1;
                    buf_pos += 1;
                } else {
                    buffer[buf_pos] = key;
                    if (buf_pos == buf_len) buf_len += 1;
                    buf_pos += 1;
                }
                refreshLine();
            }
        } else if (key == 27) { // ESC
            // Clear line?
        }
    }
}

fn loadHistory() void {
    buf_len = history_lens[history_index];
    for (0..buf_len) |i| buffer[i] = history[history_index][i];
    for (buf_len..BUFFER_SIZE) |i| buffer[i] = 0;
    buf_pos = buf_len;
    refreshLine();
}

fn saveToHistory() void {
    if (history_count == HISTORY_SIZE) {
        for (0..HISTORY_SIZE - 1) |i| {
            history[i] = history[i + 1];
            history_lens[i] = history_lens[i + 1];
        }
        history_count -= 1;
    }
    for (0..buf_len) |i| history[history_count][i] = buffer[i];
    history_lens[history_count] = buf_len;
    history_count += 1;
}

fn autocomplete() void {
    if (buf_len == 0 and !auto_cycling) return;

    if (!auto_cycling) {
        var s_idx: usize = 0;
        var idx: usize = buf_pos;
        while (idx > 0) {
            idx -= 1;
            if (buffer[idx] == ' ' or buffer[idx] == ';') {
                s_idx = idx + 1;
                break;
            }
        }
        auto_start_pos = @intCast(s_idx);
        auto_prefix_len = 0;
        const to_copy = buf_pos - s_idx;
        while (auto_prefix_len < to_copy and auto_prefix_len < 63) : (auto_prefix_len += 1) {
            auto_prefix[auto_prefix_len] = buffer[s_idx + auto_prefix_len];
        }
        auto_match_index = 0;
        auto_cycling = true;
    }

    const current_prefix = auto_prefix[0..auto_prefix_len];
    var total_matches: usize = 0;

    for (NOVA_KEYWORDS) |kw| {
        if (global_common.startsWithIgnoreCase(kw, current_prefix)) total_matches += 1;
    }

    if (total_matches == 0) {
        auto_cycling = false;
        return;
    }

    const match_to_pick = auto_match_index % total_matches;
    var current_match_idx: usize = 0;

    for (NOVA_KEYWORDS) |kw| {
        if (global_common.startsWithIgnoreCase(kw, current_prefix)) {
            if (current_match_idx == match_to_pick) {
                buf_len = auto_start_pos;
                for (kw) |c| {
                    buffer[buf_len] = c;
                    buf_len += 1;
                }
                buf_pos = buf_len;
                var z = buf_len;
                while (z < BUFFER_SIZE) : (z += 1) buffer[z] = 0;
                break;
            }
            current_match_idx += 1;
        }
    }
}

fn refreshLine() void {
    const saved_pos = buf_pos;

    // VGA Update
    vga.zig_set_cursor(prompt_row, prompt_col);
    {
        var row = prompt_row;
        var col = prompt_col;
        var cleared: usize = 0;
        while (cleared < 80) : (cleared += 1) {
            if (row >= 25) break;
            const idx = @as(usize, row) * 80 + col;
            vga.VIDEO_MEMORY[idx] = vga.DEFAULT_ATTR | ' ';
            col += 1;
            if (col >= 80) {
                col = 0;
                row += 1;
            }
        }
    }

    vga.zig_set_cursor(prompt_row, prompt_col);
    const row_before = vga.zig_get_cursor_row();
    for (buffer[0..buf_len]) |c| vga.zig_print_char(c);
    const row_after = vga.zig_get_cursor_row();
    if (row_after < row_before and prompt_row > 0) prompt_row -= 1;

    // Serial Update
    serial.serial_hide_cursor();
    serial.serial_set_cursor(prompt_row, prompt_col);
    serial.serial_print_str(buffer[0..buf_len]);
    serial.serial_clear_line();

    buf_pos = saved_pos;
    moveScreenCursor();
    serial.serial_show_cursor();

    // Update status indicators
    vga.VIDEO_MEMORY[80 - 14] = (if (keyboard.keyboard_get_caps_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'C';
    vga.VIDEO_MEMORY[80 - 13] = (if (keyboard.keyboard_get_caps_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'A';
    vga.VIDEO_MEMORY[80 - 12] = (if (keyboard.keyboard_get_caps_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'P';
    vga.VIDEO_MEMORY[80 - 11] = (if (keyboard.keyboard_get_caps_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'S';

    vga.VIDEO_MEMORY[80 - 9] = (if (keyboard.keyboard_get_num_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'N';
    vga.VIDEO_MEMORY[80 - 8] = (if (keyboard.keyboard_get_num_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'U';
    vga.VIDEO_MEMORY[80 - 7] = (if (keyboard.keyboard_get_num_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'M';

    const attr = @as(u16, 0x0E00);
    const status = if (insert_mode) " INS " else " OVR ";
    for (status, 0..) |c, k| vga.VIDEO_MEMORY[80 - 5 + k] = attr | @as(u16, c);
}

fn moveScreenCursor() void {
    var new_col = @as(u16, prompt_col) + buf_pos;
    var new_row = prompt_row;
    while (new_col >= 80) {
        new_col -= 80;
        new_row += 1;
    }
    vga.zig_set_cursor(@intCast(new_row), @intCast(new_col));
}

/// Parse and execute the buffered command line
fn executeLine() void {
    if (buf_len == 0) return;
    executeScript(buffer[0..buf_len]);
}
