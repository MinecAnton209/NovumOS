const common = @import("common.zig");
const lfb = @import("../drivers/lfb.zig");
const vga = @import("../drivers/vga.zig");
const timer = @import("../drivers/timer.zig");
const keyboard = @import("../keyboard_isr.zig");
const quantum = @import("../quantum.zig");

// The fire grid is rendered as BLOCKxBLOCK screen pixels per cell,
// giving the chunky pixel look of the original DOOM fire demo.
const BLOCK: u32 = 8;
const MAX_FIRE_CELLS = 320 * 240;
var fire_buf: [MAX_FIRE_CELLS]u8 = undefined;

// Heat gradient: index 0 is cold black, last index is the white-hot source.
const FIRE_PALETTE = [_]u32{
    0x000000, 0x070707, 0x1F0707, 0x2F0F07, 0x470F07, 0x571707,
    0x671F07, 0x771F07, 0x8F2707, 0x9F2F07, 0xAF3F07, 0xBF4707,
    0xC74707, 0xDF4F07, 0xDF5707, 0xD75F07, 0xE76707, 0xE76F07,
    0xE77707, 0xE77F07, 0xF78707, 0xF78F07, 0xF79707, 0xFF9F07,
    0xFFA707, 0xFFAF07, 0xFFB707, 0xFFBF07, 0xFFC707, 0xFFCF07,
    0xFFD707, 0xFFDF07, 0xFFE707, 0xFFEF07, 0xFFF707, 0xFFFFFF,
};

// LCG for spread randomness. Seeded from the quantum RNG and re-mixed
// with a fresh quantum byte every frame, so each flame run is unique.
var lcg_state: u32 = 0;

fn fire_rand() u8 {
    lcg_state = lcg_state *% 1664525 +% 1013904223;
    return @intCast(lcg_state >> 24);
}

fn quantum_seed() void {
    lcg_state = (@as(u32, quantum.randByte()) << 24) |
        (@as(u32, quantum.randByte()) << 16) |
        (@as(u32, quantum.randByte()) << 8) |
        quantum.randByte();
}

// Each cell climbs into the row above, drifting one cell left/right and
// cooling by 0 or 1 heat units. A cold cell extinguishes the one above it.
fn propagate(fire_w: u32, fire_h: u32) void {
    var y: u32 = 1;
    while (y < fire_h) : (y += 1) {
        var x: u32 = 0;
        while (x < fire_w) : (x += 1) {
            const pixel = fire_buf[y * fire_w + x];
            if (pixel == 0) {
                fire_buf[(y - 1) * fire_w + x] = 0;
                continue;
            }
            const rnd = fire_rand() % 3;
            var col = x;
            if (rnd == 0 and x + 1 < fire_w) {
                col = x + 1;
            } else if (rnd == 2 and x > 0) {
                col = x - 1;
            }
            const cool = rnd & 1;
            const above = (y - 1) * fire_w + col;
            fire_buf[above] = if (pixel > cool) pixel - cool else 0;
        }
    }
}

fn blit(fire_w: u32, fire_h: u32) void {
    const bb = lfb.backbuffer_ptr orelse return;

    if (lfb.bpp == 32) {
        const fb32: [*]u32 = @ptrCast(@alignCast(bb));
        const pitch32 = lfb.pitch / 4;
        var fy: u32 = 0;
        while (fy < fire_h) : (fy += 1) {
            var fx: u32 = 0;
            while (fx < fire_w) : (fx += 1) {
                const color = FIRE_PALETTE[fire_buf[fy * fire_w + fx]];
                const x0 = fx * BLOCK;
                const y0 = fy * BLOCK;
                var dy: u32 = 0;
                while (dy < BLOCK) : (dy += 1) {
                    const row = fb32 + (y0 + dy) * pitch32 + x0;
                    var dx: u32 = 0;
                    while (dx < BLOCK) : (dx += 1) {
                        row[dx] = color;
                    }
                }
            }
        }
    } else {
        var fy: u32 = 0;
        while (fy < fire_h) : (fy += 1) {
            var fx: u32 = 0;
            while (fx < fire_w) : (fx += 1) {
                const color = FIRE_PALETTE[fire_buf[fy * fire_w + fx]];
                const x0 = fx * BLOCK;
                const y0 = fy * BLOCK;
                var dy: u32 = 0;
                while (dy < BLOCK) : (dy += 1) {
                    var dx: u32 = 0;
                    while (dx < BLOCK) : (dx += 1) {
                        lfb.put_pixel(x0 + dx, y0 + dy, color);
                    }
                }
            }
        }
    }
}

pub fn cmd_doomfire() void {
    if (!lfb.initialized or lfb.backbuffer_ptr == null) {
        common.printZ("doomfire: no framebuffer available\n");
        return;
    }

    common.printZ("Igniting quantum DOOM fire... (q / Ctrl+C to exit)\n");
    timer.sleep(1200);
    vga.clear_screen();

    const fire_w = lfb.width / BLOCK;
    const fire_h = lfb.height / BLOCK;
    const fire_size = fire_w * fire_h;
    const hottest: u8 = @intCast(FIRE_PALETTE.len - 1);

    if (fire_size > MAX_FIRE_CELLS) {
        common.printZ("doomfire: resolution too large\n");
        vga.clear_screen();
        return;
    }

    // Drop stale keystrokes so the command doesn't exit instantly.
    while (keyboard.keyboard_has_data()) {
        _ = keyboard.keyboard_getchar();
    }

    quantum_seed();
    @memset(fire_buf[0..fire_size], 0);

    while (true) {
        // Keep the bottom row white-hot: the fire source.
        for (0..fire_w) |x| {
            fire_buf[fire_size - fire_w + x] = hottest;
        }

        lcg_state ^= @as(u32, quantum.randByte()) << 24;
        propagate(fire_w, fire_h);

        blit(fire_w, fire_h);
        lfb.mark_dirty(0, 0, lfb.width - 1, lfb.height - 1);
        lfb.swap_buffers();

        if (keyboard.check_ctrl_c()) break;
        if (keyboard.keyboard_has_data()) {
            const c = keyboard.keyboard_getchar();
            if (c == 'q' or c == 'Q' or c == 27) break;
        }
    }

    vga.clear_screen();
    vga.reset_color();
}
