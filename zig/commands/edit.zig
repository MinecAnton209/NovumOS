// Basic Text Editor (Nano-like)
const common = @import("common.zig");
const keyboard = @import("../keyboard_isr.zig");
const vga = @import("../drivers/vga.zig");
const serial = @import("../drivers/serial.zig");
const fat = @import("../drivers/fat.zig");
const ata = @import("../drivers/ata.zig");

const MAX_BUF = 8192;
var buffer: [MAX_BUF]u8 = [_]u8{0} ** MAX_BUF;
var buf_len: usize = 0;
var cursor_pos: usize = 0;
var filename: [32]u8 = [_]u8{0} ** 32;
var filename_len: usize = 0;
var insert_mode: bool = true;
var is_modified: bool = false;
var current_status: [40]u8 = [_]u8{0} ** 40;
var status_len: usize = 0;

// Scrolling state
var viewport_top: usize = 0; // Which screen-line is at the top of the content area
const COLS = 79;
const ROWS = 23; // Content area height

// Clipboard
var clipboard: [1024]u8 = [_]u8{0} ** 1024;
var clip_len: usize = 0;

pub fn execute(name: []const u8) void {
    // 1. Initialize
    for (&buffer) |*b| b.* = 0;
    buf_len = 0;
    cursor_pos = 0;
    viewport_top = 0;
    is_modified = false;
    filename_len = @min(name.len, 31);
    for (0..filename_len) |i| filename[i] = name[i];

    // 2. Load from disk
    if (common.selected_disk >= 0) {
        const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
        if (fat.read_bpb(drive)) |bpb| {
            const read = fat.read_file(drive, bpb, common.current_dir_cluster, name, &buffer);
            if (read >= 0) buf_len = @intCast(read);
        }
    }

    // 3. Editor loop
    vga.save_screen_buffer();
    vga.clear_screen();
    serial.serial_clear_screen();

    var last_cursor_pos: usize = 9999;
    var last_buf_len: usize = 9999;
    var last_viewport_top: usize = 9999;

    while (true) {
        const needs_redraw = (cursor_pos != last_cursor_pos or buf_len != last_buf_len or viewport_top != last_viewport_top);
        if (needs_redraw) {
            serial.serial_hide_cursor();
            draw_ui();
            last_cursor_pos = cursor_pos;
            last_buf_len = buf_len;
            last_viewport_top = viewport_top;
            serial.serial_show_cursor();
        } else {
            vga.update_hardware_cursor();
        }

        const char = keyboard.keyboard_wait_char();
        const ctrl = keyboard.keyboard_get_ctrl();

        if (char != 0 and char != keyboard.KEY_CAPS and char != keyboard.KEY_NUM) {
            if (!(ctrl and char == 's')) status_len = 0;
        }

        // Support both hardware Ctrl and ASCII control chars from serial
        const is_save = (ctrl and (char == 's' or char == 'S')) or char == 19; // Ctrl+S
        const is_quit = (ctrl and (char == 'q' or char == 'Q')) or char == 17 or char == 3; // Ctrl+Q or Ctrl+C
        const is_cut = (ctrl and (char == 'k' or char == 'K')) or char == 11; // Ctrl+K
        const is_paste = (ctrl and (char == 'u' or char == 'U')) or char == 21; // Ctrl+U

        if (is_save) {
            save_file();
            status_msg("File saved!");
            continue;
        }
        if (is_quit) {
            if (char == 3) break; // Emergency exit on Ctrl+C
            if (is_modified) {
                const choice = show_exit_dialog();
                if (choice == .Cancel) continue;
                if (choice == .Save) save_file();
                break;
            }
            break;
        }

        if (is_cut) {
            cut_line();
            continue;
        }
        if (is_paste) {
            paste_line();
            continue;
        }

        if (char == keyboard.KEY_LEFT) {
            if (cursor_pos > 0) cursor_pos -= 1;
        } else if (char == keyboard.KEY_RIGHT) {
            if (cursor_pos < buf_len) cursor_pos += 1;
        } else if (char == keyboard.KEY_UP) {
            move_up();
        } else if (char == keyboard.KEY_DOWN) {
            move_down();
        } else if (char == keyboard.KEY_HOME) {
            if (ctrl) cursor_pos = 0 else move_home();
        } else if (char == keyboard.KEY_END) {
            if (ctrl) cursor_pos = buf_len else move_end();
        } else if (char == keyboard.KEY_PGUP) {
            var l: usize = 0;
            while (l < ROWS) : (l += 1) move_up();
        } else if (char == keyboard.KEY_PGDN) {
            var l: usize = 0;
            while (l < ROWS) : (l += 1) move_down();
        } else if (char == keyboard.KEY_INSERT) {
            insert_mode = !insert_mode;
        } else if (char == 8 or char == 127) { // Backspace
            if (cursor_pos > 0) {
                var i = cursor_pos - 1;
                while (i < buf_len - 1) : (i += 1) buffer[i] = buffer[i + 1];
                buffer[buf_len - 1] = 0;
                buf_len -= 1;
                cursor_pos -= 1;
                is_modified = true;
            }
        } else if (char == keyboard.KEY_DELETE) {
            if (cursor_pos < buf_len) {
                var i = cursor_pos;
                while (i < buf_len - 1) : (i += 1) buffer[i] = buffer[i + 1];
                buffer[buf_len - 1] = 0;
                buf_len -= 1;
                is_modified = true;
            }
        } else if (char == 10 or char == 13) {
            insert_char('\n');
            is_modified = true;
        } else if (char >= 32 and char <= 126) {
            insert_char(char);
            is_modified = true;
        }
    }
    vga.restore_screen_buffer();
}

