// VGA Compatibility Layer for LFB
const lfb = @import("lfb.zig");

var internal_char_buffer: [256 * 160]u16 = undefined;
pub const VIDEO_MEMORY: [*]volatile u16 = @ptrCast(&internal_char_buffer);

pub var MAX_COLS: usize = 80;
pub var MAX_ROWS: usize = 25;
pub const DEFAULT_ATTR: u16 = 0x0f00;

pub var vga_initialized: bool = false;

pub fn init_dimensions() void {
    if (lfb.initialized) {
        var nc = lfb.width / 8;
        var nr = lfb.height / 14;

        // Sanity checks
        if (nc == 0) nc = 1;
        if (nr == 0) nr = 1;
        if (nc > 256) nc = 256;
        if (nr > 160) nr = 160;

        // Forced initialization on first call or resolution change
        if (!vga_initialized or nc != MAX_COLS or nr != MAX_ROWS) {
            MAX_COLS = nc;
            MAX_ROWS = nr;

            // Clear physical video memory (flush old demons)
            lfb.fill_screen(0x000000);

            for (0..internal_char_buffer.len) |i| {
                internal_char_buffer[i] = DEFAULT_ATTR | ' ';
            }

            // Also initialize screen buffer once
            for (0..screen_buffer.len) |i| {
                screen_buffer[i] = DEFAULT_ATTR | ' ';
            }
            vga_initialized = true;
        }
    }
}

pub var current_color: u16 = DEFAULT_ATTR;

pub export var cursor_row: u8 = 0;
pub export var cursor_col: u8 = 0;

var screen_buffer: [256 * 160]u16 = undefined;
var saved_cursor_row: u16 = 0;
var saved_cursor_col: u16 = 0;

pub export fn set_color(fg: u8, bg: u8) void {
    current_color = (@as(u16, bg) << 12) | (@as(u16, fg) << 8);
}

pub export fn reset_color() void {
    current_color = DEFAULT_ATTR;
}

pub export fn save_screen_buffer() void {
    var i: usize = 0;
    while (i < MAX_COLS * MAX_ROWS) : (i += 1) {
        if (i >= screen_buffer.len) break;
        screen_buffer[i] = VIDEO_MEMORY[i];
    }
    saved_cursor_row = cursor_row;
    saved_cursor_col = cursor_col;
}

pub export fn restore_screen_buffer() void {
    var i: usize = 0;
    while (i < MAX_COLS * MAX_ROWS) : (i += 1) {
        if (i >= screen_buffer.len) break;
        VIDEO_MEMORY[i] = screen_buffer[i];
    }
    cursor_row = @intCast(saved_cursor_row);
    cursor_col = @intCast(saved_cursor_col);
    update_hardware_cursor();
}

pub export fn clear_screen() void {
    if (!lfb.initialized) return;
    lfb.fill_screen(0x000000); // Black
    cursor_row = 0;
    cursor_col = 0;
}

pub export fn zig_set_cursor(row: u8, col: u8) void {
    // Detect User Mode (Ring 3)
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 3) {
        asm volatile ("int $0x80"
            :
            : [sys] "{eax}" (@as(u32, 3)),
              [ebx] "{ebx}" (@as(u32, row)),
              [ecx] "{ecx}" (@as(u32, col)),
        );
        return;
    }

    cursor_row = row;
    cursor_col = col;
    update_hardware_cursor();
}

pub export fn zig_get_cursor_row() u8 {
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 3) {
        const res = asm volatile ("int $0x80"
            : [ret] "={eax}" (-> u32),
            : [sys] "{eax}" (@as(u32, 4)),
        );
        return @intCast(res >> 8);
    }
    return cursor_row;
}
pub export fn zig_get_cursor_col() u8 {
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 3) {
        const res = asm volatile ("int $0x80"
            : [ret] "={eax}" (-> u32),
            : [sys] "{eax}" (@as(u32, 4)),
        );
        return @intCast(res & 0xFF);
    }
    return cursor_col;
}

fn scroll() void {
    if (!lfb.initialized) return;

    // 1. Shift lines 1..MAX_ROWS-1 up into 0..MAX_ROWS-2
    // Each line is 14 pixels high.
    const row_height: u32 = 14;
    const scroll_rows: u32 = @intCast(MAX_ROWS - 1);
    lfb.copy_region(row_height, 0, scroll_rows * row_height);

    // 2. Clear the bottom line
    const last_row: u8 = @intCast(MAX_ROWS - 1);
    zig_clear_line(last_row);

    // 3. Move cursor to the last row
    cursor_row = last_row;
    cursor_col = 0;

    // 4. Update the VIDEO_MEMORY buffer (optional but good for consistency)
    var r: usize = 0;
    while (r < MAX_ROWS - 1) : (r += 1) {
        var c: usize = 0;
        while (c < MAX_COLS) : (c += 1) {
            VIDEO_MEMORY[r * MAX_COLS + c] = VIDEO_MEMORY[(r + 1) * MAX_COLS + c];
        }
    }
}

fn internal_newline() void {
    cursor_col = 0;
    cursor_row += 1;
    if (cursor_row >= MAX_ROWS) {
        scroll();
    }
}

