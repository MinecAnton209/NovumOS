const common = @import("../../commands/common.zig");
const ata = @import("../ata.zig");
const vga = @import("../vga.zig");
const bpb_mod = @import("bpb.zig");
const rtc = @import("../time/time.zig");

pub fn getCurrentTimestamp() struct { time: u16, date: u16 } {
    const dt = rtc.get_datetime();

    const hour16: u16 = dt.hour;
    const minute16: u16 = dt.minute;
    const second16: u16 = dt.second / 2;

    const time: u16 = (hour16 << 11) | (minute16 << 5) | second16;

    const year: u16 = @intCast((dt.year - 1980) & 0x7F);
    const month16: u16 = dt.month;
    const day16: u16 = dt.day;

    const date: u16 = (year << 9) | (month16 << 5) | day16;

    return .{ .time = time, .date = date };
}

fn printSize(size: u32) void {
    if (size == 0) {
        common.printZ("0 B");
        return;
    }
    const kb: u32 = 1024;
    const mb: u32 = kb * 1024;
    const gb: u32 = mb * 1024;

    if (size >= gb) {
        common.printNum(@intCast(size / gb));
        common.printZ(".");
        common.printNum(@intCast((size % gb) / (mb / 10)));
        common.printZ("G");
    } else if (size >= mb) {
        common.printNum(@intCast(size / mb));
        common.printZ(".");
        common.printNum(@intCast((size % mb) / (kb / 10)));
        common.printZ("M");
    } else if (size >= kb) {
        common.printNum(@intCast(size / kb));
        common.printZ(".");
        common.printNum(@intCast((size % kb) / 10));
        common.printZ("K");
    } else {
        common.printNum(@intCast(size));
        common.printZ("B");
    }
}

fn printSizePad(size: u32) void {
    if (size == 0) {
        common.printZ("   0B ");
        return;
    }
    const kb: u32 = 1024;
    const mb: u32 = kb * 1024;
    const gb: u32 = mb * 1024;

    if (size >= gb) {
        common.printNum(@intCast(size / gb));
        common.printZ(".");
        common.printNum(@intCast((size % gb) / (mb / 10)));
        common.printZ("G ");
    } else if (size >= mb) {
        common.printNum(@intCast(size / mb));
        common.printZ(".");
        common.printNum(@intCast((size % mb) / (kb / 10)));
        common.printZ("M ");
    } else if (size >= kb) {
        common.printNum(@intCast(size / kb));
        common.printZ(".");
        common.printNum(@intCast((size % kb) / 10));
        common.printZ("K ");
    } else {
        common.printNum(@intCast(size));
        common.printZ("B ");
    }
}

fn printSizeNice(size: u32) void {
    if (size == 0) {
        common.printZ("0B ");
        return;
    }
    const kb: u32 = 1024;
    const mb: u32 = kb * 1024;
    const gb: u32 = mb * 1024;

    if (size >= gb) {
        const gb_val = size / gb;
        const mb_val = (size % gb) / mb;
        if (mb_val > 0) {
            common.printNum(@intCast(gb_val));
            common.print_char('.');
            common.printNum(@intCast(mb_val));
            common.printZ("G");
        } else {
            common.printNum(@intCast(gb_val));
            common.printZ("G");
        }
    } else if (size >= mb) {
        const mb_val = size / mb;
        const kb_val = (size % mb) / kb;
        if (kb_val > 0) {
            common.printNum(@intCast(mb_val));
            common.print_char('.');
            common.printNum(@intCast(kb_val));
            common.printZ("M");
        } else {
            common.printNum(@intCast(mb_val));
            common.printZ("M");
        }
    } else if (size >= kb) {
        const kb_val = size / kb;
        common.printNum(@intCast(kb_val));
        common.printZ("K");
    } else {
        common.printNum(@intCast(size));
        common.printZ("B");
    }
}

fn printIntToBuf(n: u32, out: []u8) usize {
    var i: usize = 0;
    if (n == 0) {
        out[0] = '0';
        return 1;
    }
    var temp = n;
    var digits: [10]u8 = undefined;
    var digit_count: usize = 0;
    while (temp > 0) {
        digits[digit_count] = @intCast((temp % 10) + '0');
        digit_count += 1;
        temp /= 10;
    }
    var j: usize = digit_count;
    while (j > 0) {
        j -= 1;
        out[i] = digits[j];
        i += 1;
    }
    return i;
}

pub const BPB = bpb_mod.BPB;
pub const DirEntry = bpb_mod.DirEntry;
pub const LfnState = bpb_mod.LfnState;
pub const extract_lfn_part = bpb_mod.extract_lfn_part;

const cache = @import("cache.zig");
pub const fat_read_cached_sector = cache.fat_read_cached_sector;

pub const EntryLocation = struct {
    sector: u32,
    offset: u32,
};

pub const FatName = struct {
    name: []const u8,
    ext: []const u8,
};

pub const PathResolution = struct {
    dir_cluster: u32,
    file_name: []const u8,
};

pub const ResolvedPath = struct {
    cluster: u32,
    is_dir: bool,
    path: [256]u8,
    path_len: usize,
};

pub fn get_fat_entry(drive: ata.Drive, bpb: BPB, cluster: u32) u32 {
    if (bpb.fat_type == .FAT12) {
        const fat_offset = cluster + (cluster / 2);
        const sector = bpb.first_fat_sector + (fat_offset / 512);
        const ent_offset = fat_offset % 512;

        const buf1 = fat_read_cached_sector(drive, sector);
        const buf2 = fat_read_cached_sector(drive, sector + 1);

        const val = @as(u16, buf1[ent_offset]) | (@as(u16, buf2[ent_offset + 1]) << 8);
        return if (cluster % 2 == 1) val >> 4 else val & 0xFFF;
    } else if (bpb.fat_type == .FAT16) {
        const fat_offset = cluster * 2;
        const sector = bpb.first_fat_sector + (fat_offset / 512);
        const ent_offset = fat_offset % 512;

        const buf = fat_read_cached_sector(drive, sector);
        return @as(u16, buf[ent_offset]) | (@as(u16, buf[ent_offset + 1]) << 8);
    } else {
        const fat_offset = cluster * 4;
        const sector = bpb.first_fat_sector + (fat_offset / 512);
        const ent_offset = fat_offset % 512;

        const buf = fat_read_cached_sector(drive, sector);
        const val = @as(u32, buf[ent_offset]) | (@as(u32, buf[ent_offset + 1]) << 8) | (@as(u32, buf[ent_offset + 2]) << 16) | (@as(u32, buf[ent_offset + 3]) << 24);
        return val & 0x0FFFFFFF;
    }
}

