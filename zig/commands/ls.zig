// ls command - list files
const common = @import("common.zig");

pub fn execute() void {
    var ids: [16]u8 = undefined;
    const count = common.fs_list(&ids);

    if (count == 0) {
        common.printZ("No files\r\n");
        return;
    }

    var i: u8 = 0;
    while (i < count) : (i += 1) {
        const id = ids[i];
        var name_buf: [13]u8 = [_]u8{0} ** 13;
        _ = common.fs_getname(id, &name_buf);

        var len: usize = 0;
        while (len < 12 and name_buf[len] != 0) : (len += 1) {}
        const name = name_buf[0..len];

        // Determine Color
        var color: u8 = 15;
        if (common.endsWithIgnoreCase(name, ".nv")) {
            color = 10;
        } else if (common.endsWithIgnoreCase(name, ".bin") or common.endsWithIgnoreCase(name, ".o")) {
            color = 12;
        } else if (name.len > 0 and name[0] == '.') {
            color = 8;
        }

        common.vga.set_color(color, 0);
        common.printZ(name);
        common.vga.reset_color();

        const size = common.fs_size(id);
        common.printZ("  ");
        common.printNum(size);
        common.printZ(" bytes\r\n");
    }
}
