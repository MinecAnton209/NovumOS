// VGA Compatibility Layer for LFB
const lfb = @import("lfb.zig");

pub const VIDEO_MEMORY: [*]volatile u16 = @ptrFromInt(0xb8000);
pub const MAX_COLS: usize = 80;
pub const MAX_ROWS: usize = 25;
pub const DEFAULT_ATTR: u16 = 0x0f00;

pub var current_color: u16 = DEFAULT_ATTR;

pub export var cursor_row: u8 = 0;
pub export var cursor_col: u8 = 0;

var screen_buffer: [MAX_COLS * MAX_ROWS]u16 = [_]u16{0} ** (MAX_COLS * MAX_ROWS);
var saved_cursor_row: u8 = 0;
var saved_cursor_col: u8 = 0;

pub export fn set_color(fg: u8, bg: u8) void {
    current_color = (@as(u16, bg) << 12) | (@as(u16, fg) << 8);
}

pub export fn reset_color() void {
    current_color = DEFAULT_ATTR;
}

pub export fn save_screen_buffer() void {
    var i: usize = 0;
    while (i < MAX_COLS * MAX_ROWS) : (i += 1) {
        screen_buffer[i] = VIDEO_MEMORY[i];
    }
    saved_cursor_row = cursor_row;
    saved_cursor_col = cursor_col;
}

pub export fn restore_screen_buffer() void {
    var i: usize = 0;
    while (i < MAX_COLS * MAX_ROWS) : (i += 1) {
        VIDEO_MEMORY[i] = screen_buffer[i];
    }
    cursor_row = saved_cursor_row;
    cursor_col = saved_cursor_col;
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
    lfb.fill_screen(0x000000); // Simple clear for now
    cursor_row = 0;
    cursor_col = 0;
}

fn internal_newline() void {
    cursor_col = 0;
    cursor_row += 1;
    if (cursor_row >= MAX_ROWS) {
        scroll();
    }
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
            cursor_col = MAX_COLS - 1;
        }

        if (lfb.initialized) {
            const bx = @as(u32, cursor_col) * 8;
            const by = @as(u32, cursor_row) * 12;
            var r: u32 = 0;
            while (r < 8) : (r += 1) {
                var cl: u32 = 0;
                while (cl < 8) : (cl += 1) {
                    lfb.put_pixel(bx + cl, by + r, 0x000000);
                }
            }
        }
    } else if (c >= 32 and c <= 126) {
        if (cursor_row >= MAX_ROWS) {
            scroll();
        }

        if (lfb.initialized) {
            const char_x = @as(u32, cursor_col) * 8;
            const char_y = @as(u32, cursor_row) * 12;
            lfb.draw_char(c, char_x, char_y, 0xFFFFFF); // White
        }

        cursor_col += 1;
        if (cursor_col >= MAX_COLS) {
            internal_newline();
        }
    }
}

pub export fn zig_clear_line(row: u8) void {
    if (row >= MAX_ROWS) return;
    const py = @as(u32, row) * 12;
    var y: u32 = py;
    while (y < py + 8) : (y += 1) {
        var x: u32 = 0;
        while (x < @as(u32, MAX_COLS) * 8) : (x += 1) {
            lfb.put_pixel(x, y, 0x000000);
        }
    }
}

pub fn update_vga_cursor() void {
    // Hardware VGA cursor doesn't work in LFB
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