pub fn set_fat_entry(drive: ata.Drive, bpb: BPB, cluster: u32, value: u32) void {
    if (bpb.fat_type == .FAT12) {
        const fat_offset = cluster + (cluster / 2);
        const sector = bpb.first_fat_sector + (fat_offset / 512);
        const ent_offset = fat_offset % 512;

        const buf1 = fat_read_cached_sector(drive, sector);
        const buf2 = fat_read_cached_sector(drive, sector + 1);

        var val = @as(u16, buf1[ent_offset]) | (@as(u16, buf2[ent_offset + 1]) << 8);
        if (cluster % 2 == 1) {
            val = (val & 0x000F) | (@as(u16, @intCast(value)) << 4);
        } else {
            val = (val & 0xF000) | (@as(u16, @intCast(value)) & 0x0FFF);
        }

        buf1[ent_offset] = @intCast(val & 0xFF);
        buf2[ent_offset + 1] = @intCast(val >> 8);

        ata.write_sector(drive, sector, buf1);
        ata.write_sector(drive, sector + 1, buf2);
    } else if (bpb.fat_type == .FAT16) {
        const fat_offset = cluster * 2;
        const sector = bpb.first_fat_sector + (fat_offset / 512);
        const ent_offset = fat_offset % 512;

        const buf = fat_read_cached_sector(drive, sector);
        buf[ent_offset] = @intCast(value & 0xFF);
        buf[ent_offset + 1] = @intCast(value >> 8);
        ata.write_sector(drive, sector, buf);
    } else {
        const fat_offset = cluster * 4;
        const sector = bpb.first_fat_sector + (fat_offset / 512);
        const ent_offset = fat_offset % 512;

        const buf = fat_read_cached_sector(drive, sector);
        const old_val = @as(u32, buf[ent_offset]) | (@as(u32, buf[ent_offset + 1]) << 8) | (@as(u32, buf[ent_offset + 2]) << 16) | (@as(u32, buf[ent_offset + 3]) << 24);
        const new_val = (old_val & 0xF0000000) | (value & 0x0FFFFFFF);
        buf[ent_offset] = @intCast(new_val & 0xFF);
        buf[ent_offset + 1] = @intCast((new_val >> 8) & 0xFF);
        buf[ent_offset + 2] = @intCast((new_val >> 16) & 0xFF);
        buf[ent_offset + 3] = @intCast((new_val >> 24) & 0xFF);
        ata.write_sector(drive, sector, buf);
    }
}

fn toUpper(c: u8) u8 {
    if (c >= 'a' and c <= 'z') return c - 'a' + 'A';
    return c;
}

pub fn get_name_from_raw(entry: []const u8) struct { buf: [13]u8, len: usize } {
    var res: [13]u8 = [_]u8{0} ** 13;
    var n_len: usize = 0;
    const case_bits = entry[12];
    const name_lower = (case_bits & 0x08) != 0;
    const ext_lower = (case_bits & 0x10) != 0;
    for (0..8) |k| {
        const c = entry[k];
        if (c == ' ') break;
        res[n_len] = if (name_lower and c >= 'A' and c <= 'Z') c + 32 else c;
        n_len += 1;
    }
    if (entry[8] != ' ' and entry[8] != 0) {
        res[n_len] = '.';
        n_len += 1;
        for (0..3) |k| {
            const c = entry[8 + k];
            if (c == ' ' or c == 0) break;
            res[n_len] = if (ext_lower and c >= 'A' and c <= 'Z') c + 32 else c;
            n_len += 1;
        }
    }
    return .{ .buf = res, .len = n_len };
}

fn printLsHeader() void {
    common.printZ(" ATTRIB  SIZE     DATE       TIME   NAME\n");
    vga.set_color(8, 0);
    common.printZ(" ");
    for (0..56) |_| common.print_char('-');
    common.printZ("\n");
    vga.reset_color();
}

pub fn list_directory(drive: ata.Drive, bpb: BPB, dir_cluster: u32, show_hidden: bool) void {
    printLsHeader();

    var lfn: LfnState = .{ .buf = [_]u8{0} ** 256, .active = false, .checksum = 0 };

    if (dir_cluster == 0) {
        if (bpb.fat_type == .FAT32) {
            var current = bpb.root_cluster;
            const eof_val: u32 = 0x0FFFFFF8;
            while (current < eof_val) {
                const lba = bpb.first_data_sector + (current - 2) * bpb.sectors_per_cluster;
                var s: u32 = 0;
                while (s < bpb.sectors_per_cluster) : (s += 1) {
                    if (!list_sector(drive, lba + s, show_hidden, &lfn)) break;
                }
                current = get_fat_entry(drive, bpb, current);
                if (current < 2 or current >= eof_val) break;
            }
            return;
        }

        var sector = bpb.first_root_dir_sector;
        while (sector < bpb.first_data_sector) : (sector += 1) {
            if (!list_sector(drive, sector, show_hidden, &lfn)) break;
        }
    } else {
        var current = dir_cluster;
        const eof_val = switch (bpb.fat_type) {
            .FAT12 => @as(u32, 0xFF8),
            .FAT16 => @as(u32, 0xFFF8),
            .FAT32 => @as(u32, 0x0FFFFFF8),
            else => @as(u32, 0xFFF8),
        };
        while (current < eof_val) {
            const lba = bpb.first_data_sector + (current - 2) * bpb.sectors_per_cluster;
            var s: u32 = 0;
            while (s < bpb.sectors_per_cluster) : (s += 1) {
                if (!list_sector(drive, lba + s, show_hidden, &lfn)) break;
            }
            current = get_fat_entry(drive, bpb, current);
            if (current < 2 or current >= eof_val) break;
        }
    }
}

