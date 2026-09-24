const user = @import("../arch/mod.zig").user;
const lfb = @import("../drivers/lfb.zig");
const memory = @import("../kernel/memory.zig");
const events = @import("../kernel/events.zig");

const VideoMode = extern struct {
    width: u32,
    height: u32,
    bpp: u32,
    pitch: u32,
};

/// Syscall 58: SetResolution(EBX=width, ECX=height) -> EAX=0|1
/// Runs the BGA resolution switch in Ring 0 because it maps new
/// framebuffer and backbuffer pages (invlpg is privileged).
pub fn setResolution(regs: *user.Registers) void {
    regs.eax = if (lfb.init_bga(@intCast(regs.ebx), @intCast(regs.ecx))) 1 else 0;
}

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
