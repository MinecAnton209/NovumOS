const std = @import("std");
const fat = @import("fat");
const ata = @import("fat_ata");

const Kind = enum { fat12, fat16 };

const Fs = struct {
    allocator: std.mem.Allocator,
    image: []u8,
    bpb: fat.BPB,

    fn deinit(self: *Fs) void {
        self.allocator.free(self.image);
        ata.test_image = &.{};
    }
};

// Builds a blank volume: a 1.44 MB FAT12 floppy layout and a 10 MB FAT16 layout
// whose cluster counts land on each side of the FAT12/FAT16 threshold.
fn setup(allocator: std.mem.Allocator, kind: Kind) !Fs {
    const total: u32 = switch (kind) {
        .fat12 => 2880,
        .fat16 => 20000,
    };
    const image = try allocator.alloc(u8, total * 512);
    errdefer allocator.free(image);
    @memset(image, 0);

    const boot = image[0..512];
    boot[0] = 0xEB;
    boot[1] = 0x3C;
    boot[2] = 0x90;
    @memcpy(boot[3..11], "CUBETEST");
    std.mem.writeInt(u16, boot[11..13], 512, .little);
    boot[13] = switch (kind) {
        .fat12 => 1,
        .fat16 => 4,
    };
    std.mem.writeInt(u16, boot[14..16], switch (kind) {
        .fat12 => 1,
        .fat16 => 4,
    }, .little);
    boot[16] = 2;
    std.mem.writeInt(u16, boot[17..19], switch (kind) {
        .fat12 => 224,
        .fat16 => 512,
    }, .little);
    std.mem.writeInt(u16, boot[19..21], @intCast(total), .little);
    boot[21] = 0xF8;
    std.mem.writeInt(u16, boot[22..24], switch (kind) {
        .fat12 => 9,
        .fat16 => 20,
    }, .little);
    std.mem.writeInt(u16, boot[24..26], 18, .little);
    std.mem.writeInt(u16, boot[26..28], 2, .little);
    @memcpy(boot[0x36..0x3E], switch (kind) {
        .fat12 => "FAT12   ",
        .fat16 => "FAT16   ",
    });
    boot[510] = 0x55;
    boot[511] = 0xAA;

    ata.test_image = image;
    ata.partition_lba = 0;
    fat.invalidate_bpb_cache(.Master);
    const bpb = fat.read_bpb(.Master) orelse return error.NotFormatted;
    if (!fat.format(.Master, bpb, null)) return error.FormatFailed;
    return .{ .allocator = allocator, .image = image, .bpb = bpb };
}

fn patternByte(i: usize) u8 {
    return 'a' + @as(u8, @intCast(i % 26));
}

fn fillPattern(buf: []u8) void {
    for (buf, 0..) |*b, i| b.* = patternByte(i);
}

fn readAll(allocator: std.mem.Allocator, bpb: fat.BPB, path: []const u8) ![]u8 {
    const size = fat.fat_size(.Master, bpb, 0, path);
    const buf = try allocator.alloc(u8, size);
    errdefer allocator.free(buf);
    const n = fat.read_file_bounded(.Master, bpb, 0, path, buf.ptr, size);
    try std.testing.expectEqual(@as(i32, @intCast(size)), n);
    return buf;
}

fn usedClusters(bpb: fat.BPB) u32 {
    const total: u32 = if (bpb.total_sectors_16 == 0) bpb.total_sectors_32 else bpb.total_sectors_16;
    const clusters = (total - bpb.first_data_sector) / bpb.sectors_per_cluster;
    var used: u32 = 0;
    var c: u32 = 2;
    while (c < clusters + 2) : (c += 1) {
        if (fat.get_fat_entry(.Master, bpb, c) != 0) used += 1;
    }
    return used;
}

fn clusterBytes(bpb: fat.BPB) u32 {
    return @as(u32, bpb.sectors_per_cluster) * 512;
}

fn testBpbDetection(kind: Kind, expected: fat.FatType) !void {
    var fs = try setup(std.testing.allocator, kind);
    defer fs.deinit();
    try std.testing.expectEqual(expected, fs.bpb.fat_type);
}

test "FAT12 volume is detected" {
    try testBpbDetection(.fat12, .FAT12);
}

test "FAT16 volume is detected" {
    try testBpbDetection(.fat16, .FAT16);
}

fn testMultiClusterRoundTrip(kind: Kind) !void {
    const allocator = std.testing.allocator;
    var fs = try setup(allocator, kind);
    defer fs.deinit();

    const data = try allocator.alloc(u8, 3000);
    defer allocator.free(data);
    fillPattern(data);
    try std.testing.expect(fat.write_file(.Master, fs.bpb, 0, "DATA.BIN", data));

    const back = try readAll(allocator, fs.bpb, "DATA.BIN");
    defer allocator.free(back);
    try std.testing.expectEqualSlices(u8, data, back);
}