fn list_sector(drive: ata.Drive, sector: u32, show_hidden: bool, lfn: *LfnState) bool {
    var buffer: [512]u8 = undefined;
    ata.read_sector(drive, sector, &buffer);
    var i: u32 = 0;
    while (i < 512) : (i += 32) {
        if (buffer[i] == 0) {
            lfn.active = false;
            return false;
        }
        if (buffer[i] == 0xE5) {
            lfn.active = false;
            continue;
        }

        if (buffer[i + 11] == 0x0F) {
            const seq = buffer[i];
            const chk = buffer[i + 13];

            if ((seq & 0x40) != 0) {
                lfn.active = true;
                lfn.checksum = chk;
                @memset(&lfn.buf, 0);
            } else if (!lfn.active or lfn.checksum != chk) {
                lfn.active = false;
                continue;
            }

            var index = (seq & 0x1F);
            if (index < 1) index = 1;
            const offset = (index - 1) * 13;

            if (offset < 240) {
                extract_lfn_part(&buffer, i + 1, 5, &lfn.buf, offset);
                extract_lfn_part(&buffer, i + 14, 6, &lfn.buf, offset + 5);
                extract_lfn_part(&buffer, i + 28, 2, &lfn.buf, offset + 11);
            }
            continue;
        }

        const attr = buffer[i + 11];

        var sum: u8 = 0;
        for (0..11) |k| {
            const is_odd = (sum & 1) != 0;
            sum = (sum >> 1) + (if (is_odd) @as(u8, 0x80) else 0);
            sum = sum +% buffer[i + k];
        }

        var use_lfn = false;
        if (lfn.active and lfn.checksum == sum) {
            use_lfn = true;
        }
        lfn.active = false;

        if (!show_hidden) {
            if ((attr & 0x02) != 0) continue;
            if (use_lfn) {
                if (lfn.buf[0] == '.') continue;
            } else {
                if (buffer[i] == '.') continue;
            }
        }

        const is_dir = (attr & 0x10) != 0;

        var name_buf: [256]u8 = [_]u8{0} ** 256;
        var name_len: usize = 0;

        if (use_lfn) {
            while (name_len < 256 and lfn.buf[name_len] != 0) : (name_len += 1) {
                name_buf[name_len] = lfn.buf[name_len];
            }
        } else {
            const case_bits = buffer[i + 12];
            const name_lower = (case_bits & 0x08) != 0;
            const ext_lower = (case_bits & 0x10) != 0;

            for (0..8) |j| {
                const c = buffer[i + j];
                if (c == ' ') break;
                name_buf[name_len] = if (name_lower and c >= 'A' and c <= 'Z') c + 32 else c;
                name_len += 1;
            }
            if (buffer[i + 8] != ' ' and buffer[i + 8] != 0) {
                name_buf[name_len] = '.';
                name_len += 1;
                for (0..3) |j| {
                    const c = buffer[i + 8 + j];
                    if (c == ' ' or c == 0) break;
                    name_buf[name_len] = if (ext_lower and c >= 'A' and c <= 'Z') c + 32 else c;
                    name_len += 1;
                }
            }
        }

        const full_name = name_buf[0..name_len];

        const file_attr = buffer[i + 11];
        const is_readonly = (file_attr & 0x01) != 0;
        const is_hidden = (file_attr & 0x02) != 0;
        const is_system = (file_attr & 0x04) != 0;
        const is_archive = (file_attr & 0x20) != 0;

        const write_date = @as(u16, buffer[i + 24]) | (@as(u16, buffer[i + 25]) << 8);
        const write_time = @as(u16, buffer[i + 22]) | (@as(u16, buffer[i + 23]) << 8);

        const day = (write_date >> 0) & 0x1F;
        const month = (write_date >> 5) & 0x0F;
        const year = ((write_date >> 9) & 0x7F) + 1980;
        const hour = (write_time >> 11) & 0x1F;
        const minute = (write_time >> 5) & 0x3F;
        const second = (write_time & 0x1F) * 2;

        vga.set_color(15, 0);

        common.print_char(if (is_dir) 'D' else '-');
        common.print_char(if (is_readonly) 'R' else '.');
        common.print_char(if (is_hidden) 'H' else '.');
        common.print_char(if (is_system) 'S' else '.');
        common.print_char(if (is_archive) 'A' else '.');

        common.printZ(" ");

        if (is_dir) {
            vga.set_color(11, 0);
            common.printZ("<DIR>");
        } else {
            const size = @as(u32, buffer[i + 28]) | (@as(u32, buffer[i + 29]) << 8) | (@as(u32, buffer[i + 30]) << 16) | (@as(u32, buffer[i + 31]) << 24);
            vga.set_color(15, 0);
            printSizeNice(size);
        }

        common.printZ(" ");

        common.printNum(@intCast(year));
        common.print_char('-');
        if (month < 10) common.print_char('0');
        common.printNum(@intCast(month));
        common.print_char('-');
        if (day < 10) common.print_char('0');
        common.printNum(@intCast(day));

        common.printZ(" ");

        if (hour < 10) common.print_char('0');
        common.printNum(@intCast(hour));
        common.print_char(':');
        if (minute < 10) common.print_char('0');
        common.printNum(@intCast(minute));
        common.print_char(':');
        if (second < 10) common.print_char('0');
        common.printNum(@intCast(second));

        common.printZ("  ");

        if (is_dir) {
            vga.set_color(11, 0);
        } else {
            vga.set_color(14, 0);
        }
        common.printZ(full_name);
        if (is_dir) common.print_char('/');
        vga.reset_color();

        common.printZ("\n");
    }
    return true;
}

pub fn resolve_full_path(drive: ata.Drive, bpb: BPB, start_cluster: u32, start_path: []const u8, input_path: []const u8) ?ResolvedPath {
    var res: ResolvedPath = undefined;
    res.cluster = start_cluster;
    res.is_dir = true;
    res.path_len = 0;

    var input = input_path;
    if (input.len > 0 and (input[0] == '/' or input[0] == '\\')) {
        res.cluster = 0;
        input = input[1..];
    } else {
        for (start_path, 0..) |c, i| {
            if (i >= 256) break;
            res.path[i] = c;
        }
        res.path_len = @min(start_path.len, 256);
    }

    var i: usize = 0;
    while (i < input.len) {
        while (i < input.len and (input[i] == '/' or input[i] == '\\')) : (i += 1) {}
        if (i >= input.len) break;

        const start = i;
        while (i < input.len and input[i] != '/' and input[i] != '\\') : (i += 1) {}
        const component = input[start..i];

        if (common.std_mem_eql(component, ".")) {
            continue;
        } else if (common.std_mem_eql(component, "..")) {
            if (res.cluster != 0) {
                const entry = find_entry_literal(drive, bpb, res.cluster, "..") orelse return null;
                res.cluster = entry.first_cluster_low;
                if (res.path_len > 0) {
                    var p = res.path_len - 1;
                    while (p > 0 and res.path[p] != '/') : (p -= 1) {}
                    res.path_len = p;
                }
            }
        } else {
            if (!res.is_dir) return null;

            const entry = find_entry_literal(drive, bpb, res.cluster, component) orelse return null;
            res.cluster = entry.first_cluster_low;
            res.is_dir = (entry.attr & 0x10) != 0;

            if (res.path_len + 1 + component.len < 256) {
                res.path[res.path_len] = '/';
                res.path_len += 1;
                for (component, 0..) |c, k| {
                    res.path[res.path_len + k] = c;
                }
                res.path_len += component.len;
            } else {
                return null;
            }
        }
    }

    return res;
}

pub fn resolve_path(drive: ata.Drive, bpb: BPB, start_dir: u32, path: []const u8) ?PathResolution {
    if (path.len == 0) return null;

    var current_dir = start_dir;
    var remainder = path;

    if (path[0] == '/' or path[0] == '\\') {
        current_dir = 0;
        remainder = path[1..];
    }

    while (true) {
        var i: usize = 0;
        while (i < remainder.len and remainder[i] != '/' and remainder[i] != '\\') : (i += 1) {}

        const component = remainder[0..i];

        if (i == remainder.len) {
            if (component.len == 0) {
                return PathResolution{ .dir_cluster = current_dir, .file_name = "." };
            }
            return PathResolution{ .dir_cluster = current_dir, .file_name = component };
        }

        if (component.len > 0) {
            if (common.std_mem_eql(component, ".")) {
            } else if (common.std_mem_eql(component, "..")) {
                if (current_dir != 0) {
                    const entry = find_entry_literal(drive, bpb, current_dir, "..") orelse return null;
                    current_dir = entry.first_cluster_low;
                }
            } else {
                const entry = find_entry_literal(drive, bpb, current_dir, component) orelse return null;
                if ((entry.attr & 0x10) == 0) return null;
                current_dir = entry.first_cluster_low;
            }
        }

        remainder = remainder[i + 1 ..];
        if (remainder.len == 0) return PathResolution{ .dir_cluster = current_dir, .file_name = "." };
    }
}

fn fat_parse_name(name: []const u8) FatName {
    if (common.std_mem_eql(name, ".")) return FatName{ .name = ".", .ext = "" };
    if (common.std_mem_eql(name, "..")) return FatName{ .name = "..", .ext = "" };

    var last_dot: ?usize = null;
    var i: usize = 0;
    while (i < name.len) : (i += 1) {
        if (name[i] == '/' or name[i] == '\\') break;
        if (name[i] == '.') last_dot = i;
    }

    if (last_dot) |dot| {
        if (dot == 0) {
            return FatName{ .name = name[0..i], .ext = "" };
        }

        return FatName{ .name = name[0..dot], .ext = name[dot + 1 ..i] };
    }

    return FatName{ .name = name[0..i], .ext = "" };
}

