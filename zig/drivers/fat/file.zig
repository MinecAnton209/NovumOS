const common = @import("../../commands/common.zig");
const ata = @import("../ata.zig");
const dir = @import("dir.zig");

pub const getCurrentTimestamp = dir.getCurrentTimestamp;

pub const FileHandle = struct {
    drive: ata.Drive,
    bpb: BPB,
    dir_cluster: u32,
    name: []const u8,
    cluster: u32,
    offset: u32,
    size: u32,
};

pub fn fat_open(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8) ?FileHandle {
    const res = resolve_path(drive, bpb, dir_cluster, path) orelse return null;
    const entry = find_entry_literal(drive, bpb, res.dir_cluster, res.file_name) orelse return null;

    if ((entry.attr & 0x10) != 0) return null;

    return FileHandle{
        .drive = drive,
        .bpb = bpb,
        .dir_cluster = res.dir_cluster,
        .name = res.file_name,
        .cluster = @as(u32, entry.first_cluster_low) | (@as(u32, entry.first_cluster_high) << 16),
        .offset = 0,
        .size = entry.file_size,
    };
}

pub fn fat_size(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8) u32 {
    const res = resolve_path(drive, bpb, dir_cluster, path) orelse return 0;
    const entry = find_entry_literal(drive, bpb, res.dir_cluster, res.file_name) orelse return 0;
    return entry.file_size;
}

pub fn fat_getcwd() [*]u8 {
    return @ptrCast(&common.current_path);
}

pub fn fat_getcwd_len() usize {
    return common.current_path_len;
}

pub fn fat_lseek(handle: *FileHandle, offset: i64, whence: i32) i64 {
    var new_offset: i64 = 0;

    switch (whence) {
        0 => new_offset = offset,
        1 => new_offset = @as(i64, @intCast(handle.offset)) + offset,
        2 => new_offset = @as(i64, @intCast(handle.size)) + offset,
        else => return -1,
    }

    if (new_offset < 0) return -1;
    if (new_offset > handle.size) new_offset = handle.size;

    handle.offset = @intCast(new_offset);

    const cluster_offset = handle.offset / (@as(u32, handle.bpb.sectors_per_cluster) * 512);
    var current = handle.cluster;
    var i: u32 = 0;
    while (i < cluster_offset and current >= 2) {
        current = get_fat_entry(handle.drive, handle.bpb, current);
        i += 1;
    }
    handle.cluster = current;

    return new_offset;
}

pub fn fat_tell(handle: *FileHandle) u32 {
    return handle.offset;
}

pub fn fat_truncate(handle: *FileHandle, length: u32) i32 {
    if (length > handle.size) {
        return 0;
    }

    const bytes_per_cluster = @as(u32, handle.bpb.sectors_per_cluster) * 512;
    const old_clusters_needed = (handle.size + bytes_per_cluster - 1) / bytes_per_cluster;
    const new_clusters_needed = (length + bytes_per_cluster - 1) / bytes_per_cluster;

    if (new_clusters_needed < old_clusters_needed) {
        var current = handle.cluster;
        var i: u32 = 0;
        while (i < new_clusters_needed - 1 and current >= 2) {
            current = get_fat_entry(handle.drive, handle.bpb, current);
            i += 1;
        }

        if (current >= 2) {
            const next = get_fat_entry(handle.drive, handle.bpb, current);
            if (next >= 2) {
                _ = free_cluster_chain(handle.drive, handle.bpb, next);
                const eof_val: u32 = switch (handle.bpb.fat_type) {
                    .FAT12 => 0xFF8,
                    .FAT16 => 0xFFF8,
                    .FAT32 => 0x0FFFFFF8,
                    else => 0xFFF8,
                };
                set_fat_entry(handle.drive, handle.bpb, current, eof_val);
            }
        }
    }

    const entry_loc = find_entry_location_literal(handle.drive, handle.bpb, handle.dir_cluster, handle.name) orelse return -1;
    var sector_buf: [512]u8 = undefined;
    ata.read_sector(handle.drive, entry_loc.sector, &sector_buf);

    const timestamp = dir.getCurrentTimestamp();
    const i = entry_loc.offset;

    sector_buf[i + 28] = @intCast(length & 0xFF);
    sector_buf[i + 29] = @intCast((length >> 8) & 0xFF);
    sector_buf[i + 30] = @intCast((length >> 16) & 0xFF);
    sector_buf[i + 31] = @intCast((length >> 24) & 0xFF);
    sector_buf[i + 11] = sector_buf[i + 11] | 0x20;

    sector_buf[i + 22] = @intCast(timestamp.time & 0xFF);
    sector_buf[i + 23] = @intCast((timestamp.time >> 8) & 0xFF);
    sector_buf[i + 24] = @intCast(timestamp.date & 0xFF);
    sector_buf[i + 25] = @intCast((timestamp.date >> 8) & 0xFF);

    ata.write_sector(handle.drive, entry_loc.sector, &sector_buf);

    handle.size = length;
    if (handle.offset > length) {
        handle.offset = length;
    }

    return 0;
}

