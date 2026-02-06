// Disk Management Commands
const common = @import("common.zig");
const ata = @import("../drivers/ata.zig");

pub fn lsdsk() void {
    common.printZ("Scanning for ATA disks...\n");
    common.printZ("NUM | SIZE (MB) | FILESYSTEM         | STATUS\n");
    common.printZ("----------------------------------------------\n");

    var drive_idx: u8 = 0;
    while (drive_idx < 2) : (drive_idx += 1) {
        const drive = if (drive_idx == 0) ata.Drive.Master else ata.Drive.Slave;
        const total_sectors = ata.identify(drive);

        if (total_sectors > 0) {
            common.printNum(@intCast(drive_idx));
            common.printZ("   | ");

            const size_mb = (total_sectors * 512) / (1024 * 1024);
            common.printNum(@intCast(size_mb));
            common.printZ("       | ");

            // Check sector 0 for FS
            var buffer: [512]u8 = undefined;
            ata.read_sector(drive, 0, &buffer);

            if (buffer[510] == 0x55 and buffer[511] == 0xAA) {
                // Check for FAT
                if (common.std_mem_eql(buffer[0x36..0x3E], "FAT12   ")) {
                    common.printZ("FAT12              ");
                } else if (common.std_mem_eql(buffer[0x36..0x3E], "FAT16   ")) {
                    common.printZ("FAT16              ");
                } else if (common.std_mem_eql(buffer[0x52..0x5A], "FAT32   ")) {
                    common.printZ("FAT32              ");
                } else {
                    common.printZ("Unknown            ");
                }
            } else {
                common.printZ("None               ");
            }

            common.printZ("| ");
            if (drive_idx == 0) {
                common.printZ("System\n");
            } else if (common.selected_disk == @as(i32, @intCast(drive_idx))) {
                common.printZ("Active\n");
            } else {
                common.printZ("Ready\n");
            }
        }
    }
}

