// NovumOS Shell - Main command line interface
const common = @import("commands/common.zig");
const keyboard = @import("keyboard_isr.zig");
const shell_cmds = @import("shell_cmds.zig");
const nova = @import("nova.zig");
const messages = @import("messages.zig");
const vga = @import("drivers/vga.zig");
const versioning = @import("versioning.zig");
const serial = @import("drivers/serial.zig");
const fat = @import("drivers/fat.zig");
const ata = @import("drivers/ata.zig");
const config = @import("config.zig");
const nova_interpreter = @import("nova/interpreter.zig");
const nova_commands = @import("nova/commands.zig");
const top_cmd = @import("commands/top.zig");

// Embedded Nova Scripts
const EmbeddedScript = struct {
    name: []const u8,
    source: []const u8,
};

const BUILTIN_SCRIPTS = [_]EmbeddedScript{
    .{ .name = "hello", .source = @embedFile("nova/scripts/hello.nv") },
    .{ .name = "syscheck", .source = @embedFile("nova/scripts/syscheck.nv") },
};

// Shell configuration
const build_config = @import("build_config");
const HISTORY_SIZE = if (build_config.history_size) |h| h else config.HISTORY_SIZE;

// Command Structure for automated handling and autocomplete
const Command = struct {
    name: []const u8,
    help: []const u8,
    handler: *const fn ([]const u8) void,
};

const SHELL_COMMANDS = [_]Command{
    .{ .name = "help", .help = "Show this help message (Tip: help 2)", .handler = cmd_handler_help },
    .{ .name = "?", .help = "Alias for help", .handler = cmd_handler_help },
    .{ .name = "clear", .help = "Clear screen and reset console state", .handler = cmd_handler_clear },
    .{ .name = "cls", .help = "Alias for clear", .handler = cmd_handler_clear },
    .{ .name = "about", .help = "Show legal information & credits", .handler = cmd_handler_about },
    .{ .name = "nova", .help = "Start Nova Scripting Interpreter", .handler = cmd_handler_nova },
    .{ .name = "top", .help = "Real-time CPU and Task Monitor", .handler = cmd_handler_top },
    .{ .name = "uptime", .help = "Show system runtime and RTC time", .handler = cmd_handler_uptime },
    .{ .name = "reboot", .help = "Safely restart the system", .handler = cmd_handler_reboot },
    .{ .name = "shutdown", .help = "Safely turn off the system (ACPI)", .handler = cmd_handler_shutdown },
    .{ .name = "ls", .help = "List files/folders in current directory", .handler = cmd_handler_ls },
    .{ .name = "hexdump", .help = "hexdump <f> - Display file content in hex/ASCII", .handler = cmd_handler_hexdump },
    .{ .name = "more", .help = "more <f> - Display file content with paging", .handler = cmd_handler_more },
    .{ .name = "la", .help = "List all files (including hidden)", .handler = cmd_handler_la },
    .{ .name = "lsdsk", .help = "List storage devices and partitions", .handler = cmd_handler_lsdsk },
    .{ .name = "mount", .help = "mount <0|1> - Select active drive", .handler = cmd_handler_mount },
    .{ .name = "mkdir", .help = "mkdir <name> - Create a new directory", .handler = cmd_handler_mkdir },
    .{ .name = "md", .help = "Alias for mkdir", .handler = cmd_handler_mkdir },
    .{ .name = "cd", .help = "cd <dir|..|/> - Change directory", .handler = cmd_handler_cd },
    .{ .name = "pwd", .help = "Print current working directory", .handler = cmd_handler_pwd },
    .{ .name = "tree", .help = "Display recursive directory structure", .handler = cmd_handler_tree },
    .{ .name = "mkfs-fat12", .help = "Format drive as FAT12 (legacy)", .handler = cmd_handler_mkfs12 },
    .{ .name = "mkfs-fat16", .help = "Format drive as FAT16 (standard)", .handler = cmd_handler_mkfs16 },
    .{ .name = "mkfs-fat32", .help = "Format drive as FAT32 (advanced)", .handler = cmd_handler_mkfs32 },
    .{ .name = "touch", .help = "Create an empty file", .handler = cmd_handler_touch },
    .{ .name = "write", .help = "write [-a] <f> <t> - Write string to file (-a to append)", .handler = cmd_handler_write },
    .{ .name = "rm", .help = "rm [-d] [-r] <f|*> - Delete file/dir", .handler = cmd_handler_rm },
    .{ .name = "cat", .help = "Display text file contents", .handler = cmd_handler_cat },
    .{ .name = "edit", .help = "Open primitive text editor", .handler = cmd_handler_edit },
    .{ .name = "history", .help = "Show command history list", .handler = cmd_handler_history },
    .{ .name = "echo", .help = "Print text to standard output", .handler = cmd_handler_echo },
    .{ .name = "time", .help = "Show full current RTC date and time", .handler = cmd_handler_time },
    .{ .name = "mem", .help = "Show memory & test demand paging (mem --test [MB])", .handler = cmd_handler_mem },
    .{ .name = "sysinfo", .help = "Display system hardware info", .handler = cmd_handler_sysinfo },
    .{ .name = "cpuinfo", .help = "Show detailed CPU vendor, brand and features", .handler = cmd_handler_cpuinfo },
    .{ .name = "docs", .help = "Show internal documentation topics", .handler = cmd_handler_docs },
    .{ .name = "cp", .help = "cp <src> <dest> - Copy file/folder recursively", .handler = cmd_handler_cp },
    .{ .name = "fetch", .help = "Show stylish system info summary", .handler = cmd_handler_fetch },
    .{ .name = "matrix", .help = "Enter the NovumOS Matrix (fun!)", .handler = cmd_handler_matrix },
    .{ .name = "mv", .help = "mv <src> <dest> - Move or rename file/folder", .handler = cmd_handler_mv },
    .{ .name = "ren", .help = "Alias for mv (rename file/folder)", .handler = cmd_handler_rename },
    .{ .name = "format", .help = "Low-level drive formatting tool", .handler = cmd_handler_format },
    .{ .name = "mkfs", .help = "Create filesystem on current drive", .handler = cmd_handler_mkfs },
    .{ .name = "install", .help = "install <src> [name] - Install Nova script", .handler = cmd_handler_install },
    .{ .name = "uninstall", .help = "uninstall <name> - Remove installed command", .handler = cmd_handler_uninstall },
    .{ .name = "ring3", .help = "Switch to Ring 3 (User Mode) test", .handler = cmd_handler_ring3 },
} ++ (if (config.ENABLE_DEBUG_CRASH_COMMANDS) [_]Command{
    .{ .name = "panic", .help = "Trigger a CPU exception for testing", .handler = cmd_handler_panic },
    .{ .name = "abort", .help = "Trigger a manual kernel panic", .handler = cmd_handler_abort },
    .{ .name = "invalid_op", .help = "Trigger an Invalid Opcode exception", .handler = cmd_handler_invalid_op },
    .{ .name = "stack_overflow", .help = "Trigger a Double Fault via stack overflow", .handler = cmd_handler_stack_overflow },
    .{ .name = "page_fault", .help = "Trigger a Page Fault exception", .handler = cmd_handler_page_fault },
    .{ .name = "gpf", .help = "Trigger a General Protection Fault", .handler = cmd_handler_gpf },
} else [_]Command{}) ++ (if (config.ENABLE_DEBUG_COMMANDS) [_]Command{
    .{ .name = "smp-test", .help = "Test global task queue across cores", .handler = cmd_handler_smp_test },
    .{ .name = "stress-test", .help = "Run heavy math on AP cores while BSP stays free", .handler = cmd_handler_stress_test },
} else [_]Command{});

