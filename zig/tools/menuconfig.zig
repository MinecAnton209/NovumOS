const std = @import("std");
const vaxis = @import("vaxis");
const config_schema = @import("config_schema");
const kconfig = config_schema.k;
const cfg_write = @import("cfg_write.zig");

const schema = &config_schema.schema;

const group_defs = [_]struct { name: []const u8, keys: []const []const u8 }{
    .{ .name = "Compile-out gates", .keys = &.{
        "ENABLE_QUANTUM",   "ENABLE_DOOMFIRE",  "ENABLE_BUILTIN_SCRIPTS",
        "ENABLE_MOUSE",     "ENABLE_SPEAKER",   "ENABLE_SMP",
        "ENABLE_NOVA",
    } },
    .{ .name = "Debug output", .keys = &.{
        "ENABLE_SERIAL_DEBUG",   "ENABLE_EARLY_LFB_DEBUG", "ENABLE_FAT_DEBUG",
        "ENABLE_KERNEL_LOGGING", "MOUSE_DEBUG",             "NOVA_DEBUG",
    } },
    .{ .name = "Audio", .keys = &.{ "ENABLE_BOOT_BEEP", "ENABLE_ERROR_BEEP" } },
    .{ .name = "Shell/system", .keys = &.{
        "ENABLE_DEBUG_COMMANDS",    "ENABLE_DEBUG_CRASH_COMMANDS", "HISTORY_SIZE",
        "ENABLE_EMBEDDED_ELFS",     "ENABLE_IDT_WATCHDOG",         "ENABLE_RSOD_REBOOT",
        "USE_GARBAGE_COLLECTOR",
    } },
    .{ .name = "Security", .keys = &.{"NOVA_PATH_POLICY_ENABLED"} },
    .{ .name = "Sizes", .keys = &.{"HEAP_INITIAL_SIZE"} },
};

const Row = union(enum) { group: []const u8, opt: usize };

fn schemaIndex(comptime name: []const u8) usize {
    for (schema, 0..) |f, i| {
        if (std.mem.eql(u8, f.name, name)) return i;
    }
    @compileError("menuconfig: group key not in schema: " ++ name);
}

const rows: [schema.len + group_defs.len]Row = blk: {
    var r: [schema.len + group_defs.len]Row = undefined;
    var n: usize = 0;
    var seen: [schema.len]bool = .{false} ** schema.len;
    for (group_defs) |g| {
        r[n] = .{ .group = g.name };
        n += 1;
        for (g.keys) |k| {
            const idx = schemaIndex(k);
            if (seen[idx]) @compileError("menuconfig: duplicate schema key in group_defs: " ++ k);
            seen[idx] = true;
            r[n] = .{ .opt = idx };
            n += 1;
        }
    }
    if (n != r.len) @compileError("menuconfig: group_defs must cover every schema key exactly once");
    for (seen, 0..) |was_seen, i| {
        if (!was_seen) @compileError("menuconfig: schema key missing from group_defs: " ++ schema[i].name);
    }
    break :blk r;
};

fn nextOpt(from: usize) ?usize {
    var i = from + 1;
    while (i < rows.len) : (i += 1) {
        if (std.meta.activeTag(rows[i]) == .opt) return i;
    }
    return null;
}

fn prevOpt(from: usize) ?usize {
    var i = from;
    while (i > 0) {
        i -= 1;
        if (std.meta.activeTag(rows[i]) == .opt) return i;
    }
    return null;
}

fn firstOpt() usize {
    for (rows, 0..) |row, i| {
        if (std.meta.activeTag(row) == .opt) return i;
    }
    return 0;
}

fn lastOpt() usize {
    var i = rows.len;
    while (i > 0) {
        i -= 1;
        if (std.meta.activeTag(rows[i]) == .opt) return i;
    }
    return 0;
}

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
    winsize: vaxis.Winsize,
};

var original: []const u8 = "";
var values: [schema.len]kconfig.Option = undefined;
var cursor: usize = 0;
var scroll: usize = 0;
var dirty = false;
var should_quit = false;
var mode: enum { nav, edit, help, confirm } = .nav;
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