pub fn mkfs_fat12(drive_num: u8) void {
    if (drive_num >= 2) {
        common.printZ("Error: Invalid drive number (0-1)\n");
        return;
    }

    const drive = if (drive_num == 0) ata.Drive.Master else ata.Drive.Slave;
    const total_sectors = ata.identify(drive);

    if (total_sectors == 0) {
        common.printZ("Error: Drive not found\n");
        return;
    }

    // FAT12 Limit: ~4084 clusters. With 8 sectors per cluster (4KB),
    // max size is roughly 16MB.
    if (total_sectors > 32768) { // 32768 sectors * 512 bytes = 16MB
        common.printZ("Error: Disk too large for FAT12 (Max 16MB)\n");
        return;
    }

    common.printZ("Formatting drive ");
    common.printNum(@intCast(drive_num));
    common.printZ(" with FAT12...\n");

    var boot_sector: [512]u8 = [_]u8{0} ** 512;

    // JMP 0x3C, NOP
    boot_sector[0] = 0xEB;
    boot_sector[1] = 0x3C;
    boot_sector[2] = 0x90;

    // OEM Name
    const oem = "NOVUMOS ";
    for (oem, 0..) |c, i| boot_sector[3 + i] = c;

    // BPB
    boot_sector[11] = 0x00;
    boot_sector[12] = 0x02; // Bytes per sector (512)
    boot_sector[13] = 0x08; // Sectors per cluster (8 -> 4KB)
    boot_sector[14] = 0x01;
    boot_sector[15] = 0x00; // Reserved sectors (1)
    boot_sector[16] = 0x02; // Number of FATs (2)
    boot_sector[17] = 0xE0;
    boot_sector[18] = 0x00; // Root entry count (224)

    if (total_sectors < 65536) {
        boot_sector[19] = @intCast(total_sectors & 0xFF);
        boot_sector[20] = @intCast((total_sectors >> 8) & 0xFF);
    } else {
        boot_sector[19] = 0;
        boot_sector[20] = 0;
        boot_sector[32] = @intCast(total_sectors & 0xFF);
        boot_sector[33] = @intCast((total_sectors >> 8) & 0xFF);
        boot_sector[34] = @intCast((total_sectors >> 16) & 0xFF);
        boot_sector[35] = @intCast((total_sectors >> 24) & 0xFF);
    }

    boot_sector[21] = 0xF8; // Media descriptor (Hard Disk)

    // Sectors per FAT (rough estimate for FAT12)
    // Max FAT12 clusters ~ 4084. 4084 * 1.5 = 6126 bytes = 12 sectors.
    boot_sector[22] = 0x0C;
    boot_sector[23] = 0x00; // 12 sectors per FAT

    boot_sector[24] = 0x20;
    boot_sector[25] = 0x00; // Sectors per track (32)
    boot_sector[26] = 0x40;
    boot_sector[27] = 0x00; // Heads (64)

    // EBPB
    boot_sector[36] = 0x80; // Drive number
    boot_sector[38] = 0x29; // Signature
    boot_sector[39] = 0x78;
    boot_sector[40] = 0x56;
    boot_sector[41] = 0x34;
    boot_sector[42] = 0x12; // Serial

    const label = "NOVUMOS FAT12";
    for (label, 0..) |c, i| boot_sector[43 + i] = c;

    const fstype = "FAT12   ";
    for (fstype, 0..) |c, i| boot_sector[54 + i] = c;

    boot_sector[510] = 0x55;
    boot_sector[511] = 0xAA;

    ata.write_sector(drive, 0, &boot_sector);

    // Clear FATs (2 FATs of 12 sectors each)
    var zero_sector: [512]u8 = [_]u8{0} ** 512;
    // FAT1st byte: Media Descriptor, following bytes: 0xFF
    var fat_start_sector: [512]u8 = [_]u8{0} ** 512;
    fat_start_sector[0] = 0xF8;
    fat_start_sector[1] = 0xFF;
    fat_start_sector[2] = 0xFF;

    common.printZ("Initializing FAT tables...\n");
    var i: u32 = 0;
    while (i < 24) : (i += 1) {
        if (i == 0 or i == 12) {
            ata.write_sector(drive, 1 + i, &fat_start_sector);
        } else {
            ata.write_sector(drive, 1 + i, &zero_sector);
        }
    }

    // Clear Root Directory (224 entries * 32 bytes = 7168 bytes = 14 sectors)
    common.printZ("Initializing Root Directory...\n");
    i = 0;
    while (i < 14) : (i += 1) {
        ata.write_sector(drive, 25 + i, &zero_sector);
    }

    common.printZ("Format complete.\n");
}

