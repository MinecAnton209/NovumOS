const std = @import("std");
const vaxis = @import("vaxis");
const config_schema = @import("config_schema");
const kconfig = config_schema.k;
const cfg_write = @import("cfg_write.zig");

const schema = &config_schema.schema;

const root_opt_keys = [_][]const u8{
    "USE_GARBAGE_COLLECTOR",
    "ENABLE_QUANTUM",
    "ENABLE_DOOMFIRE",
    "ENABLE_BUILTIN_SCRIPTS",
    "ENABLE_MOUSE",
    "ENABLE_SPEAKER",
    "ENABLE_SMP",
    "ENABLE_NOVA",
};

const submenu_defs = [_]struct { name: []const u8, keys: []const []const u8 }{
    .{ .name = "Debug output", .keys = &.{
        "ENABLE_SERIAL_DEBUG",   "ENABLE_EARLY_LFB_DEBUG", "ENABLE_FAT_DEBUG",
        "ENABLE_KERNEL_LOGGING", "MOUSE_DEBUG",             "NOVA_DEBUG",
    } },
    .{ .name = "Audio", .keys = &.{ "ENABLE_BOOT_BEEP", "ENABLE_ERROR_BEEP" } },
    .{ .name = "Shell / System", .keys = &.{
        "ENABLE_DEBUG_COMMANDS", "ENABLE_DEBUG_CRASH_COMMANDS", "HISTORY_SIZE",
        "ENABLE_EMBEDDED_ELFS",  "ENABLE_IDT_WATCHDOG",         "ENABLE_RSOD_REBOOT",
    } },
    .{ .name = "Security", .keys = &.{"NOVA_PATH_POLICY_ENABLED"} },
    .{ .name = "Memory / Sizes", .keys = &.{"HEAP_INITIAL_SIZE"} },
};

fn schemaIndex(comptime name: []const u8) usize {
    @setEvalBranchQuota(10000);
    for (schema, 0..) |f, i| {
        if (std.mem.eql(u8, f.name, name)) return i;
    }
    @compileError("menuconfig: key not in schema: " ++ name);
}

const MenuItem = union(enum) {
    opt: usize,
    submenu: usize,
};

const root_items: [root_opt_keys.len + submenu_defs.len]MenuItem = blk: {
    var items: [root_opt_keys.len + submenu_defs.len]MenuItem = undefined;
    var n: usize = 0;
    for (root_opt_keys) |k| {
        items[n] = .{ .opt = schemaIndex(k) };
        n += 1;
    }
    for (0..submenu_defs.len) |si| {
        items[n] = .{ .submenu = si };
        n += 1;
    }
    break :blk items;
};

const Group = struct {
    name: []const u8,
    opt_indices: []const usize,
};

fn groupKeyIndices(comptime keys: []const []const u8) []const usize {
    var arr: [keys.len]usize = undefined;
    for (keys, 0..) |k, i| {
        arr[i] = schemaIndex(k);
    }
    const final_arr = arr;
    return &final_arr;
}

const submenus: [submenu_defs.len]Group = blk: {
    var s_arr: [submenu_defs.len]Group = undefined;
    var seen: [schema.len]bool = .{false} ** schema.len;
    for (root_opt_keys) |k| {
        const idx = schemaIndex(k);
        if (seen[idx]) @compileError("menuconfig: duplicate key in root_opt_keys: " ++ k);
        seen[idx] = true;
    }
    for (submenu_defs, 0..) |sd, i| {
        for (sd.keys) |k| {
            const idx = schemaIndex(k);
            if (seen[idx]) @compileError("menuconfig: duplicate schema key: " ++ k);
            seen[idx] = true;
        }
        s_arr[i] = .{
            .name = sd.name,
            .opt_indices = groupKeyIndices(sd.keys),
        };
    }
    for (seen, 0..) |was_seen, i| {
        if (!was_seen) @compileError("menuconfig: missing key in menuconfig: " ++ schema[i].name);
    }
    break :blk s_arr;
};

fn clampScroll(cursor_row: usize, view: usize, cur_scroll: usize) usize {
    if (view == 0) return cur_scroll;
    if (cursor_row < cur_scroll) return cursor_row;
    if (cursor_row >= cur_scroll + view) return cursor_row - view + 1;
    return cur_scroll;
}

fn parseEdit(buf: []const u8) ?u32 {
    return std.fmt.parseInt(u32, buf, 10) catch null;
}

// Colors matching Linux kernel ncurses menuconfig (lxdialog)
const col_bg_blue = vaxis.Cell.Color{ .rgb = .{ 0, 0, 168 } }; // Deep classic blue
const col_top_banner = vaxis.Cell.Color{ .rgb = .{ 85, 255, 255 } }; // Bright cyan
const col_dialog_bg = vaxis.Cell.Color{ .rgb = .{ 192, 192, 192 } }; // Light gray
const col_dialog_fg = vaxis.Cell.Color{ .rgb = .{ 0, 0, 0 } }; // Black text
const col_dialog_border = vaxis.Cell.Color{ .rgb = .{ 0, 0, 0 } }; // Dark border
const col_shadow = vaxis.Cell.Color{ .rgb = .{ 0, 0, 0 } }; // Drop shadow
const col_title = vaxis.Cell.Color{ .rgb = .{ 0, 128, 128 } }; // Cyan title
const col_sel_bg = vaxis.Cell.Color{ .rgb = .{ 0, 0, 168 } }; // Selection bar blue
const col_sel_fg = vaxis.Cell.Color{ .rgb = .{ 255, 255, 255 } }; // Selection bar white
const col_sel_tag = vaxis.Cell.Color{ .rgb = .{ 255, 255, 85 } }; // Selection tag yellow
const col_tag = vaxis.Cell.Color{ .rgb = .{ 0, 0, 168 } }; // Unselected tag blue
const col_hotkey = vaxis.Cell.Color{ .rgb = .{ 180, 0, 0 } }; // Hotkey red
const col_input_bg = vaxis.Cell.Color{ .rgb = .{ 255, 255, 255 } }; // Input box white
const col_input_fg = vaxis.Cell.Color{ .rgb = .{ 0, 0, 0 } }; // Input text black

const Event = union(enum) {
    key_press: vaxis.Key,
    mouse: vaxis.Mouse,
    winsize: vaxis.Winsize,
};

var original: []const u8 = "";
var values: [schema.len]kconfig.Option = undefined;
var saved_values: [schema.len]kconfig.Option = undefined;

fn isDirty() bool {
    for (0..schema.len) |i| {
        switch (values[i]) {
            .bool => |bv| {
                if (bv != saved_values[i].bool) return true;
            },
            .int => |iv| {
                if (iv != saved_values[i].int) return true;
            },
            .str => |sv| {
                if (!std.mem.eql(u8, sv, saved_values[i].str)) return true;
            },
        }
    }
    return false;
}

var current_menu: ?usize = null;
var menu_cursor_stack: usize = 0;
var cursor: usize = 0;
var scroll: usize = 0;
var should_quit = false;
const Button = enum(u2) {
    select = 0,
    exit = 1,
    help = 2,
    save = 3,
};
var active_btn: Button = .select;
var save_modal_btn: enum(u1) { ok = 0, cancel = 1 } = .ok;
var confirm_modal_btn: enum(u2) { yes = 0, no = 1, cancel = 2 } = .yes;
var edit_modal_btn: enum(u1) { ok = 0, cancel = 1 } = .ok;

var mode: enum { nav, edit, help, save_dialog, confirm } = .nav;
var edit_target: usize = 0;
var edit_buf: [16]u8 = undefined;
var edit_len: usize = 0;
var status: []const u8 = "";
var status_buf: [256]u8 = undefined;
var g_io: std.Io = undefined;
var g_alloc: std.mem.Allocator = undefined;
var frame_arena: std.heap.ArenaAllocator = undefined;

fn readText(io: std.Io, alloc: std.mem.Allocator, path: []const u8) ?[]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => null,
        else => {
            std.log.err("menuconfig: cannot read {s}: {s}", .{ path, @errorName(err) });
            std.process.exit(1);
        },
    };
}

fn currentCount() usize {
    if (current_menu) |g| {
        return submenus[g].opt_indices.len;
    } else {
        return root_items.len;
    }
}

