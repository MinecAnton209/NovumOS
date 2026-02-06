// touch command - create empty file
const common = @import("common.zig");

pub fn execute(name_ptr: [*]const u8, name_len: u8) void {
    const existing = common.fs_find(name_ptr, name_len);
    if (existing >= 0) {
        common.printZ("File already exists\r\n");
        return;
    }

    const id = common.fs_create(name_ptr, name_len);
    if (id < 0) {
        common.printZ("Cannot create file\r\n");
        return;
    }

    common.printZ("Created: ");
    var i: u8 = 0;
    while (i < name_len) : (i += 1) {
        common.print_char(name_ptr[i]);
    }
    common.printZ("\r\n");
}