pub fn mkfs_fat16(drive_num: u8) void {
    if (drive_num >= 2) {
        common.printZ("Error: Invalid drive number (0-1)\n");
        return;
    }

    const drive = if (drive_num == 0) ata.Drive.Master else ata.Drive.Slave;
    const total_sectors = ata.identify(drive);

    if (total_sectors == 0) {
        common.printZ("Error: Drive not found\n");
        return;
    }

    // FAT16 Limit: Min 4085 clusters, Max 65525 clusters.
    // We'll use 8 sectors per cluster (4KB) as default.
    // 4085 * 8 = 32680 sectors (~16MB min)
    // 65525 * 8 = 524200 sectors (~256MB max with this cluster size)
    if (total_sectors < 32680) {
        common.printZ("Error: Disk too small for FAT16 (Min 16MB required with 4KB clusters)\n");
        return;
    }
    if (total_sectors > 4194304) { // 2GB limit for FAT16
        common.printZ("Error: Disk too large for FAT16 (Max 2GB)\n");
        return;
    }

    common.printZ("Formatting drive ");
    common.printNum(@intCast(drive_num));
    common.printZ(" with FAT16...\n");

    var boot_sector: [512]u8 = [_]u8{0} ** 512;

    boot_sector[0] = 0xEB;
    boot_sector[1] = 0x3C;
    boot_sector[2] = 0x90;
    const oem = "NOVUMOS ";
    for (oem, 0..) |c, i| boot_sector[3 + i] = c;

    boot_sector[11] = 0x00;
    boot_sector[12] = 0x02; // 512 bytes per sector

    // Choose sectors per cluster based on size
    var spc: u8 = 8; // 4KB
    if (total_sectors > 1048576) spc = 32; // > 512MB, use 16KB clusters
    if (total_sectors > 2097152) spc = 64; // > 1GB, use 32KB clusters
    boot_sector[13] = spc;

    boot_sector[14] = 0x01;
    boot_sector[15] = 0x00; // 1 reserved sector
    boot_sector[16] = 0x02; // 2 FATs
    boot_sector[17] = 0x00;
    boot_sector[18] = 0x02; // 512 root entries

    if (total_sectors < 65536) {
        boot_sector[19] = @intCast(total_sectors & 0xFF);
        boot_sector[20] = @intCast((total_sectors >> 8) & 0xFF);
    } else {
        boot_sector[19] = 0;
        boot_sector[20] = 0;
        boot_sector[32] = @intCast(total_sectors & 0xFF);
        boot_sector[33] = @intCast((total_sectors >> 8) & 0xFF);
        boot_sector[34] = @intCast((total_sectors >> 16) & 0xFF);
        boot_sector[35] = @intCast((total_sectors >> 24) & 0xFF);
    }

    boot_sector[21] = 0xF8;

    // Calculate sectors per FAT: (clusters * 2) / 512
    const total_clusters = total_sectors / spc;
    const fat_size = @as(u16, @intCast((total_clusters * 2 + 511) / 512));
    boot_sector[22] = @intCast(fat_size & 0xFF);
    boot_sector[23] = @intCast((fat_size >> 8) & 0xFF);

    boot_sector[24] = 0x20;
    boot_sector[25] = 0x00;
    boot_sector[26] = 0x40;
    boot_sector[27] = 0x00;
    boot_sector[36] = 0x80;
    boot_sector[38] = 0x29;
    boot_sector[39] = 0xEF;
    boot_sector[40] = 0xBE;
    boot_sector[41] = 0xAD;
    boot_sector[42] = 0xDE;

    const label = "NOVUMOS FAT16";
    for (label, 0..) |c, i| boot_sector[43 + i] = c;
    const fstype = "FAT16   ";
    for (fstype, 0..) |c, i| boot_sector[54 + i] = c;

    boot_sector[510] = 0x55;
    boot_sector[511] = 0xAA;

    ata.write_sector(drive, 0, &boot_sector);

    var fat_start: [512]u8 = [_]u8{0} ** 512;
    fat_start[0] = 0xF8;
    fat_start[1] = 0xFF;
    fat_start[2] = 0xFF;
    fat_start[3] = 0xFF;

    common.printZ("Initializing FAT tables...\n");
    var zero_sector: [512]u8 = [_]u8{0} ** 512;
    var i: u32 = 0;
    while (i < fat_size * 2) : (i += 1) {
        if (i == 0 or i == fat_size) {
            ata.write_sector(drive, 1 + i, &fat_start);
        } else {
            ata.write_sector(drive, 1 + i, &zero_sector);
        }
    }

    common.printZ("Initializing Root Directory...\n");
    i = 0;
    while (i < 32) : (i += 1) { // 512 entries * 32 bytes = 16KB = 32 sectors
        ata.write_sector(drive, 1 + (fat_size * 2) + i, &zero_sector);
    }

    common.printZ("Format complete.\n");
}