fn draw_ui() void {
    const attr_bar = 0x7000;
    for (0..80) |i| vga.VIDEO_MEMORY[i] = attr_bar | @as(u16, ' ');
    draw_text_at(0, 1, "NovumOS Editor - ", attr_bar);
    draw_text_at(0, 16, filename[0..filename_len], attr_bar);
    if (is_modified) draw_text_at(0, 16 + filename_len, " [*]", attr_bar);

    // Position indicator
    const coords = get_cursor_coords(cursor_pos);
    var pos_buf: [20]u8 = undefined;
    const pos_str = common.fmt_to_buf(&pos_buf, "L: {d} C: {d}", .{ coords.r, coords.c });
    draw_text_at(0, 45, pos_str, attr_bar);

    for (0..80) |i| vga.VIDEO_MEMORY[24 * 80 + i] = attr_bar | @as(u16, ' ');
    draw_text_at(24, 1, "^S Save ^Q Exit ^K Cut ^U Paste", attr_bar);

    if (status_len > 0) draw_text_at(24, 40, current_status[0..status_len], 0x7E00);

    // Serial UI sync
    serial.serial_set_cursor(0, 0);
    serial.serial_set_color(0); // Black bg
    serial.serial_print_str("NovumOS Editor - ");
    serial.serial_print_str(filename[0..filename_len]);
    if (is_modified) serial.serial_print_str(" [*]");
    serial.serial_print_str("    ");
    serial.serial_print_str(pos_str);
    serial.serial_clear_line();

    serial.serial_set_cursor(24, 0);
    serial.serial_print_str("^S Save ^Q Exit ^K Cut ^U Paste");
    if (status_len > 0) {
        serial.serial_print_str("  ");
        serial.serial_print_str(current_status[0..status_len]);
    }
    serial.serial_clear_line();

    draw_content();
}

fn draw_text_at(row: usize, col: usize, text: []const u8, attr: u16) void {
    for (text, 0..) |c, i| {
        if (col + i >= 80) break;
        vga.VIDEO_MEMORY[row * 80 + col + i] = attr | @as(u16, c);
    }
}

fn draw_content() void {
    const coords = get_cursor_coords(cursor_pos);
    // Auto-scroll logic
    if (coords.r - 1 < viewport_top) {
        viewport_top = coords.r - 1;
    } else if (coords.r - 1 >= viewport_top + ROWS) {
        viewport_top = coords.r - ROWS;
    }

    for (1..24) |r| {
        for (0..80) |c| vga.VIDEO_MEMORY[r * 80 + c] = 0x0F00 | @as(u16, ' ');
    }

    var r: usize = 1;
    var c: usize = 0;
    var i: usize = 0;

    serial.serial_set_color(7); // White fg

    var last_draw_r: usize = 999;
    i = 0;
    r = 1;
    c = 0;
    while (i <= buf_len) : (i += 1) {
        const cur_screen_row = r - 1;
        if (cur_screen_row >= viewport_top and cur_screen_row < viewport_top + ROWS) {
            const draw_r = cur_screen_row - viewport_top + 1;
            if (i < buf_len and buffer[i] != '\n') {
                vga.VIDEO_MEMORY[draw_r * 80 + c] = 0x0F00 | @as(u16, buffer[i]);

                // Serial draw optimization: only set cursor if we moved to a new line
                if (draw_r != last_draw_r) {
                    serial.serial_set_cursor(@intCast(draw_r), @intCast(c));
                    serial.serial_clear_line();
                    last_draw_r = draw_r;
                }
                serial.serial_print_char(buffer[i]);
            }
        }

        if (i == buf_len) break;
        if (buffer[i] == '\n') {
            r += 1;
            c = 0;
        } else {
            c += 1;
            if (c >= COLS) {
                if (r - 1 >= viewport_top and r - 1 < viewport_top + ROWS) {
                    vga.VIDEO_MEMORY[(r - viewport_top + 1) * 80 + 79] = 0x081A;
                }
                c = 0;
                r += 1;
            }
        }
        if (r - 1 >= viewport_top + ROWS) break;
    }

    const final_r = coords.r - 1 - viewport_top + 1;
    vga.zig_set_cursor(@intCast(final_r), @intCast(coords.c));
    serial.serial_set_cursor(@intCast(final_r), @intCast(coords.c));
}

