const common = @import("../commands/common.zig");
const keyboard = @import("../arch/mod.zig").keyboard_isr;
const shell_cmds = @import("shell_cmds.zig");
const elf = @import("../kernel/elf.zig");
const messages = @import("../kernel/messages.zig");
const vga = @import("../drivers/vga.zig");
const versioning = @import("../kernel/versioning.zig");
const serial = @import("../drivers/serial.zig");
const fat = @import("../drivers/fat.zig");
const ata = @import("../drivers/ata.zig");
const config = @import("../config.zig");
const nova_legacy_interpreter = @import("../nova_legacy/interpreter.zig");
const nova_legacy_commands = @import("../nova_legacy/commands.zig");
const top_cmd = @import("../commands/top.zig");
const doomfire_cmd = @import("../commands/doomfire.zig");
const lfb = @import("../drivers/lfb.zig");
const rtc = @import("../drivers/time/time.zig");
const idt_watchdog = @import("../arch/mod.zig").idt_watchdog;
const mouse = @import("../kernel/mouse.zig");
const speaker = @import("../drivers/speaker.zig");
const speaker_timer = @import("../drivers/timer.zig");
const quantum = @import("../kernel/quantum.zig");
const memory = @import("../kernel/memory.zig");

// NovumOS Shell - Main command line interface

extern const mb2_info: u32;
extern const fb_addr: u32;
extern const fb_pitch: u32;
extern const fb_width: u32;
extern const fb_height: u32;
extern const fb_bpp: u32;

// Embedded Nova Scripts
const EmbeddedScript = struct {
    name: []const u8,
    source: []const u8,
};

const BUILTIN_SCRIPTS = [_]EmbeddedScript{
    .{ .name = "hello", .source = @embedFile("../nova_legacy/scripts/hello.nv") },
    .{ .name = "syscheck", .source = @embedFile("../nova_legacy/scripts/syscheck.nv") },
};

// Shell configuration
const build_config = @import("build_config");
const HISTORY_SIZE = if (build_config.history_size) |h| h else config.HISTORY_SIZE;

// Command dispatcher kinds — eliminates 50+ thin wrapper functions
const CmdKind = enum {
    direct_args, // handler(args.ptr, args.len)
    no_args, // handler()
    guarded_args, // handler(args.ptr, len) if args.len > 0, else print usage
    custom, // handler(args) with custom logic
};

const Command = struct {
    name: []const u8,
    help: []const u8,
    handler: *const fn ([]const u8) void,
    kind: CmdKind = .custom,
    usage: ?[]const u8 = null,
};

fn cmd_handler_kill(args: []const u8) void {
    shell_cmds.cmd_kill(args.ptr, @intCast(args.len));
}

fn cmd_handler_idt_modify(args: []const u8) void {
    idt_watchdog.cmd_idt_modify(args);
}

fn cmd_handler_mouse(_: []const u8) void {
    if (mouse.initialized) {
        common.printZ("Mouse: Initialized\n");
        common.printZ("  Buttons: ");
        common.printNum(@as(i32, mouse.last_buttons));
        common.printZ("\n");
        common.printZ("  Packets: ");
        common.printNum(@as(i32, @intCast(mouse.packet_count)));
        common.printZ("\n");
    } else {
        common.printZ("Mouse: Not initialized\n");
        common.printZ("  Debug: ");
        common.printNum(@as(i32, @intCast(mouse.init_debug)));
        common.printZ("\n");
    }
}

// Generic handlers that eliminate per-command wrapper functions
// via comptime dispatch on the underlying shell_cmds function.
fn direct_handler(comptime f: anytype) fn ([]const u8) void {
    return struct {
        fn h(args: []const u8) void {
            f(args.ptr, @intCast(args.len));
        }
    }.h;
}
fn no_args_handler(comptime f: anytype) fn ([]const u8) void {
    return struct {
        fn h(_: []const u8) void {
            f();
        }
    }.h;
}
fn guarded_handler(comptime f: anytype, comptime usage: []const u8) fn ([]const u8) void {
    return struct {
        fn h(args: []const u8) void {
            if (args.len > 0) f(args.ptr, @intCast(args.len)) else common.printZ(usage);
        }
    }.h;
}

