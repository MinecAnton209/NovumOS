const memory = @import("../memory.zig");
const font = @import("font.zig");
const bga = @import("bga.zig");
const vga = @import("vga.zig");

extern const fb_addr: u32;
extern const fb_pitch: u32;
extern const fb_width: u32;
extern const fb_height: u32;
extern const fb_bpp: u32;

pub const VbeModeInfo = extern struct {
    attributes: u16,
    win_a_attributes: u8,
    win_b_attributes: u8,
    win_granularity: u16,
    win_size: u16,
    win_a_segment: u16,
    win_b_segment: u16,
    win_func_ptr: u32,
    bytes_per_scanline: u16,
    width: u16,
    height: u16,
    x_char_size: u8,
    y_char_size: u8,
    planes: u8,
    bits_per_pixel: u8,
    banks: u8,
    memory_model: u8,
    bank_size: u8,
    image_pages: u8,
    reserved1: u8,
    red_mask_size: u8,
    red_field_position: u8,
    green_mask_size: u8,
    green_field_position: u8,
    blue_mask_size: u8,
    blue_field_position: u8,
    rsvd_mask_size: u8,
    rsvd_field_position: u8,
    direct_color_mode_info: u8,
    phys_base_ptr: u32,
    reserved2: u32,
    reserved3: u16,
    reserved4: [206]u8,
};

pub var initialized: bool = false;
pub var width: u32 = 1024;
pub var height: u32 = 768;
pub var bpp: u32 = 32;
pub var pitch: u32 = 4096;
pub var framebuffer: ?[*]u8 = null;
pub var fb_mapped_size: usize = 0;
pub var fb_phys_base: u32 = 0;

// Dynamic backbuffer allocation
pub var backbuffer_ptr: ?[*]u8 = null;
pub var backbuffer_mapped_size: usize = 0;

fn ensure_backbuffer(size: usize) void {
    if (size <= backbuffer_mapped_size) return;
    const vaddr_start: usize = 0xD0000000;
    const aligned_size: usize = (size + 4095) & ~@as(usize, 4095);
    var offset: usize = backbuffer_mapped_size;

    while (offset < aligned_size) : (offset += 4096) {
        if (memory.pmm.alloc_page()) |paddr| {
            _ = memory.map_page_at(vaddr_start + offset, paddr, true);
        } else {
            break;
        }
    }
    backbuffer_mapped_size = offset;
    backbuffer_ptr = @ptrFromInt(vaddr_start);
}

pub var dirty: bool = false;
pub var dirty_min_x: u32 = 0;
pub var dirty_min_y: u32 = 0;
pub var dirty_max_x: u32 = 0;
pub var dirty_max_y: u32 = 0;

pub fn mark_dirty(min_x: u32, min_y: u32, max_x: u32, max_y: u32) void {
    if (!dirty) {
        dirty = true;
        dirty_min_x = min_x;
        dirty_min_y = min_y;
        dirty_max_x = max_x;
        dirty_max_y = max_y;
    } else {
        if (min_x < dirty_min_x) dirty_min_x = min_x;
        if (min_y < dirty_min_y) dirty_min_y = min_y;
        if (max_x > dirty_max_x) dirty_max_x = max_x;
        if (max_y > dirty_max_y) dirty_max_y = max_y;
    }
}

pub fn init() void {
    // First try Multiboot2 framebuffer from bootloader
    if (fb_addr != 0) {
        // Use Multiboot2 provided framebuffer
        fb_phys_base = fb_addr;
        width = fb_width;
        height = fb_height;
        bpp = fb_bpp;
        pitch = fb_pitch;
        
        if (pitch == 0) pitch = width * (bpp / 8);
        fb_mapped_size = @as(usize, pitch) * height;
        
        memory.user_mmio_start = fb_phys_base;
        memory.user_mmio_end = fb_phys_base + fb_mapped_size;
        
        memory.map_range(fb_phys_base, fb_mapped_size, true);
        framebuffer = @ptrFromInt(fb_phys_base);
        ensure_backbuffer(fb_mapped_size);
        initialized = true;
        return;
    }
    
    // Fallback to VBE info
    const raw_info: *VbeModeInfo = @ptrFromInt(0x8000);

    width = raw_info.width;
    height = raw_info.height;
    bpp = raw_info.bits_per_pixel;
    pitch = raw_info.bytes_per_scanline;

    if (width == 0) width = 1024;
    if (height == 0) height = 768;
    if (pitch == 0) pitch = width * (bpp / 8);

    fb_phys_base = raw_info.phys_base_ptr;
    fb_mapped_size = @as(usize, pitch) * height;
    memory.user_mmio_start = fb_phys_base;
    memory.user_mmio_end = fb_phys_base + fb_mapped_size;

    memory.map_range(fb_phys_base, fb_mapped_size, true);
    framebuffer = @ptrFromInt(fb_phys_base);
    ensure_backbuffer(fb_mapped_size);
    initialized = true;

    // Calibrate smart vsync
    calibrate_vsync();
}