test "FAT12 file spanning several clusters round-trips" {
    try testMultiClusterRoundTrip(.fat12);
}

test "FAT16 file spanning several clusters round-trips" {
    try testMultiClusterRoundTrip(.fat16);
}

fn testLongNameRoundTrip(kind: Kind) !void {
    const allocator = std.testing.allocator;
    var fs = try setup(allocator, kind);
    defer fs.deinit();

    const name = "Long Document Name.txt";
    try std.testing.expect(fat.write_file(.Master, fs.bpb, 0, name, "hello long name"));
    const back = try readAll(allocator, fs.bpb, name);
    defer allocator.free(back);
    try std.testing.expectEqualStrings("hello long name", back);
}

test "FAT12 long file name is stored through LFN entries" {
    try testLongNameRoundTrip(.fat12);
}

test "FAT16 long file name is stored through LFN entries" {
    try testLongNameRoundTrip(.fat16);
}

fn testOverwriteFreesClusters(kind: Kind) !void {
    var fs = try setup(std.testing.allocator, kind);
    defer fs.deinit();

    var data: [3000]u8 = undefined;
    fillPattern(&data);
    try std.testing.expect(fat.write_file(.Master, fs.bpb, 0, "DATA.BIN", &data));
    const cluster_size = clusterBytes(fs.bpb);
    try std.testing.expectEqual(@as(u32, (3000 + cluster_size - 1) / cluster_size), usedClusters(fs.bpb));

    try std.testing.expect(fat.write_file(.Master, fs.bpb, 0, "DATA.BIN", "small"));
    try std.testing.expectEqual(@as(u32, 1), usedClusters(fs.bpb));
}

test "FAT12 overwrite with shorter data frees the old chain" {
    try testOverwriteFreesClusters(.fat12);
}

test "FAT16 overwrite with shorter data frees the old chain" {
    try testOverwriteFreesClusters(.fat16);
}

fn testFatCopiesMatch(kind: Kind) !void {
    var fs = try setup(std.testing.allocator, kind);
    defer fs.deinit();

    var data: [3000]u8 = undefined;
    fillPattern(&data);
    try std.testing.expect(fat.write_file(.Master, fs.bpb, 0, "DATA.BIN", &data));

    const first = fs.bpb.first_fat_sector;
    const spf = fs.bpb.sectors_per_fat;
    var i: u32 = 0;
    while (i < spf) : (i += 1) {
        const primary = fs.image[(first + i) * 512 ..][0..512];
        const secondary = fs.image[(first + spf + i) * 512 ..][0..512];
        try std.testing.expectEqualSlices(u8, primary, secondary);
    }
}

test "FAT12 writes keep the second FAT copy identical" {
    try testFatCopiesMatch(.fat12);
}

test "FAT16 writes keep the second FAT copy identical" {
    try testFatCopiesMatch(.fat16);
}

fn testLseekFromChainStart(kind: Kind) !void {
    const allocator = std.testing.allocator;
    var fs = try setup(allocator, kind);
    defer fs.deinit();

    var data: [3000]u8 = undefined;
    fillPattern(&data);
    try std.testing.expect(fat.write_file(.Master, fs.bpb, 0, "DATA.BIN", &data));

    var handle = fat.fat_open(.Master, fs.bpb, 0, "DATA.BIN") orelse return error.OpenFailed;
    try std.testing.expectEqual(@as(i64, 2500), fat.fat_lseek(&handle, 2500, 0));
    try std.testing.expectEqual(@as(i64, 1600), fat.fat_lseek(&handle, 1600, 0));

    var out: [10]u8 = undefined;
    try std.testing.expectEqual(@as(i32, 10), fat.fat_gets(&handle, &out, out.len));
    try std.testing.expectEqualSlices(u8, data[1600..1610], &out);
}

test "FAT12 lseek twice positions from the start of the chain" {
    try testLseekFromChainStart(.fat12);
}

test "FAT16 lseek twice positions from the start of the chain" {
    try testLseekFromChainStart(.fat16);
}

