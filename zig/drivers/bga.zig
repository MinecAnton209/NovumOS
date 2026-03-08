const common = @import("../commands/common.zig");

pub const VBE_DISPI_IOPORT_INDEX = 0x01CE;
pub const VBE_DISPI_IOPORT_DATA = 0x01CF;

pub const VBE_DISPI_INDEX_ID = 0;
pub const VBE_DISPI_INDEX_XRES = 1;
pub const VBE_DISPI_INDEX_YRES = 2;
pub const VBE_DISPI_INDEX_BPP = 3;
pub const VBE_DISPI_INDEX_ENABLE = 4;

pub const VBE_DISPI_DISABLED = 0x00;
pub const VBE_DISPI_ENABLED = 0x01;
pub const VBE_DISPI_LFB_ENABLED = 0x40;

fn bga_write(index: u16, data: u16) void {
    common.outw(VBE_DISPI_IOPORT_INDEX, index);
    common.outw(VBE_DISPI_IOPORT_DATA, data);
}

fn bga_read(index: u16) u16 {
    common.outw(VBE_DISPI_IOPORT_INDEX, index);
    return common.inw(VBE_DISPI_IOPORT_DATA);
}

pub fn is_available() bool {
    const id = bga_read(VBE_DISPI_INDEX_ID);
    return id >= 0xB0C0 and id <= 0xB0C5;
}

pub fn set_resolution(width: u16, height: u16, bpp: u16) void {
    bga_write(VBE_DISPI_INDEX_ENABLE, VBE_DISPI_DISABLED);
    bga_write(VBE_DISPI_INDEX_XRES, width);
    bga_write(VBE_DISPI_INDEX_YRES, height);
    bga_write(VBE_DISPI_INDEX_BPP, bpp);
    bga_write(VBE_DISPI_INDEX_ENABLE, VBE_DISPI_ENABLED | VBE_DISPI_LFB_ENABLED);
}