pub fn init_bga(w: u16, h: u16) bool {
    if (!bga.is_available()) return false;

    // Set 32bpp resolution via BGA ports
    bga.set_resolution(w, h, 32);

    // Update our internal LFB info
    width = w;
    height = h;
    bpp = 32;
    pitch = @as(u32, w) * 4;

    const new_size = @as(usize, pitch) * height;

    if (!initialized) {
        fb_phys_base = 0xE0000000; // Default QEMU
        fb_mapped_size = new_size;

        memory.user_mmio_start = fb_phys_base;
        memory.user_mmio_end = fb_phys_base + fb_mapped_size;

        memory.map_range(fb_phys_base, fb_mapped_size, true);
        framebuffer = @ptrFromInt(fb_phys_base);
        ensure_backbuffer(new_size);
        initialized = true;
    } else if (new_size > fb_mapped_size) {
        // Map more memory if resolution increased
        memory.map_range(fb_phys_base + @as(u32, @intCast(fb_mapped_size)), new_size - fb_mapped_size, true);
        fb_mapped_size = new_size;
        memory.user_mmio_end = fb_phys_base + fb_mapped_size;
        ensure_backbuffer(new_size);
    } else {
        ensure_backbuffer(new_size);
    }

    // Refresh shell/vga dimensions
    vga.init_dimensions();

    // Re-calibrate vsync if resolution logic altered timings (unlikely but safe)
    calibrate_vsync();

    return true;
}

pub fn fill_rect(start_x: u32, start_y: u32, w: u32, h: u32, color: u32) void {
    if (!initialized) return;
    const bb = backbuffer_ptr orelse return;

    if (start_x >= width or start_y >= height) return;
    var draw_w = w;
    var draw_h = h;
    if (start_x + draw_w > width) draw_w = width - start_x;
    if (start_y + draw_h > height) draw_h = height - start_y;
    if (draw_w == 0 or draw_h == 0) return;

    mark_dirty(start_x, start_y, start_x + draw_w - 1, start_y + draw_h - 1);

    var y = start_y;
    while (y < start_y + draw_h) : (y += 1) {
        if (bpp == 32) {
            const offset = y * pitch + start_x * 4;
            const p: [*]u32 = @ptrCast(@alignCast(&bb[offset]));
            var i: usize = 0;
            while (i < draw_w) : (i += 1) {
                p[i] = color;
            }
        } else {
            var x = start_x;
            while (x < start_x + draw_w) : (x += 1) {
                const offset = y * pitch + x * 3;
                bb[offset] = @intCast(color & 0xFF);
                bb[offset + 1] = @intCast((color >> 8) & 0xFF);
                bb[offset + 2] = @intCast((color >> 16) & 0xFF);
            }
        }
    }
}

pub fn put_pixel(x: u32, y: u32, color: u32) void {
    if (!initialized) return;
    if (x >= width or y >= height) return;
    const backbuffer = backbuffer_ptr orelse return;

    mark_dirty(x, y, x, y);

    if (bpp == 32) {
        const offset = y * pitch + x * 4;
        const p: *u32 = @ptrCast(@alignCast(&backbuffer[offset]));
        p.* = color;
    } else if (bpp == 24) {
        const offset = y * pitch + x * 3;
        backbuffer[offset] = @intCast(color & 0xFF);
        backbuffer[offset + 1] = @intCast((color >> 8) & 0xFF);
        backbuffer[offset + 2] = @intCast((color >> 16) & 0xFF);
    }
}

pub fn fill_screen(color: u32) void {
    if (!initialized) return;
    fill_rect(0, 0, width, height, color);
}