fn testGetsCrossesSector(kind: Kind) !void {
    const allocator = std.testing.allocator;
    var fs = try setup(allocator, kind);
    defer fs.deinit();

    var data: [604]u8 = undefined;
    @memset(data[0..599], 'a');
    data[599] = '\n';
    @memcpy(data[600..], "tail");
    try std.testing.expect(fat.write_file(.Master, fs.bpb, 0, "LINES.TXT", &data));

    var handle = fat.fat_open(.Master, fs.bpb, 0, "LINES.TXT") orelse return error.OpenFailed;
    var out: [1000]u8 = undefined;
    const n = fat.fat_gets(&handle, &out, out.len);
    try std.testing.expectEqual(@as(i32, 600), n);
    try std.testing.expectEqualSlices(u8, data[0..600], out[0..600]);
}

test "FAT12 fat_gets returns a full line across a sector boundary" {
    try testGetsCrossesSector(.fat12);
}

test "FAT16 fat_gets returns a full line across a sector boundary" {
    try testGetsCrossesSector(.fat16);
}

fn testPutsKeepsNeighbours(kind: Kind) !void {
    const allocator = std.testing.allocator;
    var fs = try setup(allocator, kind);
    defer fs.deinit();

    var data: [1000]u8 = undefined;
    @memset(&data, 'x');
    try std.testing.expect(fat.write_file(.Master, fs.bpb, 0, "MID.TXT", &data));

    var handle = fat.fat_open(.Master, fs.bpb, 0, "MID.TXT") orelse return error.OpenFailed;
    try std.testing.expectEqual(@as(i64, 100), fat.fat_lseek(&handle, 100, 0));
    try std.testing.expectEqual(@as(i32, 5), fat.fat_puts(&handle, "HELLO", 5));

    @memcpy(data[100..105], "HELLO");
    const back = try readAll(allocator, fs.bpb, "MID.TXT");
    defer allocator.free(back);
    try std.testing.expectEqualSlices(u8, &data, back);
}

test "FAT12 mid-file puts leaves neighbouring bytes intact" {
    try testPutsKeepsNeighbours(.fat12);
}

test "FAT16 mid-file puts leaves neighbouring bytes intact" {
    try testPutsKeepsNeighbours(.fat16);
}

fn testCopyDirectorySpansClusters(kind: Kind) !void {
    const allocator = std.testing.allocator;
    var fs = try setup(allocator, kind);
    defer fs.deinit();

    try std.testing.expect(fat.create_directory(.Master, fs.bpb, 0, "SRC"));
    var name_buf: [16]u8 = undefined;
    var i: u32 = 0;
    while (i < 80) : (i += 1) {
        const path = try std.fmt.bufPrint(&name_buf, "SRC/F{d:0>2}.TXT", .{i});
        try std.testing.expect(fat.write_file(.Master, fs.bpb, 0, path, path["SRC/".len..]));
    }

    try std.testing.expect(fat.copy_directory(.Master, fs.bpb, 0, "SRC", "DST"));

    i = 0;
    while (i < 80) : (i += 1) {
        const name = try std.fmt.bufPrint(&name_buf, "DST/F{d:0>2}.TXT", .{i});
        const back = try readAll(allocator, fs.bpb, name);
        defer allocator.free(back);
        try std.testing.expectEqualStrings(name["DST/".len..], back);
    }
}

test "FAT12 copy_directory copies entries from a multi-cluster directory" {
    try testCopyDirectorySpansClusters(.fat12);
}

test "FAT16 copy_directory copies entries from a multi-cluster directory" {
    try testCopyDirectorySpansClusters(.fat16);
}

test "FAT12 entries use the standard packed layout, including a sector-boundary straddle" {
    var fs = try setup(std.testing.allocator, .fat12);
    defer fs.deinit();
    const fat_base = @as(usize, fs.bpb.first_fat_sector) * 512;

    // Cluster 2 is even: its FAT byte offset is 3, and bits 8-11 sit in the low nibble of byte 4.
    fat.set_fat_entry(.Master, fs.bpb, 2, 0x123);
    try std.testing.expectEqual(@as(u8, 0x23), fs.image[fat_base + 3]);
    try std.testing.expectEqual(@as(u8, 0x01), fs.image[fat_base + 4] & 0x0F);
    try std.testing.expectEqual(@as(u32, 0x123), fat.get_fat_entry(.Master, fs.bpb, 2));

    // Cluster 341 is odd and starts at FAT byte 511, so its high byte is the first byte of the next sector.
    fat.set_fat_entry(.Master, fs.bpb, 341, 0xABC);
    try std.testing.expectEqual(@as(u8, 0xC0), fs.image[fat_base + 511] & 0xF0);
    try std.testing.expectEqual(@as(u8, 0xAB), fs.image[fat_base + 512]);
    try std.testing.expectEqual(@as(u32, 0xABC), fat.get_fat_entry(.Master, fs.bpb, 341));
}
