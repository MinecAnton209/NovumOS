const std = @import("std");
const vaxis = @import("vaxis");

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.gpa;

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

    var quit = false;
    while (!quit) {
        const event = try loop.nextEvent();
        switch (event) {
            .key_press => quit = true,
            .winsize => |ws| try vx.resize(alloc, tty.writer(), ws),
        }
        const win = vx.window();
        win.clear();
        _ = win.print(&[_]vaxis.Segment{.{ .text = "menuconfig ok - press any key" }}, .{ .wrap = .none });
        try vx.render(tty.writer());
    }
}
