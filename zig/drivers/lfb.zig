const memory = @import("../memory.zig");
const font = @import("font.zig");

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

pub fn init() void {
    const raw_info: *VbeModeInfo = @ptrFromInt(0x8000);

    width = raw_info.width;
    height = raw_info.height;
    bpp = raw_info.bits_per_pixel;
    pitch = raw_info.bytes_per_scanline;

    if (width == 0) width = 1024;
    if (height == 0) height = 768;
    if (pitch == 0) pitch = width * (bpp / 8);

    const fb_phys = raw_info.phys_base_ptr;
    const fb_size = @as(usize, pitch) * height;

    memory.map_range(fb_phys, fb_size);
    framebuffer = @ptrFromInt(fb_phys);
    initialized = true;
}

pub fn put_pixel(x: u32, y: u32, color: u32) void {
    if (!initialized) return;
    if (x >= width or y >= height) return;

    const fb = framebuffer.?;
    if (bpp == 32) {
        const offset = y * pitch + x * 4;
        const p: *u32 = @ptrCast(@alignCast(&fb[offset]));
        p.* = color;
    } else if (bpp == 24) {
        const offset = y * pitch + x * 3;
        fb[offset] = @intCast(color & 0xFF);
        fb[offset + 1] = @intCast((color >> 8) & 0xFF);
        fb[offset + 2] = @intCast((color >> 16) & 0xFF);
    }
}

pub fn fill_screen(color: u32) void {
    if (!initialized) return;
    var y: u32 = 0;
    while (y < height) : (y += 1) {
        var x: u32 = 0;
        while (x < width) : (x += 1) {
            put_pixel(x, y, color);
        }
    }
}

pub fn draw_char(c: u8, x: u32, y: u32, color: u32, scale: u32) void {
    if (!initialized) return;
    if (c < 32 or c > 126) return;
    const char_idx = @as(usize, c) * font.FONT_HEIGHT;

    var row: u32 = 0;
    while (row < font.FONT_HEIGHT) : (row += 1) {
        const row_data = font.font_data[char_idx + row];
        var col: u32 = 0;
        while (col < font.FONT_WIDTH) : (col += 1) {
            const is_set = (row_data & (@as(u8, 0x80) >> @as(u3, @intCast(col)))) != 0;
            const pcolor = if (is_set) color else 0x000000;

            // Draw a 'scale x scale' pixel block
            var dy: u32 = 0;
            while (dy < scale) : (dy += 1) {
                var dx: u32 = 0;
                while (dx < scale) : (dx += 1) {
                    put_pixel(x + (col * scale) + dx, y + (row * scale) + dy, pcolor);
                }
            }
        }
    }
}

pub fn draw_string(s: []const u8, x: u32, y: u32, color: u32, scale: u32) void {
    if (!initialized) return;
    var cx = x;
    var cy = y;
    for (s) |c| {
        if (c == '\n') {
            cx = x;
            cy += font.FONT_HEIGHT * scale;
        } else {
            draw_char(c, cx, cy, color, scale);
            cx += font.FONT_WIDTH * scale;
        }
    }
}
