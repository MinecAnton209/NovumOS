const user = @import("../user.zig");
const lfb = @import("../drivers/lfb.zig");
const memory = @import("../memory.zig");
const events = @import("../events.zig");

const VideoMode = extern struct {
    width: u32,
    height: u32,
    bpp: u32,
    pitch: u32,
};

pub fn getVideoMode(regs: *user.Registers) void {
    const dst = @as(*VideoMode, @ptrFromInt(regs.ebx));
    dst.width = lfb.width;
    dst.height = lfb.height;
    dst.bpp = lfb.bpp;
    dst.pitch = lfb.pitch;
    regs.eax = 0;
}

pub fn requestFramebuffer(regs: *user.Registers) void {
    const fb_vaddr: usize = memory.RESERVED_FB_VADDR;
    memory.map_range_physical(fb_vaddr, lfb.fb_phys_base, lfb.fb_mapped_size, true);
    regs.eax = @as(u32, @intCast(fb_vaddr));
}

pub fn releaseFramebuffer(regs: *user.Registers) void {
    regs.eax = 0;
}

pub fn pollEvent(regs: *user.Registers) void {
    const dst = @as(*events.InputEvent, @ptrFromInt(regs.ebx));
    if (events.poll()) |ev| {
        dst.* = ev;
        regs.eax = 1;
    } else {
        regs.eax = 0;
    }
}