fn find_entry_in_sectors(drive: ata.Drive, name: []const u8, start_sector: u32, end_sector: u32) ?EntryLocation {
    var buffer: [512]u8 = undefined;
    const parts = fat_parse_name(name);
    const sn_name = parts.name;
    const sn_ext = parts.ext;

    var lfn: LfnState = .{ .buf = [_]u8{0} ** 256, .active = false, .checksum = 0 };

    var sector = start_sector;
    while (sector < end_sector) : (sector += 1) {
        ata.read_sector(drive, sector, &buffer);
        var i: u32 = 0;
        while (i < 512) : (i += 32) {
            if (buffer[i] == 0) return null;
            if (buffer[i] == 0xE5) {
                lfn.active = false;
                continue;
            }

            if (buffer[i + 11] == 0x0F) {
                const seq = buffer[i];
                const chk = buffer[i + 13];

                if ((seq & 0x40) != 0) {
                    lfn.active = true;
                    lfn.checksum = chk;
                    @memset(&lfn.buf, 0);
                } else if (!lfn.active or lfn.checksum != chk) {
                    lfn.active = false;
                    continue;
                }

                var index = (seq & 0x1F);
                if (index < 1) index = 1;
                const offset = (index - 1) * 13;

                if (offset < 240) {
                    extract_lfn_part(&buffer, i + 1, 5, &lfn.buf, offset);
                    extract_lfn_part(&buffer, i + 14, 6, &lfn.buf, offset + 5);
                    extract_lfn_part(&buffer, i + 28, 2, &lfn.buf, offset + 11);
                }
                continue;
            }

            var sum: u8 = 0;
            for (0..11) |k| {
                const is_odd = (sum & 1) != 0;
                sum = (sum >> 1) + (if (is_odd) @as(u8, 0x80) else 0);
                sum = sum +% buffer[i + k];
            }

            if (lfn.active and lfn.checksum == sum) {
                var len: usize = 0;
                while (len < 256 and lfn.buf[len] != 0) : (len += 1) {}
                const lfn_str = lfn.buf[0..len];

                if (common.std_mem_eql(lfn_str, name)) {
                    lfn.active = false;
                    return EntryLocation{ .sector = sector, .offset = i };
                }
            }
            lfn.active = false;

            var match = true;
            for (0..8) |j| {
                const c = if (j < sn_name.len) toUpper(sn_name[j]) else ' ';
                if (buffer[i + j] != c) {
                    match = false;
                    break;
                }
            }
            if (match) {
                for (0..3) |j| {
                    const c = if (j < sn_ext.len) toUpper(sn_ext[j]) else ' ';
                    if (buffer[i + 8 + j] != c) {
                        match = false;
                        break;
                    }
                }
            }
            if (match) return EntryLocation{ .sector = sector, .offset = i };
        }
    }
    return null;
}

pub fn find_entry_location(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8) ?EntryLocation {
    if (resolve_path(drive, bpb, dir_cluster, path)) |res| {
        return find_entry_location_literal(drive, bpb, res.dir_cluster, res.file_name);
    }
    return null;
}

pub fn find_entry_location_literal(drive: ata.Drive, bpb: BPB, dir_cluster: u32, name: []const u8) ?EntryLocation {
    var current = dir_cluster;
    if (current == 0) {
        if (bpb.fat_type == .FAT32) {
            current = bpb.root_cluster;
        } else {
            return find_entry_in_sectors(drive, name, bpb.first_root_dir_sector, bpb.first_data_sector);
        }
    }

    const eof_val = switch (bpb.fat_type) {
        .FAT12 => @as(u32, 0xFF8),
        .FAT16 => @as(u32, 0xFFF8),
        .FAT32 => @as(u32, 0x0FFFFFF8),
        else => @as(u32, 0xFFF8),
    };

    while (current < eof_val) {
        const lba = bpb.first_data_sector + (current - 2) * bpb.sectors_per_cluster;
        if (find_entry_in_sectors(drive, name, lba, lba + bpb.sectors_per_cluster)) |loc| return loc;
        current = get_fat_entry(drive, bpb, current);
        if (current < 2 or current >= eof_val) break;
    }
    return null;
}

pub fn find_entry(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8) ?DirEntry {
    if (resolve_path(drive, bpb, dir_cluster, path)) |res| {
        return find_entry_literal(drive, bpb, res.dir_cluster, res.file_name);
    }
    return null;
}

pub fn find_entry_literal(drive: ata.Drive, bpb: BPB, dir_cluster: u32, name: []const u8) ?DirEntry {
    if (common.std_mem_eql(name, ".")) {
        var entry: DirEntry = undefined;
        for (0..8) |j| entry.name[j] = ' ';
        entry.name[0] = '.';
        for (0..3) |j| entry.ext[j] = ' ';
        entry.attr = 0x10;
        entry.first_cluster_low = @intCast(dir_cluster & 0xFFFF);
        entry.first_cluster_high = @intCast((dir_cluster >> 16) & 0xFFFF);
        entry.file_size = 0;
        return entry;
    }

    if (dir_cluster == 0 and common.std_mem_eql(name, "..")) {
        return find_entry_literal(drive, bpb, 0, ".");
    }

    const loc = find_entry_location_literal(drive, bpb, dir_cluster, name) orelse return null;
    var buffer: [512]u8 = undefined;
    ata.read_sector(drive, loc.sector, &buffer);

    const i = loc.offset;
    var entry: DirEntry = undefined;
    for (0..8) |j| entry.name[j] = buffer[i + j];
    for (0..3) |j| entry.ext[j] = buffer[i + 8 + j];
    entry.attr = buffer[i + 11];
    entry.reserved = buffer[i + 12];
    entry.creation_time_tenth = buffer[i + 13];
    entry.creation_time = @as(u16, buffer[i + 14]) | (@as(u16, buffer[i + 15]) << 8);
    entry.creation_date = @as(u16, buffer[i + 16]) | (@as(u16, buffer[i + 17]) << 8);
    entry.last_access_date = @as(u16, buffer[i + 18]) | (@as(u16, buffer[i + 19]) << 8);
    entry.first_cluster_high = @as(u16, buffer[i + 20]) | (@as(u16, buffer[i + 21]) << 8);
    entry.write_time = @as(u16, buffer[i + 22]) | (@as(u16, buffer[i + 23]) << 8);
    entry.write_date = @as(u16, buffer[i + 24]) | (@as(u16, buffer[i + 25]) << 8);
    entry.first_cluster_low = @as(u16, buffer[i + 26]) | (@as(u16, buffer[i + 27]) << 8);
    entry.file_size = @as(u32, buffer[i + 28]) | (@as(u32, buffer[i + 29]) << 8) | (@as(u32, buffer[i + 30]) << 16) | (@as(u32, buffer[i + 31]) << 24);
    return entry;
}

pub fn delete_file(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8) bool {
    const res = resolve_path(drive, bpb, dir_cluster, path) orelse return false;
    const entry = find_entry_literal(drive, bpb, res.dir_cluster, res.file_name) orelse return false;
    if ((entry.attr & 0x04) != 0) {
        return false;
    }
    return delete_file_literal(drive, bpb, res.dir_cluster, res.file_name);
}

fn delete_file_literal(drive: ata.Drive, bpb: BPB, dir_cluster: u32, name: []const u8) bool {
    const entry = find_entry_literal(drive, bpb, dir_cluster, name) orelse return false;

    if (!mark_entry_deleted(drive, bpb, dir_cluster, name)) return false;

    free_cluster_chain(drive, bpb, entry.first_cluster_low);

    return true;
}

