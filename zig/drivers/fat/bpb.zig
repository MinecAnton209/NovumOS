const common = @import("../../commands/common.zig");
const ata = @import("../ata.zig");

pub const FatType = enum {
    None,
    FAT12,
    FAT16,
    FAT32,
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

pub fn read_bpb(drive: ata.Drive) ?BPB {
    var buffer: [512]u8 = undefined;
    ata.read_sector(drive, 0, &buffer);

    if (buffer[510] != 0x55 or buffer[511] != 0xAA) return null;

    var bpb: BPB = undefined;

    for (0..8) |i| bpb.oem_name[i] = buffer[3 + i];

    bpb.bytes_per_sector = @as(u16, buffer[11]) | (@as(u16, buffer[12]) << 8);
    bpb.sectors_per_cluster = buffer[13];
    bpb.reserved_sectors = @as(u16, buffer[14]) | (@as(u16, buffer[15]) << 8);
    bpb.num_fats = buffer[16];
    bpb.root_entries = @as(u16, buffer[17]) | (@as(u16, buffer[18]) << 8);
    bpb.total_sectors_16 = @as(u16, buffer[19]) | (@as(u16, buffer[20]) << 8);
    bpb.media_descriptor = buffer[21];
    bpb.sectors_per_fat = @as(u16, buffer[22]) | (@as(u16, buffer[23]) << 8);
    bpb.sectors_per_track = @as(u16, buffer[24]) | (@as(u16, buffer[25]) << 8);
    bpb.num_heads = @as(u16, buffer[26]) | (@as(u16, buffer[27]) << 8);
    bpb.hidden_sectors = @as(u32, buffer[28]) | (@as(u32, buffer[29]) << 8) | (@as(u32, buffer[30]) << 16) | (@as(u32, buffer[31]) << 24);
    bpb.total_sectors_32 = @as(u32, buffer[32]) | (@as(u32, buffer[33]) << 8) | (@as(u32, buffer[34]) << 16) | (@as(u32, buffer[35]) << 24);

    if (bpb.bytes_per_sector != 512) return null;

    const is_fat12 = common.std_mem_eql(buffer[0x36..0x3E], "FAT12   ");
    const is_fat16 = common.std_mem_eql(buffer[0x36..0x3E], "FAT16   ");
    const is_fat32 = common.std_mem_eql(buffer[0x52..0x5A], "FAT32   ");

    if (!is_fat12 and !is_fat16 and !is_fat32) return null;

    bpb.sectors_per_fat32 = @as(u32, buffer[36]) | (@as(u32, buffer[37]) << 8) | (@as(u32, buffer[38]) << 16) | (@as(u32, buffer[39]) << 24);
    bpb.root_cluster = @as(u32, buffer[44]) | (@as(u32, buffer[45]) << 8) | (@as(u32, buffer[46]) << 16) | (@as(u32, buffer[47]) << 24);

    const spf = if (bpb.sectors_per_fat == 0) bpb.sectors_per_fat32 else bpb.sectors_per_fat;

    bpb.root_dir_sectors = ((@as(u32, bpb.root_entries) * 32) + (bpb.bytes_per_sector - 1)) / bpb.bytes_per_sector;
    bpb.first_fat_sector = bpb.reserved_sectors;
    bpb.first_root_dir_sector = bpb.first_fat_sector + (bpb.num_fats * spf);
    bpb.first_data_sector = bpb.first_root_dir_sector + bpb.root_dir_sectors;

    const total_sectors = if (bpb.total_sectors_16 == 0) bpb.total_sectors_32 else bpb.total_sectors_16;
    const data_sectors = total_sectors - (bpb.reserved_sectors + (bpb.num_fats * spf) + bpb.root_dir_sectors);
    const total_clusters = data_sectors / bpb.sectors_per_cluster;

    if (bpb.sectors_per_fat == 0) {
        bpb.fat_type = .FAT32;
    } else if (total_clusters < 4085) {
        bpb.fat_type = .FAT12;
    } else {
        bpb.fat_type = .FAT16;
    }

    return bpb;
}

pub const DirEntry = struct {
    name: [8]u8,
    ext: [3]u8,
    attr: u8,
    reserved: u8,
    creation_time_tenth: u8,
    creation_time: u16,
    creation_date: u16,
    last_access_date: u16,
    first_cluster_high: u16,
    write_time: u16,
    write_date: u16,
    first_cluster_low: u16,
    file_size: u32,
};

pub const LfnState = struct {
    buf: [256]u8,
    active: bool,
    checksum: u8,
};

pub fn extract_lfn_part(buf: []const u8, start: usize, count: usize, out: []u8, out_offset: usize) void {
    for (0..count) |j| {
        if (out_offset + j >= out.len) return;
        const char_low = buf[start + j * 2];
        const char_high = buf[start + j * 2 + 1];
        if (char_low == 0 and char_high == 0) {
            out[out_offset + j] = 0;
            return;
        }
        out[out_offset + j] = if (char_high == 0) char_low else '?';
    }
}