pub fn fat_sync(drive: ata.Drive, bpb: BPB) i32 {
    _ = drive;
    _ = bpb;
    return 0;
}

pub fn fat_expand(handle: *FileHandle, length: u32) i32 {
    if (length <= handle.size) {
        return 0;
    }

    const bytes_per_cluster = @as(u32, handle.bpb.sectors_per_cluster) * 512;
    const old_size = handle.size;
    const old_clusters_needed = (old_size + bytes_per_cluster - 1) / bytes_per_cluster;
    const new_clusters_needed = (length + bytes_per_cluster - 1) / bytes_per_cluster;

    if (new_clusters_needed > old_clusters_needed) {
        const clusters_to_add = new_clusters_needed - old_clusters_needed;
        var current = handle.cluster;

        var i: u32 = 0;
        while (i < old_clusters_needed - 1 and current >= 2) {
            current = get_fat_entry(handle.drive, handle.bpb, current);
            i += 1;
        }

        if (current >= 2) {
            var added: u32 = 0;
            while (added < clusters_to_add) {
                const new_cluster = find_free_cluster(handle.drive, handle.bpb) orelse return -1;
                set_fat_entry(handle.drive, handle.bpb, current, new_cluster);
                current = new_cluster;
                added += 1;
            }

            const eof_val: u32 = switch (handle.bpb.fat_type) {
                .FAT12 => 0xFF8,
                .FAT16 => 0xFFF8,
                .FAT32 => 0x0FFFFFF8,
                else => 0xFFF8,
            };
            set_fat_entry(handle.drive, handle.bpb, current, eof_val);
        }
    }

    const entry_loc = find_entry_location_literal(handle.drive, handle.bpb, handle.dir_cluster, handle.name) orelse return -1;
    var sector_buf: [512]u8 = undefined;
    ata.read_sector(handle.drive, entry_loc.sector, &sector_buf);

    const timestamp = dir.getCurrentTimestamp();
    const i = entry_loc.offset;

    sector_buf[i + 28] = @intCast(length & 0xFF);
    sector_buf[i + 29] = @intCast((length >> 8) & 0xFF);
    sector_buf[i + 30] = @intCast((length >> 16) & 0xFF);
    sector_buf[i + 31] = @intCast((length >> 24) & 0xFF);
    sector_buf[i + 11] = sector_buf[i + 11] | 0x20;

    sector_buf[i + 22] = @intCast(timestamp.time & 0xFF);
    sector_buf[i + 23] = @intCast((timestamp.time >> 8) & 0xFF);
    sector_buf[i + 24] = @intCast(timestamp.date & 0xFF);
    sector_buf[i + 25] = @intCast((timestamp.date >> 8) & 0xFF);

    ata.write_sector(handle.drive, entry_loc.sector, &sector_buf);

    handle.size = length;
    return 0;
}

pub fn fat_forward(handle: *FileHandle, count: u32) i32 {
    const new_offset = handle.offset + count;
    if (new_offset > handle.size) {
        return -1;
    }
    handle.offset = new_offset;

    const cluster_size = @as(u32, handle.bpb.sectors_per_cluster) * 512;
    const cluster_offset = handle.offset / cluster_size;
    var current = handle.cluster;
    var i: u32 = 0;
    while (i < cluster_offset and current >= 2) {
        current = get_fat_entry(handle.drive, handle.bpb, current);
        i += 1;
    }
    handle.cluster = current;

    return @intCast(new_offset);
}

