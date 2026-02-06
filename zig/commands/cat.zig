// cat command - show file contents
const common = @import("common.zig");

pub fn execute(name_ptr: [*]const u8, name_len: u8) void {
    const id = common.fs_find(name_ptr, name_len);
    if (id < 0) {
        common.printZ("File not found\r\n");
        return;
    }

    var buffer: [1024]u8 = undefined;
    const size = common.fs_read(@intCast(id), &buffer, 1024);
    if (size > 0) {
        var i: usize = 0;
        while (i < @as(usize, @intCast(size))) : (i += 1) {
            common.print_char(buffer[i]);
        }
        common.printZ("\r\n");
    }
}
