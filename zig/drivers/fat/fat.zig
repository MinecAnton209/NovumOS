const ata = @import("../ata.zig");

pub const cache = @import("cache.zig");
pub const bpb_mod = @import("bpb.zig");
pub const dir = @import("dir.zig");
pub const file = @import("file.zig");

pub const FatCacheSize = cache.FatCacheSize;
pub const fat_read_cached_sector = cache.fat_read_cached_sector;

pub const FatType = bpb_mod.FatType;
pub const BPB = bpb_mod.BPB;
pub const read_bpb = bpb_mod.read_bpb;
pub const DirEntry = bpb_mod.DirEntry;
pub const LfnState = bpb_mod.LfnState;
pub const extract_lfn_part = bpb_mod.extract_lfn_part;

pub const EntryLocation = dir.EntryLocation;
pub const FatName = dir.FatName;
pub const PathResolution = dir.PathResolution;
pub const ResolvedPath = dir.ResolvedPath;
pub const list_directory = dir.list_directory;
pub const resolve_path = dir.resolve_path;
pub const resolve_full_path = dir.resolve_full_path;
pub const find_entry = dir.find_entry;
pub const find_entry_literal = dir.find_entry_literal;
pub const find_entry_location = dir.find_entry_location;
pub const find_entry_location_literal = dir.find_entry_location_literal;
pub const delete_file = dir.delete_file;
pub const delete_directory = dir.delete_directory;
pub const is_directory_empty = dir.is_directory_empty;
pub const delete_all_in_directory = dir.delete_all_in_directory;
pub const copy_file = dir.copy_file;
pub const copy_file_literal = dir.copy_file_literal;
pub const copy_directory = dir.copy_directory;
pub const copy_directory_literal = dir.copy_directory_literal;
pub const create_directory = dir.create_directory;
pub const set_file_attrib = dir.set_file_attrib;
pub const rename_file = dir.rename_file;
pub const get_name_from_raw = dir.get_name_from_raw;
pub const get_fat_entry = dir.get_fat_entry;
pub const set_fat_entry = dir.set_fat_entry;
pub const add_directory_entry = dir.add_directory_entry;
pub const find_free_cluster = dir.find_free_cluster;
pub const free_cluster_chain = dir.free_cluster_chain;

pub const read_file = file.read_file;
pub const read_file_literal = file.read_file_literal;
pub const stream_to_console = file.stream_to_console;
pub const stream_to_console_literal = file.stream_to_console_literal;
pub const write_file = file.write_file;
pub const append_to_file = file.append_to_file;

pub fn format(drive: ata.Drive, bpb: BPB, progress_cb: ?*const fn (u32, u32) void) bool {
    var buffer: [512]u8 = [_]u8{0} ** 512;

    const root_dir_sectors = bpb.root_dir_sectors;
    const total_fat_sectors = bpb.num_fats * bpb.sectors_per_fat;

    const total_ops = total_fat_sectors + root_dir_sectors;
    var current_op: u32 = 0;

    var sector = bpb.first_fat_sector;
    var end_sector = bpb.first_fat_sector + total_fat_sectors;

    while (sector < end_sector) : (sector += 1) {
        ata.write_sector(drive, @intCast(sector), &buffer);
        current_op += 1;
        if (progress_cb) |cb| cb(current_op, total_ops);
    }

    sector = bpb.first_root_dir_sector;
    end_sector = bpb.first_root_dir_sector + root_dir_sectors;
    while (sector < end_sector) : (sector += 1) {
        ata.write_sector(drive, @intCast(sector), &buffer);
        current_op += 1;
        if (progress_cb) |cb| cb(current_op, total_ops);
    }

    ata.read_sector(drive, @intCast(bpb.first_fat_sector), &buffer);
    if (bpb.fat_type == .FAT12) {
        buffer[0] = 0xF8;
        buffer[1] = 0xFF;
        buffer[2] = 0xFF;
    } else {
        buffer[0] = 0xF8;
        buffer[1] = 0xFF;
        buffer[2] = 0xFF;
        buffer[3] = 0xFF;
    }
    ata.write_sector(drive, @intCast(bpb.first_fat_sector), &buffer);

    if (bpb.num_fats > 1) {
        ata.write_sector(drive, @intCast(bpb.first_fat_sector + bpb.sectors_per_fat), &buffer);
    }

    return true;
}