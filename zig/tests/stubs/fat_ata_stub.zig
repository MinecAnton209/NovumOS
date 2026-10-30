// Host-test stub for zig/drivers/ata.zig: sectors come from an in-memory image.
pub const Drive = enum(u1) {
    Master = 0,
    Slave = 1,
};

pub var partition_lba: u32 = 0;
pub var test_image: []u8 = &.{};

pub fn read_sector(drive: Drive, lba: u32, buffer: [*]u8) void {
    const offset = (@as(usize, partition_lba) + lba) * 512;
    if (drive != .Master or offset + 512 > test_image.len) {
        @memset(buffer[0..512], 0);
        return;
    }
    @memcpy(buffer[0..512], test_image[offset..][0..512]);
}

pub fn write_sector(drive: Drive, lba: u32, data: [*]const u8) void {
    const offset = (@as(usize, partition_lba) + lba) * 512;
    if (drive != .Master or offset + 512 > test_image.len) return;
    @memcpy(test_image[offset..][0..512], data[0..512]);
}