pub fn delete_directory(drive: ata.Drive, bpb: BPB, parent_cluster: u32, path: []const u8, recursive: bool) bool {
    if (resolve_path(drive, bpb, parent_cluster, path)) |res| {
        return delete_directory_literal(drive, bpb, res.dir_cluster, res.file_name, recursive);
    }
    return false;
}

fn delete_directory_literal(drive: ata.Drive, bpb: BPB, parent_cluster: u32, name: []const u8, recursive: bool) bool {
    const entry = find_entry_literal(drive, bpb, parent_cluster, name) orelse return false;
    if ((entry.attr & 0x10) == 0) return delete_file_literal(drive, bpb, parent_cluster, name);

    const cluster = entry.first_cluster_low;
    if (cluster == 0) return false;

    if (!recursive) {
        if (!is_directory_empty(drive, bpb, cluster)) return false;
    }

    delete_all_in_directory(drive, bpb, cluster, recursive, true, "");

    return delete_file_literal(drive, bpb, parent_cluster, name);
}

pub fn is_directory_empty(drive: ata.Drive, bpb: BPB, dir_cluster: u32) bool {
    var buffer: [512]u8 = undefined;
    if (dir_cluster == 0) return false;

    var current = dir_cluster;
    const eof_val = if (bpb.fat_type == .FAT12) @as(u32, 0xFF8) else @as(u32, 0xFFF8);
    while (current < eof_val) {
        const lba = bpb.first_data_sector + (current - 2) * bpb.sectors_per_cluster;
        var s: u32 = 0;
        while (s < bpb.sectors_per_cluster) : (s += 1) {
            ata.read_sector(drive, lba + s, &buffer);
            var i: u32 = 0;
            while (i < 512) : (i += 32) {
                if (buffer[i] == 0) return true;
                if (buffer[i] == 0xE5) continue;
                if (buffer[i + 11] == 0x0F) continue;

                if (buffer[i] == '.' and (buffer[i + 1] == ' ' or (buffer[i + 1] == '.' and buffer[i + 2] == ' '))) {
                    continue;
                }

                const name = get_name_from_raw(buffer[i .. i + 32]);
                const n = name.buf[0..name.len];
                if (common.std_mem_eql(n, ".") or common.std_mem_eql(n, "..")) continue;

                return false;
            }
        }
        current = get_fat_entry(drive, bpb, current);
        if (current == 0) break;
    }
    return true;
}

pub fn delete_all_in_directory(drive: ata.Drive, bpb: BPB, dir_cluster: u32, recursive: bool, delete_subdirs: bool, prefix: []const u8) void {
    var buffer: [512]u8 = undefined;
    if (dir_cluster == 0) {
        var sector = bpb.first_root_dir_sector;
        while (sector < bpb.first_data_sector) : (sector += 1) {
            ata.read_sector(drive, sector, &buffer);
            delete_all_in_sector(drive, bpb, sector, &buffer, recursive, delete_subdirs, prefix);
        }
    } else {
        var current = dir_cluster;
        const eof_val = if (bpb.fat_type == .FAT12) @as(u32, 0xFF8) else @as(u32, 0xFFF8);
        while (current < eof_val) {
            const lba = bpb.first_data_sector + (current - 2) * bpb.sectors_per_cluster;
            var s: u32 = 0;
            while (s < bpb.sectors_per_cluster) : (s += 1) {
                ata.read_sector(drive, lba + s, &buffer);
                delete_all_in_sector(drive, bpb, lba + s, &buffer, recursive, delete_subdirs, prefix);
            }
            current = get_fat_entry(drive, bpb, current);
            if (current == 0) break;
        }
    }
}

fn delete_all_in_sector(drive: ata.Drive, bpb: BPB, sector: u32, buffer: *[512]u8, recursive: bool, delete_subdirs: bool, prefix: []const u8) void {
    var lfn: LfnState = .{ .buf = [_]u8{0} ** 256, .active = false, .checksum = 0 };
    var i: u32 = 0;
    var changed = false;
    while (i < 512) : (i += 32) {
        if (buffer[i] == 0) break;
        if (buffer[i] == 0xE5) {
            lfn.active = false;
            continue;
        }

        if (buffer[i + 11] == 0x0F) {
            const seq = buffer[i];
            const chk = buffer[i + 13];
            if ((seq & 0x40) != 0) {
                lfn.active = true;
                lfn.checksum = chk;
                @memset(&lfn.buf, 0);
            } else if (!lfn.active or lfn.checksum != chk) {
                lfn.active = false;
                continue;
            }
            var index = (seq & 0x1F);
            if (index < 1) index = 1;
            const offset = (index - 1) * 13;
            if (offset < 240) {
                extract_lfn_part(buffer, i + 1, 5, &lfn.buf, offset);
                extract_lfn_part(buffer, i + 14, 6, &lfn.buf, offset + 5);
                extract_lfn_part(buffer, i + 28, 2, &lfn.buf, offset + 11);
            }
            continue;
        }

        var sum: u8 = 0;
        for (0..11) |k| {
            const is_odd = (sum & 1) != 0;
            sum = (sum >> 1) + (if (is_odd) @as(u8, 0x80) else 0);
            sum = sum +% buffer[i + k];
        }

        var name_str: []const u8 = undefined;
        if (lfn.active and lfn.checksum == sum) {
            var len: usize = 0;
            while (len < 256 and lfn.buf[len] != 0) : (len += 1) {}
            name_str = lfn.buf[0..len];
        } else {
            const sn = get_name_from_raw(buffer[i .. i + 32]);
            name_str = sn.buf[0..sn.len];
        }
        lfn.active = false;

        if (common.std_mem_eql(name_str, ".") or common.std_mem_eql(name_str, "..")) continue;

        if (prefix.len > 0) {
            if (!common.startsWith(name_str, prefix)) continue;
        }

        const is_dir = (buffer[i + 11] & 0x10) != 0;
        const cluster = @as(u32, buffer[i + 26]) | (@as(u32, buffer[i + 27]) << 8);

        if (is_dir) {
            if (delete_subdirs) {
                if (recursive) {
                    delete_all_in_directory(drive, bpb, cluster, true, true, "");
                } else {
                    if (!is_directory_empty(drive, bpb, cluster)) {
                        common.printZ("Skipping non-empty directory: ");
                        common.printZ(name_str);
                        common.printZ(" (use -r)\n");
                        continue;
                    }
                }
                free_cluster_chain(drive, bpb, cluster);

                var k = i;
                while (k >= 32) {
                    k -= 32;
                    if (buffer[k + 11] == 0x0F) {
                        buffer[k] = 0xE5;
                    } else {
                        break;
                    }
                }
                buffer[i] = 0xE5;
                changed = true;
            } else {
                common.printZ("Skipping directory: ");
                common.printZ(name_str);
                common.printZ(" (use -d)\n");
            }
        } else {
            free_cluster_chain(drive, bpb, cluster);
            var k = i;
            while (k >= 32) {
                k -= 32;
                if (buffer[k + 11] == 0x0F) {
                    buffer[k] = 0xE5;
                } else {
                    break;
                }
            }
            buffer[i] = 0xE5;
            changed = true;
        }
    }
    if (changed) ata.write_sector(drive, sector, buffer);
}