pub fn fat_gets(handle: *FileHandle, buffer: [*]u8, max_len: u32) i32 {
    if (handle.offset >= handle.size) return -1;

    var bytes_read: u32 = 0;
    const cluster_size = @as(u32, handle.bpb.sectors_per_cluster) * 512;
    var sector_buf: [512]u8 = undefined;

    while (bytes_read < max_len and handle.offset < handle.size) {
        const sector_lba = handle.bpb.first_data_sector + (handle.cluster - 2) * @as(u32, handle.bpb.sectors_per_cluster);
        const offset_in_cluster = handle.offset % cluster_size;
        const sector_offset = offset_in_cluster / 512;

        const lba = sector_lba + sector_offset;
        ata.read_sector(handle.drive, @intCast(lba), &sector_buf);

        const remaining_in_sector = 512 - (offset_in_cluster % 512);
        const to_read = @min(remaining_in_sector, max_len - bytes_read);

        var j: u32 = 0;
        while (j < to_read and handle.offset < handle.size) {
            const ch = sector_buf[(offset_in_cluster % 512) + j];
            buffer[bytes_read] = ch;
            bytes_read += 1;
            handle.offset += 1;
            j += 1;
            if (ch == '\n') break;
        }

        if (j < to_read) break;

        const next_cluster = get_fat_entry(handle.drive, handle.bpb, handle.cluster);
        const eof_val: u32 = switch (handle.bpb.fat_type) {
            .FAT12 => 0xFF8,
            .FAT16 => 0xFFF8,
            .FAT32 => 0x0FFFFFF8,
            else => 0xFFF8,
        };
        if (next_cluster >= eof_val) break;
        handle.cluster = next_cluster;
    }

    if (bytes_read == 0 and handle.offset >= handle.size) return -1;
    return @intCast(bytes_read);
}

pub fn fat_puts(handle: *FileHandle, str: [*]const u8, len: u32) i32 {
    if (len == 0) return 0;

    const cluster_size = @as(u32, handle.bpb.sectors_per_cluster) * 512;
    var sector_buf: [512]u8 = undefined;
    var written: u32 = 0;

    while (written < len) {
        const sector_lba = handle.bpb.first_data_sector + (handle.cluster - 2) * @as(u32, handle.bpb.sectors_per_cluster);
        const offset_in_cluster = handle.offset % cluster_size;
        const sector_offset = offset_in_cluster / 512;
        const lba = sector_lba + sector_offset;

        const offset_in_sector = offset_in_cluster % 512;
        const to_write = @min(512 - offset_in_sector, len - written);

        if (offset_in_sector > 0) {
            ata.read_sector(handle.drive, @intCast(lba), &sector_buf);
        }

        @memcpy(sector_buf[offset_in_sector..offset_in_sector + to_write], str[written..written + to_write]);
        ata.write_sector(handle.drive, @intCast(lba), &sector_buf);

        written += to_write;
        handle.offset += to_write;

        if (handle.offset > handle.size) {
            handle.size = handle.offset;
        }

        const new_cluster_needed = (handle.offset + cluster_size - 1) / cluster_size;
        const current_cluster = (handle.size + cluster_size - 1) / cluster_size;

        if (new_cluster_needed > current_cluster) {
            const new_cluster = find_free_cluster(handle.drive, handle.bpb) orelse return -1;
            const eof_val: u32 = switch (handle.bpb.fat_type) {
                .FAT12 => 0xFF8,
                .FAT16 => 0xFFF8,
                .FAT32 => 0x0FFFFFF8,
                else => 0xFFF8,
            };
            set_fat_entry(handle.drive, handle.bpb, handle.cluster, new_cluster);
            set_fat_entry(handle.drive, handle.bpb, new_cluster, eof_val);
            handle.cluster = new_cluster;
        }
    }

    const entry_loc = find_entry_location_literal(handle.drive, handle.bpb, handle.dir_cluster, handle.name);
    if (entry_loc) |loc| {
        var sec_buf: [512]u8 = undefined;
        ata.read_sector(handle.drive, loc.sector, &sec_buf);
        const i = loc.offset;
        sec_buf[i + 28] = @intCast(handle.size & 0xFF);
        sec_buf[i + 29] = @intCast((handle.size >> 8) & 0xFF);
        sec_buf[i + 30] = @intCast((handle.size >> 16) & 0xFF);
        sec_buf[i + 31] = @intCast((handle.size >> 24) & 0xFF);
        sec_buf[i + 11] = sec_buf[i + 11] | 0x20;

        const ts = dir.getCurrentTimestamp();
        sec_buf[i + 22] = @intCast(ts.time & 0xFF);
        sec_buf[i + 23] = @intCast((ts.time >> 8) & 0xFF);
        sec_buf[i + 24] = @intCast(ts.date & 0xFF);
        sec_buf[i + 25] = @intCast((ts.date >> 8) & 0xFF);

        ata.write_sector(handle.drive, loc.sector, &sec_buf);
    }

    return @intCast(written);
}

