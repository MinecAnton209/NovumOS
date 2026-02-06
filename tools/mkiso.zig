const std = @import("std");

// ISO 9660 / El Torito structures constants
const SECTOR_SIZE = 2048;
const SYSTEM_ID = "NOVUMOS_BOOT";
const VOLUME_ID = "NOVUMOS_INSTALL";

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    if (args.len != 3) {
        std.debug.print("Usage: {s} <input.img> <output.iso>\n", .{args[0]});
        return error.InvalidArgs;
    }

    const input_path = args[1];
    const output_path = args[2];

    std.debug.print("Creating ISO: {s} -> {s}\n", .{ input_path, output_path });

    // Open compressed input (the floppy image)
    const file = try std.fs.cwd().openFile(input_path, .{});
    defer file.close();
    const input_size = try file.getEndPos();
    const input_data = try allocator.alloc(u8, input_size);

    var total_read: usize = 0;
    while (total_read < input_size) {
        const bytes_read = try file.read(input_data[total_read..]);
        if (bytes_read == 0) break;
        total_read += bytes_read;
    }

    // Calculate sectors needed for the image
    const image_sectors = (input_size + SECTOR_SIZE - 1) / SECTOR_SIZE;

    // We need sectors for:
    // 0-15: System Area (unused/reserved) - 16 sectors
    // 16: Primary Volume Descriptor (PVD)
    // 17-18: Reserved/Boot Record
    // 19: Boot Catalog
    // 20+: The Floppy Image Data

    // Layout:
    // Sector 0-15: Zeroes
    // Sector 16: PVD
    // Sector 17: Boot Record (El Torito)
    // Sector 18: Terminator
    // Sector 19: Boot Catalog
    // Sector 20...: Image Data

    const iso_size_sectors = 20 + image_sectors;
    const iso_total_size = iso_size_sectors * SECTOR_SIZE;

    const out_file = try std.fs.cwd().createFile(output_path, .{});
    defer out_file.close();

    // 1. Write System Area (Sectors 0-15) - 32KB of zeros
    try writeZeros(out_file, 16 * SECTOR_SIZE);

    // 2. Primary Volume Descriptor (Sector 16)
    var pvd = try allocator.alloc(u8, SECTOR_SIZE);
    @memset(pvd, 0);
    pvd[0] = 1; // Type: Primary
    @memcpy(pvd[1..6], "CD001"); // Identifier
    pvd[6] = 1; // Version

    // System ID (byte 8, 32 bytes)
    @memcpy(pvd[8 .. 8 + SYSTEM_ID.len], SYSTEM_ID);
    // Volume ID (byte 40, 32 bytes)
    @memcpy(pvd[40 .. 40 + VOLUME_ID.len], VOLUME_ID);

    // Volume Space Size (byte 80, dual endian)
    setBothEndian32(pvd, 80, @intCast(iso_size_sectors));

    // Logic Block Size (byte 120, dual endian) = 2048
    setBothEndian16(pvd, 120, 2048);

    // Path Table Size (byte 132) - 0 for now as we have no file tree
    setBothEndian32(pvd, 132, 0);

    // Root Directory Record (byte 156) - Minimal dummy
    pvd[156] = 34; // Len

    // Volume Set Size (byte 120) - 1
    setBothEndian16(pvd, 120, 2048);

    // Standard version
    pvd[881] = 1;

    try out_file.writeAll(pvd);

    // 3. Boot Record (Sector 17)
    var br = try allocator.alloc(u8, SECTOR_SIZE);
    @memset(br, 0);
    br[0] = 0; // Boot Record Indicator
    @memcpy(br[1..6], "CD001");
    br[6] = 1; // Version
    @memcpy(br[7..39], "EL TORITO SPECIFICATION" ++ ([1]u8{0} ** 9)); // System ID

    // Pointer to Boot Catalog (Sector 19)
    setLittleEndian32(br, 0x47, 19);

    try out_file.writeAll(br);

    // 4. Volume Descriptor Terminator (Sector 18)
    var term = try allocator.alloc(u8, SECTOR_SIZE);
    @memset(term, 0);
    term[0] = 255;
    @memcpy(term[1..6], "CD001");
    term[6] = 1;
    try out_file.writeAll(term);

    // 5. Boot Catalog (Sector 19)
    var catalog = try allocator.alloc(u8, SECTOR_SIZE);
    @memset(catalog, 0);

    // Validation Entry (First 32 bytes)
    catalog[0] = 1; // Header ID
    catalog[1] = 0; // Platform ID (80x86)

    // Checksum
    var sum: u32 = 0;
    // Calc checksum later? It's just a sum of words.
    // Actually simpler: 0x55AA signature at offset 0x1E
    catalog[0x1E] = 0x55;
    catalog[0x1F] = 0xAA;

    // Calc checksum
    var i: usize = 0;
    while (i < 32) : (i += 2) {
        const val = @as(u16, catalog[i]) | (@as(u16, catalog[i + 1]) << 8);
        sum += val;
    }
    // Adjust checksum to be 0 (mod 65536)
    // But we already wrote bytes. The checksum entry is offset 28 (0x1C).
    // Let's redo.
    // Validation Entry is mostly static.
    // ID: 01, Platform: 00, Reserved: 00 00, ID: ..., Checksum: ?, 55 AA

    // Initial Entry (Default Entry) - starts at offset 32 (0x20)
    catalog[32] = 0x88; // Bootable
    catalog[33] = 0x02; // Media Type: 1.44MB Floppy (0x02)
    catalog[34] = 0; // Load Segment (0=7C0)
    catalog[35] = 0; // System Type
    catalog[36] = 0; // Unused

    // Sector Count (1 Virtual Sector = 512 bytes?)
    // Spec says: "Sector Count: This is the number of 512-byte virtual sectors to load"
    // Our image is input_size.
    const virt_sectors = (input_size + 511) / 512;
    catalog[37] = @intCast(virt_sectors & 0xFF);
    catalog[38] = @intCast((virt_sectors >> 8) & 0xFF);

    // Load RBA (Start Sector of Image) = 20
    setLittleEndian32(catalog, 32 + 8, 20);

    // Fix checksum for Validation Entry
    // The sum of all 16-bit words in the first 32 bytes must be 0.
    // 01 00 (0x0001) + ... + 55 AA (0xAA55)
    // We didn't set ID string, so it's mostly 0s.
    // Words:
    // 0: 01 00 = 0x0001
    // 1-13: 0
    // 14: Checksum
    // 15: 55 AA = 0xAA55
    // Sum = 1 + 0xAA55 = 0xAA56
    // We need 0x10000 - 0xAA56 = 0x55AA
    // So Checksum word = 0x55AA?

    // 0x0001 + 0 + X + 0xAA55 = 0 (mod 10000)
    // X = -0xAA56 = 0x55AA.
    catalog[0x1C] = 0xAA;
    catalog[0x1D] = 0x55;

    try out_file.writeAll(catalog);

    // 6. Write Image Data (Sector 20+)
    try out_file.writeAll(input_data);

    // Pad last sector to 2048 if needed
    const written_so_far = input_size;
    const padding = (SECTOR_SIZE - (written_so_far % SECTOR_SIZE)) % SECTOR_SIZE;
    if (padding > 0) {
        try writeZeros(out_file, padding);
    }

    std.debug.print("Success! Created {s} ({d} bytes)\n", .{ output_path, iso_total_size });
}