fn mark_entry_deleted(drive: ata.Drive, bpb: BPB, dir_cluster: u32, name: []const u8) bool {
    const loc = find_entry_location_literal(drive, bpb, dir_cluster, name) orelse return false;

    var buffer: [512]u8 = undefined;
    ata.read_sector(drive, loc.sector, &buffer);

    buffer[loc.offset] = 0xE5;

    var i = loc.offset;
    while (i >= 32) {
        i -= 32;
        if (buffer[i + 11] == 0x0F) {
            buffer[i] = 0xE5;
        } else {
            break;
        }
    }

    ata.write_sector(drive, loc.sector, &buffer);
    return true;
}

pub fn copy_file(drive: ata.Drive, bpb: BPB, dir_cluster: u32, src_path: []const u8, dest_path: []const u8) bool {
    const src_res = resolve_path(drive, bpb, dir_cluster, src_path) orelse return false;
    const dest_res = resolve_path(drive, bpb, dir_cluster, dest_path) orelse return false;
    return copy_file_literal(drive, bpb, src_res.dir_cluster, src_res.file_name, dest_res.dir_cluster, dest_res.file_name);
}

pub fn copy_file_literal(drive: ata.Drive, bpb: BPB, src_dir: u32, src_name: []const u8, dest_dir: u32, dest_name: []const u8) bool {
    const src_entry = find_entry_literal(drive, bpb, src_dir, src_name) orelse return false;
    if ((src_entry.attr & 0x10) != 0) return false;

    const dest_cluster = find_free_cluster(drive, bpb) orelse return false;
    const fat_eof = if (bpb.fat_type == .FAT12) @as(u32, 0xFFF) else @as(u32, 0xFFFF);
    set_fat_entry(drive, bpb, dest_cluster, fat_eof);

    if (!add_directory_entry(drive, bpb, dest_dir, dest_name, dest_cluster, src_entry.file_size, src_entry.attr)) {
        set_fat_entry(drive, bpb, dest_cluster, 0);
        return false;
    }

    var current_src = @as(u32, src_entry.first_cluster_low);
    var current_dest = dest_cluster;
    const eof_limit = if (bpb.fat_type == .FAT12) @as(u32, 0xFF8) else @as(u32, 0xFFF8);

    var sector_buf: [512]u8 = undefined;
    while (current_src < eof_limit) {
        if (current_src < 2) break;

        const src_lba = bpb.first_data_sector + (current_src - 2) * bpb.sectors_per_cluster;

        if (current_dest < 2) break;
        const dest_lba = bpb.first_data_sector + (current_dest - 2) * bpb.sectors_per_cluster;

        var s: u32 = 0;
        while (s < bpb.sectors_per_cluster) : (s += 1) {
            ata.read_sector(drive, src_lba + s, &sector_buf);
            ata.write_sector(drive, dest_lba + s, &sector_buf);
        }

        current_src = get_fat_entry(drive, bpb, current_src);
        if (current_src < 2 or current_src >= eof_limit) break;

        const next_dest = find_free_cluster(drive, bpb) orelse {
            return false;
        };
        set_fat_entry(drive, bpb, current_dest, next_dest);
        set_fat_entry(drive, bpb, next_dest, fat_eof);
        current_dest = next_dest;
    }

    return true;
}

pub fn copy_directory(drive: ata.Drive, bpb: BPB, parent_cluster: u32, src_path: []const u8, dest_path: []const u8) bool {
    const src_res = resolve_path(drive, bpb, parent_cluster, src_path) orelse return false;
    const dest_res = resolve_path(drive, bpb, parent_cluster, dest_path) orelse return false;
    return copy_directory_literal(drive, bpb, src_res.dir_cluster, src_res.file_name, dest_res.dir_cluster, dest_res.file_name);
}

pub fn copy_directory_literal(drive: ata.Drive, bpb: BPB, src_parent: u32, src_name: []const u8, dest_parent: u32, dest_name: []const u8) bool {
    const entry = find_entry_literal(drive, bpb, src_parent, src_name) orelse return false;
    if ((entry.attr & 0x10) == 0) return copy_file_literal(drive, bpb, src_parent, src_name, dest_parent, dest_name);

    if (!create_directory_literal(drive, bpb, dest_parent, dest_name)) return false;
    const target_entry = find_entry_literal(drive, bpb, dest_parent, dest_name) orelse return false;
    const target_cluster = target_entry.first_cluster_low;

    copy_all_entries(drive, bpb, entry.first_cluster_low, target_cluster);
    return true;
}

fn copy_all_entries(drive: ata.Drive, bpb: BPB, src_cluster: u32, dest_cluster: u32) void {
    var buffer: [512]u8 = undefined;
    var current = src_cluster;
    const eof_val = if (bpb.fat_type == .FAT12) @as(u32, 0xFF8) else @as(u32, 0xFFF8);

    while (current < eof_val) {
        const lba = bpb.first_data_sector + (current - 2) * bpb.sectors_per_cluster;
        var s: u32 = 0;
        while (s < bpb.sectors_per_cluster) : (s += 1) {
            ata.read_sector(drive, lba + s, &buffer);
            var i: u32 = 0;
            while (i < 512) : (i += 32) {
                if (buffer[i] == 0) return;
                if (buffer[i] == 0xE5) continue;
                if (buffer[i + 11] == 0x0F) continue;

                const name_info = get_name_from_raw(buffer[i .. i + 32]);
                const name = name_info.buf[0..name_info.len];
                if (common.std_mem_eql(name, ".") or common.std_mem_eql(name, "..")) continue;

                copy_entry_recursive(drive, bpb, current, name, dest_cluster);
            }
        }
        current = get_fat_entry(drive, bpb, current);
        if (current == 0) break;
    }
}

fn copy_entry_recursive(drive: ata.Drive, bpb: BPB, src_dir_cluster: u32, name: []const u8, dest_dir_cluster: u32) void {
    const entry = find_entry_literal(drive, bpb, src_dir_cluster, name) orelse return;
    if ((entry.attr & 0x10) != 0) {
        _ = copy_directory_literal(drive, bpb, src_dir_cluster, name, dest_dir_cluster, name);
    } else {
        _ = copy_file_literal(drive, bpb, src_dir_cluster, name, dest_dir_cluster, name);
    }
}

pub fn free_cluster_chain(drive: ata.Drive, bpb: BPB, start_cluster: u32) void {
    if (start_cluster < 2) return;
    var current = start_cluster;
    const eof_val = if (bpb.fat_type == .FAT12) @as(u32, 0xFF8) else @as(u32, 0xFFF8);

    while (current < eof_val) {
        const next = get_fat_entry(drive, bpb, current);
        set_fat_entry(drive, bpb, current, 0);
        if (next < 2 or next >= eof_val) break;
        current = next;
    }
}

pub fn find_free_cluster(drive: ata.Drive, bpb: BPB) ?u32 {
    var cluster: u32 = 2;

    const max_clusters = switch (bpb.fat_type) {
        .FAT12 => @as(u32, 4085),
        .FAT16 => @as(u32, 65525),
        .FAT32 => (bpb.total_sectors_32 - bpb.first_data_sector) / bpb.sectors_per_cluster,
        else => 0,
    };

    while (cluster < max_clusters) : (cluster += 1) {
        const val = get_fat_entry(drive, bpb, cluster);
        if (val == 0) return cluster;
    }
    return null;
}

const ATTR_LONG_NAME = 0x0F;

