// NovumOS Zig Kernel Extension
// Provides: SimpleFS (RAM-based file system) + FAT support

pub const MAX_FILES = 16;
pub const MAX_FILENAME = 12;
pub const MAX_FILESIZE = 1024;

pub const FileEntry = struct {
    name: [MAX_FILENAME]u8,
    data: [MAX_FILESIZE]u8,
    size: u16,
    used: bool,
};

pub var files: [MAX_FILES]FileEntry = undefined;
var fs_initialized: bool = false;

fn zeroMem(ptr: [*]u8, len: usize) void {
    for (0..len) |i| {
        ptr[i] = 0;
    }
}

pub export fn fs_init() void {
    for (&files) |*file| {
        file.used = false;
        file.size = 0;
        zeroMem(&file.name, MAX_FILENAME);
        zeroMem(&file.data, MAX_FILESIZE);
    }
    fs_initialized = true;
}

pub export fn fs_create(name_ptr: [*]const u8, name_len: u8) i32 {
    if (!fs_initialized) return -1;

    for (&files, 0..) |*file, i| {
        if (!file.used) {
            file.used = true;
            file.size = 0;
            zeroMem(&file.name, MAX_FILENAME);

            const len = @min(name_len, MAX_FILENAME);
            for (0..len) |j| {
                file.name[j] = name_ptr[j];
            }
            return @intCast(i);
        }
    }
    return -1;
}

pub export fn fs_write(file_id: u8, data_ptr: [*]const u8, data_len: u16) i32 {
    if (file_id >= MAX_FILES) return -1;
    if (!files[file_id].used) return -1;

    const len = @min(data_len, MAX_FILESIZE);
    for (0..len) |i| {
        files[file_id].data[i] = data_ptr[i];
    }
    files[file_id].size = len;
    return @intCast(len);
}

pub export fn fs_read(file_id: u8, buffer_ptr: [*]u8, max_len: u16) i32 {
    if (file_id >= MAX_FILES) return -1;
    if (!files[file_id].used) return -1;

    const len = @min(files[file_id].size, max_len);
    for (0..len) |i| {
        buffer_ptr[i] = files[file_id].data[i];
    }
    return @intCast(len);
}

pub export fn fs_size(file_id: u8) i32 {
    if (file_id >= MAX_FILES) return -1;
    if (!files[file_id].used) return -1;
    return files[file_id].size;
}

pub export fn fs_delete(file_id: u8) i32 {
    if (file_id >= MAX_FILES) return -1;
    if (!files[file_id].used) return -1;

    files[file_id].used = false;
    files[file_id].size = 0;
    return 0;
}

pub export fn fs_find(name_ptr: [*]const u8, name_len: u8) i32 {
    if (!fs_initialized) return -1;

    for (&files, 0..) |*file, i| {
        if (file.used) {
            var match = true;
            const len = @min(name_len, MAX_FILENAME);
            for (0..len) |j| {
                if (file.name[j] != name_ptr[j]) {
                    match = false;
                    break;
                }
            }
            if (match and (len == MAX_FILENAME or file.name[len] == 0)) {
                return @intCast(i);
            }
        }
    }
    return -1;
}

pub export fn fs_list(buffer: [*]u8) u8 {
    var count: u8 = 0;
    for (&files, 0..) |*file, i| {
        if (file.used) {
            buffer[count] = @intCast(i);
            count += 1;
        }
    }
    return count;
}

pub export fn fs_getname(file_id: u8, buffer: [*]u8) i32 {
    if (file_id >= MAX_FILES) return -1;
    if (!files[file_id].used) return -1;

    for (0..MAX_FILENAME) |i| {
        buffer[i] = files[file_id].name[i];
    }
    return MAX_FILENAME;
}