fn optUnderCursor() ?usize {
    if (current_menu) |g| {
        if (cursor < submenus[g].opt_indices.len) {
            return submenus[g].opt_indices[cursor];
        }
    } else {
        if (cursor < root_items.len) {
            switch (root_items[cursor]) {
                .opt => |idx| return idx,
                .submenu => return null,
            }
        }
    }
    return null;
}

fn drawShadow(win: vaxis.Window, x: i17, y: i17, w: u16, h: u16) void {
    const shadow_cell = vaxis.Cell{
        .char = .{ .grapheme = " ", .width = 1 },
        .style = .{ .bg = col_shadow },
    };
    // Right shadow (2 columns wide)
    var r: u16 = 1;
    while (r <= h) : (r += 1) {
        const row: u16 = @intCast(@as(i32, @intCast(y)) + r);
        const col1: u16 = @intCast(@as(i32, @intCast(x)) + w);
        const col2: u16 = @intCast(@as(i32, @intCast(x)) + w + 1);
        win.writeCell(col1, row, shadow_cell);
        win.writeCell(col2, row, shadow_cell);
    }
    // Bottom shadow (1 row high)
    var c: u16 = 2;
    while (c <= w + 1) : (c += 1) {
        const col: u16 = @intCast(@as(i32, @intCast(x)) + c);
        const row: u16 = @intCast(@as(i32, @intCast(y)) + h);
        win.writeCell(col, row, shadow_cell);
    }
}

fn renderOptRow(win: vaxis.Window, arena: std.mem.Allocator, r: usize, opt_idx: usize, is_cursor: bool) void {
    const f = schema[opt_idx];
    const bg_color = if (is_cursor) col_sel_bg else col_dialog_bg;
    const fg_color = if (is_cursor) col_sel_fg else col_dialog_fg;
    const tag_color = if (is_cursor) col_sel_tag else col_tag;

    switch (values[opt_idx]) {
        .bool => |bv| {
            const tag = if (bv) "[*]" else "[ ]";
            const help_text = std.fmt.allocPrint(arena, " {s}", .{f.help}) catch f.help;
            _ = win.print(&[_]vaxis.Segment{
                .{ .text = "  ", .style = .{ .bg = bg_color } },
                .{ .text = tag, .style = .{ .fg = tag_color, .bg = bg_color, .bold = true } },
                .{ .text = help_text, .style = .{ .fg = fg_color, .bg = bg_color, .bold = is_cursor } },
            }, .{ .row_offset = @intCast(r), .col_offset = 0, .wrap = .none });
        },
        .int => |iv| {
            const tag = std.fmt.allocPrint(arena, "({d})", .{iv}) catch "(?)";
            const help_text = std.fmt.allocPrint(arena, " {s}", .{f.help}) catch f.help;
            _ = win.print(&[_]vaxis.Segment{
                .{ .text = "  ", .style = .{ .bg = bg_color } },
                .{ .text = tag, .style = .{ .fg = tag_color, .bg = bg_color, .bold = true } },
                .{ .text = help_text, .style = .{ .fg = fg_color, .bg = bg_color, .bold = is_cursor } },
            }, .{ .row_offset = @intCast(r), .col_offset = 0, .wrap = .none });
        },
        .str => |sv| {
            const tag = std.fmt.allocPrint(arena, "({s})", .{sv}) catch "(?)";
            const help_text = std.fmt.allocPrint(arena, " {s}", .{f.help}) catch f.help;
            _ = win.print(&[_]vaxis.Segment{
                .{ .text = "  ", .style = .{ .bg = bg_color } },
                .{ .text = tag, .style = .{ .fg = tag_color, .bg = bg_color, .bold = true } },
                .{ .text = help_text, .style = .{ .fg = fg_color, .bg = bg_color, .bold = is_cursor } },
            }, .{ .row_offset = @intCast(r), .col_offset = 0, .wrap = .none });
        },
    }
}