fn check_needs_lfn(name: []const u8) bool {
    if (name.len > 12) return true;
    var dot_pos: ?usize = null;
    for (name, 0..) |c, i| {
        if (c == '.') {
            if (dot_pos != null) return true;
            if (i > 8) return true;
            dot_pos = i;
        } else {
            if (c >= 'a' and c <= 'z') return true;
            if (c == ' ' or c == '+' or c == ',' or c == ';' or c == '=' or c == '[' or c == ']' or
                c == '"' or c == '*' or c == '<' or c == '>' or c == '?' or c == '|') return true;
        }
    }
    if (dot_pos) |pos| {
        if (name.len - pos - 1 > 3) return true;
    } else {
        if (name.len > 8) return true;
    }
    return false;
}

fn lfn_checksum(short_name: []const u8) u8 {
    var sum: u8 = 0;
    for (short_name) |c| {
        const is_odd = (sum & 1) != 0;
        sum = (sum >> 1) + (if (is_odd) @as(u8, 0x80) else 0);
        sum = sum +% c;
    }
    return sum;
}

fn generate_short_alias(name: []const u8, out: *[11]u8) void {
    @memset(out, ' ');
    var out_idx: usize = 0;
    var i: usize = 0;
    while (i < name.len and out_idx < 6) {
        const c = name[i];
        if (c == '.') break;
        if (c != ' ' and c != '+' and c != ',' and c != ';' and c != '=' and c != '[' and c != ']' and
            c != '"' and c != '*' and c != '<' and c != '>' and c != '?' and c != '|')
        {
            out[out_idx] = toUpper(c);
            out_idx += 1;
        }
        i += 1;
    }
    out[out_idx] = '~';
    out[out_idx + 1] = '1';

    while (i < name.len and name[i] != '.') : (i += 1) {}
    if (i < name.len) {
        i += 1;
        var ext_idx: usize = 8;
        while (i < name.len and ext_idx < 11) : (i += 1) {
            const c = name[i];
            if (c != ' ' and c != '.' and c != '+' and c != ',' and c != ';' and c != '=' and c != '[' and c != ']' and
                c != '"' and c != '*' and c != '<' and c != '>' and c != '?' and c != '|')
            {
                out[ext_idx] = toUpper(c);
                ext_idx += 1;
            }
        }
    }
}

pub fn add_directory_entry(drive: ata.Drive, bpb: BPB, dir_cluster: u32, name: []const u8, cluster: u32, size: u32, attr: u8) bool {
    var short_name: [11]u8 = undefined;
    const needs_alias = check_needs_lfn(name);

    if (needs_alias) {
        generate_short_alias(name, &short_name);
    } else {
        const parts = fat_parse_name(name);
        @memset(&short_name, ' ');
        for (0..@min(parts.name.len, 8)) |j| short_name[j] = toUpper(parts.name[j]);
        for (0..@min(parts.ext.len, 3)) |j| short_name[8 + j] = toUpper(parts.ext[j]);
    }

    const slots_needed = if (needs_alias) (name.len + 12) / 13 + 1 else 1;

    if (dir_cluster == 0) {
        if (bpb.fat_type == .FAT32) {
            return add_directory_entry(drive, bpb, bpb.root_cluster, name, cluster, size, attr);
        }
        var sector = bpb.first_root_dir_sector;
        while (sector < bpb.first_data_sector) : (sector += 1) {
            if (try_add_entry_to_sector(drive, sector, name, &short_name, cluster, size, attr, slots_needed, needs_alias)) return true;
        }
        return false;
    }

    var current = dir_cluster;
    const eof_val = switch (bpb.fat_type) {
        .FAT12 => @as(u32, 0xFF8),
        .FAT16 => @as(u32, 0xFFF8),
        .FAT32 => @as(u32, 0x0FFFFFF8),
        else => @as(u32, 0xFFF8),
    };

    while (current < eof_val) {
        const lba = bpb.first_data_sector + (current - 2) * bpb.sectors_per_cluster;
        var s: u32 = 0;
        while (s < bpb.sectors_per_cluster) : (s += 1) {
            if (try_add_entry_to_sector(drive, lba + s, name, &short_name, cluster, size, attr, slots_needed, needs_alias)) return true;
        }

        var next = get_fat_entry(drive, bpb, current);
        if (next >= eof_val) {
            next = find_free_cluster(drive, bpb) orelse return false;
            set_fat_entry(drive, bpb, current, next);

            const next_eof = switch (bpb.fat_type) {
                .FAT12 => @as(u32, 0xFFF),
                .FAT16 => @as(u32, 0xFFFF),
                .FAT32 => @as(u32, 0x0FFFFFFF),
                else => @as(u32, 0xFFFF),
            };
            set_fat_entry(drive, bpb, next, next_eof);

            var buffer: [512]u8 = [_]u8{0} ** 512;
            const new_lba = bpb.first_data_sector + (next - 2) * bpb.sectors_per_cluster;
            var j: u32 = 0;
            while (j < bpb.sectors_per_cluster) : (j += 1) {
                ata.write_sector(drive, new_lba + j, &buffer);
            }
        }
        current = next;
    }
    return false;
}

fn try_add_entry_to_sector(drive: ata.Drive, sector: u32, name: []const u8, short_name: *[11]u8, cluster: u32, size: u32, attr: u8, slots: usize, use_lfn: bool) bool {
    var buffer: [512]u8 = undefined;
    ata.read_sector(drive, sector, &buffer);

    var free_count: usize = 0;
    var start_index: usize = 0;

    var i: usize = 0;
    while (i < 512) : (i += 32) {
        if (buffer[i] == 0 or buffer[i] == 0xE5) {
            if (free_count == 0) start_index = i;
            free_count += 1;
            if (free_count == slots) {

                if (use_lfn) {
                    const lfn_count = slots - 1;
                    const chk = lfn_checksum(short_name);

                    var entry_idx: usize = 0;
                    while (entry_idx < lfn_count) : (entry_idx += 1) {
                        const lfn_seq = lfn_count - entry_idx;
                        const offset = start_index + (entry_idx * 32);

                        for (0..32) |k| buffer[offset + k] = 0;

                        buffer[offset] = @intCast(lfn_seq | (if (entry_idx == 0) @as(u8, 0x40) else 0));
                        buffer[offset + 11] = ATTR_LONG_NAME;
                        buffer[offset + 12] = 0;
                        buffer[offset + 13] = chk;
                        buffer[offset + 26] = 0;
                        buffer[offset + 27] = 0;

                        const char_offset = (lfn_seq - 1) * 13;
                        write_lfn_chars(&buffer, offset, name, char_offset);
                    }

                    write_short_entry(&buffer, start_index + (lfn_count * 32), short_name, cluster, size, attr);
                } else {
                    write_short_entry(&buffer, start_index, short_name, cluster, size, attr);
                }

                ata.write_sector(drive, sector, &buffer);
                return true;
            }
        } else {
            free_count = 0;
        }
    }
    return false;
}

fn write_lfn_chars(buffer: *[512]u8, offset: usize, name: []const u8, start_char: usize) void {
    var char_idx: usize = 0;

    for (0..5) |j| {
        write_lfn_char(buffer, offset + 1 + j * 2, name, start_char + char_idx);
        char_idx += 1;
    }
    for (0..6) |j| {
        write_lfn_char(buffer, offset + 14 + j * 2, name, start_char + char_idx);
        char_idx += 1;
    }
    for (0..2) |j| {
        write_lfn_char(buffer, offset + 28 + j * 2, name, start_char + char_idx);
        char_idx += 1;
    }
}

