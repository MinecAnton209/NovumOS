// rm command - delete file
const common = @import("common.zig");

pub fn execute(name_ptr: [*]const u8, name_len: u8) void {
    const id = common.fs_find(name_ptr, name_len);
    if (id < 0) {
        common.printZ("File not found\r\n");
        return;
    }

    _ = common.fs_delete(@intCast(id));
    common.printZ("Deleted: ");
    var i: u8 = 0;
    while (i < name_len) : (i += 1) {
        common.print_char(name_ptr[i]);
    }
    common.printZ("\r\n");
}
