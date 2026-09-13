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

const FatType = enum { Fat12, Fat16, Fat32 };

/// Unified mkfs for FAT12/16/32. Comptime dispatch on `ft` keeps all
/// FAT-specific logic inline while eliminating the three-way copy-paste.
pub fn mkfs(drive_num: u8, comptime ft: FatType) void {
    const fmt_name = comptime switch (ft) {
        .Fat12 => "FAT12",
        .Fat16 => "FAT16",
        .Fat32 => "FAT32",
    };

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

    // --- size validation (runtime: depends on total_sectors) -----------
    const too_large: bool = switch (ft) {
        .Fat12 => total_sectors > 32768,
        .Fat16 => total_sectors > 4194304,
        .Fat32 => false,
    };
    if (too_large) {
        const msg = comptime switch (ft) {
            .Fat12 => "Disk too large for FAT12 (Max 16MB)",
            .Fat16 => "Disk too large for FAT16 (Max 2GB)",
            .Fat32 => unreachable,
        };
        common.printZ("Error: ");
        common.printZ(msg);
        common.printZ("\n");
        return;
    }
    const too_small: bool = switch (ft) {
        .Fat12 => false,
        .Fat16 => total_sectors < 32680,
        .Fat32 => total_sectors < 65536,
    };
    if (too_small) {
        switch (ft) {
            .Fat16 => common.printZ("Error: Disk too small for FAT16 (Min 16MB required with 4KB clusters)\n"),
            .Fat32 => common.printZ("Error: Disk too small for FAT32 (Min 32MB recommended)\n"),
            .Fat12 => unreachable,
        }
        return;
    }

    common.printZ("Formatting drive ");
    common.printNum(@intCast(drive_num));
    common.printZ(" with ");
    common.printZ(fmt_name);
    common.printZ("...\n");

    var boot_sector: [512]u8 = [_]u8{0} ** 512;

    // --- boot jump & OEM (same for all FAT variants) -------------------
    boot_sector[0] = 0xEB;
    boot_sector[1] = comptime switch (ft) { .Fat32 => 0x34, else => 0x3C };
    boot_sector[2] = 0x90;
    const oem = "NOVUMOS ";
    for (oem, 0..) |c, i| boot_sector[3 + i] = c;

    // --- BPB common fields ---------------------------------------------
    boot_sector[11] = 0x00;
    boot_sector[12] = 0x02; // 512 bytes per sector

    const spc: u8 = switch (ft) {
        .Fat12 => 8,
        .Fat16 => blk: {
            var s: u8 = 8;
            if (total_sectors > 1048576) s = 32;
            if (total_sectors > 2097152) s = 64;
            break :blk s;
        },
        .Fat32 => blk: {
            var s: u8 = 8;
            if (total_sectors > 16777216) s = 16;
            if (total_sectors > 33554432) s = 32;
            if (total_sectors > 67108864) s = 64;
            break :blk s;
        },
    };
    boot_sector[13] = spc;

    const reserved_sectors: u16 = comptime switch (ft) {
        .Fat12 => 1,
        .Fat16 => 1,
        .Fat32 => 32,
    };

    const root_entry_count: u16 = comptime switch (ft) {
        .Fat12 => 224,
        .Fat16 => 512,
        .Fat32 => 0,
    };

    boot_sector[14] = @intCast(reserved_sectors & 0xFF);
    boot_sector[15] = @intCast((reserved_sectors >> 8) & 0xFF);
    boot_sector[16] = 0x02; // 2 FATs
    boot_sector[21] = 0xF8; // Media descriptor

    // --- total sectors / root entry count ------------------------------
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

    // --- FAT-size -------------------------------------------------------
    const fat_size: u32 = switch (ft) {
        .Fat12 => 12, // fixed estimate: ~6126 bytes
        .Fat16 => blk: {
            const total_clusters = total_sectors / spc;
            break :blk @as(u32, (total_clusters * 2 + 511) / 512);
        },
        .Fat32 => blk: {
            const data_sectors = total_sectors - reserved_sectors;
            const total_clusters = data_sectors / spc;
            break :blk (total_clusters * 4 + 511) / 512;
        },
    };

    switch (ft) {
        .Fat12 => {
            boot_sector[17] = 0xE0; // root entry count high byte (224)
            boot_sector[18] = 0x00;
            boot_sector[22] = 0x0C; // 12 sectors per FAT
            boot_sector[23] = 0x00;
        },
        .Fat16 => {
            boot_sector[17] = 0x00;
            boot_sector[18] = @intCast(root_entry_count & 0xFF);
            boot_sector[22] = @intCast(fat_size & 0xFF);
            boot_sector[23] = @intCast((fat_size >> 8) & 0xFF);
        },
        .Fat32 => {
            boot_sector[17] = 0x00;
            boot_sector[18] = 0;
            boot_sector[19] = 0;
            boot_sector[20] = 0;
            boot_sector[21] = 0xF8;
            boot_sector[22] = 0;
            boot_sector[23] = 0; // FAT16 size 0 (FAT32 uses root_clus)
            boot_sector[32] = @intCast(total_sectors & 0xFF);
            boot_sector[33] = @intCast((total_sectors >> 8) & 0xFF);
            boot_sector[34] = @intCast((total_sectors >> 16) & 0xFF);
            boot_sector[35] = @intCast((total_sectors >> 24) & 0xFF);
            boot_sector[36] = @intCast(fat_size & 0xFF);
            boot_sector[37] = @intCast((fat_size >> 8) & 0xFF);
            boot_sector[38] = @intCast((fat_size >> 16) & 0xFF);
            boot_sector[39] = @intCast((fat_size >> 24) & 0xFF);
            boot_sector[44] = 2; // Root cluster starts at 2
            boot_sector[48] = 1; // FSInfo sector
            boot_sector[50] = 6; // Backup boot sector
        },
    }

    // --- physical drive + serial + label --------------------------------
    switch (ft) {
        .Fat12 => {
            boot_sector[24] = 0x20;
            boot_sector[25] = 0x00; // Sectors per track (32)
            boot_sector[26] = 0x40;
            boot_sector[27] = 0x00; // Heads (64)
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
        },
        .Fat16 => {
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
        },
        .Fat32 => {
            boot_sector[66] = 0x29;
            boot_sector[67] = 0x78;
            boot_sector[68] = 0x56;
            boot_sector[69] = 0x34;
            boot_sector[70] = 0x12;
            const label = "NOVUMOS F32";
            for (label, 0..) |c, j| boot_sector[71 + j] = c;
            const fstype = "FAT32   ";
            for (fstype, 0..) |c, j| boot_sector[82 + j] = c;
        },
    }

    boot_sector[510] = 0x55;
    boot_sector[511] = 0xAA;
    ata.write_sector(drive, 0, &boot_sector);

    // --- FAT tables + root directory ------------------------------------
    const zero_sector: [512]u8 = [_]u8{0} ** 512;
    var fat_start: [512]u8 = [_]u8{0} ** 512;
    fat_start[0] = 0xF8;
    fat_start[1] = 0xFF;
    fat_start[2] = 0xFF;

    common.printZ("Initializing FAT tables...\n");
    var i: u32 = 0;
    while (i < fat_size * 2) : (i += 1) {
        const write_sector = switch (ft) {
            .Fat12 => 1 + i,                     // FAT12 ignores fat_size scaling
            .Fat16, .Fat32 => reserved_sectors + i, // FAT16/32 respect reserved_sectors
        };
        if (i == 0 or i == fat_size) {
            const media_byte = comptime switch (ft) {
                .Fat12 => 3,
                .Fat16 => 4,
                .Fat32 => 12,
            };
            // FAT-type-specific leading media bytes
            var fs: [512]u8 = [_]u8{0} ** 512;
            fs[0] = 0xF8;
            var j: u32 = 1;
            while (j < media_byte) : (j += 1) fs[j] = 0xFF;
            if (ft == .Fat32) {
                fs[3] = 0x0F; fs[4] = 0xFF; fs[5] = 0xFF;
                fs[6] = 0x0F; fs[7] = 0xFF; fs[8] = 0xFF;
                fs[9] = 0x0F; fs[10] = 0xFF; fs[11] = 0x0F; // Root EOC
            }
            ata.write_sector(drive, write_sector, &fs);
        } else {
            ata.write_sector(drive, write_sector, &zero_sector);
        }
    }

    switch (ft) {
        .Fat12 => {
            common.printZ("Initializing Root Directory...\n");
            i = 0;
            while (i < 14) : (i += 1) { // 224 entries * 32 bytes = 14 sectors
                ata.write_sector(drive, 25 + i, &zero_sector);
            }
        },
        .Fat16 => {
            common.printZ("Initializing Root Directory...\n");
            i = 0;
            while (i < 32) : (i += 1) {
                ata.write_sector(drive, 1 + (fat_size * 2) + i, &zero_sector);
            }
        },
        .Fat32 => {
            common.printZ("Initializing Root Directory Cluster...\n");
            const root_lba = reserved_sectors + (2 * fat_size);
            i = 0;
            while (i < spc) : (i += 1) {
                ata.write_sector(drive, root_lba + i, &zero_sector);
            }
        },
    }

    common.printZ("Format complete.\n");
}

/// Thin wrapper so existing call sites stay stable.
pub fn mkfs_fat12(drive_num: u8) void { mkfs(drive_num, .Fat12); }
pub fn mkfs_fat16(drive_num: u8) void { mkfs(drive_num, .Fat16); }
pub fn mkfs_fat32(drive_num: u8) void { mkfs(drive_num, .Fat32); }