fn cut_line() void {
    move_home();
    const start = cursor_pos;
    move_end();
    if (cursor_pos < buf_len and buffer[cursor_pos] == '\n') cursor_pos += 1;
    const end = cursor_pos;
    const len = end - start;
    if (len == 0) return;

    clip_len = @min(len, 1023);
    for (0..clip_len) |i| clipboard[i] = buffer[start + i];

    var i = start;
    while (i < buf_len - len) : (i += 1) buffer[i] = buffer[i + len];
    for (0..len) |j| buffer[buf_len - 1 - j] = 0;
    buf_len -= len;
    cursor_pos = start;
    is_modified = true;
    status_msg("Line cut");
}

fn paste_line() void {
    if (clip_len == 0) return;
    if (buf_len + clip_len >= MAX_BUF) return;
    var i = buf_len + clip_len - 1;
    while (i >= cursor_pos + clip_len) : (i -= 1) buffer[i] = buffer[i - clip_len];
    for (0..clip_len) |j| buffer[cursor_pos + j] = clipboard[j];
    buf_len += clip_len;
    cursor_pos += clip_len;
    is_modified = true;
    status_msg("Pasted");
}

fn insert_char(c: u8) void {
    if (buf_len >= MAX_BUF - 1) return;
    if (insert_mode or cursor_pos == buf_len) {
        var i = buf_len;
        while (i > cursor_pos) : (i -= 1) buffer[i] = buffer[i - 1];
        buffer[cursor_pos] = c;
        buf_len += 1;
    } else {
        buffer[cursor_pos] = c;
    }
    cursor_pos += 1;
}

fn save_file() void {
    if (common.selected_disk >= 0) {
        const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
        if (fat.read_bpb(drive)) |bpb| {
            _ = fat.write_file(drive, bpb, common.current_dir_cluster, filename[0..filename_len], buffer[0..buf_len]);
            is_modified = false;
        }
    }
}

fn status_msg(msg: []const u8) void {
    status_len = @min(msg.len, 39);
    for (0..status_len) |i| current_status[i] = msg[i];
}

const ExitChoice = enum { Save, DontSave, Cancel };
fn show_exit_dialog() ExitChoice {
    const box_row = 10;
    const box_col = 15;
    for (box_row..box_row + 6) |r| {
        for (box_col..box_col + 50) |c| vga.VIDEO_MEMORY[r * 80 + c] = 0x1F00 | @as(u16, ' ');
    }
    draw_text_at(box_row + 1, box_col + 2, "File modified! Save changes?", 0x1F00);
    draw_text_at(box_row + 3, box_col + 2, "^S: Save & Exit", 0x1F00);
    draw_text_at(box_row + 4, box_col + 2, "^X: Discard", 0x1F00);
    draw_text_at(box_row + 4, box_col + 30, "Esc: Cancel", 0x1F00);

    // Serial dialog
    serial.serial_set_cursor(box_row, box_col);
    serial.serial_print_str("[ FILE MODIFIED! SAVE CHANGES? ]");
    serial.serial_set_cursor(box_row + 1, box_col);
    serial.serial_print_str("^S: Save, ^X: Discard, Esc: Cancel");

    while (true) {
        const key = keyboard.keyboard_wait_char();
        const ctrl = keyboard.keyboard_get_ctrl();
        if ((ctrl and (key == 's' or key == 'S')) or key == 19) return .Save;
        if ((ctrl and (key == 'x' or key == 'X')) or key == 24) return .DontSave; // Ctrl+X is 24
        if (key == 27) return .Cancel;
    }
}

fn move_up() void {
    const curr = get_cursor_coords(cursor_pos);
    if (curr.r > 1) cursor_pos = get_pos_from_coords(curr.r - 1, curr.c);
}
fn move_down() void {
    const curr = get_cursor_coords(cursor_pos);
    cursor_pos = get_pos_from_coords(curr.r + 1, curr.c);
}
fn move_home() void {
    const curr = get_cursor_coords(cursor_pos);
    cursor_pos = get_pos_from_coords(curr.r, 0);
}
fn move_end() void {
    const curr = get_cursor_coords(cursor_pos);
    cursor_pos = get_pos_from_coords(curr.r, COLS - 1);
}

fn get_cursor_coords(pos: usize) struct { r: usize, c: usize } {
    var r: usize = 1;
    var c: usize = 0;
    var i: usize = 0;
    while (i < pos) : (i += 1) {
        if (buffer[i] == '\n') {
            r += 1;
            c = 0;
        } else {
            c += 1;
            if (c >= COLS) {
                c = 0;
                r += 1;
            }
        }
    }
    return .{ .r = r, .c = c };
}

fn get_pos_from_coords(target_r: usize, target_c: usize) usize {
    var r: usize = 1;
    var c: usize = 0;
    var i: usize = 0;
    while (i < buf_len and r < target_r) : (i += 1) {
        if (buffer[i] == '\n') {
            r += 1;
            c = 0;
        } else {
            c += 1;
            if (c >= COLS) {
                c = 0;
                r += 1;
            }
        }
    }
    if (r < target_r) return i;
    while (i < buf_len and r == target_r and c < target_c) : (i += 1) {
        if (buffer[i] == '\n') break;
        c += 1;
        if (c >= COLS) break;
    }
    return i;
}