pub fn fat_putc(handle: *FileHandle, c: u8) i32 {
    return fat_puts(handle, @ptrCast(&c), 1);
}

pub const BPB = dir.BPB;
pub const DirEntry = dir.DirEntry;
pub const resolve_path = dir.resolve_path;
pub const find_entry_literal = dir.find_entry_literal;
pub const find_entry_location_literal = dir.find_entry_location_literal;
pub const get_fat_entry = dir.get_fat_entry;
pub const set_fat_entry = dir.set_fat_entry;
pub const find_free_cluster = dir.find_free_cluster;
pub const free_cluster_chain = dir.free_cluster_chain;
pub const add_directory_entry = dir.add_directory_entry;

pub fn read_file(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8, output: [*]u8) i32 {
    if (resolve_path(drive, bpb, dir_cluster, path)) |res| {
        return read_file_literal(drive, bpb, res.dir_cluster, res.file_name, output);
    }
    return -1;
}

pub fn read_file_literal(drive: ata.Drive, bpb: BPB, dir_cluster: u32, name: []const u8, output: [*]u8) i32 {
    const entry = find_entry_literal(drive, bpb, dir_cluster, name) orelse return -1;

    var current_cluster = @as(u32, entry.first_cluster_low) | (@as(u32, entry.first_cluster_high) << 16);
    var bytes_read: u32 = 0;
    const total_size = entry.file_size;

    const eof_val = switch (bpb.fat_type) {
        .FAT12 => @as(u32, 0xFF8),
        .FAT16 => @as(u32, 0xFFF8),
        .FAT32 => @as(u32, 0x0FFFFFF8),
        else => @as(u32, 0xFFF8),
    };

    while (current_cluster < eof_val and bytes_read < total_size) {
        const lba = bpb.first_data_sector + (current_cluster - 2) * bpb.sectors_per_cluster;

        var s: u32 = 0;
        while (s < bpb.sectors_per_cluster and bytes_read < total_size) : (s += 1) {
            var sector_buf: [512]u8 = undefined;
            ata.read_sector(drive, lba + s, &sector_buf);

            const to_copy = @min(total_size - bytes_read, 512);
            for (0..to_copy) |j| output[bytes_read + j] = sector_buf[j];
            bytes_read += @intCast(to_copy);
        }

        current_cluster = get_fat_entry(drive, bpb, current_cluster);
        if (current_cluster == 0) break;
    }

    return @intCast(bytes_read);
}

pub fn stream_to_console(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8) bool {
    if (resolve_path(drive, bpb, dir_cluster, path)) |res| {
        return stream_to_console_literal(drive, bpb, res.dir_cluster, res.file_name);
    }
    return false;
}

pub fn stream_to_console_literal(drive: ata.Drive, bpb: BPB, dir_cluster: u32, name: []const u8) bool {
    const entry = find_entry_literal(drive, bpb, dir_cluster, name) orelse return false;

    var current_cluster = @as(u32, entry.first_cluster_low) | (@as(u32, entry.first_cluster_high) << 16);
    var bytes_processed: u32 = 0;
    const total_size = entry.file_size;
    const eof_val = switch (bpb.fat_type) {
        .FAT12 => @as(u32, 0xFF8),
        .FAT16 => @as(u32, 0xFFF8),
        .FAT32 => @as(u32, 0x0FFFFFF8),
        else => @as(u32, 0xFFF8),
    };

    while (current_cluster < eof_val and bytes_processed < total_size) {
        const lba = bpb.first_data_sector + (current_cluster - 2) * bpb.sectors_per_cluster;

        var s: u32 = 0;
        while (s < bpb.sectors_per_cluster and bytes_processed < total_size) : (s += 1) {
            var sector_buf: [512]u8 = undefined;
            ata.read_sector(drive, lba + s, &sector_buf);

            const to_print = @min(total_size - bytes_processed, 512);
            for (0..to_print) |j| common.print_char(sector_buf[j]);
            bytes_processed += @intCast(to_print);
        }

        current_cluster = get_fat_entry(drive, bpb, current_cluster);
        if (current_cluster == 0) break;
    }
    common.printZ("\n");
    return true;
}