pub fn mkfs_fat32(drive_num: u8) void {
    if (drive_num >= 2) {
        common.printZ("Error: Invalid drive number (0-1)\n");
        return;
    }

    const drive = if (drive_num == 0) ata.Drive.Master else ata.Drive.Slave;
    const total_sectors = ata.identify(drive);

    if (total_sectors == 0) {
        common.printZ("Error: Drive not found\n");
        return;
    }

    // FAT32 Limits:
    // - Partition: Standard u32 LBA @ 512B/sector = 2 TB (theoretical 16 TB with 4KB sectors)
    // - File: 4 GB (u32 file_size)
    if (total_sectors < 65536) {
        common.printZ("Error: Disk too small for FAT32 (Min 32MB recommended)\n");
        return;
    }

    common.printZ("Formatting drive ");
    common.printNum(@intCast(drive_num));
    common.printZ(" with FAT32...\n");

    var boot_sector: [512]u8 = [_]u8{0} ** 512;
    boot_sector[0] = 0xEB;
    boot_sector[1] = 0x34;
    boot_sector[2] = 0x90;
    const oem = "NOVUMOS ";
    for (oem, 0..) |c, j| boot_sector[3 + j] = c;

    boot_sector[11] = 0x00;
    boot_sector[12] = 0x02; // 512 bytes per sector

    // Choose sectors per cluster based on disk size
    var spc: u8 = 8; // 4KB
    if (total_sectors > 16777216) spc = 16; // > 8GB
    if (total_sectors > 33554432) spc = 32; // > 16GB
    if (total_sectors > 67108864) spc = 64; // > 32GB
    boot_sector[13] = spc;

    const reserved_sectors: u16 = 32;
    boot_sector[14] = @intCast(reserved_sectors & 0xFF);
    boot_sector[15] = @intCast(reserved_sectors >> 8);
    boot_sector[16] = 0x02; // 2 FATs
    boot_sector[17] = 0;
    boot_sector[18] = 0; // Root entries 0 for FAT32
    boot_sector[19] = 0;
    boot_sector[20] = 0;
    boot_sector[21] = 0xF8;
    boot_sector[22] = 0;
    boot_sector[23] = 0; // FAT16 size 0

    boot_sector[32] = @intCast(total_sectors & 0xFF);
    boot_sector[33] = @intCast((total_sectors >> 8) & 0xFF);
    boot_sector[34] = @intCast((total_sectors >> 16) & 0xFF);
    boot_sector[35] = @intCast((total_sectors >> 24) & 0xFF);

    // Calculate FAT size
    const data_sectors = total_sectors - reserved_sectors;
    const total_clusters = data_sectors / spc;
    const fat_size = (total_clusters * 4 + 511) / 512;

    boot_sector[36] = @intCast(fat_size & 0xFF);
    boot_sector[37] = @intCast((fat_size >> 8) & 0xFF);
    boot_sector[38] = @intCast((fat_size >> 16) & 0xFF);
    boot_sector[39] = @intCast((fat_size >> 24) & 0xFF);

    boot_sector[44] = 2; // Root cluster starts at 2
    boot_sector[48] = 1; // FSInfo sector
    boot_sector[50] = 6; // Backup boot sector (standard)

    boot_sector[66] = 0x29;
    boot_sector[67] = 0x78;
    boot_sector[68] = 0x56;
    boot_sector[69] = 0x34;
    boot_sector[70] = 0x12;
    const label = "NOVUMOS F32";
    for (label, 0..) |c, j| boot_sector[71 + j] = c;
    const fstype = "FAT32   ";
    for (fstype, 0..) |c, j| boot_sector[82 + j] = c;

    boot_sector[510] = 0x55;
    boot_sector[511] = 0xAA;
    ata.write_sector(drive, 0, &boot_sector);

    // Clear FAT tables
    var zero_sector: [512]u8 = [_]u8{0} ** 512;
    common.printZ("Initializing FAT tables...\n");
    var i: u32 = 0;
    while (i < fat_size * 2) : (i += 1) {
        if (i == 0 or i == fat_size) {
            var fat_start: [512]u8 = [_]u8{0} ** 512;
            fat_start[0] = 0xF8;
            fat_start[1] = 0xFF;
            fat_start[2] = 0xFF;
            fat_start[3] = 0x0F; // Media
            fat_start[4] = 0xFF;
            fat_start[5] = 0xFF;
            fat_start[6] = 0xFF;
            fat_start[7] = 0x0F; // Partition
            fat_start[8] = 0xFF;
            fat_start[9] = 0xFF;
            fat_start[10] = 0xFF;
            fat_start[11] = 0x0F; // Root EOC
            ata.write_sector(drive, reserved_sectors + i, &fat_start);
        } else {
            ata.write_sector(drive, reserved_sectors + i, &zero_sector);
        }
    }

    // Initialize Root Directory Cluster (Clear cluster 2)
    common.printZ("Initializing Root Directory Cluster...\n");
    const root_lba = reserved_sectors + (2 * fat_size);
    i = 0;
    while (i < spc) : (i += 1) {
        ata.write_sector(drive, root_lba + i, &zero_sector);
    }

    common.printZ("Format complete. (Note: 4GB Max File Size Supported)\n");
}