pub fn vga_attr_to_rgb(attr: u16) u32 {
    const fg = @as(u8, @intCast((attr >> 8) & 0x0F));
    return switch (fg) {
        0 => 0x000000, // Black
        1 => 0x0000AA, // Blue
        2 => 0x00AA00, // Green
        3 => 0x00AAAA, // Cyan
        4 => 0xAA0000, // Red
        5 => 0xAA00AA, // Magenta
        6 => 0xAA5500, // Brown
        7 => 0xAAAAAA, // Light Gray
        8 => 0x555555, // Dark Gray
        9 => 0x5555FF, // Light Blue
        10 => 0x55FF55, // Light Green
        11 => 0x55FFFF, // Light Cyan
        12 => 0xFF5555, // Light Red
        13 => 0xFF55FF, // Light Magenta
        14 => 0xFFFF55, // Yellow
        15 => 0xFFFFFF, // White
        else => 0xFFFFFF,
    };
}

pub export fn zig_print_char(c: u8) void {
    if (c == '\n' or c == 10) {
        internal_newline();
    } else if (c == '\r' or c == 13) {
        cursor_col = 0;
    } else if (c == 8) { // Backspace
        if (cursor_col > 0) {
            cursor_col -= 1;
        } else if (cursor_row > 0) {
            cursor_row -= 1;
            cursor_col = @intCast(MAX_COLS - 1);
        }

        if (lfb.initialized) {
            const bx = @as(u32, @intCast(cursor_col)) * 8;
            const by = @as(u32, @intCast(cursor_row)) * 14;
            var r: u32 = 0;
            while (r < 14) : (r += 1) {
                var cl: u32 = 0;
                while (cl < 8) : (cl += 1) {
                    lfb.put_pixel(bx + cl, by + r, 0x000000);
                }
            }
        }
    } else if (c >= 32) {
        if (cursor_row >= MAX_ROWS) {
            scroll();
        }

        const attr = current_color;
        if (cursor_row < MAX_ROWS and cursor_col < MAX_COLS) {
            const idx = @as(usize, cursor_row) * MAX_COLS + cursor_col;
            VIDEO_MEMORY[idx] = attr | @as(u16, c);
        }

        if (lfb.initialized) {
            const char_x = @as(u32, @intCast(cursor_col)) * 8;
            const char_y = @as(u32, @intCast(cursor_row)) * 14;
            lfb.draw_char(c, char_x, char_y, vga_attr_to_rgb(attr), 1);
        }

        cursor_col += 1;
        if (cursor_col >= MAX_COLS) {
            internal_newline();
        }
    }
}

pub export fn zig_clear_line(row: u8) void {
    if (row >= MAX_ROWS) return;
    const py = @as(u32, row) * 14;
    var y: u32 = py;
    while (y < py + 14) : (y += 1) {
        var x: u32 = 0;
        while (x < @as(u32, MAX_COLS) * 8) : (x += 1) {
            lfb.put_pixel(x, y, 0x000000);
        }
    }
    // Also clear the VIDEO_MEMORY buffer
    var col: usize = 0;
    while (col < MAX_COLS) : (col += 1) {
        VIDEO_MEMORY[@as(usize, row) * MAX_COLS + col] = DEFAULT_ATTR | ' ';
    }
}

pub export fn clear_prompt_area(start_row: u8, start_col: u8) void {
    var row = start_row;
    var col = start_col;
    var cleared: usize = 0;
    while (cleared < 160) : (cleared += 1) {
        if (row >= MAX_ROWS) break;
        const idx = @as(usize, row) * MAX_COLS + col;
        VIDEO_MEMORY[idx] = DEFAULT_ATTR | ' ';

        if (lfb.initialized) {
            const bx = @as(u32, @intCast(col)) * 8;
            const by = @as(u32, @intCast(row)) * 14;
            var r: u32 = 0;
            while (r < 14) : (r += 1) {
                var c: u32 = 0;
                while (c < 8) : (c += 1) {
                    lfb.put_pixel(bx + c, by + r, 0x000000);
                }
            }
        }

        col += 1;
        if (col >= MAX_COLS) {
            col = 0;
            row += 1;
        }
    }
}

pub export fn draw_indicator(col: u8, attr: u16, c: u8) void {
    const row = 0; // Fixed top row for indicators
    if (col >= MAX_COLS) return;

    const idx = @as(usize, row) * MAX_COLS + col;
    VIDEO_MEMORY[idx] = attr | @as(u16, c);

    if (lfb.initialized) {
        const bx = @as(u32, col) * 8;
        const by = @as(u32, row) * 14;
        lfb.draw_char(c, bx, by, vga_attr_to_rgb(attr), 1);
    }
}

pub export fn erase_vga_cursor() void {
    // Disabled stateful cursor erasing to prevent visual glitches
}

pub export fn update_vga_cursor() void {
    // Disabled stateful cursor drawing to prevent visual glitches
}

pub export fn update_hardware_cursor() void {
    update_vga_cursor();
}

fn outb(port: u16, val: u8) void {
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );

    if ((cs & 3) == 3) {
        asm volatile ("int $0x80"
            :
            : [sys] "{eax}" (@as(u32, 7)),
              [p] "{ebx}" (@as(u32, port)),
              [v] "{ecx}" (@as(u32, val)),
        );
        return;
    }

    asm volatile ("outb %[val], %[port]"
        :
        : [val] "{al}" (val),
          [port] "{dx}" (port),
    );
}
