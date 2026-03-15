// FatFS Zig Wrapper - provides compatible API with old fat.zig
const ata = @import("ata.zig");
const common = @import("../commands/common.zig");
const std = @import("std");

pub const FatType = enum {
    None,
    FAT12,
    Fat16,
    Fat32,
};

pub const BPB = struct {
    oem_name: [8]u8,
    bytes_per_sector: u16,
    sectors_per_cluster: u8,
    reserved_sectors: u16,
    num_fats: u8,
    root_entries: u16,
    total_sectors_16: u16,
    media_descriptor: u8,
    sectors_per_fat: u16,
    sectors_per_track: u16,
    num_heads: u16,
    hidden_sectors: u32,
    total_sectors_32: u32,
    first_fat_sector: u32,
    first_root_dir_sector: u32,
    first_data_sector: u32,
    root_dir_sectors: u32,
    fat_type: FatType,
    sectors_per_fat32: u32,
    root_cluster: u32,
};

pub const DirEntry = struct {
    name: [11]u8,
    attr: u8,
    reserved: u8,
    creation_time_tenth: u8,
    creation_time: u16,
    creation_date: u16,
    access_date: u16,
    cluster_high: u16,
    modification_time: u16,
    modification_date: u16,
    cluster_low: u16,
    size: u32,
};

pub const EntryLocation = struct {
    sector: u32,
    offset: u32,
};

pub const PathResolution = struct {
    cluster: u32,
    name: [11]u8,
    is_dir: bool,
};

pub const ResolvedPath = struct {
    parent_cluster: u32,
    name: [11]u8,
    entry_location: EntryLocation,
    is_dir: bool,
};

var fs_initialized: bool = false;
var fat_fs: [1]FatFs = undefined;

const FatFs = opaque {
    // C struct - opaque
};

const FIL = opaque {
    // C struct - opaque
};

// C functions from ff.h
extern "C" fn f_mount(fs: ?*FatFs, path: [*]const u8) c_int;
extern "C" fn f_open(fp: ?*FIL, path: [*]const u8, mode: u8) c_int;
extern "C" fn f_close(fp: ?*FIL) c_int;
extern "C" fn f_read(fp: ?*FIL, buff: ?*anyopaque, btr: UINT, br: *UINT) c_int;
extern "C" fn f_write(fp: ?*FIL, buff: ?*anyopaque, btw: UINT, *UINT) c_int;
extern "C" fn f_opendir(dp: ?*DIR, path: [*]const u8) c_int;
extern "C" fn f_readdir(dp: ?*DIR, fno: ?*FILEINFO) c_int;
extern "C" fn f_closedir(dp: ?*DIR) c_int;
extern "C" fn f_mkdir(path: [*]const u8) c_int;
extern "C" fn f_unlink(path: [*]const u8) c_int;
extern "C" fn f_rename(old: [*]const u8, new: [*]const u8) c_int;
extern "C" fn f_getfree(path: [*]const u8, nclst: *DWORD, fs: *?*FatFs) c_int;

const DIR = opaque {};
const FILEINFO = extern struct {
    fname: [13]u8,
    fattrib: u8,
    fsize: DWORD,
    fdate: WORD,
    ftime: WORD,
};

const DWORD = u32;
const WORD = u16;
const UINT = u32;
const BYTE = u8;

fn toFatType(fs: *FatFs) FatType {
    _ = fs;
    return .Fat32;
}

pub fn read_bpb(drive: ata.Drive) ?BPB {
    if (!fs_initialized) {
        _ = f_mount(&fat_fs, "/");
        fs_initialized = true;
    }

    var bpb: BPB = undefined;
    @memset(&bpb, 0);
    bpb.bytes_per_sector = 512;
    bpb.sectors_per_cluster = 1;
    bpb.fat_type = .Fat32;
    bpb.root_cluster = 2;
    return bpb;
}

pub fn find_entry(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8) ?DirEntry {
    _ = drive;
    _ = bpb;
    _ = dir_cluster;

    var dir: DIR = undefined;
    var info: FILEINFO = undefined;

    if (f_opendir(&dir, path.ptr) == 0) {
        if (f_readdir(&dir, &info) == 0) {
            var entry: DirEntry = undefined;
            @memcpy(&entry.name, &info.fname);
            entry.attr = info.fattrib;
            entry.size = info.fsize;
            _ = f_closedir(&dir);
            return entry;
        }
        _ = f_closedir(&dir);
    }
    return null;
}