// Local command buffer
var cmd_buffer: [1024]u8 = [_]u8{0} ** 1024;
var cmd_len: u16 = 0;
var cmd_pos: u16 = 0;

pub export fn shell_clear_history() void {
    history_count = 0;
    history_index = 0;
}

// Command history state
var history: [HISTORY_SIZE][1024]u8 = [_][1024]u8{[_]u8{0} ** 1024} ** HISTORY_SIZE;
var history_lens: [HISTORY_SIZE]u16 = [_]u16{0} ** HISTORY_SIZE;
var history_count: u8 = 0;
var history_index: u8 = 0;

var insert_mode: bool = true;
var prompt_row: u8 = 0;
var prompt_col: u8 = 0;

var history_loaded: bool = false;

// Autocomplete cycling state
var auto_cycling: bool = false;
var auto_prefix: [64]u8 = [_]u8{0} ** 64;
var auto_prefix_len: usize = 0;
var auto_match_index: usize = 0;
var auto_start_pos: u16 = 0;

/// Read a command from input
pub export fn read_command() void {
    vga.reset_color();
    for (&cmd_buffer) |*c| c.* = 0;
    cmd_len = 0;
    cmd_pos = 0;
    history_index = history_count;
    if (!history_loaded) {
        load_history_from_disk();
        history_loaded = true;
    }

    display_prompt();
    prompt_row = vga.zig_get_cursor_row();
    prompt_col = vga.zig_get_cursor_col();
    refresh_line(); // Initial draw of status bar

    while (true) {
        const char = keyboard.keyboard_wait_char();

        if (char == 3) {
            common.printZ("^C\n");
            cmd_len = 0;
            cmd_pos = 0;
            for (&cmd_buffer) |*b| b.* = 0;
            display_prompt();
            prompt_row = vga.zig_get_cursor_row();
            prompt_col = vga.zig_get_cursor_col();
            continue;
        }

        if (char != 9) auto_cycling = false;

        if (char == 10) { // Enter
            break;
        } else if (char == 8 or char == 127) { // Backspace
            if (cmd_pos > 0) {
                // Shift buffer left
                var i: usize = cmd_pos - 1;
                while (i < cmd_len - 1) : (i += 1) {
                    cmd_buffer[i] = cmd_buffer[i + 1];
                }
                cmd_buffer[cmd_len - 1] = 0;
                cmd_pos -= 1;
                cmd_len -= 1;
                refresh_line();
            }
        } else if (char == keyboard.KEY_LEFT) {
            if (cmd_pos > 0) {
                cmd_pos -= 1;
                move_screen_cursor();
            }
        } else if (char == keyboard.KEY_RIGHT) {
            if (cmd_pos < cmd_len) {
                cmd_pos += 1;
                move_screen_cursor();
            }
        } else if (char == keyboard.KEY_HOME) {
            cmd_pos = 0;
            move_screen_cursor();
        } else if (char == keyboard.KEY_END) {
            cmd_pos = cmd_len;
            move_screen_cursor();
        } else if (char == keyboard.KEY_DELETE) {
            if (cmd_pos < cmd_len) {
                // Shift buffer left starting from pos
                var i: usize = cmd_pos;
                while (i < cmd_len - 1) : (i += 1) {
                    cmd_buffer[i] = cmd_buffer[i + 1];
                }
                cmd_buffer[cmd_len - 1] = 0;
                cmd_len -= 1;
                refresh_line();
            }
        } else if (char == keyboard.KEY_INSERT) {
            insert_mode = !insert_mode;
            refresh_line();
        } else if (char == keyboard.KEY_CAPS or char == keyboard.KEY_NUM) {
            refresh_line();
        } else if (char == keyboard.KEY_UP) {
            if (history_count > 0 and history_index > 0) {
                history_index -= 1;
                load_history();
            }
        } else if (char == keyboard.KEY_DOWN) {
            if (history_index < history_count) {
                history_index += 1;
                if (history_index == history_count) {
                    clear_input_line();
                } else {
                    load_history();
                }
            }
        } else if (char == 9) { // Tab
            if (auto_cycling) {
                auto_match_index += 1;
            }
            autocomplete();
            refresh_line();
        } else if (char >= 32 and char <= 126) { // Printable characters
            if (cmd_len < 1023) {
                if (insert_mode) {
                    // Shift buffer right
                    var i: usize = cmd_len;
                    while (i > cmd_pos) : (i -= 1) {
                        cmd_buffer[i] = cmd_buffer[i - 1];
                    }
                    cmd_buffer[cmd_pos] = char;
                    cmd_len += 1;
                    cmd_pos += 1;
                } else {
                    // Overwrite mode
                    cmd_buffer[cmd_pos] = char;
                    if (cmd_pos == cmd_len) cmd_len += 1;
                    cmd_pos += 1;
                }
                refresh_line();
            }
        }
    }

    if (cmd_len > 0) {
        save_to_history();
        save_history_to_disk();
    }
    common.print_char('\r');
    common.print_char('\n');
}

fn save_history_to_disk() void {
    if (common.selected_disk < 0) return;
    const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;

    if (fat.read_bpb(drive)) |bpb| {
        var join_buf: [HISTORY_SIZE * 1024]u8 = [_]u8{0} ** (HISTORY_SIZE * 1024);
        var offset: usize = 0;

        var i: u8 = 0;
        while (i < history_count) : (i += 1) {
            const h_len = history_lens[i];
            for (0..h_len) |j| {
                join_buf[offset] = history[i][j];
                offset += 1;
            }
            join_buf[offset] = '\n';
            offset += 1;
        }

        _ = fat.write_file(drive, bpb, 0, ".HISTORY", join_buf[0..offset]);
    }
}

fn load_history_from_disk() void {
    if (common.selected_disk < 0) return;
    const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;

    if (fat.read_bpb(drive)) |bpb| {
        var load_buf: [HISTORY_SIZE * 1024]u8 = [_]u8{0} ** (HISTORY_SIZE * 1024);
        const read = fat.read_file(drive, bpb, 0, ".HISTORY", &load_buf);
        if (read <= 0) return;

        history_count = 0;
        var start: usize = 0;
        var i: usize = 0;
        const total: usize = @intCast(read);

        while (i < total and history_count < HISTORY_SIZE) : (i += 1) {
            if (load_buf[i] == '\n') {
                const len = i - start;
                if (len > 0 and len < 1024) {
                    for (0..len) |j| history[history_count][j] = load_buf[start + j];
                    history_lens[history_count] = @intCast(len);
                    history_count += 1;
                }
                start = i + 1;
            }
        }
        history_index = history_count;
    }
}