fn optUnderCursor() ?usize {
    if (cursor < rows.len) {
        switch (rows[cursor]) {
            .opt => |idx| return idx,
            .group => return null,
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
    const banner_text = if (dirty)
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
    const title_str = " NovumOS Kernel Configuration ";
    const title_x: u16 = if (dw > title_str.len) @intCast((dw - @as(u16, @intCast(title_str.len))) / 2) else 1;
    _ = win.print(&[_]vaxis.Segment{.{
        .text = title_str,
        .style = .{ .fg = col_title, .bg = col_dialog_bg, .bold = true },
    }}, .{ .row_offset = @intCast(dy), .col_offset = @intCast(dx + @as(i17, @intCast(title_x))), .wrap = .none });

    // Dialog instructions
    if (dh >= 10) {
        _ = dialog_box.print(&[_]vaxis.Segment{
            .{ .text = "Arrow keys navigate the menu. ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
            .{ .text = "<Enter>", .style = .{ .fg = col_tag, .bg = col_dialog_bg, .bold = true } },
            .{ .text = " edits/selects, ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
            .{ .text = "<Space>", .style = .{ .fg = col_tag, .bg = col_dialog_bg, .bold = true } },
            .{ .text = " toggles.", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
        }, .{ .row_offset = 0, .col_offset = 1, .wrap = .none });

        _ = dialog_box.print(&[_]vaxis.Segment{
            .{ .text = "<s>", .style = .{ .fg = col_hotkey, .bg = col_dialog_bg, .bold = true } },
            .{ .text = " to save, ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
            .{ .text = "<Esc>", .style = .{ .fg = col_tag, .bg = col_dialog_bg, .bold = true } },
            .{ .text = " / ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
            .{ .text = "<q>", .style = .{ .fg = col_hotkey, .bg = col_dialog_bg, .bold = true } },
            .{ .text = " to exit, ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
            .{ .text = "<?>", .style = .{ .fg = col_tag, .bg = col_dialog_bg, .bold = true } },
            .{ .text = " for Help. Legend: ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
            .{ .text = "[*]", .style = .{ .fg = col_tag, .bg = col_dialog_bg, .bold = true } },
            .{ .text = " enabled  ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
            .{ .text = "[ ]", .style = .{ .fg = col_tag, .bg = col_dialog_bg, .bold = true } },
            .{ .text = " disabled", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
        }, .{ .row_offset = 1, .col_offset = 1, .wrap = .none });
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
    scroll = clampScroll(cursor, list_h, scroll);

    // Scroll indicators on inner box top / bottom border
    if (scroll > 0) {
        _ = dialog_box.print(&[_]vaxis.Segment{.{
            .text = "(-)",
            .style = .{ .fg = col_tag, .bg = col_dialog_bg, .bold = true },
        }}, .{ .row_offset = @intCast(inner_top), .col_offset = @intCast(inner_w - 5), .wrap = .none });
    }
    if (scroll + list_h < rows.len) {
        _ = dialog_box.print(&[_]vaxis.Segment{.{
            .text = "(+)",
            .style = .{ .fg = col_tag, .bg = col_dialog_bg, .bold = true },
        }}, .{ .row_offset = @intCast(inner_top + @as(i17, @intCast(inner_h)) - 1), .col_offset = @intCast(inner_w - 5), .wrap = .none });
    }

    // Render option rows
    var r: usize = 0;
    while (r < list_h and scroll + r < rows.len) : (r += 1) {
        const row_idx = scroll + r;
        const row = rows[row_idx];
        const is_cursor = (row_idx == cursor);

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

        switch (row) {
            .group => |name| {
                const group_text = std.fmt.allocPrint(arena, "    {s}  --->", .{name}) catch name;
                _ = inner_box.print(&[_]vaxis.Segment{.{
                    .text = group_text,
                    .style = if (is_cursor)
                        .{ .fg = col_sel_tag, .bg = col_sel_bg, .bold = true }
                    else
                        .{ .fg = col_tag, .bg = col_dialog_bg, .bold = true },
                }}, .{ .row_offset = @intCast(r), .col_offset = 0, .wrap = .none });
            },
            .opt => |i| {
                const f = schema[i];
                const bg_color = if (is_cursor) col_sel_bg else col_dialog_bg;
                const fg_color = if (is_cursor) col_sel_fg else col_dialog_fg;
                const tag_color = if (is_cursor) col_sel_tag else col_tag;

                switch (values[i]) {
                    .bool => |bv| {
                        const tag = if (bv) "[*]" else "[ ]";
                        const help_text = std.fmt.allocPrint(arena, " {s}", .{f.help}) catch f.help;
                        _ = inner_box.print(&[_]vaxis.Segment{
                            .{ .text = "  ", .style = .{ .bg = bg_color } },
                            .{ .text = tag, .style = .{ .fg = tag_color, .bg = bg_color, .bold = true } },
                            .{ .text = help_text, .style = .{ .fg = fg_color, .bg = bg_color, .bold = is_cursor } },
                        }, .{ .row_offset = @intCast(r), .col_offset = 0, .wrap = .none });
                    },
                    .int => |iv| {
                        const tag = std.fmt.allocPrint(arena, "({d})", .{iv}) catch "(?)";
                        const help_text = std.fmt.allocPrint(arena, " {s}", .{f.help}) catch f.help;
                        _ = inner_box.print(&[_]vaxis.Segment{
                            .{ .text = "  ", .style = .{ .bg = bg_color } },
                            .{ .text = tag, .style = .{ .fg = tag_color, .bg = bg_color, .bold = true } },
                            .{ .text = help_text, .style = .{ .fg = fg_color, .bg = bg_color, .bold = is_cursor } },
                        }, .{ .row_offset = @intCast(r), .col_offset = 0, .wrap = .none });
                    },
                    .str => |sv| {
                        const tag = std.fmt.allocPrint(arena, "({s})", .{sv}) catch "(?)";
                        const help_text = std.fmt.allocPrint(arena, " {s}", .{f.help}) catch f.help;
                        _ = inner_box.print(&[_]vaxis.Segment{
                            .{ .text = "  ", .style = .{ .bg = bg_color } },
                            .{ .text = tag, .style = .{ .fg = tag_color, .bg = bg_color, .bold = true } },
                            .{ .text = help_text, .style = .{ .fg = fg_color, .bg = bg_color, .bold = is_cursor } },
                        }, .{ .row_offset = @intCast(r), .col_offset = 0, .wrap = .none });
                    },
                }
            },
        }
    }

    // Bottom action buttons inside main dialog
    if (dh >= 6) {
        const btn_row: u16 = dh - 3;
        const btn_str_len: u16 = 48;
        const btn_start: u16 = if (dw > btn_str_len) (dw - btn_str_len) / 2 else 1;

        _ = dialog_box.print(&[_]vaxis.Segment{
            // <Select> (Active focused button)
            .{ .text = "<", .style = .{ .fg = col_sel_fg, .bg = col_sel_bg, .bold = true } },
            .{ .text = "Select", .style = .{ .fg = col_sel_fg, .bg = col_sel_bg, .bold = true } },
            .{ .text = ">", .style = .{ .fg = col_sel_fg, .bg = col_sel_bg, .bold = true } },
            .{ .text = "    ", .style = .{ .bg = col_dialog_bg } },

            // < Exit >
            .{ .text = "< ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
            .{ .text = "E", .style = .{ .fg = col_hotkey, .bg = col_dialog_bg, .bold = true } },
            .{ .text = "xit >", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
            .{ .text = "    ", .style = .{ .bg = col_dialog_bg } },

            // < Help >
            .{ .text = "< ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
            .{ .text = "H", .style = .{ .fg = col_hotkey, .bg = col_dialog_bg, .bold = true } },
            .{ .text = "elp >", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
            .{ .text = "    ", .style = .{ .bg = col_dialog_bg } },

            // < Save >
            .{ .text = "< ", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
            .{ .text = "S", .style = .{ .fg = col_hotkey, .bg = col_dialog_bg, .bold = true } },
            .{ .text = "ave >", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
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
        .confirm => renderConfirmModal(win),
    }
}

fn renderHelpModal(win: vaxis.Window, arena: std.mem.Allocator) void {
    const opt_idx = optUnderCursor() orelse return;
    const f = schema[opt_idx];

    const mw: u16 = @min(win.width -| 4, 68);
    const mh: u16 = @min(win.height -| 2, 14);
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

    const title_str = std.fmt.allocPrint(arena, " Help: CONFIG_{s} ", .{f.name}) catch " Help ";
    const tx: u16 = if (mw > title_str.len) @intCast((mw - @as(u16, @intCast(title_str.len))) / 2) else 1;
    _ = win.print(&[_]vaxis.Segment{.{
        .text = title_str,
        .style = .{ .fg = col_title, .bg = col_dialog_bg, .bold = true },
    }}, .{ .row_offset = @intCast(my), .col_offset = @intCast(mx + @as(i17, @intCast(tx))), .wrap = .none });

    const key_str = std.fmt.allocPrint(arena, "Symbol: CONFIG_{s}", .{f.name}) catch "";
    _ = modal.print(&[_]vaxis.Segment{.{
        .text = key_str,
        .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg, .bold = true },
    }}, .{ .row_offset = 0, .col_offset = 1, .wrap = .none });

    _ = modal.print(&[_]vaxis.Segment{.{
        .text = f.help,
        .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg },
    }}, .{ .row_offset = 2, .col_offset = 1, .wrap = .none });

    const val_str = switch (values[opt_idx]) {
        .bool => |bv| if (bv) "Current: [*] y (enabled)" else "Current: [ ] n (disabled)",
        .int => |iv| std.fmt.allocPrint(arena, "Current: {d}", .{iv}) catch "",
        .str => |sv| std.fmt.allocPrint(arena, "Current: \"{s}\"", .{sv}) catch "",
    };
    _ = modal.print(&[_]vaxis.Segment{.{
        .text = val_str,
        .style = .{ .fg = col_tag, .bg = col_dialog_bg, .bold = true },
    }}, .{ .row_offset = 4, .col_offset = 1, .wrap = .none });

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

    _ = modal.print(&[_]vaxis.Segment{
        .{ .text = "<  Ok  >", .style = .{ .fg = col_sel_fg, .bg = col_sel_bg, .bold = true } },
        .{ .text = "      ", .style = .{ .bg = col_dialog_bg } },
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

    _ = modal.print(&[_]vaxis.Segment{
        .{ .text = "<  ", .style = .{ .bg = col_dialog_bg } },
        .{ .text = "Y", .style = .{ .fg = col_hotkey, .bg = col_dialog_bg, .bold = true } },
        .{ .text = "es  >", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
        .{ .text = "    ", .style = .{ .bg = col_dialog_bg } },
        .{ .text = "<  ", .style = .{ .bg = col_dialog_bg } },
        .{ .text = "N", .style = .{ .fg = col_hotkey, .bg = col_dialog_bg, .bold = true } },
        .{ .text = "o  >", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
        .{ .text = "    ", .style = .{ .bg = col_dialog_bg } },
        .{ .text = "< Cancel >", .style = .{ .fg = col_dialog_fg, .bg = col_dialog_bg } },
    }, .{ .row_offset = modal.height - 2, .col_offset = 6, .wrap = .none });
}

fn requestQuit() void {
    if (dirty) {
        mode = .confirm;
    } else {
        should_quit = true;
    }
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
    dirty = false;
    status = "Configuration saved to .config";
    return true;
}

fn navKey(key: vaxis.Key) void {
    if (key.matches('c', .{ .ctrl = true })) return requestQuit();
    if (key.matches(vaxis.Key.escape, .{}) or key.matches('q', .{})) return requestQuit();
    if (key.matches('?', .{}) or key.matches('h', .{})) {
        mode = .help;
        return;
    }
    if (key.matches('s', .{})) {
        _ = doSave();
        return;
    }
    if (key.matches(vaxis.Key.down, .{}) or key.matches('j', .{})) {
        status = "";
        if (nextOpt(cursor)) |n| cursor = n;
        return;
    }
    if (key.matches(vaxis.Key.up, .{}) or key.matches('k', .{})) {
        status = "";
        if (prevOpt(cursor)) |n| cursor = n;
        return;
    }
    if (key.matches(vaxis.Key.page_down, .{})) {
        status = "";
        var i: usize = 0;
        while (i < 10) : (i += 1) {
            cursor = nextOpt(cursor) orelse break;
        }
        return;
    }
    if (key.matches(vaxis.Key.page_up, .{})) {
        status = "";
        var i: usize = 0;
        while (i < 10) : (i += 1) {
            cursor = prevOpt(cursor) orelse break;
        }
        return;
    }
    if (key.matches(vaxis.Key.home, .{})) {
        status = "";
        cursor = firstOpt();
        return;
    }
    if (key.matches(vaxis.Key.end, .{})) {
        status = "";
        cursor = lastOpt();
        return;
    }
    if (key.matches('y', .{}) or key.matches('Y', .{})) {
        if (optUnderCursor()) |idx| {
            switch (values[idx]) {
                .bool => {
                    values[idx] = .{ .bool = true };
                    dirty = true;
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
                    dirty = true;
                    status = "";
                },
                else => {},
            }
        }
        return;
    }
    if (key.matches(vaxis.Key.space, .{})) {
        status = "";
        if (optUnderCursor()) |idx| {
            switch (values[idx]) {
                .bool => |bv| {
                    values[idx] = .{ .bool = !bv };
                    dirty = true;
                },
                .int => |iv| {
                    edit_target = idx;
                    edit_len = (std.fmt.bufPrint(&edit_buf, "{d}", .{iv}) catch unreachable).len;
                    mode = .edit;
                },
                else => {},
            }
        }
        return;
    }
    if (key.matches(vaxis.Key.enter, .{})) {
        status = "";
        if (optUnderCursor()) |idx| {
            switch (values[idx]) {
                .int => |iv| {
                    edit_target = idx;
                    edit_len = (std.fmt.bufPrint(&edit_buf, "{d}", .{iv}) catch unreachable).len;
                    mode = .edit;
                },
                .bool => |bv| {
                    values[idx] = .{ .bool = !bv };
                    dirty = true;
                },
                else => {},
            }
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
    if (key.matches(vaxis.Key.enter, .{})) {
        if (parseEdit(edit_buf[0..edit_len])) |v| {
            values[edit_target] = .{ .int = v };
            dirty = true;
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
    if (key.matches('y', .{}) or key.matches('Y', .{}) or key.matches(vaxis.Key.enter, .{})) {
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
}

fn handleKey(key: vaxis.Key) void {
    switch (mode) {
        .nav => navKey(key),
        .edit => editKey(key),
        .help => helpKey(key),
        .confirm => confirmKey(key),
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
    cursor = firstOpt();

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

    render(vx.window());
    try vx.render(tty.writer());

    while (!should_quit) {
        const event = try loop.nextEvent();
        switch (event) {
            .key_press => |key| handleKey(key),
            .winsize => |ws| try vx.resize(alloc, tty.writer(), ws),
        }
        render(vx.window());
        try vx.render(tty.writer());
    }
}

test "navigation covers every option and skips group headers" {
    var forward: usize = 0;
    var i = firstOpt();
    while (true) {
        forward += 1;
        i = nextOpt(i) orelse break;
    }
    try std.testing.expectEqual(schema.len, forward);

    var backward: usize = 0;
    var j = lastOpt();
    while (true) {
        backward += 1;
        j = prevOpt(j) orelse break;
    }
    try std.testing.expectEqual(schema.len, backward);

    try std.testing.expectEqual(@as(?usize, null), nextOpt(rows.len - 1));
    try std.testing.expectEqual(@as(?usize, null), prevOpt(0));
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