fn writeZeros(file: std.fs.File, count: usize) !void {
    const buffer = try std.heap.page_allocator.alloc(u8, 4096);
    defer std.heap.page_allocator.free(buffer);
    @memset(buffer, 0);

    var remaining = count;
    while (remaining > 0) {
        const to_write = @min(remaining, buffer.len);
        try file.writeAll(buffer[0..to_write]);
        remaining -= to_write;
    }
}

fn setBothEndian16(buf: []u8, offset: usize, val: u16) void {
    buf[offset] = @intCast(val & 0xFF);
    buf[offset + 1] = @intCast((val >> 8) & 0xFF);
    buf[offset + 2] = @intCast((val >> 8) & 0xFF);
    buf[offset + 3] = @intCast(val & 0xFF);
}

fn setBothEndian32(buf: []u8, offset: usize, val: u32) void {
    // Little Endian
    buf[offset] = @intCast(val & 0xFF);
    buf[offset + 1] = @intCast((val >> 8) & 0xFF);
    buf[offset + 2] = @intCast((val >> 16) & 0xFF);
    buf[offset + 3] = @intCast((val >> 24) & 0xFF);
    // Big Endian
    buf[offset + 4] = @intCast((val >> 24) & 0xFF);
    buf[offset + 5] = @intCast((val >> 16) & 0xFF);
    buf[offset + 6] = @intCast((val >> 8) & 0xFF);
    buf[offset + 7] = @intCast(val & 0xFF);
}

fn setLittleEndian32(buf: []u8, offset: usize, val: u32) void {
    buf[offset] = @intCast(val & 0xFF);
    buf[offset + 1] = @intCast((val >> 8) & 0xFF);
    buf[offset + 2] = @intCast((val >> 16) & 0xFF);
    buf[offset + 3] = @intCast((val >> 24) & 0xFF);
}