const SHELL_COMMANDS = [_]Command{
    .{ .name = "help", .help = "Show this help message (Tip: help 2)", .handler = cmd_handler_help, .kind = .custom },
    .{ .name = "?", .help = "Alias for help", .handler = cmd_handler_help, .kind = .custom },
    .{ .name = "clear", .help = "Clear screen and reset console state", .handler = cmd_handler_clear, .kind = .custom },
    .{ .name = "cls", .help = "Alias for clear", .handler = cmd_handler_clear, .kind = .custom },
    .{ .name = "about", .help = "Show legal information & credits", .handler = cmd_handler_about, .kind = .custom },
    .{ .name = "nova", .help = "Start Nova Scripting Interpreter", .handler = cmd_handler_nova_legacy, .kind = .custom },
    .{ .name = "nova_legacy", .help = "Alias for nova", .handler = cmd_handler_nova_legacy, .kind = .custom },
    .{ .name = "top", .help = "Real-time CPU and Task Monitor", .handler = no_args_handler(&top_cmd.cmd_top), .kind = .no_args },
    .{ .name = "ps", .help = "List active system processes", .handler = no_args_handler(&shell_cmds.cmd_ps), .kind = .no_args },
    .{ .name = "mouse", .help = "Show PS/2 mouse status and statistics", .handler = cmd_handler_mouse, .kind = .custom },
    .{ .name = "kill", .help = "kill <pid> - Terminate a running process", .handler = cmd_handler_kill, .kind = .custom },
    .{ .name = "uptime", .help = "Show system runtime and RTC time", .handler = no_args_handler(&shell_cmds.cmd_uptime), .kind = .no_args },
    .{ .name = "reboot", .help = "Safely restart the system", .handler = no_args_handler(&shell_cmds.cmd_reboot), .kind = .no_args },
    .{ .name = "shutdown", .help = "Safely turn off the system (ACPI)", .handler = no_args_handler(&shell_cmds.cmd_shutdown), .kind = .no_args },
    .{ .name = "ls", .help = "List files/folders in current directory", .handler = direct_handler(&shell_cmds.cmd_ls), .kind = .direct_args },
    .{ .name = "hexdump", .help = "hexdump <f> - Display file content in hex/ASCII", .handler = guarded_handler(&shell_cmds.cmd_hexdump, "Usage: hexdump <file>\n"), .kind = .guarded_args, .usage = "Usage: hexdump <file>\n" },
    .{ .name = "more", .help = "more <f> - Display file content with paging", .handler = guarded_handler(&shell_cmds.cmd_more, "Usage: more <file>\n"), .kind = .guarded_args, .usage = "Usage: more <file>\n" },
    .{ .name = "la", .help = "List all files (including hidden)", .handler = cmd_handler_la, .kind = .custom },
    .{ .name = "lsdsk", .help = "List storage devices and partitions", .handler = no_args_handler(&shell_cmds.cmd_lsdsk), .kind = .no_args },
    .{ .name = "lspci", .help = "List PCI devices and hardware bridges", .handler = no_args_handler(&shell_cmds.cmd_lspci), .kind = .no_args },
    .{ .name = "mount", .help = "mount <0|1> - Select active drive", .handler = guarded_handler(&shell_cmds.cmd_mount, "Usage: mount <drive>\n"), .kind = .guarded_args, .usage = "Usage: mount <drive>\n" },
    .{ .name = "mkdir", .help = "mkdir <name> - Create a new directory", .handler = guarded_handler(&shell_cmds.cmd_mkdir, "Usage: mkdir <name>\n"), .kind = .guarded_args, .usage = "Usage: mkdir <name>\n" },
    .{ .name = "md", .help = "Alias for mkdir", .handler = guarded_handler(&shell_cmds.cmd_mkdir, "Usage: mkdir <name>\n"), .kind = .guarded_args, .usage = "Usage: mkdir <name>\n" },
    .{ .name = "cd", .help = "cd <dir|..|/> - Change directory", .handler = cmd_handler_cd, .kind = .custom, .usage = "Usage: cd <directory>\n" },
    .{ .name = "pwd", .help = "Print current working directory", .handler = no_args_handler(&shell_cmds.cmd_pwd), .kind = .no_args },
    .{ .name = "tree", .help = "Display recursive directory structure", .handler = no_args_handler(&shell_cmds.cmd_tree), .kind = .no_args },
    .{ .name = "mkfs-fat12", .help = "Format drive as FAT12 (legacy)", .handler = guarded_handler(&shell_cmds.cmd_mkfs_fat12, "Usage: mkfs-fat12 <drive>\n"), .kind = .guarded_args, .usage = "Usage: mkfs-fat12 <drive>\n" },
    .{ .name = "mkfs-fat16", .help = "Format drive as FAT16 (standard)", .handler = guarded_handler(&shell_cmds.cmd_mkfs_fat16, "Usage: mkfs-fat16 <drive>\n"), .kind = .guarded_args, .usage = "Usage: mkfs-fat16 <drive>\n" },
    .{ .name = "mkfs-fat32", .help = "Format drive as FAT32 (advanced)", .handler = guarded_handler(&shell_cmds.cmd_mkfs_fat32, "Usage: mkfs-fat32 <drive>\n"), .kind = .guarded_args, .usage = "Usage: mkfs-fat32 <drive>\n" },
    .{ .name = "touch", .help = "Create an empty file", .handler = guarded_handler(&shell_cmds.cmd_touch, "Usage: touch <file>\n"), .kind = .guarded_args, .usage = "Usage: touch <file>\n" },
    .{ .name = "lseek", .help = "lseek <f> <off> [SET|CUR|END]", .handler = guarded_handler(&shell_cmds.cmd_lseek, "Usage: lseek <file> <offset> [SEEK_SET|SEEK_CUR|SEEK_END]\n"), .kind = .guarded_args, .usage = "Usage: lseek <file> <offset> [SEEK_SET|SEEK_CUR|SEEK_END]\n" },
    .{ .name = "truncate", .help = "truncate <f> <size> - Truncate file", .handler = guarded_handler(&shell_cmds.cmd_truncate, "Usage: truncate <file> <size>\n"), .kind = .guarded_args, .usage = "Usage: truncate <file> <size>\n" },
    .{ .name = "sync", .help = "Sync filesystem to disk", .handler = no_args_handler(&shell_cmds.cmd_sync), .kind = .no_args },
    .{ .name = "expand", .help = "expand <f> <size> - Expand file", .handler = guarded_handler(&shell_cmds.cmd_expand, "Usage: expand <file> <size>\n"), .kind = .guarded_args, .usage = "Usage: expand <file> <size>\n" },
    .{ .name = "forward", .help = "forward <f> <count> - Move forward", .handler = guarded_handler(&shell_cmds.cmd_forward, "Usage: forward <file> <count>\n"), .kind = .guarded_args, .usage = "Usage: forward <file> <count>\n" },
    .{ .name = "attrib", .help = "Set file attributes [+R|+H|+S|+A]", .handler = guarded_handler(&shell_cmds.cmd_attrib, "Usage: attrib [+R|-R] [+H|-H] [+S|-S] [+A|-A] <file>\n"), .kind = .guarded_args, .usage = "Usage: attrib [+R|-R] [+H|-H] [+S|-S] [+A|-A] <file>\n" },
    .{ .name = "write", .help = "write [-a] <f> <t> - Write string to file (-a to append)", .handler = cmd_handler_write, .kind = .custom },
    .{ .name = "rm", .help = "rm [-d] [-r] <f|*> - Delete file/dir", .handler = guarded_handler(&shell_cmds.cmd_rm, "Usage: rm <file>\n"), .kind = .guarded_args, .usage = "Usage: rm <file>\n" },
    .{ .name = "cat", .help = "Display text file contents", .handler = guarded_handler(&shell_cmds.cmd_cat, "Usage: cat <file>\n"), .kind = .guarded_args, .usage = "Usage: cat <file>\n" },
    .{ .name = "edit", .help = "Open primitive text editor", .handler = guarded_handler(&shell_cmds.cmd_edit, "Usage: edit <file>\n"), .kind = .guarded_args, .usage = "Usage: edit <file>\n" },
    .{ .name = "history", .help = "Show command history list", .handler = cmd_handler_history, .kind = .custom },
    .{ .name = "echo", .help = "Print text to standard output", .handler = direct_handler(&shell_cmds.cmd_echo), .kind = .direct_args },
    .{ .name = "time", .help = "Show full current RTC date and time", .handler = no_args_handler(&shell_cmds.cmd_time), .kind = .no_args },
    .{ .name = "mem", .help = "Show memory & test demand paging (mem --test [MB])", .handler = direct_handler(&shell_cmds.cmd_mem), .kind = .direct_args },
    .{ .name = "sysinfo", .help = "Display system hardware info", .handler = no_args_handler(&shell_cmds.cmd_sysinfo), .kind = .no_args },
    .{ .name = "cpuinfo", .help = "Show detailed CPU vendor, brand and features", .handler = no_args_handler(&shell_cmds.cmd_cpuinfo), .kind = .no_args },
    .{ .name = "docs", .help = "Show internal documentation topics", .handler = direct_handler(&shell_cmds.cmd_docs), .kind = .direct_args },
    .{ .name = "cp", .help = "cp <src> <dest> - Copy file/folder recursively", .handler = direct_handler(&shell_cmds.cmd_cp), .kind = .direct_args },
    .{ .name = "codename", .help = "Show current release codename", .handler = cmd_handler_codename, .kind = .custom },
    .{ .name = "fetch", .help = "Show stylish system info summary", .handler = no_args_handler(&shell_cmds.cmd_fetch), .kind = .no_args },
    .{ .name = "matrix", .help = "Enter the NovumOS Matrix (fun!)", .handler = cmd_handler_matrix, .kind = .custom },
    .{ .name = "mv", .help = "mv <src> <dest> - Move or rename file/folder", .handler = direct_handler(&shell_cmds.cmd_mv), .kind = .direct_args },
    .{ .name = "ren", .help = "Alias for mv (rename file/folder)", .handler = direct_handler(&shell_cmds.cmd_rename), .kind = .direct_args },
    .{ .name = "format", .help = "Low-level drive formatting tool", .handler = direct_handler(&shell_cmds.cmd_format), .kind = .direct_args },
    .{ .name = "mkfs", .help = "Create filesystem on current drive", .handler = direct_handler(&shell_cmds.cmd_mkfs), .kind = .direct_args },
    .{ .name = "install", .help = "install <src> [name] - Install Nova script", .handler = cmd_handler_install, .kind = .custom },
    .{ .name = "uninstall", .help = "uninstall <name> - Remove installed command", .handler = cmd_handler_uninstall, .kind = .custom },
    .{ .name = "ring3", .help = "Switch to Ring 3 (User Mode) test", .handler = no_args_handler(&shell_cmds.cmd_ring3), .kind = .no_args },
    .{ .name = "run", .help = "run <elf> - Execute an ELF (RAM FS or disk)", .handler = guarded_handler(&shell_cmds.cmd_run, "Usage: run <elf>\n"), .kind = .guarded_args, .usage = "Usage: run <elf>\n" },
    .{ .name = "exec", .help = "Alias for run", .handler = guarded_handler(&shell_cmds.cmd_run, "Usage: run <elf>\n"), .kind = .guarded_args, .usage = "Usage: run <elf>\n" },
    .{ .name = "calc", .help = "Evaluate math & bitwise expressions (e.g. 1 << 8)", .handler = direct_handler(&shell_cmds.cmd_calc), .kind = .direct_args },
    .{ .name = "res", .help = "res <w> <h> - Set custom resolution via BGA", .handler = direct_handler(&shell_cmds.cmd_res), .kind = .direct_args },
    .{ .name = "beep", .help = "beep [freq|note] [dur] - Play a tone via PC speaker", .handler = cmd_handler_beep, .kind = .custom },
} ++ (if (config.ENABLE_DEBUG_CRASH_COMMANDS) [_]Command{
    .{ .name = "panic", .help = "Trigger a CPU exception for testing", .handler = no_args_handler(&shell_cmds.cmd_panic), .kind = .no_args },
    .{ .name = "crash", .help = "Alias for panic - trigger a CPU exception", .handler = no_args_handler(&shell_cmds.cmd_panic), .kind = .no_args },
    .{ .name = "abort", .help = "Trigger a manual kernel panic", .handler = no_args_handler(&shell_cmds.cmd_abort), .kind = .no_args },
    .{ .name = "invalid_op", .help = "Trigger an Invalid Opcode exception", .handler = no_args_handler(&shell_cmds.cmd_invalid_op), .kind = .no_args },
    .{ .name = "stack_overflow", .help = "Trigger a Double Fault via stack overflow", .handler = no_args_handler(&shell_cmds.cmd_stack_overflow), .kind = .no_args },
    .{ .name = "page_fault", .help = "Trigger a Page Fault exception", .handler = no_args_handler(&shell_cmds.cmd_page_fault), .kind = .no_args },
    .{ .name = "gpf", .help = "Trigger a General Protection Fault", .handler = no_args_handler(&shell_cmds.cmd_gpf), .kind = .no_args },
} else [_]Command{}) ++ (if (config.ENABLE_DEBUG_COMMANDS) [_]Command{
    .{ .name = "smp-test", .help = "Test global task queue across cores", .handler = no_args_handler(&shell_cmds.cmd_smp_test), .kind = .no_args },
    .{ .name = "stress-test", .help = "Run heavy math on AP cores while BSP stays free", .handler = no_args_handler(&shell_cmds.cmd_stress_test), .kind = .no_args },
    .{ .name = "idt-check", .help = "Verify IDT integrity against saved snapshot", .handler = no_args_handler(&idt_watchdog.cmd_idt_check), .kind = .no_args },
    .{ .name = "idt-modify", .help = "Test IDT modification (for watchdog testing)", .handler = cmd_handler_idt_modify, .kind = .custom },
    .{ .name = "idt-move", .help = "Test IDTR relocation (detected by watchdog)", .handler = no_args_handler(&common.idt_move), .kind = .no_args },
    .{ .name = "fbinfo", .help = "Display framebuffer info", .handler = cmd_handler_fbinfo, .kind = .custom },
    .{ .name = "fbtest", .help = "Draw test pattern to framebuffer", .handler = cmd_handler_fbtest, .kind = .custom },
} else [_]Command{}) ++ (if (config.ENABLE_QUANTUM) [_]Command{
    .{ .name = "qrand", .help = "qrand [N | --hex N | --entangle N | --info] - Quantum random numbers", .handler = cmd_handler_qrand, .kind = .custom },
    .{ .name = "qinit", .help = "qinit [N] - Init quantum register (RAM-checked, 32 MB reserved)", .handler = cmd_handler_qinit, .kind = .custom },
    .{ .name = "qh", .help = "qh <qubit> - Hadamard gate", .handler = cmd_handler_qh, .kind = .custom },
    .{ .name = "qcnot", .help = "qcnot <control> <target> - CNOT gate", .handler = cmd_handler_qcnot, .kind = .custom },
    .{ .name = "qmeasure", .help = "qmeasure <qubit> - Measure qubit (collapses state)", .handler = cmd_handler_qmeasure, .kind = .custom },
    .{ .name = "qtest", .help = "qtest - Bell state and Pauli-X self test", .handler = cmd_handler_qtest, .kind = .custom },
} else [_]Command{}) ++ (if (config.ENABLE_DOOMFIRE) [_]Command{
    .{ .name = "doomfire", .help = "Quantum-ignited DOOM fire on the framebuffer", .handler = no_args_handler(&doomfire_cmd.cmd_doomfire), .kind = .no_args },
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
var prompt_start_col: u8 = 0;

var history_loaded: bool = false;

// Autocomplete cycling state
var auto_cycling: bool = false;
var auto_prefix: [64]u8 = [_]u8{0} ** 64;
var auto_prefix_len: usize = 0;
var auto_match_index: usize = 0;
var auto_start_pos: u16 = 0;

var shell_cursor_visible: bool = true;
var last_shell_cursor_row: u16 = 0;
var last_shell_cursor_col: u16 = 0;

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
    shell_cursor_visible = true;
    refresh_line(); // Initial draw of status bar

    while (true) {
        if (config.ENABLE_SPEAKER) speaker.beep_async_check();
        const char = keyboard.keyboard_wait_char();

        if (char == 3) { // Ctrl+C
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

        handle_input_char(char);
        if (char == 10) break; // Enter
        vga.vga_flush();
    }

    if (cmd_len > 0) {
        save_to_history();
        save_history_to_disk();
    }
    common.print_char('\r');
    common.print_char('\n');
}

/// Dispatch a single keystroke within the read_command loop.
fn handle_input_char(char: u8) void {
    if (char == 10) { // Enter
        shell_cursor_visible = false;
        refresh_line();
        return;
    }

    if (char == 12) { // Ctrl+L — clear screen
        vga.clear_screen();
        messages.print_welcome();
        common.printZ("\n");
        display_prompt();
        prompt_row = vga.zig_get_cursor_row();
        prompt_col = vga.zig_get_cursor_col();
        shell_cursor_visible = true;
        refresh_line();
        return;
    }

    if (char == 9) { // Tab — autocomplete, may auto-cycle
        if (auto_cycling) auto_match_index += 1;
        autocomplete();
        refresh_line();
        return;
    }

    if (char == keyboard.KEY_INSERT) {
        insert_mode = !insert_mode;
        refresh_line();
        return;
    }
    if (char == keyboard.KEY_CAPS or char == keyboard.KEY_NUM) {
        refresh_line();
        return;
    }

    if (char == 1) { // Ctrl+A — jump to beginning
        cmd_pos = 0;
        move_screen_cursor();
        return;
    }
    if (char == 5) { // Ctrl+E — jump to end
        cmd_pos = cmd_len;
        move_screen_cursor();
        return;
    }

    if (char == 23) { // Ctrl+W — delete word backwards
        handle_delete_word();
        return;
    }
    if (char == 21) { // Ctrl+U — clear line
        for (&cmd_buffer) |*b| b.* = 0;
        cmd_len = 0;
        cmd_pos = 0;
        refresh_line();
        return;
    }

    if (char == 8 or char == 127) {
        handle_backspace();
        return;
    } // Backspace
    if (char == keyboard.KEY_DELETE) {
        handle_delete();
        return;
    }

    if (handle_navigation_key(char)) return;
    if (handle_history_key(char)) return;

    if (char >= 32 and char <= 126) {
        handle_printable(char);
    }
}

fn handle_printable(char: u8) void {
    if (cmd_len >= 1023) return;

    if (insert_mode) {
        var i: usize = cmd_len;
        while (i > cmd_pos) : (i -= 1) cmd_buffer[i] = cmd_buffer[i - 1];
        cmd_buffer[cmd_pos] = char;
        cmd_len += 1;
        cmd_pos += 1;
    } else {
        cmd_buffer[cmd_pos] = char;
        if (cmd_pos == cmd_len) cmd_len += 1;
        cmd_pos += 1;
    }
    refresh_line();
}

fn handle_backspace() void {
    if (cmd_pos == 0) return;
    var i: usize = cmd_pos - 1;
    while (i < cmd_len - 1) : (i += 1) cmd_buffer[i] = cmd_buffer[i + 1];
    cmd_buffer[cmd_len - 1] = 0;
    cmd_pos -= 1;
    cmd_len -= 1;
    refresh_line();
}

fn handle_delete() void {
    if (cmd_pos >= cmd_len) return;
    var i: usize = cmd_pos;
    while (i < cmd_len - 1) : (i += 1) cmd_buffer[i] = cmd_buffer[i + 1];
    cmd_buffer[cmd_len - 1] = 0;
    cmd_len -= 1;
    refresh_line();
}

fn handle_delete_word() void {
    if (cmd_pos == 0) return;
    var pos: u16 = cmd_pos;
    while (pos > 0 and cmd_buffer[pos - 1] == ' ') pos -= 1;
    while (pos > 0 and cmd_buffer[pos - 1] != ' ') pos -= 1;

    const deleted: u16 = cmd_pos - pos;
    var i: usize = pos;
    const limit: usize = cmd_len - deleted;
    while (i < limit) : (i += 1) cmd_buffer[i] = cmd_buffer[i + deleted];
    while (i < cmd_len) : (i += 1) cmd_buffer[i] = 0;
    cmd_len -= deleted;
    cmd_pos = pos;
    refresh_line();
}

/// Returns true if char was a recognized arrow-key (navigation handled).
fn handle_navigation_key(char: u8) bool {
    if (char == keyboard.KEY_LEFT) {
        if (cmd_pos > 0) {
            cmd_pos -= 1;
            move_screen_cursor();
        }
        return true;
    }
    if (char == keyboard.KEY_RIGHT) {
        if (cmd_pos < cmd_len) {
            cmd_pos += 1;
            move_screen_cursor();
        }
        return true;
    }
    if (char == keyboard.KEY_HOME) {
        if (cmd_pos != 0) {
            cmd_pos = 0;
            move_screen_cursor();
        }
        return true;
    }
    if (char == keyboard.KEY_END) {
        if (cmd_pos != cmd_len) {
            cmd_pos = cmd_len;
            move_screen_cursor();
        }
        return true;
    }
    return false;
}

/// Returns true if char was an Up/Down arrow.
fn handle_history_key(char: u8) bool {
    if (char == keyboard.KEY_UP) {
        if (history_count > 0 and history_index > 0) {
            history_index -= 1;
            load_history();
        }
        return true;
    }
    if (char == keyboard.KEY_DOWN) {
        if (history_index < history_count) {
            history_index += 1;
            if (history_index == history_count) clear_input_line() else load_history();
        }
        return true;
    }
    return false;
}

fn save_history_to_disk() void {
    if (common.selected_disk < 0) return;
    const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;

    if (fat.read_bpb(drive)) |bpb| {
        const buf_ptr = memory.heap.alloc(HISTORY_SIZE * 1024) orelse return;
        defer memory.heap.free(buf_ptr);
        const join_buf = buf_ptr[0 .. HISTORY_SIZE * 1024];
        var offset: usize = 0;

        var i: u8 = 0;
        while (i < history_count) : (i += 1) {
            const h_len = history_lens[i];
            // HISTORY_SIZE x (1024 + newline) can exceed the 50 KB join
            // buffer by up to HISTORY_SIZE bytes: drop the tail instead.
            if (offset + @as(usize, h_len) + 1 > join_buf.len) break;
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
        const load_ptr = memory.heap.alloc(HISTORY_SIZE * 1024) orelse return;
        defer memory.heap.free(load_ptr);
        const load_buf = load_ptr[0 .. HISTORY_SIZE * 1024];
        const read = fat.read_file_bounded(drive, bpb, 0, ".HISTORY", load_ptr, @as(u32, @intCast(load_buf.len)));
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
    render_vga_line();
    draw_prompt_clock();
    render_serial_line();
    move_screen_cursor();
    serial.serial_show_cursor();
    draw_status_indicators();
}

/// Overwrite the prompt's HH:MM:SS digits in place so the clock keeps
/// ticking while the user types.
fn draw_prompt_clock() void {
    const now = rtc.get_datetime();
    var buf: [8]u8 = undefined;
    buf[0] = @as(u8, '0') + @as(u8, @intCast(now.hour / 10));
    buf[1] = @as(u8, '0') + @as(u8, @intCast(now.hour % 10));
    buf[2] = ':';
    buf[3] = @as(u8, '0') + @as(u8, @intCast(now.minute / 10));
    buf[4] = @as(u8, '0') + @as(u8, @intCast(now.minute % 10));
    buf[5] = ':';
    buf[6] = @as(u8, '0') + @as(u8, @intCast(now.second / 10));
    buf[7] = @as(u8, '0') + @as(u8, @intCast(now.second % 10));

    // Raw VGA write: common.print_char would mirror to serial at stream
    // position instead of the addressed prompt cell.
    const save_row = vga.cursor_row;
    const save_col = vga.cursor_col;
    vga.cursor_row = prompt_row;
    vga.cursor_col = prompt_start_col + 1;
    vga.set_color(7, 0);
    for (buf) |ch| vga.zig_print_char(ch);
    vga.reset_color();
    vga.cursor_row = save_row;
    vga.cursor_col = save_col;

    serial.serial_set_cursor(prompt_row, prompt_start_col + 1);
    serial.serial_print_str(&buf);
}

/// Redraw cmd_buffer on the serial console at the prompt position.
fn render_serial_line() void {
    serial.serial_hide_cursor();
    serial.serial_set_cursor(prompt_row, prompt_col);
    serial.serial_print_str(cmd_buffer[0..cmd_len]);
    serial.serial_clear_line();
}

/// Render cmd_buffer to VGA, tracking prompt_row for scroll correction.
fn render_vga_line() void {
    vga.clear_prompt_area(prompt_row, prompt_col);
    vga.cursor_row = prompt_row;
    vga.cursor_col = prompt_col;

    for (cmd_buffer[0..cmd_len]) |c| {
        const row_before = vga.zig_get_cursor_row();
        vga.zig_print_char(c);
        const row_after = vga.zig_get_cursor_row();

        // Scroll detection: row dropped, or last row stayed (wrap/newline)
        if (row_after < row_before) {
            if (prompt_row > 0) prompt_row -= 1;
        } else if (row_before == vga.MAX_ROWS - 1 and row_after == vga.MAX_ROWS - 1) {
            if (c == '\n' or (vga.zig_get_cursor_col() == 0 and c != '\r' and c != 8)) {
                if (prompt_row > 0) prompt_row -= 1;
            }
        }
    }
}

/// Draw CAPS/NUM/INS status indicators in the top-right corner.
fn draw_status_indicators() void {
    const cols = vga.MAX_COLS;
    const caps_attr = if (keyboard.keyboard_get_caps_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800);
    vga.draw_indicator(@intCast(cols - 14), caps_attr, 'C');
    vga.draw_indicator(@intCast(cols - 13), caps_attr, 'A');
    vga.draw_indicator(@intCast(cols - 12), caps_attr, 'P');
    vga.draw_indicator(@intCast(cols - 11), caps_attr, 'S');

    const num_attr = if (keyboard.keyboard_get_num_lock()) @as(u16, 0x0F00) else @as(u16, 0x0800);
    vga.draw_indicator(@intCast(cols - 9), num_attr, 'N');
    vga.draw_indicator(@intCast(cols - 8), num_attr, 'U');
    vga.draw_indicator(@intCast(cols - 7), num_attr, 'M');

    const ins_attr = @as(u16, 0x0E00); // Yellow on black
    const status = if (insert_mode) " INS " else " OVR ";
    for (status, 0..) |c, k| {
        vga.draw_indicator(@intCast(cols - 5 + k), ins_attr, c);
    }
}

fn move_screen_cursor() void {
    var new_col = @as(u16, prompt_col) + cmd_pos;
    var new_row = prompt_row;
    const cols = vga.MAX_COLS;

    while (new_col >= cols) {
        new_col -= @intCast(cols);
        new_row += 1;
    }
    vga.zig_set_cursor(@intCast(new_row), @intCast(new_col));

    last_shell_cursor_row = new_row;
    last_shell_cursor_col = new_col;
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
            var lfn: fat.LfnState = .{ .buf = [_]u8{0} ** 256, .active = false, .checksum = 0 };

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
                        if (fat.consume_lfn_entry(&d_buf, j, &lfn)) continue;

                        if (is_cd_cmd and (d_buf[j + 11] & 0x10) == 0) {
                            lfn.active = false;
                            continue;
                        }

                        var name_str: []const u8 = undefined;
                        const sn = fat.get_name_from_raw(d_buf[j .. j + 32]);

                        if (lfn.active) {
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
                            if (fat.consume_lfn_entry(&d_buf, j, &lfn)) continue;

                            if (is_cd_cmd and (d_buf[j + 11] & 0x10) == 0) {
                                lfn.active = false;
                                continue;
                            }

                            var name_str: []const u8 = undefined;
                            const sn = fat.get_name_from_raw(d_buf[j .. j + 32]);

                            if (lfn.active) {
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
    var picked_is_dir = false;

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
            var lfn: fat.LfnState = .{ .buf = [_]u8{0} ** 256, .active = false, .checksum = 0 };

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
                        if (fat.consume_lfn_entry(&d_buf, j, &lfn)) continue;
                        if (is_cd_cmd and (d_buf[j + 11] & 0x10) == 0) {
                            lfn.active = false;
                            continue;
                        }

                        var name_str: []const u8 = undefined;
                        const sn = fat.get_name_from_raw(d_buf[j .. j + 32]);

                        if (lfn.active) {
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
                                picked_is_dir = (d_buf[j + 11] & 0x10) != 0;
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
                            if (fat.consume_lfn_entry(&d_buf, j, &lfn)) continue;
                            if (is_cd_cmd and (d_buf[j + 11] & 0x10) == 0) {
                                lfn.active = false;
                                continue;
                            }

                            var name_str: []const u8 = undefined;
                            const sn = fat.get_name_from_raw(d_buf[j .. j + 32]);

                            if (lfn.active) {
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
                                    picked_is_dir = (d_buf[j + 11] & 0x10) != 0;
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

        if (picked_is_dir and picked_len < picked_name_buf.len) {
            picked_name_buf[picked_len] = '/';
            picked_len += 1;
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

/// Parsed redirection: optional file + append flag.
const Redirection = struct {
    file: ?[]const u8,
    append: bool,
};

/// Extract `>file`, `>>file` from the command, returning the cleaned command
/// and (optionally) the redirect target.
fn parse_redirection(cmd: []const u8) struct { []const u8, Redirection } {
    var cmd_raw = common.trim(cmd);
    var redir: Redirection = .{ .file = null, .append = false };

    if (common.std_mem_indexOf(u8, cmd_raw, ">>")) |idx| {
        const file_part = common.trim(cmd_raw[idx + 2 ..]);
        if (file_part.len > 0) {
            redir.file = file_part;
            redir.append = true;
            cmd_raw = common.trim(cmd_raw[0..idx]);
        }
    } else if (common.std_mem_indexOf(u8, cmd_raw, ">")) |idx| {
        const file_part = common.trim(cmd_raw[idx + 1 ..]);
        if (file_part.len > 0) {
            redir.file = file_part;
            cmd_raw = common.trim(cmd_raw[0..idx]);
        }
    }
    return .{ cmd_raw, redir };
}

/// Run a builtin shell command (exact match in SHELL_COMMANDS).
/// Returns true if a builtin was dispatched.
fn try_builtin(cmd_raw: []const u8, name: []const u8) bool {
    for (SHELL_COMMANDS) |sc| {
        if (common.std_mem_eql(sc.name, name)) {
            // Reconstruct args string for legacy handlers
            var i: usize = 0;
            while (i < cmd_raw.len and cmd_raw[i] != ' ') : (i += 1) {}
            while (i < cmd_raw.len and cmd_raw[i] == ' ') : (i += 1) {}
            sc.handler(cmd_raw[i..]);
            return true;
        }
    }
    return false;
}

/// Resolve and run a Nova script: relative path, builtin, or system path.
/// Returns true if a script was dispatched (or error reported), false if
/// the command was not recognized as a script.
fn try_nova_script(name: []const u8, argv: [8][]const u8, argc: usize) bool {
    // Relative/absolute path scripts (containing /)
    var contains_slash = false;
    for (name) |c| {
        if (c == '/' or c == '\\') {
            contains_slash = true;
            break;
        }
    }

    if (contains_slash) {
        if (!common.endsWithIgnoreCase(name, ".nv")) {
            common.printError("shell: Direct path execution requires .nv extension\n");
            return true; // error reported, consumed
        }
        if (common.selected_disk >= 0) {
            const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
            if (fat.read_bpb(drive)) |bpb| {
                if (fat.resolve_full_path(drive, bpb, common.current_dir_cluster, common.current_path[0..common.current_path_len], name)) |res| {
                    if (!res.is_dir) {
                        nova_legacy_commands.setScriptArgs(argv[1..argc]);
                        nova_legacy_interpreter.runScript(res.path[0..res.path_len]);
                        return true;
                    }
                }
            }
        }
        return true; // path specified but unresolved — consumed
    }

    // Built-in Nova scripts
    for (BUILTIN_SCRIPTS) |script| {
        if (common.std_mem_eql(script.name, name)) {
            nova_legacy_commands.setScriptArgs(argv[1..argc]);
            nova_legacy_interpreter.runScriptSource(script.source, null, false);
            return true;
        }
    }

    // System path scripts (/.SYSTEM/CMDS/<name>.nv)
    if (common.selected_disk >= 0) {
        var path_buf: [128]u8 = [_]u8{0} ** 128;
        const prefix = "/.SYSTEM/CMDS/";
        const extension = ".nv";

        if (prefix.len + name.len + extension.len < 128) {
            common.copy(path_buf[0..], prefix);
            common.copy(path_buf[prefix.len..], name);
            common.copy(path_buf[prefix.len + name.len ..], extension);
            const full_path = path_buf[0 .. prefix.len + name.len + extension.len];

            const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
            if (fat.read_bpb(drive)) |bpb| {
                if (fat.find_entry(drive, bpb, 0, full_path)) |_| {
                    nova_legacy_commands.setScriptArgs(argv[1..argc]);
                    nova_legacy_interpreter.runScript(full_path);
                    return true;
                }
            }
        }
    }
    return false; // nothing matched → caller prints "command not found"
}

/// Flush redirect output to disk after command execution.
fn flush_redirect(append: bool, file: []const u8) void {
    const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
    if (fat.read_bpb(drive)) |bpb| {
        if (append) {
            _ = fat.append_to_file(drive, bpb, common.current_dir_cluster, file, common.redirect_buffer[0..common.redirect_pos]);
        } else {
            _ = fat.write_file(drive, bpb, common.current_dir_cluster, file, common.redirect_buffer[0..common.redirect_pos]);
        }
    }
    common.redirect_pos = 0;
}

pub fn shell_execute_literal(cmd: []const u8) void {
    // Pipe support: cmd1 | cmd2
    if (common.std_mem_indexOf(u8, cmd, "|")) |idx| {
        const left = common.trim(cmd[0..idx]);
        const right = common.trim(cmd[idx + 1 ..]);
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
        }
        return;
    }

    const cmd_raw, const redir = parse_redirection(cmd);
    if (cmd_raw.len == 0) return;

    var argv: [8][]const u8 = undefined;
    const argc = common.parseArgs(cmd_raw, &argv);
    if (argc == 0) return;

    const cmd_name = argv[0];

    // Setup redirect guard. The cleanup defer must live at function scope:
    // Zig's defer is block-scoped, so nesting it in the if would flush
    // before the command even runs.
    const is_redirect = redir.file != null;
    const append_mode = redir.append;
    if (is_redirect) {
        if (common.selected_disk < 0) {
            common.printError("Error: Redirection requires a mounted disk\n");
            return;
        }
        common.redirect_active = true;
        common.redirect_pos = 0;
    }
    defer {
        if (is_redirect) {
            common.redirect_active = false;
            flush_redirect(append_mode, redir.file.?);
        }
    }

    // 1. Built-in Shell Commands
    if (try_builtin(cmd_raw, cmd_name)) return;

    // 2-4. Nova scripts (relative path, builtin, system path)
    if (!try_nova_script(cmd_name, argv, argc)) {
        common.printError("shell: command not found: ");
        common.printError(cmd_name);
        common.printError("\n");
        if (config.ENABLE_ERROR_BEEP) {
            speaker.beep_pattern_async(200, 80, 50);
        }
    }
}

fn note_name_to_freq(name: []const u8) ?u32 {
    if (common.std_mem_eql(name, "C3")) return 131;
    if (common.std_mem_eql(name, "CSH3")) return 139;
    if (common.std_mem_eql(name, "D3")) return 147;
    if (common.std_mem_eql(name, "DSH3")) return 156;
    if (common.std_mem_eql(name, "E3")) return 165;
    if (common.std_mem_eql(name, "F3")) return 175;
    if (common.std_mem_eql(name, "FSH3")) return 185;
    if (common.std_mem_eql(name, "G3")) return 196;
    if (common.std_mem_eql(name, "GSH3")) return 208;
    if (common.std_mem_eql(name, "A3")) return 220;
    if (common.std_mem_eql(name, "ASH3")) return 233;
    if (common.std_mem_eql(name, "B3")) return 247;
    if (common.std_mem_eql(name, "C4")) return 262;
    if (common.std_mem_eql(name, "CSH4")) return 277;
    if (common.std_mem_eql(name, "D4")) return 294;
    if (common.std_mem_eql(name, "DSH4")) return 311;
    if (common.std_mem_eql(name, "E4")) return 330;
    if (common.std_mem_eql(name, "F4")) return 349;
    if (common.std_mem_eql(name, "FSH4")) return 370;
    if (common.std_mem_eql(name, "G4")) return 392;
    if (common.std_mem_eql(name, "GSH4")) return 415;
    if (common.std_mem_eql(name, "A4")) return 440;
    if (common.std_mem_eql(name, "ASH4")) return 466;
    if (common.std_mem_eql(name, "B4")) return 494;
    if (common.std_mem_eql(name, "C5")) return 523;
    if (common.std_mem_eql(name, "CSH5")) return 554;
    if (common.std_mem_eql(name, "D5")) return 587;
    if (common.std_mem_eql(name, "DSH5")) return 622;
    if (common.std_mem_eql(name, "E5")) return 659;
    if (common.std_mem_eql(name, "F5")) return 698;
    if (common.std_mem_eql(name, "FSH5")) return 740;
    if (common.std_mem_eql(name, "G5")) return 784;
    if (common.std_mem_eql(name, "GSH5")) return 831;
    if (common.std_mem_eql(name, "A5")) return 880;
    if (common.std_mem_eql(name, "ASH5")) return 932;
    if (common.std_mem_eql(name, "B5")) return 988;
    if (common.std_mem_eql(name, "C6")) return 1047;
    if (common.std_mem_eql(name, "CSH6")) return 1109;
    if (common.std_mem_eql(name, "D6")) return 1175;
    if (common.std_mem_eql(name, "DSH6")) return 1245;
    if (common.std_mem_eql(name, "E6")) return 1319;
    if (common.std_mem_eql(name, "F6")) return 1397;
    if (common.std_mem_eql(name, "FSH6")) return 1480;
    if (common.std_mem_eql(name, "G6")) return 1568;
    if (common.std_mem_eql(name, "GSH6")) return 1661;
    if (common.std_mem_eql(name, "A6")) return 1760;
    if (common.std_mem_eql(name, "ASH6")) return 1865;
    if (common.std_mem_eql(name, "B6")) return 1976;
    return null;
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

fn cmd_handler_nova_legacy(_: []const u8) void {
    elf.load_and_run_nova_legacy() catch |err| {
        common.printZ("Error: Failed to load nova_legacy.elf: ");
        common.printZ(@errorName(err));
        common.printZ("\n");
    };
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

fn cmd_handler_history(_: []const u8) void {
    var j: u8 = 0;
    while (j < history_count) : (j += 1) {
        common.printNum(j + 1);
        common.printZ(". ");
        common.printZ(history[j][0..history_lens[j]]);
        common.printZ("\n");
    }
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

fn cmd_handler_codename(_: []const u8) void {
    common.printZ("NovumOS \"");
    common.printZ(versioning.NOVUMOS_CODENAME);
    common.printZ("\"\n");
}

fn cmd_handler_matrix(_: []const u8) void {
    shell_cmds.cmd_matrix();
}

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

fn cmd_handler_res(args: []const u8) void {
    shell_cmds.cmd_res(args.ptr, @intCast(args.len));
}

fn cmd_handler_calc(args: []const u8) void {
    shell_cmds.cmd_calc(args.ptr, @intCast(args.len));
}

fn cmd_handler_fbinfo(args: []const u8) void {
    _ = args;
    common.printZ("\n=== Multiboot2 Framebuffer ===\n");
    common.printZ("fb_addr:   ");
    common.printHex(fb_addr);
    common.printZ("\n");
    common.printZ("fb_pitch: ");
    common.printHex(fb_pitch);
    common.printZ("\n");
    common.printZ("fb_width: ");
    common.printHex(fb_width);
    common.printZ("\n");
    common.printZ("fb_h:     ");
    common.printHex(fb_height);
    common.printZ("\n");
    common.printZ("fb_bpp:   ");
    common.printHex(fb_bpp);
    common.printZ("\n");
}

fn cmd_handler_fbtest(args: []const u8) void {
    _ = args;
    if (fb_addr == 0) {
        common.printZ("fb_addr is 0\n");
        return;
    }
    const fb = @as([*]volatile u32, @ptrFromInt(fb_addr));
    const w = fb_width;
    const h = fb_height;
    var y: u32 = 0;
    while (y < h) : (y += 1) {
        var x: u32 = 0;
        while (x < w) : (x += 1) {
            fb[y * w + x] = if ((y & 1) == 0) 0xFFFFFFFF else 0x000000FF;
        }
    }
    common.printZ("Done\n");
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

fn cmd_handler_qrand(args: []const u8) void {
    var argv: [4][]const u8 = undefined;
    const argc = common.parseArgs(args, &argv);

    const hex = struct {
        fn byte(b: u8) void {
            const hi = b >> 4;
            const lo = b & 0xF;
            common.print_char(if (hi < 10) @as(u8, '0' + hi) else @as(u8, 'A' + hi - 10));
            common.print_char(if (lo < 10) @as(u8, '0' + lo) else @as(u8, 'A' + lo - 10));
        }
    };

    if (argc >= 1 and (common.std_mem_eql(argv[0], "--help") or common.std_mem_eql(argv[0], "-h") or common.std_mem_eql(argv[0], "/?"))) {
        common.printZ("Usage: qrand [options] [N]\n");
        common.printZ("Generate quantum random numbers using qubit measurement.\n");
        common.printZ("\n");
        common.printZ("  N               Number of random bytes to show (1-512, default 1)\n");
        common.printZ("  --hex [N]       Output as hex string\n");
        common.printZ("  --entangle [N]  Show N entangled qubit pairs\n");
        common.printZ("  --info          Show QRNG status and RDRAND availability\n");
        common.printZ("  --help, -h      Show this help message\n");
        common.printZ("\n");
        common.printZ("Examples:\n");
        common.printZ("  qrand            Random byte in hex/dec/ASCII\n");
        common.printZ("  qrand 16         16 random bytes\n");
        common.printZ("  qrand --hex 32   32 bytes as hex string\n");
        common.printZ("  qrand --entangle  Entangled Bell state pair\n");
        return;
    }

    if (argc >= 1 and common.std_mem_eql(argv[0], "--info")) {
        common.printZ("QRNG Status:\n");
        common.printZ("  RDRAND: ");
        if (quantum.hasRdrand()) {
            common.printZ("available (hardware quantum noise)\n");
        } else {
            common.printZ("unavailable (using RDTSC jitter fallback)\n");
        }
        common.printZ("  State: ready\n");
        return;
    }

    if (argc >= 1 and common.std_mem_eql(argv[0], "--entangle")) {
        var n: u32 = 1;
        if (argc >= 2) {
            const parsed = common.parse_int(argv[1]);
            if (parsed) |val| n = @min(@as(u32, @intCast(val)), 256);
        }
        common.printZ("Entangled pairs (|00> + |11>)/sqrt2:\n");
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            const pair = quantum.entangledPair();
            common.printZ("  0x");
            hex.byte(pair[0]);
            common.printZ(" <-> 0x");
            hex.byte(pair[1]);
            if (pair[0] == pair[1]) {
                common.printZ(" [CORRELATED]\n");
            } else {
                common.printZ(" [decoherence]\n");
            }
        }
        return;
    }

    var hex_mode = false;
    var arg_start: usize = 0;
    if (argc >= 1 and common.std_mem_eql(argv[0], "--hex")) {
        hex_mode = true;
        arg_start = 1;
    }
    var n: u32 = 1;
    if (argc > arg_start) {
        const parsed = common.parse_int(argv[arg_start]);
        if (parsed) |val| n = @min(@as(u32, @intCast(val)), 512);
    }

    if (hex_mode) {
        common.printZ("Quantum random bytes (hex): ");
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            hex.byte(quantum.randByte());
        }
        common.printZ("\n");
    } else if (n == 1) {
        const b = quantum.randByte();
        common.printZ("Quantum random byte: 0x");
        hex.byte(b);
        common.printZ(" (");
        common.printNum(@as(i32, @intCast(b)));
        common.printZ(") '");
        if (b >= 32 and b < 127) {
            common.print_char(b);
        } else {
            common.print_char('.');
        }
        common.printZ("'\n");
    } else {
        common.printZ("Quantum random bytes (");
        common.printNum(@as(i32, @intCast(n)));
        common.printZ("):\n  ");
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            common.printZ("0x");
            hex.byte(quantum.randByte());
            common.print_char(' ');
            if ((i + 1) % 8 == 0 and i + 1 < n) {
                common.printZ("\n  ");
            }
        }
        common.printZ("\n");
    }
}

fn cmd_handler_qinit(args: []const u8) void {
    var argv: [2][]const u8 = undefined;
    const argc = common.parseArgs(args, &argv);
    var n: i32 = 2;
    if (argc >= 1) {
        const parsed = common.parse_int(argv[0]) orelse {
            common.printZ("Usage: qinit [N]\n");
            return;
        };
        n = parsed;
    }
    if (n < 1 or n > quantum.MAX_QUBITS) {
        common.printZ("qinit: qubit count must be 1..");
        common.printNum(quantum.MAX_QUBITS);
        common.printZ("\n");
        return;
    }

    const ram = struct {
        fn show(bytes: usize) void {
            if (bytes >= 1024 * 1024) {
                common.printNum(@intCast(bytes / (1024 * 1024)));
                common.printZ(" MB");
            } else if (bytes >= 1024) {
                common.printNum(@intCast(bytes / 1024));
                common.printZ(" KB");
            } else {
                common.printNum(@intCast(bytes));
                common.printZ(" B");
            }
        }
    };

    switch (quantum.simInit(@intCast(n))) {
        .ok => |need| {
            common.printZ("qinit: ");
            common.printNum(n);
            common.printZ(" qubit(s), state |0");
            var i: i32 = 1;
            while (i < n) : (i += 1) common.printZ("0");
            common.printZ(">, needs ");
            ram.show(need);
            common.printZ("\n");
        },
        .bad_qubits => {
            common.printZ("qinit: qubit count out of range\n");
        },
        .insufficient => |r| {
            common.printZ("qinit: needs ");
            ram.show(r.need);
            common.printZ(", only ");
            ram.show(r.avail);
            common.printZ(" usable with 32 MB reserved for the OS\n");
        },
        .oom => |need| {
            common.printZ("qinit: needs ");
            ram.show(need);
            common.printZ(", heap could not serve it\n");
        },
    }
}

fn cmd_handler_qh(args: []const u8) void {
    var argv: [2][]const u8 = undefined;
    const argc = common.parseArgs(args, &argv);
    if (argc < 1) {
        common.printZ("Usage: qh <qubit>\n");
        return;
    }
    const q = common.parse_int(argv[0]) orelse -1;
    if (q < 0 or !quantum.applyH(@intCast(q))) {
        common.printZ("qh: invalid qubit (qinit first)\n");
        return;
    }
    common.printZ("H applied\n");
}

fn cmd_handler_qcnot(args: []const u8) void {
    var argv: [3][]const u8 = undefined;
    const argc = common.parseArgs(args, &argv);
    if (argc < 2) {
        common.printZ("Usage: qcnot <control> <target>\n");
        return;
    }
    const c = common.parse_int(argv[0]) orelse -1;
    const t = common.parse_int(argv[1]) orelse -1;
    if (c < 0 or t < 0 or !quantum.applyCNOT(@intCast(c), @intCast(t))) {
        common.printZ("qcnot: invalid qubits (qinit first)\n");
        return;
    }
    common.printZ("CNOT applied\n");
}

fn cmd_handler_qmeasure(args: []const u8) void {
    var argv: [2][]const u8 = undefined;
    const argc = common.parseArgs(args, &argv);
    if (argc < 1) {
        common.printZ("Usage: qmeasure <qubit>\n");
        return;
    }
    const q = common.parse_int(argv[0]) orelse -1;
    const outcome = if (q < 0) null else quantum.measure(@intCast(q));
    if (outcome) |bit| {
        common.printZ("qmeasure: qubit ");
        common.printNum(q);
        common.printZ(" -> ");
        common.print_char(if (bit) '1' else '0');
        common.printZ("\n");
    } else {
        common.printZ("qmeasure: invalid qubit (qinit first)\n");
    }
}

fn cmd_handler_qtest(args: []const u8) void {
    _ = args;
    const r = quantum.selfTest(100);
    const pass = r.x_ok and r.mixed == 0 and r.zero_zero + r.one_one == r.trials;
    common.printZ("qtest: X gate ");
    common.printZ(if (r.x_ok) "ok" else "FAIL");
    common.printZ(", Bell ");
    common.printNum(@intCast(r.zero_zero));
    common.printZ("x 00, ");
    common.printNum(@intCast(r.one_one));
    common.printZ("x 11, ");
    common.printNum(@intCast(r.mixed));
    common.printZ(" mixed -> ");
    common.printZ(if (pass) "PASS" else "FAIL");
    common.printZ("\n");
}

fn cmd_handler_beep(args: []const u8) void {
    var argv: [4][]const u8 = undefined;
    const argc = common.parseArgs(args, &argv);
    var freq: u32 = 440;
    var dur_ms: u32 = 200;

    if (argc >= 1) {
        const parsed = common.parse_int(argv[0]);
        if (parsed) |val| {
            freq = @intCast(@max(20, @min(val, 20000)));
        } else if (note_name_to_freq(argv[0])) |note_freq| {
            freq = note_freq;
        } else {
            common.printZ("Usage: beep [freq|note] [dur_ms]\n");
            return;
        }
    }

    if (argc >= 2) {
        const parsed = common.parse_int(argv[1]);
        if (parsed) |val| {
            dur_ms = @intCast(@max(0, val));
        }
    }

    speaker.beep_async(freq, dur_ms);
}

fn display_prompt() void {
    if (vga.zig_get_cursor_col() > 0) common.print_char('\n');

    // 1. Clock [HH:MM:SS]
    prompt_start_col = vga.zig_get_cursor_col();
    const now = rtc.get_datetime();
    vga.set_color(8, 0); // Dark Gray
    common.print_char('[');
    vga.set_color(7, 0); // Gray
    if (now.hour < 10) common.print_char('0');
    common.printNum(now.hour);
    common.print_char(':');
    if (now.minute < 10) common.print_char('0');
    common.printNum(now.minute);
    common.print_char(':');
    if (now.second < 10) common.print_char('0');
    common.printNum(now.second);
    vga.set_color(8, 0);
    common.printZ("] ");

    vga.set_color(10, 0); // Light Green for Drive
    if (common.selected_disk >= 0) {
        common.print_char(@intCast(@as(u8, @intCast(common.selected_disk)) + '0'));
        common.printZ(":");
    }

    vga.set_color(11, 0); // Light Cyan for path
    if (common.current_path_len == 0) {
        common.printZ("/");
    } else {
        common.printZ(common.current_path[0..common.current_path_len]);
    }

    vga.set_color(15, 0); // White for prompt
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