pub fn write_file(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8, data: []const u8) bool {
    if (resolve_path(drive, bpb, dir_cluster, path)) |res| {
        return write_file_literal(drive, bpb, res.dir_cluster, res.file_name, data);
    }
    return false;
}

pub fn append_to_file(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8, data: []const u8) bool {
    if (resolve_path(drive, bpb, dir_cluster, path)) |res| {
        return append_to_file_literal(drive, bpb, res.dir_cluster, res.file_name, data);
    } else {
        return write_file(drive, bpb, dir_cluster, path, data);
    }
}

fn get_last_cluster(drive: ata.Drive, bpb: BPB, start_cluster: u32) u32 {
    var current = start_cluster;
    if (current == 0) return 0;
    const eof_limit = if (bpb.fat_type == .FAT12) @as(u32, 0xFF8) else @as(u32, 0xFFF8);
    while (true) {
        const next = get_fat_entry(drive, bpb, current);
        if (next < 2 or next >= eof_limit) return current;
        current = next;
    }
}

fn append_to_file_literal(drive: ata.Drive, bpb: BPB, dir_cluster: u32, name: []const u8, data: []const u8) bool {
    const entry = find_entry_literal(drive, bpb, dir_cluster, name) orelse return write_file_literal(drive, bpb, dir_cluster, name, data);

    if ((entry.attr & 0x04) != 0) return false;

    if (data.len == 0) return true;

    const start_cluster = entry.first_cluster_low | (@as(u32, entry.first_cluster_high) << 16);
    const old_size = entry.file_size;
    const bytes_per_cluster = @as(u32, bpb.sectors_per_cluster) * 512;

    var current_cluster = get_last_cluster(drive, bpb, start_cluster);
    var bytes_written: u32 = 0;
    var offset_in_cluster = old_size % bytes_per_cluster;
    const eof_val = if (bpb.fat_type == .FAT12) @as(u32, 0xFFF) else @as(u32, 0xFFFF);

    if (old_size > 0 and offset_in_cluster == 0) {
        const next = find_free_cluster(drive, bpb) orelse return false;
        set_fat_entry(drive, bpb, current_cluster, next);
        set_fat_entry(drive, bpb, next, eof_val);
        current_cluster = next;
        offset_in_cluster = 0;
    }

    while (bytes_written < data.len) {
        const lba = bpb.first_data_sector + (current_cluster - 2) * bpb.sectors_per_cluster;

        var sector_in_cluster = @as(u32, @intCast(offset_in_cluster / 512));
        var offset_in_sector = @as(u32, @intCast(offset_in_cluster % 512));

        while (sector_in_cluster < bpb.sectors_per_cluster and bytes_written < data.len) {
            var sector_buf: [512]u8 = [_]u8{0} ** 512;
            const to_copy = @min(data.len - bytes_written, 512 - offset_in_sector);

            if (offset_in_sector > 0 or (old_size > 0 and bytes_written == 0)) {
                ata.read_sector(drive, lba + sector_in_cluster, &sector_buf);
            }

            for (0..to_copy) |j| {
                sector_buf[offset_in_sector + j] = data[bytes_written + j];
            }
            ata.write_sector(drive, lba + sector_in_cluster, &sector_buf);

            bytes_written += @intCast(to_copy);
            offset_in_sector = 0;
            sector_in_cluster += 1;
        }

        if (bytes_written < data.len) {
            const next = find_free_cluster(drive, bpb) orelse return false;
            set_fat_entry(drive, bpb, current_cluster, next);
            set_fat_entry(drive, bpb, next, eof_val);
            current_cluster = next;
            offset_in_cluster = 0;
        }
    }

    const total_size: u32 = old_size + @as(u32, @intCast(data.len));
    return update_entry_size_literal(drive, bpb, dir_cluster, name, total_size);
}