pub fn list_directory(drive: ata.Drive, bpb: BPB, dir_cluster: u32, show_hidden: bool) void {
    _ = bpb;
    _ = show_hidden;

    var path_buf: [64]u8 = undefined;
    var path: []u8 = undefined;

    if (dir_cluster == 0) {
        path = "/";
    } else {
        path = path_buf[0..1];
        path[0] = '/';
    }

    var dir: DIR = undefined;
    var info: FILEINFO = undefined;

    if (f_opendir(&dir, path.ptr) == 0) {
        while (f_readdir(&dir, &info) == 0) {
            if (info.fname[0] == 0) break;

            var i: usize = 0;
            while (i < 13 and info.fname[i] != 0) : (i += 1) {
                common.print_char(info.fname[i]);
            }
            common.print_char('\n');
        }
        _ = f_closedir(&dir);
    }
}

pub fn read_file(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8, output: [*]u8) i32 {
    _ = drive;
    _ = bpb;
    _ = dir_cluster;

    var file: FIL = undefined;

    if (f_open(&file, path.ptr, 0) != 0) {
        return -1;
    }

    var read: UINT = 0;
    var total: u32 = 0;
    var buf: [512]u8 = undefined;

    while (true) {
        if (f_read(&file, &buf, 512, &read) != 0 or read == 0) {
            break;
        }
        std.mem.copy(u8, output[total..], buf[0..read]);
        total += read;
    }

    _ = f_close(&file);
    return @intCast(total);
}

pub fn write_file(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8, data: []const u8) bool {
    _ = drive;
    _ = bpb;
    _ = dir_cluster;

    var file: FIL = undefined;

    if (f_open(&file, path.ptr, 0x02 | 0x01) != 0) { // FA_CREATE_ALWAYS | FA_WRITE
        return false;
    }

    var written: UINT = 0;
    if (f_write(&file, data.ptr, data.len, &written) != 0) {
        _ = f_close(&file);
        return false;
    }

    _ = f_close(&file);
    return true;
}

pub fn copy_file(drive: ata.Drive, bpb: BPB, dir_cluster: u32, src_path: []const u8, dest_path: []const u8) bool {
    _ = drive;
    _ = bpb;
    _ = dir_cluster;

    var src_file: FIL = undefined;
    var dest_file: FIL = undefined;

    if (f_open(&src_file, src_path.ptr, 0) != 0) {
        return false;
    }

    if (f_open(&dest_file, dest_path.ptr, 0x02 | 0x01) != 0) {
        _ = f_close(&src_file);
        return false;
    }

    var buf: [512]u8 = undefined;
    var read: UINT = 0;
    var written: UINT = 0;

    while (true) {
        if (f_read(&src_file, &buf, 512, &read) != 0 or read == 0) {
            break;
        }
        if (f_write(&dest_file, &buf, read, &written) != 0 or written != read) {
            break;
        }
    }

    _ = f_close(&src_file);
    _ = f_close(&dest_file);
    return true;
}

pub fn rename_file(drive: ata.Drive, bpb: BPB, dir_cluster: u32, old_path: []const u8, new_path: []const u8) bool {
    _ = drive;
    _ = bpb;
    _ = dir_cluster;

    return f_rename(old_path.ptr, new_path.ptr) == 0;
}

pub fn delete_file(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8) bool {
    _ = drive;
    _ = bpb;
    _ = dir_cluster;

    return f_unlink(path.ptr) == 0;
}

pub fn create_directory(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8) bool {
    _ = drive;
    _ = bpb;
    _ = dir_cluster;

    return f_mkdir(path.ptr) == 0;
}

pub fn copy_directory(drive: ata.Drive, bpb: BPB, parent_cluster: u32, src_path: []const u8, dest_path: []const u8) bool {
    _ = drive;
    _ = bpb;
    _ = parent_cluster;
    _ = src_path;
    _ = dest_path;

    return false;
}

pub fn delete_directory(drive: ata.Drive, bpb: BPB, parent_cluster: u32, path: []const u8, recursive: bool) bool {
    _ = drive;
    _ = bpb;
    _ = parent_cluster;
    _ = path;
    _ = recursive;

    return false;
}

pub fn format(drive: ata.Drive, bpb: BPB, progress_cb: ?*const fn (u32, u32) void) bool {
    _ = drive;
    _ = bpb;
    _ = progress_cb;

    return false;
}
