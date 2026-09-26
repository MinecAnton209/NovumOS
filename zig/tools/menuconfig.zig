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

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

var original: []const u8 = "";
var values: [schema.len]kconfig.Option = undefined;
var cursor: usize = 0;
var scroll: usize = 0;
var view_h: usize = 20;
var dirty = false;
var should_quit = false;
var mode: enum { nav, edit, confirm } = .nav;
var edit_target: usize = 0;
var edit_buf: [10]u8 = undefined;
var edit_len: usize = 0;
var status: []const u8 = "";
var status_buf: [256]u8 = undefined;
var row_buf: [320]u8 = undefined;
var footer_buf: [320]u8 = undefined;
var g_io: std.Io = undefined;
var g_alloc: std.mem.Allocator = undefined;

fn readText(io: std.Io, alloc: std.mem.Allocator, path: []const u8) ?[]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => null,
        else => {
            std.log.err("menuconfig: cannot read {s}: {s}", .{ path, @errorName(err) });
            std.process.exit(1);
        },
    };
}

fn optText(i: usize) []const u8 {
    const f = schema[i];
    if (mode == .edit and edit_target == i) {
        return std.fmt.bufPrint(&row_buf, "[ ] {s} {s}_", .{ f.name, edit_buf[0..edit_len] }) catch "";
    }
    return switch (values[i]) {
        .bool => |bv| std.fmt.bufPrint(&row_buf, "[{c}] {s}", .{ if (bv) 'x' else ' ', f.name }) catch "",
        .int => |iv| std.fmt.bufPrint(&row_buf, "[{d}] {s}", .{ iv, f.name }) catch "",
        .str => |sv| std.fmt.bufPrint(&row_buf, "[{s}] {s}", .{ sv, f.name }) catch "",
    };
}

fn render(win: vaxis.Window) void {
    win.clear();
    if (win.height < 3) return;
    view_h = win.height - 2;
    scroll = clampScroll(cursor, view_h, scroll);

    _ = win.print(&[_]vaxis.Segment{.{
        .text = " menuconfig",
        .style = .{ .bold = true },
    }}, .{ .wrap = .none });

    var r: usize = 0;
    while (r < view_h and scroll + r < rows.len) : (r += 1) {
        const row = rows[scroll + r];
        const is_cursor = scroll + r == cursor;
        switch (row) {
            .group => |name| _ = win.print(&[_]vaxis.Segment{.{
                .text = name,
                .style = .{ .bold = true },
            }}, .{ .row_offset = @intCast(r + 1), .wrap = .none }),
            .opt => |i| {
                const style: vaxis.Style = if (is_cursor) .{ .reverse = true } else .{};
                _ = win.print(&[_]vaxis.Segment{
                    .{ .text = optText(i), .style = style },
                    .{ .text = "  " },
                    .{ .text = schema[i].help, .style = .{ .dim = true } },
                }, .{ .row_offset = @intCast(r + 1), .wrap = .none });
            },
        }
    }

    const footer: []const u8 = switch (mode) {
        .nav => std.fmt.bufPrint(&footer_buf, " {s} {s} Space toggle  Enter edit  s save  q quit", .{
            status, if (dirty) "[modified]" else "",
        }) catch " menuconfig",
        .edit => " digits to type, Enter commits, Esc cancels",
        .confirm => " save before quit? [y/N]",
    };
    _ = win.print(&[_]vaxis.Segment{.{
        .text = footer,
        .style = .{ .dim = true },
    }}, .{ .row_offset = win.height - 1, .wrap = .none });
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
        status = std.fmt.bufPrint(&status_buf, "invalid merged config: line {d}: {s} '{s}'", .{
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
    status = "saved.";
    return true;
}

fn navKey(key: vaxis.Key) void {
    if (key.matches('c', .{ .ctrl = true })) return requestQuit();
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
        while (i < view_h) : (i += 1) {
            cursor = nextOpt(cursor) orelse break;
        }
        return;
    }
    if (key.matches(vaxis.Key.page_up, .{})) {
        status = "";
        var i: usize = 0;
        while (i < view_h) : (i += 1) {
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
    if (key.matches(vaxis.Key.space, .{})) {
        status = "";
        switch (rows[cursor]) {
            .opt => |idx| switch (values[idx]) {
                .bool => |bv| {
                    values[idx] = .{ .bool = !bv };
                    dirty = true;
                },
                else => {},
            },
            .group => {},
        }
        return;
    }
    if (key.matches(vaxis.Key.enter, .{})) {
        switch (rows[cursor]) {
            .opt => |idx| switch (values[idx]) {
                .int => |iv| {
                    edit_target = idx;
                    edit_len = (std.fmt.bufPrint(&edit_buf, "{d}", .{iv}) catch unreachable).len;
                    mode = .edit;
                    status = "";
                },
                else => {},
            },
            .group => {},
        }
        return;
    }
    if (key.matches('s', .{})) {
        _ = doSave();
        return;
    }
    if (key.matches('q', .{})) return requestQuit();
}

fn editKey(key: vaxis.Key) void {
    if (key.matches('c', .{ .ctrl = true }) or key.matches(vaxis.Key.escape, .{})) {
        mode = .nav;
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

fn confirmKey(key: vaxis.Key) void {
    if (key.matches('y', .{})) {
        if (doSave()) should_quit = true else mode = .nav;
        return;
    }
    if (key.matches('n', .{}) or key.matches(vaxis.Key.enter, .{}) or
        key.matches(vaxis.Key.escape, .{}) or key.matches('c', .{ .ctrl = true }))
    {
        should_quit = true;
    }
}

fn handleKey(key: vaxis.Key) void {
    switch (mode) {
        .nav => navKey(key),
        .edit => editKey(key),
        .confirm => confirmKey(key),
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.gpa;
    g_io = io;
    g_alloc = alloc;

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