fn write_lfn_char(buffer: *[512]u8, buf_offset: usize, name: []const u8, name_idx: usize) void {
    if (name_idx < name.len) {
        buffer[buf_offset] = name[name_idx];
        buffer[buf_offset + 1] = 0;
    } else if (name_idx == name.len) {
        buffer[buf_offset] = 0;
        buffer[buf_offset + 1] = 0;
    } else {
        buffer[buf_offset] = 0xFF;
        buffer[buf_offset + 1] = 0xFF;
    }
}

fn write_short_entry(buffer: *[512]u8, offset: usize, short_name: *[11]u8, cluster: u32, size: u32, attr: u8) void {
    common.copy(buffer[offset..], short_name);
    buffer[offset + 11] = attr;
    buffer[offset + 12] = 0;

    const ts = getCurrentTimestamp();

    buffer[offset + 13] = 0;
    buffer[offset + 14] = @intCast(ts.time & 0xFF);
    buffer[offset + 15] = @intCast((ts.time >> 8) & 0xFF);
    buffer[offset + 16] = @intCast(ts.date & 0xFF);
    buffer[offset + 17] = @intCast((ts.date >> 8) & 0xFF);
    buffer[offset + 18] = @intCast(ts.date & 0xFF);
    buffer[offset + 19] = @intCast((ts.date >> 8) & 0xFF);

    buffer[offset + 20] = @intCast((cluster >> 16) & 0xFF);
    buffer[offset + 21] = @intCast((cluster >> 24) & 0xFF);

    buffer[offset + 22] = @intCast(ts.time & 0xFF);
    buffer[offset + 23] = @intCast((ts.time >> 8) & 0xFF);
    buffer[offset + 24] = @intCast(ts.date & 0xFF);
    buffer[offset + 25] = @intCast((ts.date >> 8) & 0xFF);

    buffer[offset + 26] = @intCast(cluster & 0xFF);
    buffer[offset + 27] = @intCast((cluster >> 8) & 0xFF);
    buffer[offset + 28] = @intCast(size & 0xFF);
    buffer[offset + 29] = @intCast((size >> 8) & 0xFF);
    buffer[offset + 30] = @intCast((size >> 16) & 0xFF);
    buffer[offset + 31] = @intCast((size >> 24) & 0xFF);
}

pub fn create_directory(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8) bool {
    if (resolve_path(drive, bpb, dir_cluster, path)) |res| {
        return create_directory_literal(drive, bpb, res.dir_cluster, res.file_name);
    }
    return false;
}

fn create_directory_literal(drive: ata.Drive, bpb: BPB, dir_cluster: u32, name: []const u8) bool {
    if (find_entry_literal(drive, bpb, dir_cluster, name) != null) return false;

    const cluster = find_free_cluster(drive, bpb) orelse return false;
    const eof_val: u32 = switch (bpb.fat_type) {
        .FAT12 => 0xFFF,
        .FAT16 => 0xFFFF,
        .FAT32 => 0x0FFFFFFF,
        else => 0xFFFF,
    };
    set_fat_entry(drive, bpb, cluster, eof_val);

    if (!add_directory_entry(drive, bpb, dir_cluster, name, cluster, 0, 0x10)) return false;

    var buffer: [512]u8 = [_]u8{0} ** 512;

    for (0..32) |j| buffer[j] = ' ';
    buffer[0] = '.';
    buffer[11] = 0x10;
    buffer[20] = @intCast((cluster >> 16) & 0xFF);
    buffer[21] = @intCast((cluster >> 24) & 0xFF);
    buffer[26] = @intCast(cluster & 0xFF);
    buffer[27] = @intCast((cluster >> 8) & 0xFF);

    for (0..32) |j| buffer[32 + j] = ' ';
    buffer[32 + 0] = '.';
    buffer[32 + 1] = '.';
    buffer[32 + 11] = 0x10;
    buffer[32 + 20] = @intCast((dir_cluster >> 16) & 0xFF);
    buffer[32 + 21] = @intCast((dir_cluster >> 24) & 0xFF);
    buffer[32 + 26] = @intCast(dir_cluster & 0xFF);
    buffer[32 + 27] = @intCast((dir_cluster >> 8) & 0xFF);

    const lba = bpb.first_data_sector + (cluster - 2) * bpb.sectors_per_cluster;
    ata.write_sector(drive, lba, &buffer);

    var s: u32 = 1;
    zero_sector(&buffer);
    while (s < bpb.sectors_per_cluster) : (s += 1) {
        ata.write_sector(drive, lba + s, &buffer);
    }

    return true;
}

fn zero_sector(buf: *[512]u8) void {
    for (0..512) |i| buf[i] = 0;
}

pub fn set_file_attrib(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8, read_only: bool, hidden: bool, system: bool, archive: bool) bool {
    const res = resolve_path(drive, bpb, dir_cluster, path) orelse return false;
    const loc = find_entry_location_literal(drive, bpb, res.dir_cluster, res.file_name) orelse return false;

    var buffer: [512]u8 = undefined;
    ata.read_sector(drive, loc.sector, &buffer);

    const i = loc.offset;
    var attr: u8 = buffer[i + 11];

    if (read_only) attr |= 0x01 else attr &= 0xFE;
    if (hidden) attr |= 0x02 else attr &= 0xFD;
    if (system) attr |= 0x04 else attr &= 0xFB;
    if (archive) attr |= 0x20 else attr &= 0xDF;

    buffer[i + 11] = attr;
    ata.write_sector(drive, loc.sector, &buffer);
    return true;
}

pub fn rename_file(drive: ata.Drive, bpb: BPB, dir_cluster: u32, old_path: []const u8, new_path: []const u8) bool {
    const old_res = resolve_path(drive, bpb, dir_cluster, old_path) orelse return false;
    const new_res = resolve_path(drive, bpb, dir_cluster, new_path) orelse return false;

    if (find_entry_literal(drive, bpb, new_res.dir_cluster, new_res.file_name) != null) return false;

    const entry = find_entry_literal(drive, bpb, old_res.dir_cluster, old_res.file_name) orelse return false;

    if ((entry.attr & 0x04) != 0) return false;

    if (!add_directory_entry(drive, bpb, new_res.dir_cluster, new_res.file_name, entry.first_cluster_low, entry.file_size, entry.attr)) return false;

    if (!mark_entry_deleted(drive, bpb, old_res.dir_cluster, old_res.file_name)) return false;

    if ((entry.attr & 0x10) != 0 and new_res.dir_cluster != old_res.dir_cluster) {
        const dir_cluster_id = entry.first_cluster_low;
        if (dir_cluster_id != 0) {
            const lba = bpb.first_data_sector + (dir_cluster_id - 2) * bpb.sectors_per_cluster;
            var dir_buf: [512]u8 = undefined;
            ata.read_sector(drive, lba, &dir_buf);
            if (dir_buf[32] == '.' and dir_buf[33] == '.') {
                dir_buf[32 + 26] = @intCast(new_res.dir_cluster & 0xFF);
                dir_buf[32 + 27] = @intCast(new_res.dir_cluster >> 8);
                ata.write_sector(drive, lba, &dir_buf);
            }
        }
    }

    return true;
}