fn write_file_literal(drive: ata.Drive, bpb: BPB, dir_cluster: u32, name: []const u8, data: []const u8) bool {
    var cluster: u32 = 0;
    var entry_attr: u8 = 0x20;
    const exists = find_entry_literal(drive, bpb, dir_cluster, name);

    if (exists) |entry| {
        if ((entry.attr & 0x04) != 0) {
            return false;
        }
        entry_attr = entry.attr | 0x20;
    } else {
        cluster = find_free_cluster(drive, bpb) orelse return false;
        const eof_val: u32 = switch (bpb.fat_type) {
            .FAT12 => 0xFFF,
            .FAT16 => 0xFFFF,
            .FAT32 => 0x0FFFFFFF,
            else => 0xFFFF,
        };
        set_fat_entry(drive, bpb, cluster, eof_val);
        const data_len: u32 = @intCast(data.len);
        if (!add_directory_entry(drive, bpb, dir_cluster, name, cluster, data_len, entry_attr)) return false;
    }

    var bytes_written: u32 = 0;
    var current_cluster = cluster;
    const eof_val: u32 = if (bpb.fat_type == .FAT12) 0xFFF else 0xFFFF;

    while (bytes_written < data.len) {
        const lba = bpb.first_data_sector + (current_cluster - 2) * bpb.sectors_per_cluster;

        var s: u32 = 0;
        while (s < bpb.sectors_per_cluster and bytes_written < data.len) : (s += 1) {
            var sector_buf: [512]u8 = [_]u8{0} ** 512;
            const to_copy = @min(data.len - bytes_written, 512);
            for (0..to_copy) |j| sector_buf[j] = data[bytes_written + j];
            ata.write_sector(drive, lba + s, &sector_buf);
            bytes_written += @intCast(to_copy);
        }

        if (bytes_written < data.len) {
            var next = get_fat_entry(drive, bpb, current_cluster);
            if (next >= (if (bpb.fat_type == .FAT12) @as(u32, 0xFF8) else @as(u32, 0xFFF8))) {
                next = find_free_cluster(drive, bpb) orelse return false;
                set_fat_entry(drive, bpb, current_cluster, next);
                set_fat_entry(drive, bpb, next, eof_val);
            }
            current_cluster = next;
        } else {
            const next = get_fat_entry(drive, bpb, current_cluster);
            const eof_limit = switch (bpb.fat_type) {
                .FAT12 => @as(u32, 0xFF8),
                .FAT16 => @as(u32, 0xFFF8),
                .FAT32 => @as(u32, 0x0FFFFFF8),
                else => @as(u32, 0xFFF8),
            };
            if (next >= 2 and next < eof_limit) {
                free_cluster_chain(drive, bpb, next);
                set_fat_entry(drive, bpb, current_cluster, eof_val);
            }
        }
    }

    const final_size: u32 = @intCast(data.len);
    return update_entry_size_literal(drive, bpb, dir_cluster, name, final_size);
}

fn update_entry_size_literal(drive: ata.Drive, bpb: BPB, dir_cluster: u32, name: []const u8, size: u32) bool {
    const loc = find_entry_location_literal(drive, bpb, dir_cluster, name) orelse return false;
    var buffer: [512]u8 = undefined;
    ata.read_sector(drive, loc.sector, &buffer);

    const ts = getCurrentTimestamp();

    const i = loc.offset;
    buffer[i + 28] = @intCast(size & 0xFF);
    buffer[i + 29] = @intCast((size >> 8) & 0xFF);
    buffer[i + 30] = @intCast((size >> 16) & 0xFF);
    buffer[i + 31] = @intCast((size >> 24) & 0xFF);
    buffer[i + 11] = buffer[i + 11] | 0x20;

    buffer[i + 22] = @intCast(ts.time & 0xFF);
    buffer[i + 23] = @intCast((ts.time >> 8) & 0xFF);
    buffer[i + 24] = @intCast(ts.date & 0xFF);
    buffer[i + 25] = @intCast((ts.date >> 8) & 0xFF);

    ata.write_sector(drive, loc.sector, &buffer);
    return true;
}