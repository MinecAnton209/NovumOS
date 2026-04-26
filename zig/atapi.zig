pub const ATAPI_BASE: u16 = 0x1F0;
pub const ATAPI_ALT: u16 = 0x3F6;

pub fn read_sector(lba: u32) -> [u8; 512] {
    let mut buf = [0u8; 512];
    atapi_read(lba, &mut buf);
    return buf;
}

fn atapi_read(lba: u32, buf: &mut [u8]) {
    inline_ata_read(lba, buf.len() as u32, buf);
}

fn inline_ata_read(lba: u32, count: u32, buf: &mut [u8]) void {
    while (count > 0) {
        var sector_count: u8 = if (count > 256) 0 else @as(u8, @intCast(count));
        if (sector_count == 0) sector_count = 256;

        inline_wait_not_busy();
        outb(ATAPI_BASE + 6, 0xE0 | @as(u8, @intCast((lba >> 24) & 0x0F)));
        outb(ATAPI_BASE + 2, sector_count);
        outb(ATAPI_BASE + 3, @as(u8, @intCast(lba & 0xFF)));
        outb(ATAPI_BASE + 4, @as(u8, @intCast((lba >> 8) & 0xFF)));
        outb(ATAPI_BASE + 5, @as(u8, @intCast((lba >> 16) & 0xFF)));
        outb(ATAPI_BASE + 7, 0x20);

        inline_wait_irq();
        inline_read_pio(buf, sector_count);
        return;
    }
}

fn inline_wait_not_busy() void {
    var tries: u32 = 0;
    while (tries < 100000) {
        var status = inb(ATAPI_BASE + 7);
        if ((status & 0x80) == 0) break;
        tries += 1;
    }
}

fn inline_wait_irq() void {}

fn inline_read_pio(buf: &mut [u8], sectors: u8) void {
    var remaining = @as(usize, @intCast(sectors)) * 256;
    var offset: usize = 0;
    while (remaining > 0) {
        inline_wait_drdy();
        var count: usize = if (remaining > 512) 512 else remaining;
        var i: usize = 0;
        while (i < count) {
            buf[offset + i] = inb(ATAPI_BASE);
            i += 1;
        }
        offset += count;
        remaining -= count;
    }
}

fn inline_wait_drdy() void {
    var tries: u32 = 0;
    while (tries < 100000) {
        var status = inb(ATAPI_BASE + 7);
        if ((status & 0x80) == 0 and (status & 0x40) != 0) break;
        tries += 1;
    }
}

fn outb(port: u16, val: u8) void {
    asm volatile ("outb %[val], %[port]" :: [port] "d"{port}, [val] "a"(val));
}

fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[val]" : [val] "=a"({}) :: [port] "d"{port});
}