pub fn draw_char(c: u8, x: u32, y: u32, fg: u32, bg: u32, scale: u32) void {
    if (!initialized) return;
    if (c < 32 or c > 126) return;
    const bb = backbuffer_ptr orelse return;
    const char_idx = @as(usize, c) * font.FONT_HEIGHT;

    mark_dirty(x, y, x + (font.FONT_WIDTH * scale) - 1, y + (font.FONT_HEIGHT * scale) - 1);

    var row: u32 = 0;
    while (row < font.FONT_HEIGHT) : (row += 1) {
        const row_data = font.font_data[char_idx + row];
        var col: u32 = 0;
        while (col < font.FONT_WIDTH) : (col += 1) {
            const is_set = (row_data & (@as(u8, 0x80) >> @as(u3, @intCast(col)))) != 0;
            const pcolor = if (is_set) fg else bg;

            var dy: u32 = 0;
            while (dy < scale) : (dy += 1) {
                const py = y + (row * scale) + dy;
                if (py >= height) continue;
                var dx: u32 = 0;
                while (dx < scale) : (dx += 1) {
                    const px = x + (col * scale) + dx;
                    if (px >= width) continue;

                    if (bpp == 32) {
                        const offset = py * pitch + px * 4;
                        const p: *u32 = @ptrCast(@alignCast(&bb[offset]));
                        p.* = pcolor;
                    } else if (bpp == 24) {
                        const offset = py * pitch + px * 3;
                        bb[offset] = @intCast(pcolor & 0xFF);
                        bb[offset + 1] = @intCast((pcolor >> 8) & 0xFF);
                        bb[offset + 2] = @intCast((pcolor >> 16) & 0xFF);
                    }
                }
            }
        }
    }
}

pub fn draw_string(s: []const u8, x: u32, y: u32, fg: u32, bg: u32, scale: u32) void {
    if (!initialized) return;
    var cx = x;
    var cy = y;
    for (s) |ch| {
        if (ch == '\n') {
            cx = x;
            cy += font.FONT_HEIGHT * scale;
        } else {
            draw_char(ch, cx, cy, fg, bg, scale);
            cx += font.FONT_WIDTH * scale;
        }
    }
}

pub fn copy_region(src_y: u32, dest_y: u32, count: u32) void {
    if (!initialized or framebuffer == null) return;
    const backbuffer = backbuffer_ptr orelse return;
    const bytes_per_line = pitch;

    mark_dirty(0, dest_y, width - 1, dest_y + count - 1);

    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const src_off = (src_y + i) * bytes_per_line;
        const dest_off = (dest_y + i) * bytes_per_line;
        @memcpy(backbuffer[dest_off .. dest_off + bytes_per_line], backbuffer[src_off .. src_off + bytes_per_line]);
    }
}

var vsync_interval_ms: usize = 0;
var last_vsync_tick: usize = 0;

pub fn calibrate_vsync() void {
    const timer = @import("timer.zig");
    // Wait until out of retrace
    while ((inb(0x3DA) & 8) != 0) {}
    // Wait until start of retrace
    while ((inb(0x3DA) & 8) == 0) {}

    const start = timer.get_ticks();

    // Wait until out of retrace
    while ((inb(0x3DA) & 8) != 0) {}
    // Wait until start of next retrace
    while ((inb(0x3DA) & 8) == 0) {}

    const end = timer.get_ticks();

    vsync_interval_ms = end - start;
    if (vsync_interval_ms == 0 or vsync_interval_ms > 100) {
        vsync_interval_ms = 16; // fallback ~60fps
    }

    last_vsync_tick = timer.get_ticks();
}

pub fn smart_vsync() void {
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 3) return; // Prevent #GP: Cannot use `inb` in Ring 3. User bounds skip vsync entirely.

    const timer = @import("timer.zig");
    if (vsync_interval_ms == 0) return;

    const now = timer.get_ticks();
    const elapsed = now - last_vsync_tick;

    // Planning: Instead of busy cycle, sleep until 1ms before vsync
    if (elapsed < vsync_interval_ms) {
        const remaining = vsync_interval_ms - elapsed;
        if (remaining > 1) {
            timer.sleep(remaining - 1);
        }
    }

    // Fine-tuning: wait exact moment
    while ((inb(0x3DA) & 8) != 0) {}
    while ((inb(0x3DA) & 8) == 0) {}

    last_vsync_tick = timer.get_ticks();
}

pub fn swap_buffers() void {
    if (!initialized or framebuffer == null or !dirty) return;
    const backbuffer = backbuffer_ptr orelse return;

    // Use Smart VSync to prevent tearing but let CPU rest
    smart_vsync();

    const fb = framebuffer.?;

    // Copy only the dirty region to VRAM
    var y: u32 = dirty_min_y;
    while (y <= dirty_max_y) : (y += 1) {
        if (y >= height) break;
        const line_off = y * pitch;
        const x_start_off = dirty_min_x * (bpp / 8);
        const copy_len = (dirty_max_x - dirty_min_x + 1) * (bpp / 8);

        @memcpy(fb[line_off + x_start_off .. line_off + x_start_off + copy_len], backbuffer[line_off + x_start_off .. line_off + x_start_off + copy_len]);
    }

    dirty = false;
}

fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[ret]"
        : [ret] "={al}" (-> u8),
        : [port] "{dx}" (port),
    );
}