fn render(win: vaxis.Window) void {
    _ = frame_arena.reset(.retain_capacity);
    const arena = frame_arena.allocator();

    // 1. Fill root screen with deep blue
    win.fill(.{
        .char = .{ .grapheme = " ", .width = 1 },
        .style = .{ .bg = col_bg_blue },
    });

    if (win.height < 6 or win.width < 20) return;

    // 2. Top title banner: .config - NovumOS Kernel Configuration
    const banner_text = if (isDirty())
        " .config - NovumOS Kernel Configuration [modified]"
    else
        " .config - NovumOS Kernel Configuration";

    _ = win.print(&[_]vaxis.Segment{.{
        .text = banner_text,
        .style = .{ .fg = col_top_banner, .bg = col_bg_blue, .bold = true },
    }}, .{ .row_offset = 0, .col_offset = 0, .wrap = .none });

    // 3. Main Dialog Box dimensions
    const dw: u16 = if (win.width > 8) @min(win.width - 4, 88) else win.width;
    const dh: u16 = if (win.height > 3) @min(win.height - 2, 32) else win.height;
    const dx: i17 = @intCast((win.width -| dw) / 2);
    const dy: i17 = 1 + @as(i17, @intCast((win.height -| 1 -| dh) / 2));

    // Draw drop shadow for main dialog
    if (win.width >= dw + 4 and win.height >= dh + 2) {
        drawShadow(win, dx, dy, dw, dh);
    }

    // Outer Dialog Box
    const dialog_box = win.child(.{
        .x_off = dx,
        .y_off = dy,
        .width = dw,
        .height = dh,
        .border = .{
            .where = .all,
            .glyphs = .single_square,
            .style = .{ .fg = col_dialog_border, .bg = col_dialog_bg },
        },
    });
    dialog_box.fill(.{
        .char = .{ .grapheme = " ", .width = 1 },
        .style = .{ .bg = col_dialog_bg },
    });

    // Dialog title in top border
    const title_str = if (current_menu) |g|
        std.fmt.allocPrint(arena, " NovumOS: {s} ", .{submenus[g].name}) catch " NovumOS Kernel Configuration "
    else
        " NovumOS Kernel Configuration ";

    const title_x: u16 = if (dw > title_str.len) @intCast((dw - @as(u16, @intCast(title_str.len))) / 2) else 1;
    _ = win.print(&[_]vaxis.Segment{.{
        .text = title_str,
        .style = .{ .fg = col_title, .bg = col_dialog_bg, .bold = true },
    }}, .{ .row_offset = @intCast(dy), .col_offset = @intCast(dx + @as(i17, @intCast(title_x))), .wrap = .none });

    // Dialog instructions
    if (dh >= 10) {
        if (current_menu == null) {
            _ = dialog_box.print(&[_]vaxis.Segment{
                .{ .text = "Arrow keys navigate the menu. ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
                .{ .text = "<Enter>", .style = .{ .fg = col_tag, .bg = col_dialog_bg, .bold = true } },
                .{ .text = " selects submenus ---> or edits.", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
            }, .{ .row_offset = 0, .col_offset = 1, .wrap = .none });

            _ = dialog_box.print(&[_]vaxis.Segment{
                .{ .text = "<s>", .style = .{ .fg = col_hotkey, .bg = col_dialog_bg, .bold = true } },
                .{ .text = " to save, ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
                .{ .text = "<Esc>", .style = .{ .fg = col_tag, .bg = col_dialog_bg, .bold = true } },
                .{ .text = " / ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
                .{ .text = "<q>", .style = .{ .fg = col_hotkey, .bg = col_dialog_bg, .bold = true } },
                .{ .text = " to exit, ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
                .{ .text = "<?>", .style = .{ .fg = col_tag, .bg = col_dialog_bg, .bold = true } },
                .{ .text = " for Help.", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
            }, .{ .row_offset = 1, .col_offset = 1, .wrap = .none });
        } else {
            _ = dialog_box.print(&[_]vaxis.Segment{
                .{ .text = "Arrow keys navigate the menu. ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
                .{ .text = "<Enter>", .style = .{ .fg = col_tag, .bg = col_dialog_bg, .bold = true } },
                .{ .text = " edits, ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
                .{ .text = "<Space>", .style = .{ .fg = col_tag, .bg = col_dialog_bg, .bold = true } },
                .{ .text = " toggles.", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
            }, .{ .row_offset = 0, .col_offset = 1, .wrap = .none });

            _ = dialog_box.print(&[_]vaxis.Segment{
                .{ .text = "<s>", .style = .{ .fg = col_hotkey, .bg = col_dialog_bg, .bold = true } },
                .{ .text = " to save, ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
                .{ .text = "<Esc>", .style = .{ .fg = col_tag, .bg = col_dialog_bg, .bold = true } },
                .{ .text = " / ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
                .{ .text = "<q>", .style = .{ .fg = col_hotkey, .bg = col_dialog_bg, .bold = true } },
                .{ .text = " to go back, ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
                .{ .text = "<?>", .style = .{ .fg = col_tag, .bg = col_dialog_bg, .bold = true } },
                .{ .text = " for Help. Legend: ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
                .{ .text = "[*]", .style = .{ .fg = col_tag, .bg = col_dialog_bg, .bold = true } },
                .{ .text = " enabled  ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
                .{ .text = "[ ]", .style = .{ .fg = col_tag, .bg = col_dialog_bg, .bold = true } },
                .{ .text = " disabled", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
            }, .{ .row_offset = 1, .col_offset = 1, .wrap = .none });
        }
    }

    // Inner Menu Box
    const inner_top: i17 = if (dh >= 10) 3 else 1;
    const inner_h: u16 = if (dh > 7) dh - 6 else 2;
    const inner_w: u16 = if (dw > 4) dw - 4 else dw;

    const inner_box = dialog_box.child(.{
        .x_off = 1,
        .y_off = inner_top,
        .width = inner_w,
        .height = inner_h,
        .border = .{
            .where = .all,
            .glyphs = .single_square,
            .style = .{ .fg = col_dialog_border, .bg = col_dialog_bg },
        },
    });
    inner_box.fill(.{
        .char = .{ .grapheme = " ", .width = 1 },
        .style = .{ .bg = col_dialog_bg },
    });

    const list_h: usize = inner_box.height;
    const total_items: usize = currentCount();
    scroll = clampScroll(cursor, list_h, scroll);

    // Scroll indicators on inner box top / bottom border
    if (scroll > 0) {
        _ = dialog_box.print(&[_]vaxis.Segment{.{
            .text = "(-)",
            .style = .{ .fg = col_tag, .bg = col_dialog_bg, .bold = true },
        }}, .{ .row_offset = @intCast(inner_top), .col_offset = @intCast(inner_w - 5), .wrap = .none });
    }
    if (scroll + list_h < total_items) {
        _ = dialog_box.print(&[_]vaxis.Segment{.{
            .text = "(+)",
            .style = .{ .fg = col_tag, .bg = col_dialog_bg, .bold = true },
        }}, .{ .row_offset = @intCast(inner_top + @as(i17, @intCast(inner_h)) - 1), .col_offset = @intCast(inner_w - 5), .wrap = .none });
    }

    // Render rows
    var r: usize = 0;
    while (r < list_h and scroll + r < total_items) : (r += 1) {
        const item_idx = scroll + r;
        const is_cursor = (item_idx == cursor);

        // Selection highlight across full inner width
        if (is_cursor) {
            var c: u16 = 0;
            while (c < inner_box.width) : (c += 1) {
                inner_box.writeCell(c, @intCast(r), .{
                    .char = .{ .grapheme = " ", .width = 1 },
                    .style = .{ .bg = col_sel_bg },
                });
            }
        }

        if (current_menu) |g| {
            // Inside submenu: list of options for group `g`
            const opt_idx = submenus[g].opt_indices[item_idx];
            renderOptRow(inner_box, arena, r, opt_idx, is_cursor);
        } else {
            // Root menu: options on top, followed by submenus
            switch (root_items[item_idx]) {
                .opt => |opt_idx| {
                    renderOptRow(inner_box, arena, r, opt_idx, is_cursor);
                },
                .submenu => |si| {
                    const group_text = std.fmt.allocPrint(arena, "    {s}  --->", .{submenus[si].name}) catch submenus[si].name;
                    _ = inner_box.print(&[_]vaxis.Segment{.{
                        .text = group_text,
                        .style = if (is_cursor)
                            .{ .fg = col_sel_tag, .bg = col_sel_bg, .bold = true }
                        else
                            .{ .fg = col_tag, .bg = col_dialog_bg, .bold = true },
                    }}, .{ .row_offset = @intCast(r), .col_offset = 0, .wrap = .none });
                },
            }
        }
    }

    // Bottom action buttons inside main dialog
    if (dh >= 6) {
        const btn_row: u16 = dh - 3;
        const btn_str_len: u16 = 48;
        const btn_start: u16 = if (dw > btn_str_len) (dw - btn_str_len) / 2 else 1;

        const is_sel = (active_btn == .select);
        const is_exit = (active_btn == .exit);
        const is_help = (active_btn == .help);
        const is_save = (active_btn == .save);

        _ = dialog_box.print(&[_]vaxis.Segment{
            // <Select>
            if (is_sel)
                .{ .text = "<Select>", .style = .{ .fg = col_sel_fg, .bg = col_sel_bg, .bold = true } }
            else
                .{ .text = "<S", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
            if (!is_sel)
                .{ .text = "e", .style = .{ .fg = col_hotkey, .bg = col_dialog_bg, .bold = true } }
            else
                .{ .text = "" },
            if (!is_sel)
                .{ .text = "lect>", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } }
            else
                .{ .text = "" },
            .{ .text = "    ", .style = .{ .bg = col_dialog_bg } },

            // < Exit >
            if (is_exit)
                .{ .text = "< Exit >", .style = .{ .fg = col_sel_fg, .bg = col_sel_bg, .bold = true } }
            else
                .{ .text = "< Exit >", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
            .{ .text = "    ", .style = .{ .bg = col_dialog_bg } },

            // < Help >
            if (is_help)
                .{ .text = "< Help >", .style = .{ .fg = col_sel_fg, .bg = col_sel_bg, .bold = true } }
            else
                .{ .text = "< ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
            if (!is_help)
                .{ .text = "H", .style = .{ .fg = col_hotkey, .bg = col_dialog_bg, .bold = true } }
            else
                .{ .text = "" },
            if (!is_help)
                .{ .text = "elp >", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } }
            else
                .{ .text = "" },
            .{ .text = "    ", .style = .{ .bg = col_dialog_bg } },

            // < Save >
            if (is_save)
                .{ .text = "< Save >", .style = .{ .fg = col_sel_fg, .bg = col_sel_bg, .bold = true } }
            else
                .{ .text = "< ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
            if (!is_save)
                .{ .text = "S", .style = .{ .fg = col_hotkey, .bg = col_dialog_bg, .bold = true } }
            else
                .{ .text = "" },
            if (!is_save)
                .{ .text = "ave >", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } }
            else
                .{ .text = "" },
        }, .{ .row_offset = btn_row, .col_offset = btn_start, .wrap = .none });

        // Status message if present
        if (status.len > 0) {
            _ = dialog_box.print(&[_]vaxis.Segment{.{
                .text = status,
                .style = .{ .fg = col_hotkey, .bg = col_dialog_bg, .bold = true },
            }}, .{ .row_offset = dh - 2, .col_offset = 2, .wrap = .none });
        }
    }

    // Modal dialogs rendered on top
    switch (mode) {
        .nav => {},
        .help => renderHelpModal(win, arena),
        .edit => renderEditModal(win, arena),
        .save_dialog => renderSaveModal(win),
        .confirm => renderConfirmModal(win),
    }
}

fn renderHelpModal(win: vaxis.Window, arena: std.mem.Allocator) void {
    const mw: u16 = @min(win.width -| 4, 72);
    const mh: u16 = @min(win.height -| 2, 16);
    const mx: i17 = @intCast((win.width -| mw) / 2);
    const my: i17 = @intCast((win.height -| mh) / 2);

    drawShadow(win, mx, my, mw, mh);

    const modal = win.child(.{
        .x_off = mx,
        .y_off = my,
        .width = mw,
        .height = mh,
        .border = .{
            .where = .all,
            .glyphs = .single_square,
            .style = .{ .fg = col_dialog_border, .bg = col_dialog_bg },
        },
    });
    modal.fill(.{
        .char = .{ .grapheme = " ", .width = 1 },
        .style = .{ .bg = col_dialog_bg },
    });

    const text_win = modal.child(.{
        .x_off = 1,
        .y_off = 0,
        .width = if (modal.width > 2) modal.width - 2 else modal.width,
        .height = modal.height,
    });

    if (optUnderCursor()) |opt_idx| {
        const f = schema[opt_idx];
        const title_str = std.fmt.allocPrint(arena, " Help: CONFIG_{s} ", .{f.name}) catch " Help ";
        const tx: u16 = if (mw > title_str.len) @intCast((mw - @as(u16, @intCast(title_str.len))) / 2) else 1;
        _ = win.print(&[_]vaxis.Segment{.{
            .text = title_str,
            .style = .{ .fg = col_title, .bg = col_dialog_bg, .bold = true },
        }}, .{ .row_offset = @intCast(my), .col_offset = @intCast(mx + @as(i17, @intCast(tx))), .wrap = .none });

        const key_str = std.fmt.allocPrint(arena, "Symbol: CONFIG_{s}", .{f.name}) catch "";
        _ = text_win.print(&[_]vaxis.Segment{.{
            .text = key_str,
            .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg, .bold = true },
        }}, .{ .row_offset = 0, .col_offset = 0, .wrap = .none });

        const prompt_str = std.fmt.allocPrint(arena, "Prompt: {s}", .{f.help}) catch "";
        _ = text_win.print(&[_]vaxis.Segment{.{
            .text = prompt_str,
            .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg, .bold = true },
        }}, .{ .row_offset = 1, .col_offset = 0, .wrap = .none });

        const desc_text = if (f.desc.len > 0) f.desc else f.help;
        _ = text_win.print(&[_]vaxis.Segment{.{
            .text = desc_text,
            .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg },
        }}, .{ .row_offset = 3, .col_offset = 0, .wrap = .word });

        const val_str = switch (values[opt_idx]) {
            .bool => |bv| if (bv) "Current value: [*] y (enabled)" else "Current value: [ ] n (disabled)",
            .int => |iv| std.fmt.allocPrint(arena, "Current value: {d}", .{iv}) catch "",
            .str => |sv| std.fmt.allocPrint(arena, "Current value: \"{s}\"", .{sv}) catch "",
        };
        _ = text_win.print(&[_]vaxis.Segment{.{
            .text = val_str,
            .style = .{ .fg = col_tag, .bg = col_dialog_bg, .bold = true },
        }}, .{ .row_offset = text_win.height -| 3, .col_offset = 0, .wrap = .none });
    } else {
        // Help on submenu category
        const si = root_items[cursor].submenu;
        const grp = submenus[si];
        const title_str = std.fmt.allocPrint(arena, " Help: {s} ", .{grp.name}) catch " Help ";
        const tx: u16 = if (mw > title_str.len) @intCast((mw - @as(u16, @intCast(title_str.len))) / 2) else 1;
        _ = win.print(&[_]vaxis.Segment{.{
            .text = title_str,
            .style = .{ .fg = col_title, .bg = col_dialog_bg, .bold = true },
        }}, .{ .row_offset = @intCast(my), .col_offset = @intCast(mx + @as(i17, @intCast(tx))), .wrap = .none });

        _ = text_win.print(&[_]vaxis.Segment{.{
            .text = "Submenu category.",
            .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg, .bold = true },
        }}, .{ .row_offset = 0, .col_offset = 0, .wrap = .none });

        const desc = std.fmt.allocPrint(arena, "Contains {d} options for {s}.", .{ grp.opt_indices.len, grp.name }) catch "";
        _ = text_win.print(&[_]vaxis.Segment{.{
            .text = desc,
            .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg },
        }}, .{ .row_offset = 2, .col_offset = 0, .wrap = .word });

        _ = text_win.print(&[_]vaxis.Segment{.{
            .text = "Press <Enter> or <Space> to open this submenu.",
            .style = .{ .fg = col_tag, .bg = col_dialog_bg, .bold = true },
        }}, .{ .row_offset = 4, .col_offset = 0, .wrap = .none });
    }

    const btn_str = "<  OK  >";
    const bx: u16 = if (mw > btn_str.len) @intCast((mw - @as(u16, @intCast(btn_str.len))) / 2) else 1;
    _ = modal.print(&[_]vaxis.Segment{.{
        .text = btn_str,
        .style = .{ .fg = col_sel_fg, .bg = col_sel_bg, .bold = true },
    }}, .{ .row_offset = modal.height - 1, .col_offset = bx, .wrap = .none });
}

fn renderEditModal(win: vaxis.Window, arena: std.mem.Allocator) void {
    const f = schema[edit_target];

    const mw: u16 = @min(win.width -| 4, 56);
    const mh: u16 = @min(win.height -| 2, 10);
    const mx: i17 = @intCast((win.width -| mw) / 2);
    const my: i17 = @intCast((win.height -| mh) / 2);

    drawShadow(win, mx, my, mw, mh);

    const modal = win.child(.{
        .x_off = mx,
        .y_off = my,
        .width = mw,
        .height = mh,
        .border = .{
            .where = .all,
            .glyphs = .single_square,
            .style = .{ .fg = col_dialog_border, .bg = col_dialog_bg },
        },
    });
    modal.fill(.{
        .char = .{ .grapheme = " ", .width = 1 },
        .style = .{ .bg = col_dialog_bg },
    });

    const title_str = std.fmt.allocPrint(arena, " CONFIG_{s} ", .{f.name}) catch " Edit ";
    const tx: u16 = if (mw > title_str.len) @intCast((mw - @as(u16, @intCast(title_str.len))) / 2) else 1;
    _ = win.print(&[_]vaxis.Segment{.{
        .text = title_str,
        .style = .{ .fg = col_title, .bg = col_dialog_bg, .bold = true },
    }}, .{ .row_offset = @intCast(my), .col_offset = @intCast(mx + @as(i17, @intCast(tx))), .wrap = .none });

    _ = modal.print(&[_]vaxis.Segment{.{
        .text = "Please enter a decimal value:",
        .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg },
    }}, .{ .row_offset = 0, .col_offset = 2, .wrap = .none });

    // Input field with white background
    const input_box_w = mw - 8;
    const input_line = modal.child(.{
        .x_off = 3,
        .y_off = 2,
        .width = input_box_w,
        .height = 3,
        .border = .{
            .where = .all,
            .glyphs = .single_square,
            .style = .{ .fg = col_dialog_border, .bg = col_input_bg },
        },
    });
    input_line.fill(.{
        .char = .{ .grapheme = " ", .width = 1 },
        .style = .{ .bg = col_input_bg },
    });

    const input_text = std.fmt.allocPrint(arena, " {s}_", .{edit_buf[0..edit_len]}) catch "";
    _ = input_line.print(&[_]vaxis.Segment{.{
        .text = input_text,
        .style = .{ .fg = col_input_fg, .bg = col_input_bg, .bold = true },
    }}, .{ .row_offset = 0, .col_offset = 0, .wrap = .none });

    if (status.len > 0) {
        _ = modal.print(&[_]vaxis.Segment{.{
            .text = status,
            .style = .{ .fg = col_hotkey, .bg = col_dialog_bg, .bold = true },
        }}, .{ .row_offset = 5, .col_offset = 3, .wrap = .none });
    }

    const is_ok = (edit_modal_btn == .ok);
    const is_cancel = (edit_modal_btn == .cancel);

    _ = modal.print(&[_]vaxis.Segment{
        // < Ok >
        if (is_ok)
            .{ .text = "<  Ok  >", .style = .{ .fg = col_sel_fg, .bg = col_sel_bg, .bold = true } }
        else
            .{ .text = "< ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
        if (!is_ok)
            .{ .text = "O", .style = .{ .fg = col_hotkey, .bg = col_dialog_bg, .bold = true } }
        else
            .{ .text = "" },
        if (!is_ok)
            .{ .text = "k  >", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } }
        else
            .{ .text = "" },
        .{ .text = "        ", .style = .{ .bg = col_dialog_bg } },

        // < Cancel >
        if (is_cancel)
            .{ .text = "< Cancel >", .style = .{ .fg = col_sel_fg, .bg = col_sel_bg, .bold = true } }
        else
            .{ .text = "< Cancel >", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
    }, .{ .row_offset = modal.height - 1, .col_offset = 12, .wrap = .none });
}

fn renderConfirmModal(win: vaxis.Window) void {
    const mw: u16 = @min(win.width -| 4, 52);
    const mh: u16 = 8;
    const mx: i17 = @intCast((win.width -| mw) / 2);
    const my: i17 = @intCast((win.height -| mh) / 2);

    drawShadow(win, mx, my, mw, mh);

    const modal = win.child(.{
        .x_off = mx,
        .y_off = my,
        .width = mw,
        .height = mh,
        .border = .{
            .where = .all,
            .glyphs = .single_square,
            .style = .{ .fg = col_dialog_border, .bg = col_dialog_bg },
        },
    });
    modal.fill(.{
        .char = .{ .grapheme = " ", .width = 1 },
        .style = .{ .bg = col_dialog_bg },
    });

    if (isDirty()) {
        const title_str = " Save Configuration ";
        const tx: u16 = if (mw > title_str.len) @intCast((mw - @as(u16, @intCast(title_str.len))) / 2) else 1;
        _ = win.print(&[_]vaxis.Segment{.{
            .text = title_str,
            .style = .{ .fg = col_title, .bg = col_dialog_bg, .bold = true },
        }}, .{ .row_offset = @intCast(my), .col_offset = @intCast(mx + @as(i17, @intCast(tx))), .wrap = .none });

        _ = modal.print(&[_]vaxis.Segment{.{
            .text = "Do you wish to save your new configuration?",
            .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg, .bold = true },
        }}, .{ .row_offset = 1, .col_offset = 3, .wrap = .none });

        const is_yes = (confirm_modal_btn == .yes);
        const is_no = (confirm_modal_btn == .no);
        const is_cancel = (confirm_modal_btn == .cancel);

        _ = modal.print(&[_]vaxis.Segment{
            // < Yes >
            if (is_yes)
                .{ .text = "< Yes >", .style = .{ .fg = col_sel_fg, .bg = col_sel_bg, .bold = true } }
            else
                .{ .text = "< ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
            if (!is_yes)
                .{ .text = "Y", .style = .{ .fg = col_hotkey, .bg = col_dialog_bg, .bold = true } }
            else
                .{ .text = "" },
            if (!is_yes)
                .{ .text = "es >", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } }
            else
                .{ .text = "" },
            .{ .text = "    ", .style = .{ .bg = col_dialog_bg } },

            // < No >
            if (is_no)
                .{ .text = "< No >", .style = .{ .fg = col_sel_fg, .bg = col_sel_bg, .bold = true } }
            else
                .{ .text = "< ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
            if (!is_no)
                .{ .text = "N", .style = .{ .fg = col_hotkey, .bg = col_dialog_bg, .bold = true } }
            else
                .{ .text = "" },
            if (!is_no)
                .{ .text = "o >", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } }
            else
                .{ .text = "" },
            .{ .text = "    ", .style = .{ .bg = col_dialog_bg } },

            // < Cancel >
            if (is_cancel)
                .{ .text = "< Cancel >", .style = .{ .fg = col_sel_fg, .bg = col_sel_bg, .bold = true } }
            else
                .{ .text = "< Cancel >", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
        }, .{ .row_offset = modal.height - 2, .col_offset = 6, .wrap = .none });
    } else {
        const title_str = " Exit Configuration ";
        const tx: u16 = if (mw > title_str.len) @intCast((mw - @as(u16, @intCast(title_str.len))) / 2) else 1;
        _ = win.print(&[_]vaxis.Segment{.{
            .text = title_str,
            .style = .{ .fg = col_title, .bg = col_dialog_bg, .bold = true },
        }}, .{ .row_offset = @intCast(my), .col_offset = @intCast(mx + @as(i17, @intCast(tx))), .wrap = .none });

        const prompt_str = "Do you wish to exit?";
        const px: u16 = if (mw > prompt_str.len) @intCast((mw - @as(u16, @intCast(prompt_str.len))) / 2) else 2;
        _ = modal.print(&[_]vaxis.Segment{.{
            .text = prompt_str,
            .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg, .bold = true },
        }}, .{ .row_offset = 1, .col_offset = px, .wrap = .none });

        const is_yes = (confirm_modal_btn == .yes);
        const is_no = (confirm_modal_btn == .no or confirm_modal_btn == .cancel);

        _ = modal.print(&[_]vaxis.Segment{
            // < Yes >
            if (is_yes)
                .{ .text = "< Yes >", .style = .{ .fg = col_sel_fg, .bg = col_sel_bg, .bold = true } }
            else
                .{ .text = "< ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
            if (!is_yes)
                .{ .text = "Y", .style = .{ .fg = col_hotkey, .bg = col_dialog_bg, .bold = true } }
            else
                .{ .text = "" },
            if (!is_yes)
                .{ .text = "es >", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } }
            else
                .{ .text = "" },
            .{ .text = "        ", .style = .{ .bg = col_dialog_bg } },

            // < No >
            if (is_no)
                .{ .text = "< No >", .style = .{ .fg = col_sel_fg, .bg = col_sel_bg, .bold = true } }
            else
                .{ .text = "< ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
            if (!is_no)
                .{ .text = "N", .style = .{ .fg = col_hotkey, .bg = col_dialog_bg, .bold = true } }
            else
                .{ .text = "" },
            if (!is_no)
                .{ .text = "o >", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } }
            else
                .{ .text = "" },
        }, .{ .row_offset = modal.height - 2, .col_offset = 14, .wrap = .none });
    }
}

fn renderSaveModal(win: vaxis.Window) void {
    const mw: u16 = @min(win.width -| 4, 56);
    const mh: u16 = 9;
    const mx: i17 = @intCast((win.width -| mw) / 2);
    const my: i17 = @intCast((win.height -| mh) / 2);

    drawShadow(win, mx, my, mw, mh);

    const modal = win.child(.{
        .x_off = mx,
        .y_off = my,
        .width = mw,
        .height = mh,
        .border = .{
            .where = .all,
            .glyphs = .single_square,
            .style = .{ .fg = col_dialog_border, .bg = col_dialog_bg },
        },
    });
    modal.fill(.{
        .char = .{ .grapheme = " ", .width = 1 },
        .style = .{ .bg = col_dialog_bg },
    });

    const title_str = " Save Configuration ";
    const tx: u16 = if (mw > title_str.len) @intCast((mw - @as(u16, @intCast(title_str.len))) / 2) else 1;
    _ = win.print(&[_]vaxis.Segment{.{
        .text = title_str,
        .style = .{ .fg = col_title, .bg = col_dialog_bg, .bold = true },
    }}, .{ .row_offset = @intCast(my), .col_offset = @intCast(mx + @as(i17, @intCast(tx))), .wrap = .none });

    _ = modal.print(&[_]vaxis.Segment{.{
        .text = "Save configuration to .config?",
        .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg, .bold = true },
    }}, .{ .row_offset = 1, .col_offset = 3, .wrap = .none });

    _ = modal.print(&[_]vaxis.Segment{.{
        .text = "Press <Enter> to commit, <Esc> to cancel.",
        .style = .{ .fg = col_tag, .bg = col_dialog_bg },
    }}, .{ .row_offset = 3, .col_offset = 3, .wrap = .none });

    const is_ok = (save_modal_btn == .ok);
    const is_cancel = (save_modal_btn == .cancel);

    _ = modal.print(&[_]vaxis.Segment{
        // < Ok >
        if (is_ok)
            .{ .text = "<  Ok  >", .style = .{ .fg = col_sel_fg, .bg = col_sel_bg, .bold = true } }
        else
            .{ .text = "< ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
        if (!is_ok)
            .{ .text = "O", .style = .{ .fg = col_hotkey, .bg = col_dialog_bg, .bold = true } }
        else
            .{ .text = "" },
        if (!is_ok)
            .{ .text = "k  >", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } }
        else
            .{ .text = "" },
        .{ .text = "        ", .style = .{ .bg = col_dialog_bg } },

        // < Cancel >
        if (is_cancel)
            .{ .text = "< Cancel >", .style = .{ .fg = col_sel_fg, .bg = col_sel_bg, .bold = true } }
        else
            .{ .text = "< Cancel >", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
    }, .{ .row_offset = modal.height - 2, .col_offset = 12, .wrap = .none });
}

fn saveDialogKey(key: vaxis.Key) void {
    if (key.matches(vaxis.Key.left, .{}) or key.matches(vaxis.Key.right, .{}) or key.matches(vaxis.Key.tab, .{})) {
        save_modal_btn = if (save_modal_btn == .ok) .cancel else .ok;
        return;
    }
    if (key.matches(vaxis.Key.enter, .{}) or key.matches(vaxis.Key.space, .{})) {
        if (save_modal_btn == .ok) {
            _ = doSave();
        }
        mode = .nav;
        return;
    }
    if (key.matches('y', .{}) or key.matches('Y', .{}) or key.matches('o', .{}) or key.matches('O', .{})) {
        _ = doSave();
        mode = .nav;
        return;
    }
    if (key.matches(vaxis.Key.escape, .{}) or key.matches('n', .{}) or key.matches('N', .{}) or key.matches('c', .{ .ctrl = true })) {
        mode = .nav;
        return;
    }
}

fn requestQuit() void {
    confirm_modal_btn = .yes;
    mode = .confirm;
}

fn doSave() bool {
    const new_text = cfg_write.merge(g_alloc, schema, original, &values) catch {
        status = "out of memory";
        return false;
    };
    if (kconfig.validate(schema, new_text)) |d| {
        status = std.fmt.bufPrint(&status_buf, "invalid config: line {d}: {s} '{s}'", .{
            d.line, @tagName(d.kind), d.key,
        }) catch "merged config invalid";
        g_alloc.free(new_text);
        return false;
    }
    std.Io.Dir.cwd().writeFile(g_io, .{ .sub_path = ".config", .data = new_text }) catch |err| {
        status = std.fmt.bufPrint(&status_buf, "write .config failed: {s}", .{@errorName(err)}) catch "write failed";
        g_alloc.free(new_text);
        return false;
    };
    g_alloc.free(original);
    original = new_text;
    saved_values = values;
    status = "Configuration saved to .config";
    return true;
}

fn performSelectAction() void {
    if (current_menu == null) {
        switch (root_items[cursor]) {
            .submenu => |si| {
                menu_cursor_stack = cursor;
                current_menu = si;
                cursor = 0;
                scroll = 0;
                status = "";
            },
            .opt => |idx| {
                switch (values[idx]) {
                    .bool => |bv| {
                        values[idx] = .{ .bool = !bv };
                    },
                    .int => |iv| {
                        edit_target = idx;
                        edit_len = (std.fmt.bufPrint(&edit_buf, "{d}", .{iv}) catch unreachable).len;
                        edit_modal_btn = .ok;
                        mode = .edit;
                    },
                    else => {},
                }
            },
        }
    } else {
        if (optUnderCursor()) |idx| {
            switch (values[idx]) {
                .bool => |bv| {
                    values[idx] = .{ .bool = !bv };
                },
                .int => |iv| {
                    edit_target = idx;
                    edit_len = (std.fmt.bufPrint(&edit_buf, "{d}", .{iv}) catch unreachable).len;
                    edit_modal_btn = .ok;
                    mode = .edit;
                },
                else => {},
            }
        }
    }
}

fn performExitAction() void {
    if (current_menu != null) {
        current_menu = null;
        cursor = menu_cursor_stack;
        scroll = 0;
        status = "";
    } else {
        requestQuit();
    }
}

fn navKey(key: vaxis.Key) void {
    if (key.matches('c', .{ .ctrl = true })) return requestQuit();

    // Left / Right arrow or Tab changes active action button
    if (key.matches(vaxis.Key.left, .{})) {
        active_btn = @enumFromInt((@as(u8, @intFromEnum(active_btn)) + 3) % 4);
        return;
    }
    if (key.matches(vaxis.Key.right, .{})) {
        active_btn = @enumFromInt((@as(u8, @intFromEnum(active_btn)) + 1) % 4);
        return;
    }
    if (key.matches(vaxis.Key.tab, .{})) {
        active_btn = @enumFromInt((@as(u8, @intFromEnum(active_btn)) + 1) % 4);
        return;
    }

    // Esc or q exits current submenu or requests quitting
    if (key.matches(vaxis.Key.escape, .{}) or key.matches('q', .{})) {
        performExitAction();
        return;
    }

    // e / E triggers Select action
    if (key.matches('e', .{}) or key.matches('E', .{})) {
        performSelectAction();
        return;
    }

    if (key.matches('?', .{}) or key.matches('h', .{}) or key.matches('H', .{})) {
        mode = .help;
        return;
    }
    if (key.matches('s', .{}) or key.matches('S', .{})) {
        save_modal_btn = .ok;
        mode = .save_dialog;
        return;
    }

    if (key.matches(vaxis.Key.down, .{}) or key.matches('j', .{})) {
        status = "";
        if (cursor + 1 < currentCount()) cursor += 1;
        return;
    }
    if (key.matches(vaxis.Key.up, .{}) or key.matches('k', .{})) {
        status = "";
        if (cursor > 0) cursor -= 1;
        return;
    }
    if (key.matches(vaxis.Key.page_down, .{})) {
        status = "";
        cursor = @min(cursor + 10, currentCount() -| 1);
        return;
    }
    if (key.matches(vaxis.Key.page_up, .{})) {
        status = "";
        cursor = cursor -| 10;
        return;
    }
    if (key.matches(vaxis.Key.home, .{})) {
        status = "";
        cursor = 0;
        return;
    }
    if (key.matches(vaxis.Key.end, .{})) {
        status = "";
        cursor = currentCount() -| 1;
        return;
    }

    // Direct hotkeys for bool toggle: y / n
    if (key.matches('y', .{}) or key.matches('Y', .{})) {
        if (optUnderCursor()) |idx| {
            switch (values[idx]) {
                .bool => {
                    values[idx] = .{ .bool = true };
                    status = "";
                },
                else => {},
            }
        }
        return;
    }
    if (key.matches('n', .{}) or key.matches('N', .{})) {
        if (optUnderCursor()) |idx| {
            switch (values[idx]) {
                .bool => {
                    values[idx] = .{ .bool = false };
                    status = "";
                },
                else => {},
            }
        }
        return;
    }

    // Space toggles the item directly under cursor (authentic menuconfig behavior)
    if (key.matches(vaxis.Key.space, .{})) {
        status = "";
        performSelectAction();
        return;
    }

    // Enter executes the selected bottom action button
    if (key.matches(vaxis.Key.enter, .{})) {
        status = "";
        switch (active_btn) {
            .select => performSelectAction(),
            .exit => performExitAction(),
            .help => { mode = .help; },
            .save => {
                save_modal_btn = .ok;
                mode = .save_dialog;
            },
        }
        return;
    }
}

fn editKey(key: vaxis.Key) void {
    if (key.matches('c', .{ .ctrl = true }) or key.matches(vaxis.Key.escape, .{})) {
        mode = .nav;
        status = "";
        return;
    }
    if (key.matches(vaxis.Key.left, .{}) or key.matches(vaxis.Key.right, .{}) or key.matches(vaxis.Key.tab, .{})) {
        edit_modal_btn = if (edit_modal_btn == .ok) .cancel else .ok;
        return;
    }
    if (key.matches(vaxis.Key.enter, .{})) {
        if (edit_modal_btn == .cancel) {
            mode = .nav;
            status = "";
            return;
        }
        if (parseEdit(edit_buf[0..edit_len])) |v| {
            values[edit_target] = .{ .int = v };
            mode = .nav;
            status = "";
        } else {
            status = "not a valid u32";
        }
        return;
    }
    if (key.matches(vaxis.Key.backspace, .{})) {
        if (edit_len > 0) edit_len -= 1;
        return;
    }
    if (key.codepoint >= '0' and key.codepoint <= '9' and
        !key.mods.ctrl and !key.mods.alt and edit_len < edit_buf.len)
    {
        edit_buf[edit_len] = @intCast(key.codepoint);
        edit_len += 1;
    }
}

fn helpKey(key: vaxis.Key) void {
    if (key.matches(vaxis.Key.enter, .{}) or
        key.matches(vaxis.Key.space, .{}) or
        key.matches(vaxis.Key.escape, .{}) or
        key.matches('q', .{}) or
        key.matches('h', .{}) or
        key.matches('?', .{}) or
        key.matches('c', .{ .ctrl = true }))
    {
        mode = .nav;
    }
}

fn confirmKey(key: vaxis.Key) void {
    if (isDirty()) {
        if (key.matches(vaxis.Key.left, .{})) {
            confirm_modal_btn = @enumFromInt((@as(u8, @intFromEnum(confirm_modal_btn)) + 2) % 3);
            return;
        }
        if (key.matches(vaxis.Key.right, .{}) or key.matches(vaxis.Key.tab, .{})) {
            confirm_modal_btn = @enumFromInt((@as(u8, @intFromEnum(confirm_modal_btn)) + 1) % 3);
            return;
        }
        if (key.matches(vaxis.Key.enter, .{}) or key.matches(vaxis.Key.space, .{})) {
            switch (confirm_modal_btn) {
                .yes => {
                    if (doSave()) should_quit = true else mode = .nav;
                },
                .no => {
                    should_quit = true;
                },
                .cancel => {
                    mode = .nav;
                },
            }
            return;
        }
        if (key.matches('y', .{}) or key.matches('Y', .{})) {
            if (doSave()) should_quit = true else mode = .nav;
            return;
        }
        if (key.matches('n', .{}) or key.matches('N', .{})) {
            should_quit = true;
            return;
        }
        if (key.matches(vaxis.Key.escape, .{}) or key.matches('c', .{}) or key.matches('C', .{})) {
            mode = .nav;
            return;
        }
    } else {
        if (key.matches(vaxis.Key.left, .{}) or key.matches(vaxis.Key.right, .{}) or key.matches(vaxis.Key.tab, .{})) {
            confirm_modal_btn = if (confirm_modal_btn == .yes) .no else .yes;
            return;
        }
        if (key.matches(vaxis.Key.enter, .{}) or key.matches(vaxis.Key.space, .{})) {
            if (confirm_modal_btn == .yes) {
                should_quit = true;
            } else {
                mode = .nav;
            }
            return;
        }
        if (key.matches('y', .{}) or key.matches('Y', .{})) {
            should_quit = true;
            return;
        }
        if (key.matches('n', .{}) or key.matches('N', .{}) or key.matches(vaxis.Key.escape, .{}) or key.matches('c', .{}) or key.matches('C', .{})) {
            mode = .nav;
            return;
        }
    }
}

fn handleKey(key: vaxis.Key) void {
    switch (mode) {
        .nav => navKey(key),
        .edit => editKey(key),
        .help => helpKey(key),
        .save_dialog => saveDialogKey(key),
        .confirm => confirmKey(key),
    }
}

fn handleNavMouse(mouse: vaxis.Mouse, win: vaxis.Window) void {
    if (mouse.button == .wheel_up) {
        status = "";
        if (cursor > 0) cursor -= 1;
        return;
    }
    if (mouse.button == .wheel_down) {
        status = "";
        if (cursor + 1 < currentCount()) cursor += 1;
        return;
    }

    if (win.height < 6 or win.width < 20) return;

    const dw: u16 = if (win.width > 8) @min(win.width - 4, 88) else win.width;
    const dh: u16 = if (win.height > 3) @min(win.height - 2, 32) else win.height;
    const dx: i16 = @intCast((win.width -| dw) / 2);
    const dy: i16 = 1 + @as(i16, @intCast((win.height -| 1 -| dh) / 2));

    const inner_top: i16 = if (dh >= 10) 3 else 1;
    const inner_h: u16 = if (dh > 7) dh - 6 else 2;
    const inner_w: u16 = if (dw > 4) dw - 4 else dw;

    const list_y_start: i16 = dy + inner_top + 2;
    const list_h: i16 = @intCast(if (inner_h > 2) inner_h - 2 else 0);
    const list_x_start: i16 = dx + 3;
    const list_x_end: i16 = dx + @as(i16, @intCast(inner_w));

    const is_in_list = (mouse.col >= list_x_start and mouse.col <= list_x_end and
        mouse.row >= list_y_start and mouse.row < list_y_start + list_h);

    const btn_y: i16 = dy + @as(i16, @intCast(dh)) - 2;
    const btn_str_len: u16 = 48;
    const btn_start: u16 = if (dw > btn_str_len) (dw - btn_str_len) / 2 else 1;
    const btn_x: i16 = dx + 1 + @as(i16, @intCast(btn_start));

    // Hover / motion tracking
    if (mouse.type == .motion or mouse.type == .drag) {
        if (is_in_list) {
            const r: usize = @intCast(mouse.row - list_y_start);
            const item_idx = scroll + r;
            if (item_idx < currentCount()) {
                cursor = item_idx;
            }
        } else if (dh >= 6 and mouse.row == btn_y) {
            if (mouse.col >= btn_x and mouse.col < btn_x + 10) {
                active_btn = .select;
            } else if (mouse.col >= btn_x + 10 and mouse.col < btn_x + 22) {
                active_btn = .exit;
            } else if (mouse.col >= btn_x + 22 and mouse.col < btn_x + 34) {
                active_btn = .help;
            } else if (mouse.col >= btn_x + 34 and mouse.col < btn_x + 48) {
                active_btn = .save;
            }
        }
        return;
    }

    // Middle click (СКМ) opens Help/Info
    if (mouse.button == .middle and mouse.type == .press) {
        if (is_in_list) {
            const r: usize = @intCast(mouse.row - list_y_start);
            const item_idx = scroll + r;
            if (item_idx < currentCount()) {
                cursor = item_idx;
            }
        }
        status = "";
        mode = .help;
        return;
    }

    if (mouse.button != .left or mouse.type != .press) return;

    // Check click on item list
    if (is_in_list) {
        const r: usize = @intCast(mouse.row - list_y_start);
        const item_idx = scroll + r;
        if (item_idx < currentCount()) {
            status = "";
            if (cursor == item_idx) {
                performSelectAction();
            } else {
                cursor = item_idx;
            }
        }
        return;
    }

    // Check click on bottom buttons
    if (dh >= 6 and mouse.row == btn_y) {
        if (mouse.col >= btn_x and mouse.col < btn_x + 10) {
            status = "";
            active_btn = .select;
            performSelectAction();
            return;
        }
        if (mouse.col >= btn_x + 10 and mouse.col < btn_x + 22) {
            status = "";
            active_btn = .exit;
            performExitAction();
            return;
        }
        if (mouse.col >= btn_x + 22 and mouse.col < btn_x + 34) {
            status = "";
            active_btn = .help;
            mode = .help;
            return;
        }
        if (mouse.col >= btn_x + 34 and mouse.col < btn_x + 48) {
            status = "";
            active_btn = .save;
            save_modal_btn = .ok;
            mode = .save_dialog;
            return;
        }
    }
}

fn handleHelpMouse(mouse: vaxis.Mouse, _: vaxis.Window) void {
    if (mouse.button == .left and mouse.type == .press) {
        mode = .nav;
    }
}

fn handleEditMouse(mouse: vaxis.Mouse, win: vaxis.Window) void {
    const mw: u16 = @min(win.width -| 4, 56);
    const mh: u16 = @min(win.height -| 2, 10);
    const mx: i16 = @intCast((win.width -| mw) / 2);
    const my: i16 = @intCast((win.height -| mh) / 2);

    const btn_y: i16 = my + @as(i16, @intCast(mh)) - 2;
    const btn_x: i16 = mx + 1 + 12;

    if (mouse.type == .motion or mouse.type == .drag) {
        if (mouse.row == btn_y) {
            if (mouse.col >= btn_x and mouse.col < btn_x + 10) {
                edit_modal_btn = .ok;
            } else if (mouse.col >= btn_x + 10 and mouse.col < btn_x + 24) {
                edit_modal_btn = .cancel;
            }
        }
        return;
    }

    if (mouse.button != .left or mouse.type != .press) return;

    if (mouse.row == btn_y) {
        if (mouse.col >= btn_x and mouse.col < btn_x + 10) {
            // <  Ok  >
            if (parseEdit(edit_buf[0..edit_len])) |v| {
                values[edit_target] = .{ .int = v };
                mode = .nav;
                status = "";
            } else {
                status = "not a valid u32";
            }
            return;
        }
        if (mouse.col >= btn_x + 10 and mouse.col < btn_x + 24) {
            // < Cancel >
            mode = .nav;
            status = "";
            return;
        }
    }
    // Clicking outside modal dismisses
    if (mouse.col < mx or mouse.col >= mx + @as(i16, @intCast(mw)) or
        mouse.row < my or mouse.row >= my + @as(i16, @intCast(mh)))
    {
        mode = .nav;
        status = "";
    }
}

fn handleSaveMouse(mouse: vaxis.Mouse, win: vaxis.Window) void {
    const mw: u16 = @min(win.width -| 4, 56);
    const mh: u16 = 9;
    const mx: i16 = @intCast((win.width -| mw) / 2);
    const my: i16 = @intCast((win.height -| mh) / 2);

    const btn_y: i16 = my + @as(i16, @intCast(mh)) - 3;
    const btn_x: i16 = mx + 1 + 12;

    if (mouse.type == .motion or mouse.type == .drag) {
        if (mouse.row == btn_y) {
            if (mouse.col >= btn_x and mouse.col < btn_x + 10) {
                save_modal_btn = .ok;
            } else if (mouse.col >= btn_x + 10 and mouse.col < btn_x + 24) {
                save_modal_btn = .cancel;
            }
        }
        return;
    }

    if (mouse.button != .left or mouse.type != .press) return;

    if (mouse.row == btn_y) {
        if (mouse.col >= btn_x and mouse.col < btn_x + 10) {
            // < Ok >
            _ = doSave();
            mode = .nav;
            return;
        }
        if (mouse.col >= btn_x + 10 and mouse.col < btn_x + 24) {
            // < Cancel >
            mode = .nav;
            return;
        }
    }
    // Clicking outside modal dismisses
    if (mouse.col < mx or mouse.col >= mx + @as(i16, @intCast(mw)) or
        mouse.row < my or mouse.row >= my + @as(i16, @intCast(mh)))
    {
        mode = .nav;
    }
}

fn handleConfirmMouse(mouse: vaxis.Mouse, win: vaxis.Window) void {
    const mw: u16 = @min(win.width -| 4, 52);
    const mh: u16 = 8;
    const mx: i16 = @intCast((win.width -| mw) / 2);
    const my: i16 = @intCast((win.height -| mh) / 2);

    const btn_y: i16 = my + @as(i16, @intCast(mh)) - 3;

    if (mouse.type == .motion or mouse.type == .drag) {
        if (mouse.row == btn_y) {
            if (isDirty()) {
                const btn_x: i16 = mx + 1 + 6;
                if (mouse.col >= btn_x and mouse.col < btn_x + 9) {
                    confirm_modal_btn = .yes;
                } else if (mouse.col >= btn_x + 9 and mouse.col < btn_x + 19) {
                    confirm_modal_btn = .no;
                } else if (mouse.col >= btn_x + 19 and mouse.col < btn_x + 32) {
                    confirm_modal_btn = .cancel;
                }
            } else {
                const btn_x: i16 = mx + 1 + 14;
                if (mouse.col >= btn_x and mouse.col < btn_x + 11) {
                    confirm_modal_btn = .yes;
                } else if (mouse.col >= btn_x + 11 and mouse.col < btn_x + 24) {
                    confirm_modal_btn = .no;
                }
            }
        }
        return;
    }

    if (mouse.button != .left or mouse.type != .press) return;

    if (isDirty()) {
        const btn_x: i16 = mx + 1 + 6;
        if (mouse.row == btn_y) {
            if (mouse.col >= btn_x and mouse.col < btn_x + 9) {
                // < Yes >
                if (doSave()) should_quit = true else mode = .nav;
                return;
            }
            if (mouse.col >= btn_x + 9 and mouse.col < btn_x + 19) {
                // < No >
                should_quit = true;
                return;
            }
            if (mouse.col >= btn_x + 19 and mouse.col < btn_x + 32) {
                // < Cancel >
                mode = .nav;
                return;
            }
        }
    } else {
        const btn_x: i16 = mx + 1 + 14;
        if (mouse.row == btn_y) {
            if (mouse.col >= btn_x and mouse.col < btn_x + 11) {
                // < Yes >
                should_quit = true;
                return;
            }
            if (mouse.col >= btn_x + 11 and mouse.col < btn_x + 24) {
                // < No >
                mode = .nav;
                return;
            }
        }
    }
    // Clicking outside modal cancels
    if (mouse.col < mx or mouse.col >= mx + @as(i16, @intCast(mw)) or
        mouse.row < my or mouse.row >= my + @as(i16, @intCast(mh)))
    {
        mode = .nav;
    }
}

fn handleMouse(mouse: vaxis.Mouse, win: vaxis.Window) void {
    switch (mode) {
        .nav => handleNavMouse(mouse, win),
        .edit => handleEditMouse(mouse, win),
        .help => handleHelpMouse(mouse, win),
        .save_dialog => handleSaveMouse(mouse, win),
        .confirm => handleConfirmMouse(mouse, win),
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.gpa;
    g_io = io;
    g_alloc = alloc;
    frame_arena = std.heap.ArenaAllocator.init(alloc);
    defer frame_arena.deinit();

    const source: []const u8 = blk: {
        if (readText(io, alloc, ".config")) |t| {
            original = t;
            break :blk ".config";
        }
        if (readText(io, alloc, "defconfig")) |t| {
            original = t;
            break :blk "defconfig";
        }
        original = try alloc.dupe(u8, "");
        break :blk "(schema defaults)";
    };
    defer alloc.free(original);

    if (kconfig.validate(schema, original)) |d| {
        if (d.first_line) |fl| {
            std.log.err("invalid config in {s} at line {d}: duplicate key '{s}' (first at line {d})", .{ source, d.line, d.key, fl });
        } else {
            std.log.err("invalid config in {s} at line {d}: {s} key '{s}' detail '{s}'", .{ source, d.line, @tagName(d.kind), d.key, d.detail });
        }
        std.process.exit(1);
    }

    inline for (schema, 0..) |f, i| {
        values[i] = switch (f.default) {
            .bool => .{ .bool = kconfig.flag(schema, original, f.name) },
            .int => .{ .int = kconfig.get(u32, schema, original, f.name) orelse f.default.int },
            .str => .{ .str = kconfig.get([]const u8, schema, original, f.name) orelse f.default.str },
        };
    }
    saved_values = values;
    cursor = 0;

    var buffer: [1024]u8 = undefined;
    var tty = try vaxis.Tty.init(io, &buffer);
    defer tty.deinit();

    var vx = try vaxis.init(io, alloc, init.environ_map, .{});
    defer vx.deinit(alloc, tty.writer());

    var loop: vaxis.Loop(Event) = .init(io, &tty, &vx);
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), .fromSeconds(1));
    try vx.setMouseMode(tty.writer(), true);

    render(vx.window());
    try vx.render(tty.writer());

    while (!should_quit) {
        const event = try loop.nextEvent();
        switch (event) {
            .key_press => |key| handleKey(key),
            .mouse => |mouse| handleMouse(mouse, vx.window()),
            .winsize => |ws| try vx.resize(alloc, tty.writer(), ws),
        }
        render(vx.window());
        try vx.render(tty.writer());
    }
}

test "menus cover every schema option exactly once" {
    var total_opts: usize = 0;
    var seen: [schema.len]bool = .{false} ** schema.len;
    for (root_items) |item| {
        switch (item) {
            .opt => |idx| {
                try std.testing.expect(!seen[idx]);
                seen[idx] = true;
                total_opts += 1;
            },
            .submenu => {},
        }
    }
    for (submenus) |s| {
        for (s.opt_indices) |idx| {
            try std.testing.expect(!seen[idx]);
            seen[idx] = true;
            total_opts += 1;
        }
    }
    try std.testing.expectEqual(schema.len, total_opts);
    for (seen) |s| {
        try std.testing.expect(s);
    }
}

test "clampScroll follows the cursor at both edges and survives zero height" {
    try std.testing.expectEqual(@as(usize, 0), clampScroll(0, 10, 5));
    try std.testing.expectEqual(@as(usize, 11), clampScroll(20, 10, 5));
    try std.testing.expectEqual(@as(usize, 5), clampScroll(7, 10, 5));
    try std.testing.expectEqual(@as(usize, 5), clampScroll(50, 0, 5));
}

test "parseEdit accepts plain u32s and rejects empty or overflowing input" {
    try std.testing.expectEqual(@as(?u32, 12), parseEdit("12"));
    try std.testing.expectEqual(@as(?u32, null), parseEdit(""));
    try std.testing.expectEqual(@as(?u32, null), parseEdit("4294967296"));
}

test "isDirty accurately detects modifications and reversions" {
    for (schema, 0..) |f, i| {
        values[i] = f.default;
        saved_values[i] = f.default;
    }
    try std.testing.expect(!isDirty());

    // Modify a boolean
    values[0] = switch (values[0]) {
        .bool => |b| .{ .bool = !b },
        else => values[0],
    };
    try std.testing.expect(isDirty());

    // Revert it back
    values[0] = saved_values[0];
    try std.testing.expect(!isDirty());
}