fn refresh_line() void {
    const saved_pos = cmd_pos;

    // 1. VGA Update (Silent clear to avoid triggering scrolls during clear)
    {
        var row = prompt_row;
        var col = prompt_col;
        var cleared: usize = 0;
        // Clear up to 2 lines or until end of screen
        while (cleared < 160) : (cleared += 1) {
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

    // Draw text on VGA. We use zig_print_char to allow natural wrapping.
    // If it scrolls, we need to detect it.
    vga.zig_set_cursor(prompt_row, prompt_col);
    for (cmd_buffer[0..cmd_len]) |c| {
        const row_before_char = vga.zig_get_cursor_row();
        vga.zig_print_char(c);
        const row_after_char = vga.zig_get_cursor_row();

        // Detection of scroll:
        // 1. row decreased (typical scroll)
        // 2. row stayed the same but we were on the last row and printed a newline/wrapped
        // Since zig_print_char handles scroll by staying on the same (last) row,
        // we need to be careful.
        if (row_after_char < row_before_char) {
            if (prompt_row > 0) prompt_row -= 1;
        } else if (row_before_char == vga.MAX_ROWS - 1 and row_after_char == vga.MAX_ROWS - 1) {
            // If we are at the last row and we just did a newline or wrapped, it scrolled
            // Note: internal_newline sets cursor_row to MAX_ROWS - 1 after scroll.
            // We can check if we wrapped or got a newline.
            if (c == '\n' or (vga.zig_get_cursor_col() == 0 and c != '\r' and c != 8)) {
                if (prompt_row > 0) prompt_row -= 1;
            }
        }
    }

    // 2. Serial Update
    serial.serial_hide_cursor();
    serial.serial_set_cursor(prompt_row, prompt_col);
    serial.serial_print_str(cmd_buffer[0..cmd_len]);
    serial.serial_clear_line();

    cmd_pos = saved_pos;
    move_screen_cursor();
    serial.serial_show_cursor();

    // Update status indicator in top-right corner
    vga.VIDEO_MEMORY[80 - 14] = (if (keyboard.keyboard_get_caps_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'C';
    vga.VIDEO_MEMORY[80 - 13] = (if (keyboard.keyboard_get_caps_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'A';
    vga.VIDEO_MEMORY[80 - 12] = (if (keyboard.keyboard_get_caps_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'P';
    vga.VIDEO_MEMORY[80 - 11] = (if (keyboard.keyboard_get_caps_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'S';

    vga.VIDEO_MEMORY[80 - 9] = (if (keyboard.keyboard_get_num_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'N';
    vga.VIDEO_MEMORY[80 - 8] = (if (keyboard.keyboard_get_num_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'U';
    vga.VIDEO_MEMORY[80 - 7] = (if (keyboard.keyboard_get_num_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800)) | 'M';

    const attr = @as(u16, 0x0E00); // Yellow on black
    const status = if (insert_mode) " INS " else " OVR ";
    for (status, 0..) |c, k| {
        vga.VIDEO_MEMORY[80 - 5 + k] = attr | @as(u16, c);
    }
}

fn move_screen_cursor() void {
    var new_col = @as(u16, prompt_col) + cmd_pos;
    var new_row = prompt_row;

    while (new_col >= 80) {
        new_col -= 80;
        new_row += 1;
    }
    vga.zig_set_cursor(@intCast(new_row), @intCast(new_col));
    serial.serial_set_cursor(@intCast(new_row), @intCast(new_col));
}

fn clear_input_line() void {
    cmd_len = 0;
    cmd_pos = 0;
    refresh_line();
}

fn load_history() void {
    clear_input_line();
    const len = history_lens[history_index];
    for (0..len) |i| {
        cmd_buffer[i] = history[history_index][i];
        common.print_char(cmd_buffer[i]);
    }
    cmd_len = len;
    cmd_pos = len;
}

fn save_to_history() void {
    if (history_count == HISTORY_SIZE) {
        for (0..HISTORY_SIZE - 1) |i| {
            history[i] = history[i + 1];
            history_lens[i] = history_lens[i + 1];
        }
        history_count -= 1;
    }
    for (0..cmd_len) |i| history[history_count][i] = cmd_buffer[i];
    history_lens[history_count] = cmd_len;
    history_count += 1;
}

const ShellLfnState = struct {
    buf: [256]u8,
    active: bool,
    checksum: u8,
};

fn shell_extract_lfn_part(buf: []const u8, start: usize, count: usize, out: []u8, out_offset: usize) void {
    for (0..count) |j| {
        if (out_offset + j >= out.len) return;
        const char_low = buf[start + j * 2];
        const char_high = buf[start + j * 2 + 1];
        if (char_low == 0 and char_high == 0) {
            out[out_offset + j] = 0;
            return;
        }
        out[out_offset + j] = if (char_high == 0) char_low else '?';
    }
}

fn autocomplete() void {
    if (cmd_len == 0 and !auto_cycling) return;

    if (!auto_cycling) {
        var start: usize = 0;
        var idx: usize = cmd_pos;
        while (idx > 0) {
            idx -= 1;
            if (cmd_buffer[idx] == ' ') {
                start = idx + 1;
                break;
            }
        }
        auto_start_pos = @intCast(start);
        auto_prefix_len = 0;
        const to_copy = cmd_pos - start;
        while (auto_prefix_len < to_copy and auto_prefix_len < 63) : (auto_prefix_len += 1) {
            auto_prefix[auto_prefix_len] = cmd_buffer[start + auto_prefix_len];
        }
        auto_match_index = 0;
        auto_cycling = true;
    }

    const current_prefix = auto_prefix[0..auto_prefix_len];
    var total_matches: usize = 0;

    var is_cd_cmd = false;
    if (auto_start_pos > 0) {
        var s_c: usize = 0;
        while (s_c < cmd_len and cmd_buffer[s_c] == ' ') : (s_c += 1) {}
        var e_c = s_c;
        while (e_c < cmd_len and cmd_buffer[e_c] != ' ') : (e_c += 1) {}
        if (common.std_mem_eql(cmd_buffer[s_c..e_c], "cd")) is_cd_cmd = true;
    }

    if (auto_start_pos == 0) {
        for (SHELL_COMMANDS) |cmd| {
            if (common.startsWithIgnoreCase(cmd.name, current_prefix)) total_matches += 1;
        }
    } else if (common.selected_disk >= 0) {
        const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
        if (fat.read_bpb(drive)) |bpb| {
            var d_buf: [512]u8 = undefined;
            var lfn: ShellLfnState = .{ .buf = [_]u8{0} ** 256, .active = false, .checksum = 0 };

            if (common.current_dir_cluster == 0 and bpb.fat_type != .FAT32) {
                var sector = bpb.first_root_dir_sector;
                while (sector < bpb.first_data_sector) : (sector += 1) {
                    ata.read_sector(drive, sector, &d_buf);
                    var j: usize = 0;
                    while (j < 512) : (j += 32) {
                        if (d_buf[j] == 0) {
                            lfn.active = false;
                            break;
                        }
                        if (d_buf[j] == 0xE5) {
                            lfn.active = false;
                            continue;
                        }
                        if (d_buf[j + 11] == 0x0F) {
                            // LFN Parse
                            const seq = d_buf[j];
                            const chk = d_buf[j + 11 + 2]; // offset 13
                            if ((seq & 0x40) != 0) {
                                lfn.active = true;
                                lfn.checksum = chk;
                                @memset(&lfn.buf, 0);
                            } else if (!lfn.active or lfn.checksum != chk) {
                                lfn.active = false;
                                continue;
                            }
                            var index = (seq & 0x1F);
                            if (index < 1) index = 1;
                            const offset = (index - 1) * 13;
                            if (offset < 240) {
                                shell_extract_lfn_part(&d_buf, j + 1, 5, &lfn.buf, offset);
                                shell_extract_lfn_part(&d_buf, j + 14, 6, &lfn.buf, offset + 5);
                                shell_extract_lfn_part(&d_buf, j + 28, 2, &lfn.buf, offset + 11);
                            }
                            continue;
                        }

                        if (is_cd_cmd and (d_buf[j + 11] & 0x10) == 0) {
                            lfn.active = false;
                            continue;
                        }

                        // Checksum for LFN match
                        var sum: u8 = 0;
                        for (0..11) |k| {
                            const is_odd = (sum & 1) != 0;
                            sum = (sum >> 1) + (if (is_odd) @as(u8, 0x80) else 0);
                            sum = sum +% d_buf[j + k];
                        }

                        var name_str: []const u8 = undefined;
                        // Temp buffer for 8.3 name if needed
                        const sn = fat.get_name_from_raw(d_buf[j .. j + 32]);

                        if (lfn.active and lfn.checksum == sum) {
                            var len: usize = 0;
                            while (len < 256 and lfn.buf[len] != 0) : (len += 1) {}
                            name_str = lfn.buf[0..len];
                        } else {
                            name_str = sn.buf[0..sn.len];
                        }
                        lfn.active = false;

                        if (common.startsWithIgnoreCase(name_str, current_prefix)) total_matches += 1;
                    }
                }
            } else {
                var current = if (common.current_dir_cluster == 0) bpb.root_cluster else common.current_dir_cluster;
                const eof_val = switch (bpb.fat_type) {
                    .FAT12 => @as(u32, 0xFF8),
                    .FAT16 => @as(u32, 0xFFF8),
                    .FAT32 => @as(u32, 0x0FFFFFF8),
                    else => @as(u32, 0xFFF8),
                };
                while (current < eof_val) {
                    const lba = bpb.first_data_sector + (current - 2) * bpb.sectors_per_cluster;
                    var s: u32 = 0;
                    while (s < bpb.sectors_per_cluster) : (s += 1) {
                        ata.read_sector(drive, lba + s, &d_buf);
                        var j: usize = 0;
                        while (j < 512) : (j += 32) {
                            if (d_buf[j] == 0) {
                                lfn.active = false;
                                break;
                            }
                            if (d_buf[j] == 0xE5) {
                                lfn.active = false;
                                continue;
                            }
                            if (d_buf[j + 11] == 0x0F) {
                                const seq = d_buf[j];
                                const chk = d_buf[j + 13];
                                if ((seq & 0x40) != 0) {
                                    lfn.active = true;
                                    lfn.checksum = chk;
                                    @memset(&lfn.buf, 0);
                                } else if (!lfn.active or lfn.checksum != chk) {
                                    lfn.active = false;
                                    continue;
                                }
                                var index = (seq & 0x1F);
                                if (index < 1) index = 1;
                                const offset = (index - 1) * 13;
                                if (offset < 240) {
                                    shell_extract_lfn_part(&d_buf, j + 1, 5, &lfn.buf, offset);
                                    shell_extract_lfn_part(&d_buf, j + 14, 6, &lfn.buf, offset + 5);
                                    shell_extract_lfn_part(&d_buf, j + 28, 2, &lfn.buf, offset + 11);
                                }
                                continue;
                            }

                            if (is_cd_cmd and (d_buf[j + 11] & 0x10) == 0) {
                                lfn.active = false;
                                continue;
                            }

                            // Checksum for LFN match
                            var sum: u8 = 0;
                            for (0..11) |k| {
                                const is_odd = (sum & 1) != 0;
                                sum = (sum >> 1) + (if (is_odd) @as(u8, 0x80) else 0);
                                sum = sum +% d_buf[j + k];
                            }

                            var name_str: []const u8 = undefined;
                            const sn = fat.get_name_from_raw(d_buf[j .. j + 32]);

                            if (lfn.active and lfn.checksum == sum) {
                                var len: usize = 0;
                                while (len < 256 and lfn.buf[len] != 0) : (len += 1) {}
                                name_str = lfn.buf[0..len];
                            } else {
                                name_str = sn.buf[0..sn.len];
                            }
                            lfn.active = false;

                            if (common.std_mem_eql(name_str, ".") or common.std_mem_eql(name_str, "..")) continue;

                            if (common.startsWithIgnoreCase(name_str, current_prefix)) total_matches += 1;
                        }
                    }
                    current = fat.get_fat_entry(drive, bpb, current);
                    if (current < 2 or current >= eof_val) break;
                }
            }
        }
    }

    if (total_matches == 0) {
        auto_cycling = false;
        return;
    }

    if (auto_match_index >= total_matches) auto_match_index = 0;

    // Pass 2: find match
    var current_match_idx: usize = 0;
    var picked_name_buf: [256]u8 = [_]u8{0} ** 256; // Buffer to hold the picked name
    var picked_len: usize = 0;
    var is_cmd = false;

    if (auto_start_pos == 0) {
        for (SHELL_COMMANDS) |cmd| {
            if (common.startsWithIgnoreCase(cmd.name, current_prefix)) {
                if (current_match_idx == auto_match_index) {
                    picked_len = @min(picked_name_buf.len, cmd.name.len);
                    for (0..picked_len) |p| picked_name_buf[p] = cmd.name[p];
                    is_cmd = true;
                    break;
                }
                current_match_idx += 1;
            }
        }
    } else if (common.selected_disk >= 0) {
        const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
        if (fat.read_bpb(drive)) |bpb| {
            var d_buf: [512]u8 = undefined;
            var lfn: ShellLfnState = .{ .buf = [_]u8{0} ** 256, .active = false, .checksum = 0 };

            if (common.current_dir_cluster == 0 and bpb.fat_type != .FAT32) {
                var sector = bpb.first_root_dir_sector;
                outer: while (sector < bpb.first_data_sector) : (sector += 1) {
                    ata.read_sector(drive, sector, &d_buf);
                    var j: usize = 0;
                    while (j < 512) : (j += 32) {
                        if (d_buf[j] == 0) {
                            lfn.active = false;
                            break;
                        }
                        if (d_buf[j] == 0xE5) {
                            lfn.active = false;
                            continue;
                        }
                        if (d_buf[j + 11] == 0x0F) {
                            // LFN Parse
                            const seq = d_buf[j];
                            const chk = d_buf[j + 13];
                            if ((seq & 0x40) != 0) {
                                lfn.active = true;
                                lfn.checksum = chk;
                                @memset(&lfn.buf, 0);
                            } else if (!lfn.active or lfn.checksum != chk) {
                                lfn.active = false;
                                continue;
                            }
                            var index = (seq & 0x1F);
                            if (index < 1) index = 1;
                            const offset = (index - 1) * 13;
                            if (offset < 240) {
                                shell_extract_lfn_part(&d_buf, j + 1, 5, &lfn.buf, offset);
                                shell_extract_lfn_part(&d_buf, j + 14, 6, &lfn.buf, offset + 5);
                                shell_extract_lfn_part(&d_buf, j + 28, 2, &lfn.buf, offset + 11);
                            }
                            continue;
                        }
                        if (is_cd_cmd and (d_buf[j + 11] & 0x10) == 0) {
                            lfn.active = false;
                            continue;
                        }

                        var sum: u8 = 0;
                        for (0..11) |k| {
                            const is_odd = (sum & 1) != 0;
                            sum = (sum >> 1) + (if (is_odd) @as(u8, 0x80) else 0);
                            sum = sum +% d_buf[j + k];
                        }

                        var name_str: []const u8 = undefined;
                        const sn = fat.get_name_from_raw(d_buf[j .. j + 32]);

                        if (lfn.active and lfn.checksum == sum) {
                            var len: usize = 0;
                            while (len < 256 and lfn.buf[len] != 0) : (len += 1) {}
                            name_str = lfn.buf[0..len];
                        } else {
                            name_str = sn.buf[0..sn.len];
                        }
                        lfn.active = false;

                        if (common.startsWithIgnoreCase(name_str, current_prefix)) {
                            if (current_match_idx == auto_match_index) {
                                picked_len = @min(picked_name_buf.len, name_str.len);
                                for (0..picked_len) |p| picked_name_buf[p] = name_str[p];
                                break :outer;
                            }
                            current_match_idx += 1;
                        }
                    }
                }
            } else {
                var current = if (common.current_dir_cluster == 0) bpb.root_cluster else common.current_dir_cluster;
                const eof_val = switch (bpb.fat_type) {
                    .FAT12 => @as(u32, 0xFF8),
                    .FAT16 => @as(u32, 0xFFF8),
                    .FAT32 => @as(u32, 0x0FFFFFF8),
                    else => @as(u32, 0xFFF8),
                };
                outer: while (current < eof_val) {
                    const lba = bpb.first_data_sector + (current - 2) * bpb.sectors_per_cluster;
                    var s: u32 = 0;
                    while (s < bpb.sectors_per_cluster) : (s += 1) {
                        ata.read_sector(drive, lba + s, &d_buf);
                        var j: usize = 0;
                        while (j < 512) : (j += 32) {
                            if (d_buf[j] == 0) {
                                lfn.active = false;
                                break;
                            }
                            if (d_buf[j] == 0xE5) {
                                lfn.active = false;
                                continue;
                            }
                            if (d_buf[j + 11] == 0x0F) {
                                // LFN Parse
                                const seq = d_buf[j];
                                const chk = d_buf[j + 13];
                                if ((seq & 0x40) != 0) {
                                    lfn.active = true;
                                    lfn.checksum = chk;
                                    @memset(&lfn.buf, 0);
                                } else if (!lfn.active or lfn.checksum != chk) {
                                    lfn.active = false;
                                    continue;
                                }
                                var index = (seq & 0x1F);
                                if (index < 1) index = 1;
                                const offset = (index - 1) * 13;
                                if (offset < 240) {
                                    shell_extract_lfn_part(&d_buf, j + 1, 5, &lfn.buf, offset);
                                    shell_extract_lfn_part(&d_buf, j + 14, 6, &lfn.buf, offset + 5);
                                    shell_extract_lfn_part(&d_buf, j + 28, 2, &lfn.buf, offset + 11);
                                }
                                continue;
                            }
                            if (is_cd_cmd and (d_buf[j + 11] & 0x10) == 0) {
                                lfn.active = false;
                                continue;
                            }

                            var sum: u8 = 0;
                            for (0..11) |k| {
                                const is_odd = (sum & 1) != 0;
                                sum = (sum >> 1) + (if (is_odd) @as(u8, 0x80) else 0);
                                sum = sum +% d_buf[j + k];
                            }

                            var name_str: []const u8 = undefined;
                            const sn = fat.get_name_from_raw(d_buf[j .. j + 32]);

                            if (lfn.active and lfn.checksum == sum) {
                                var len: usize = 0;
                                while (len < 256 and lfn.buf[len] != 0) : (len += 1) {}
                                name_str = lfn.buf[0..len];
                            } else {
                                name_str = sn.buf[0..sn.len];
                            }
                            lfn.active = false;

                            if (common.std_mem_eql(name_str, ".") or common.std_mem_eql(name_str, "..")) continue;

                            if (common.startsWithIgnoreCase(name_str, current_prefix)) {
                                if (current_match_idx == auto_match_index) {
                                    picked_len = @min(picked_name_buf.len, name_str.len);
                                    for (0..picked_len) |p| picked_name_buf[p] = name_str[p];
                                    break :outer;
                                }
                                current_match_idx += 1;
                            }
                        }
                    }
                    current = fat.get_fat_entry(drive, bpb, current);
                    if (current < 2 or current >= eof_val) break;
                }
            }
        }
    }

    if (picked_len > 0) {
        cmd_len = auto_start_pos;

        var needs_quotes = false;
        for (picked_name_buf[0..picked_len]) |c| {
            if (c == ' ') {
                needs_quotes = true;
                break;
            }
        }

        if (needs_quotes) {
            cmd_buffer[cmd_len] = '"';
            cmd_len += 1;
        }

        for (0..picked_len) |p| {
            cmd_buffer[cmd_len] = picked_name_buf[p];
            cmd_len += 1;
        }

        if (needs_quotes) {
            cmd_buffer[cmd_len] = '"';
            cmd_len += 1;
        }

        if (is_cmd) {
            cmd_buffer[cmd_len] = ' ';
            cmd_len += 1;
        }
        cmd_pos = cmd_len;
        var z = cmd_len;
        while (z < 1024) : (z += 1) cmd_buffer[z] = 0;
    }
}

/// Dispatch commands
pub export fn execute_command() void {
    shell_execute_literal(cmd_buffer[0..cmd_len]);
}

pub fn shell_execute_literal(cmd: []const u8) void {
    var cmd_raw = common.trim(cmd);
    if (cmd_raw.len == 0) return;

    // Pipe support: cmd1 | cmd2
    if (common.std_mem_indexOf(u8, cmd_raw, "|")) |idx| {
        const left = common.trim(cmd_raw[0..idx]);
        const right = common.trim(cmd_raw[idx + 1 ..]);

        if (left.len > 0 and right.len > 0) {
            common.pipe_active = true;
            common.pipe_pos = 0;
            shell_execute_literal(left);
            common.pipe_active = false;

            if (common.pipe_pos > 0) {
                common.pipe_read_active = true;
                shell_execute_literal(right);
                common.pipe_read_active = false;
                common.pipe_pos = 0;
            }
            return;
        }
    }

    // Output redirection support: cmd > file or cmd >> file
    var redirect_file: ?[]const u8 = null;
    var append_mode: bool = false;
    if (common.std_mem_indexOf(u8, cmd_raw, ">>")) |idx| {
        append_mode = true;
        const file_part = common.trim(cmd_raw[idx + 2 ..]);
        if (file_part.len > 0) {
            redirect_file = file_part;
            cmd_raw = common.trim(cmd_raw[0..idx]);
        }
    } else if (common.std_mem_indexOf(u8, cmd_raw, ">")) |idx| {
        append_mode = false;
        const file_part = common.trim(cmd_raw[idx + 1 ..]);
        if (file_part.len > 0) {
            redirect_file = file_part;
            cmd_raw = common.trim(cmd_raw[0..idx]);
        }
    }

    var argv: [8][]const u8 = undefined;
    const argc = common.parseArgs(cmd_raw, &argv);
    if (argc == 0) return;

    if (redirect_file != null) {
        if (common.selected_disk < 0) {
            common.printError("Error: Redirection requires a mounted disk\n");
            return;
        }
        common.redirect_active = true;
        common.redirect_pos = 0;
    }

    defer {
        if (redirect_file) |file| {
            common.redirect_active = false;
            const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
            if (fat.read_bpb(drive)) |bpb| {
                if (append_mode) {
                    _ = fat.append_to_file(drive, bpb, common.current_dir_cluster, file, common.redirect_buffer[0..common.redirect_pos]);
                } else {
                    _ = fat.write_file(drive, bpb, common.current_dir_cluster, file, common.redirect_buffer[0..common.redirect_pos]);
                }
            }
            common.redirect_pos = 0;
        }
    }

    const cmd_name = argv[0];

    // 1. Built-in Shell Commands
    for (SHELL_COMMANDS) |sc| {
        if (common.std_mem_eql(sc.name, cmd_name)) {
            // Reconstruct args string for legacy handlers
            var i: usize = 0;
            while (i < cmd_raw.len and cmd_raw[i] != ' ') : (i += 1) {}
            while (i < cmd_raw.len and cmd_raw[i] == ' ') : (i += 1) {}
            const args_only = cmd_raw[i..];

            sc.handler(args_only);
            return;
        }
    }

    // 2. Relative/Absolute Path Scripts (containing /)
    var contains_slash = false;
    for (cmd_name) |c| {
        if (c == '/' or c == '\\') {
            contains_slash = true;
            break;
        }
    }

    if (contains_slash) {
        if (common.endsWithIgnoreCase(cmd_name, ".nv")) {
            if (common.selected_disk >= 0) {
                const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
                if (fat.read_bpb(drive)) |bpb| {
                    if (fat.resolve_full_path(drive, bpb, common.current_dir_cluster, common.current_path[0..common.current_path_len], cmd_name)) |res| {
                        if (!res.is_dir) {
                            nova_commands.setScriptArgs(argv[1..argc]);
                            nova_interpreter.runScript(res.path[0..res.path_len]);
                            return;
                        }
                    }
                }
            }
        } else {
            common.printError("shell: Direct path execution requires .nv extension\n");
            return;
        }
    }

    // 3. Built-in Nova Scripts
    for (BUILTIN_SCRIPTS) |script| {
        if (common.std_mem_eql(script.name, cmd_name)) {
            nova_commands.setScriptArgs(argv[1..argc]);
            nova_interpreter.runScriptSource(script.source, null, false);
            return;
        }
    }

    // 4. System Path Scripts (/.SYSTEM/CMDS/<cmd_name>.nv)
    if (common.selected_disk >= 0) {
        var path_buf: [128]u8 = [_]u8{0} ** 128;
        const prefix = "/.SYSTEM/CMDS/";
        const extension = ".nv";

        if (prefix.len + cmd_name.len + extension.len < 128) {
            common.copy(path_buf[0..], prefix);
            common.copy(path_buf[prefix.len..], cmd_name);
            common.copy(path_buf[prefix.len + cmd_name.len ..], extension);
            const full_path = path_buf[0 .. prefix.len + cmd_name.len + extension.len];

            const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
            if (fat.read_bpb(drive)) |bpb| {
                if (fat.find_entry(drive, bpb, 0, full_path)) |_| {
                    nova_commands.setScriptArgs(argv[1..argc]);
                    nova_interpreter.runScript(full_path);
                    return;
                }
            }
        }
    }

    common.printError("shell: command not found: ");
    common.printError(cmd_name);
    common.printError("\n");
}

// Handler functions for commands
fn cmd_handler_help(args: []const u8) void {
    var page: usize = 1;
    const arg = common.trim(args);
    if (arg.len > 0 and arg[0] >= '0' and arg[0] <= '9') {
        page = @intCast(arg[0] - '0');
        if (page == 0) page = 1;
    }

    const items_per_page = 10;
    const total_pages = (SHELL_COMMANDS.len + items_per_page - 1) / items_per_page;

    if (page > total_pages) page = total_pages;

    common.printZ("Commands (Page ");
    common.printNum(@intCast(page));
    common.printZ("/");
    common.printNum(@intCast(total_pages));
    common.printZ("):\n");

    const start = (page - 1) * items_per_page;
    const end = @min(start + items_per_page, SHELL_COMMANDS.len);

    var i = start;
    while (i < end) : (i += 1) {
        const cmd = SHELL_COMMANDS[i];
        common.printZ("  ");
        vga.set_color(11, 0); // Light Cyan/Yellow
        common.printZ(cmd.name);
        vga.reset_color();
        // Padding
        var p = cmd.name.len;
        while (p < 15) : (p += 1) common.print_char(' ');
        common.printZ("- ");
        common.printZ(cmd.help);
        common.printZ("\n");
    }

    if (page < total_pages) {
        common.printZ("Tip: Use 'help ");
        common.printNum(@intCast(page + 1));
        common.printZ("' for more commands.\n");
    }
    common.printZ("\n");
}

fn cmd_handler_clear(_: []const u8) void {
    vga.clear_screen();
    messages.print_welcome();
}

fn cmd_handler_about(_: []const u8) void {
    common.printZ("NovumOS v" ++ versioning.NOVUMOS_VERSION ++ "\n");
    common.printZ("32-bit Protected Mode OS\n");
    common.printZ("x86 + Zig kernel modules\n");
    common.printZ("=== By MinecAnton209 ===\n\n");
}

fn cmd_handler_nova(args: []const u8) void {
    nova.nova_start(args.ptr, args.len);
}

fn cmd_handler_uptime(_: []const u8) void {
    shell_cmds.cmd_uptime();
}

fn cmd_handler_reboot(_: []const u8) void {
    shell_cmds.cmd_reboot();
}

fn cmd_handler_shutdown(_: []const u8) void {
    shell_cmds.cmd_shutdown();
}

fn cmd_handler_ring3(args: []const u8) void {
    _ = args;
    shell_cmds.cmd_ring3();
}

fn cmd_handler_ls(args: []const u8) void {
    shell_cmds.cmd_ls(args.ptr, @intCast(args.len));
}

fn cmd_handler_la(args: []const u8) void {
    var buf: [128]u8 = [_]u8{0} ** 128;
    buf[0] = '-';
    buf[1] = 'a';
    buf[2] = ' ';
    if (args.len > 0) {
        if (3 + args.len > 128) return;
        common.copy(buf[3..], args);
        shell_cmds.cmd_ls(buf[0..].ptr, @intCast(3 + args.len));
    } else {
        shell_cmds.cmd_ls(buf[0..].ptr, 2);
    }
}

fn cmd_handler_lsdsk(_: []const u8) void {
    shell_cmds.cmd_lsdsk();
}

fn cmd_handler_mount(args: []const u8) void {
    if (args.len > 0) {
        shell_cmds.cmd_mount(args.ptr, @intCast(args.len));
    } else {
        common.printZ("Usage: mount <drive>\n");
    }
}

fn cmd_handler_mkfs12(args: []const u8) void {
    if (args.len > 0) {
        shell_cmds.cmd_mkfs_fat12(args.ptr, @intCast(args.len));
    } else {
        common.printZ("Usage: mkfs-fat12 <drive>\n");
    }
}

fn cmd_handler_mkfs16(args: []const u8) void {
    if (args.len > 0) {
        shell_cmds.cmd_mkfs_fat16(args.ptr, @intCast(args.len));
    } else {
        common.printZ("Usage: mkfs-fat16 <drive>\n");
    }
}

fn cmd_handler_mkfs32(args: []const u8) void {
    if (args.len > 0) {
        shell_cmds.cmd_mkfs_fat32(args.ptr, @intCast(args.len));
    } else {
        common.printZ("Usage: mkfs-fat32 <drive>\n");
    }
}

fn cmd_handler_touch(args: []const u8) void {
    if (args.len > 0) {
        shell_cmds.cmd_touch(args.ptr, @intCast(args.len));
    } else {
        common.printZ("Usage: touch <file>\n");
    }
}

fn cmd_handler_write(args: []const u8) void {
    var argv: [8][]const u8 = undefined;
    const argc = common.parseArgs(args, &argv);
    if (argc < 2) {
        common.printZ("Usage: write [-a] <file> <text>\n");
        return;
    }

    var append = false;
    var arg_idx: usize = 0;
    if (common.std_mem_eql(argv[0], "-a")) {
        append = true;
        arg_idx = 1;
        if (argc < 2) {
            common.printZ("Usage: write [-a] <file> <text>\n");
            return;
        }
    }

    const name = argv[arg_idx];

    if (!append and common.selected_disk >= 0) {
        const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
        if (fat.read_bpb(drive)) |bpb| {
            if (fat.find_entry(drive, bpb, common.current_dir_cluster, name)) |_| {
                common.printZ("Warning: overwriting existing file '");
                common.printZ(name);
                common.printZ("'\n");
            }
        }
    }

    // Find the start of the data in the raw string
    var i: usize = 0;
    // Skip spaces
    while (i < args.len and args[i] == ' ') : (i += 1) {}

    if (append) {
        // Skip "-a" and following spaces
        i += 2;
        while (i < args.len and args[i] == ' ') : (i += 1) {}
    }

    // Skip filename
    if (i < args.len and args[i] == '"') {
        i += 1;
        while (i < args.len and args[i] != '"') : (i += 1) {}
        if (i < args.len) i += 1;
    } else {
        while (i < args.len and args[i] != ' ') : (i += 1) {}
    }
    // Skip spaces before data
    while (i < args.len and args[i] == ' ') : (i += 1) {}

    const data = args[i..];
    shell_cmds.cmd_write(name.ptr, @intCast(name.len), data.ptr, @intCast(data.len), append);
}

fn cmd_handler_rm(args: []const u8) void {
    if (args.len > 0) {
        shell_cmds.cmd_rm(args.ptr, @intCast(args.len));
    } else {
        common.printZ("Usage: rm <file>\n");
    }
}

fn cmd_handler_cat(args: []const u8) void {
    if (args.len > 0) {
        shell_cmds.cmd_cat(args.ptr, @intCast(args.len));
    } else {
        common.printZ("Usage: cat <file>\n");
    }
}

fn cmd_handler_edit(args: []const u8) void {
    if (args.len > 0) {
        shell_cmds.cmd_edit(args.ptr, @intCast(args.len));
    } else {
        common.printZ("Usage: edit <file>\n");
    }
}

fn cmd_handler_history(_: []const u8) void {
    var j: u8 = 0;
    while (j < history_count) : (j += 1) {
        common.printNum(j + 1);
        common.printZ(". ");
        common.printZ(history[j][0..history_lens[j]]);
        common.printZ("\n");
    }
}

fn cmd_handler_echo(args: []const u8) void {
    shell_cmds.cmd_echo(args.ptr, @intCast(args.len));
}

fn cmd_handler_mem(args: []const u8) void {
    shell_cmds.cmd_mem(args.ptr, @intCast(args.len));
}

fn cmd_handler_time(_: []const u8) void {
    shell_cmds.cmd_time();
}

fn cmd_handler_top(_: []const u8) void {
    top_cmd.cmd_top();
}

fn cmd_handler_sysinfo(_: []const u8) void {
    shell_cmds.cmd_sysinfo();
}

fn cmd_handler_hexdump(args: []const u8) void {
    if (args.len > 0 or common.pipe_read_active) {
        shell_cmds.cmd_hexdump(args.ptr, @intCast(args.len));
    } else {
        common.printZ("Usage: hexdump <file>\n");
    }
}

fn cmd_handler_more(args: []const u8) void {
    if (args.len > 0 or common.pipe_read_active) {
        shell_cmds.cmd_more(args.ptr, @intCast(args.len));
    } else {
        common.printZ("Usage: more <file>\n");
    }
}

fn cmd_handler_fetch(_: []const u8) void {
    shell_cmds.cmd_fetch();
}

fn cmd_handler_matrix(_: []const u8) void {
    shell_cmds.cmd_matrix();
}

fn cmd_handler_cpuinfo(_: []const u8) void {
    shell_cmds.cmd_cpuinfo();
}

fn cmd_handler_smp_test(_: []const u8) void {
    shell_cmds.cmd_smp_test();
}

fn cmd_handler_stress_test(_: []const u8) void {
    shell_cmds.cmd_stress_test();
}

fn cmd_handler_panic(_: []const u8) void {
    if (config.ENABLE_DEBUG_CRASH_COMMANDS) shell_cmds.cmd_panic();
}

const crash_suite = struct {
    fn cmd_handler_abort(_: []const u8) void {
        if (config.ENABLE_DEBUG_CRASH_COMMANDS) shell_cmds.cmd_abort();
    }

    fn cmd_handler_invalid_op(_: []const u8) void {
        if (config.ENABLE_DEBUG_CRASH_COMMANDS) shell_cmds.cmd_invalid_op();
    }

    fn cmd_handler_stack_overflow(_: []const u8) void {
        if (config.ENABLE_DEBUG_CRASH_COMMANDS) shell_cmds.cmd_stack_overflow();
    }

    fn cmd_handler_page_fault(_: []const u8) void {
        if (config.ENABLE_DEBUG_CRASH_COMMANDS) shell_cmds.cmd_page_fault();
    }

    fn cmd_handler_gpf(_: []const u8) void {
        if (config.ENABLE_DEBUG_CRASH_COMMANDS) shell_cmds.cmd_gpf();
    }
};

const cmd_handler_abort = crash_suite.cmd_handler_abort;
const cmd_handler_invalid_op = crash_suite.cmd_handler_invalid_op;
const cmd_handler_stack_overflow = crash_suite.cmd_handler_stack_overflow;
const cmd_handler_page_fault = crash_suite.cmd_handler_page_fault;
const cmd_handler_gpf = crash_suite.cmd_handler_gpf;

fn cmd_handler_docs(args: []const u8) void {
    shell_cmds.cmd_docs(args.ptr, @intCast(args.len));
}

fn cmd_handler_cp(args: []const u8) void {
    shell_cmds.cmd_cp(args.ptr, @intCast(args.len));
}

fn cmd_handler_mv(args: []const u8) void {
    shell_cmds.cmd_mv(args.ptr, @intCast(args.len));
}

fn cmd_handler_rename(args: []const u8) void {
    shell_cmds.cmd_rename(args.ptr, @intCast(args.len));
}

fn cmd_handler_format(args: []const u8) void {
    shell_cmds.cmd_format(args.ptr, @intCast(args.len));
}

fn cmd_handler_mkfs(args: []const u8) void {
    shell_cmds.cmd_mkfs(args.ptr, @intCast(args.len));
}
fn cmd_handler_mkdir(args: []const u8) void {
    if (args.len > 0) {
        shell_cmds.cmd_mkdir(args.ptr, @intCast(args.len));
    } else {
        common.printZ("Usage: mkdir <name>\n");
    }
}

fn cmd_handler_install(args: []const u8) void {
    // 1. Skip leading space
    var i: usize = 0;
    while (i < args.len and args[i] == ' ') : (i += 1) {}
    if (i >= args.len) {
        common.printZ("Usage: install <script.nv> [name]\n");
        return;
    }

    // 2. Parse src
    const start_src = i;
    while (i < args.len and args[i] != ' ') : (i += 1) {}
    const src = args[start_src..i];

    // 3. Skip space for optional name
    while (i < args.len and args[i] == ' ') : (i += 1) {}

    var name_arg: []const u8 = "";
    if (i < args.len) {
        const start_name = i;
        while (i < args.len and args[i] != ' ') : (i += 1) {}
        name_arg = args[start_name..i];
    } else {
        name_arg = src; // Default to src filename
    }

    // Ensure name has .nv extension
    var dest_name_buf: [64]u8 = [_]u8{0} ** 64;
    var dest_name: []const u8 = undefined;

    var is_nv = false;
    if (name_arg.len >= 3) {
        if (name_arg[name_arg.len - 3] == '.' and
            (name_arg[name_arg.len - 2] == 'n' or name_arg[name_arg.len - 2] == 'N') and
            (name_arg[name_arg.len - 1] == 'v' or name_arg[name_arg.len - 1] == 'V')) is_nv = true;
    }

    if (is_nv) {
        dest_name = name_arg;
    } else {
        if (name_arg.len + 3 > 64) {
            common.printZ("Error: Name too long\n");
            return;
        }
        common.copy(dest_name_buf[0..], name_arg);
        common.copy(dest_name_buf[name_arg.len..], ".nv");
        dest_name = dest_name_buf[0 .. name_arg.len + 3];
    }

    // Perform installation
    if (common.selected_disk < 0) {
        common.printZ("Error: No disk mounted.\n");
        return;
    }
    const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;

    if (fat.read_bpb(drive)) |bpb| {
        common.printZ("Installing ");
        common.printZ(src);
        common.printZ(" to /.SYSTEM/CMDS/");
        common.printZ(dest_name);
        common.printZ("...\n");

        _ = fat.create_directory(drive, bpb, 0, "/.SYSTEM");
        _ = fat.create_directory(drive, bpb, 0, "/.SYSTEM/CMDS");

        // Construct dest path: /.SYSTEM/CMDS/<dest_name>
        var dest_path_buf: [128]u8 = [_]u8{0} ** 128;
        const prefix = "/.SYSTEM/CMDS/";
        common.copy(dest_path_buf[0..], prefix);
        common.copy(dest_path_buf[prefix.len..], dest_name);
        const dest_path = dest_path_buf[0 .. prefix.len + dest_name.len];

        if (fat.copy_file(drive, bpb, common.current_dir_cluster, src, dest_path)) {
            common.printZ("Success! You can now run it by typing: ");
            if (!is_nv) {
                common.printZ(name_arg);
            } else {
                common.printZ(dest_name);
            }
            common.printZ("\n");
        } else {
            common.printZ("Error: Copy failed. Check if source exists.\n");
        }
    } else {
        common.printZ("Error: Disk read failed\n");
    }
}

fn cmd_handler_uninstall(args: []const u8) void {
    // 1. Parse name
    var i: usize = 0;
    while (i < args.len and args[i] == ' ') : (i += 1) {}
    if (i >= args.len) {
        common.printZ("Usage: uninstall <cmd_name>\n");
        return;
    }
    const name_start = i;
    while (i < args.len and args[i] != ' ') : (i += 1) {}
    const name = args[name_start..i];

    // Ensure .nv extension
    var dest_name_buf: [64]u8 = [_]u8{0} ** 64;
    var dest_name: []const u8 = undefined;

    var is_nv = false;
    if (name.len >= 3) {
        if (name[name.len - 3] == '.' and
            (name[name.len - 2] == 'n' or name[name.len - 2] == 'N') and
            (name[name.len - 1] == 'v' or name[name.len - 1] == 'V')) is_nv = true;
    }

    if (is_nv) {
        dest_name = name;
    } else {
        if (name.len + 3 > 64) {
            common.printZ("Error: Name too long\n");
            return;
        }
        common.copy(dest_name_buf[0..], name);
        common.copy(dest_name_buf[name.len..], ".nv");
        dest_name = dest_name_buf[0 .. name.len + 3];
    }

    // Perform delete
    if (common.selected_disk < 0) {
        common.printZ("Error: No disk mounted.\n");
        return;
    }
    const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;

    if (fat.read_bpb(drive)) |bpb| {
        // Construct path: /.SYSTEM/CMDS/<dest_name>
        var dest_path_buf: [128]u8 = [_]u8{0} ** 128;
        const prefix = "/.SYSTEM/CMDS/";
        common.copy(dest_path_buf[0..], prefix);
        common.copy(dest_path_buf[prefix.len..], dest_name);
        const dest_path = dest_path_buf[0 .. prefix.len + dest_name.len];

        common.printZ("Uninstalling ");
        common.printZ(dest_path);
        common.printZ("...\n");

        if (fat.delete_file(drive, bpb, 0, dest_path)) {
            common.printZ("Success!\n");
        } else {
            common.printZ("Error: Command not found or delete failed.\n");
        }
    } else {
        common.printZ("Error: Disk read failed\n");
    }
}

fn cmd_handler_cd(args: []const u8) void {
    if (args.len > 0) {
        shell_cmds.cmd_cd(args.ptr, @intCast(args.len));
    } else {
        // cd with no args goes to root
        shell_cmds.cmd_cd("/".ptr, 1);
    }
}

fn cmd_handler_pwd(_: []const u8) void {
    shell_cmds.cmd_pwd();
}

fn cmd_handler_tree(_: []const u8) void {
    shell_cmds.cmd_tree();
}

fn display_prompt() void {
    if (vga.zig_get_cursor_col() > 0) common.printZ("\n");

    vga.set_color(10, 0); // Light Green
    if (common.selected_disk >= 0) {
        common.print_char(@intCast(@as(u8, @intCast(common.selected_disk)) + '0'));
        common.print_char(':');
    }

    vga.set_color(11, 0); // Light Yellow/Cyan for path
    if (common.current_path_len == 0) {
        common.printZ("/");
    } else {
        common.printZ(common.current_path[0..common.current_path_len]);
    }

    vga.set_color(15, 0); // White for bracket
    common.printZ("> ");
    vga.reset_color();
}

fn display_prompt_serial() void {
    if (common.selected_disk >= 0) {
        serial.serial_print_char(@intCast(@as(u8, @intCast(common.selected_disk)) + '0'));
        serial.serial_print_char(':');
    }
    if (common.current_path_len == 0) {
        serial.serial_print_str("/");
    } else {
        serial.serial_print_str(common.current_path[0..common.current_path_len]);
    }
    serial.serial_print_str("> ");
}
