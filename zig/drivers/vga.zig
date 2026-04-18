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
pub var prev_cursor_row: u8 = 0;
pub var prev_cursor_col: u8 = 0;
pub var cursor_visible: bool = false;

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

        if (lfb.initialized) {
            const attr = screen_buffer[i];
            const c = @as(u8, @intCast(attr & 0xFF));
            const row = @as(u32, @intCast(i / MAX_COLS));
            const col = @as(u32, @intCast(i % MAX_COLS));
            lfb.draw_char(c, col * 8, row * 14, vga_attr_to_rgb(attr), vga_attr_to_rgb(attr >> 4), 1);
        }
    }
    cursor_row = @intCast(saved_cursor_row);
    cursor_col = @intCast(saved_cursor_col);
    update_hardware_cursor();
    lfb.swap_buffers();
}

pub export fn clear_screen() void {
    if (!lfb.initialized) return;
    lfb.fill_screen(0x000000); // Black

    for (0..internal_char_buffer.len) |i| {
        internal_char_buffer[i] = DEFAULT_ATTR | ' ';
    }

    cursor_row = 0;
    cursor_col = 0;
    cursor_visible = false;

    lfb.swap_buffers();
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

    lfb.swap_buffers(); // Flush after scrolling
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

pub var vga_lock: u32 = 0;

fn interrupts_save_vga() u32 {
    var eflags: u32 = undefined;
    asm volatile ("pushfl; popl %[f]"
        : [f] "=r" (eflags),
    );
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 0) asm volatile ("cli");
    return eflags;
}

fn interrupts_restore_vga(f: u32) void {
    asm volatile ("pushl %[f]; popfl"
        :
        : [f] "r" (f),
        : .{ .memory = true });
}

fn spin_lock_vga(lock: *volatile u32) void {
    while (@atomicRmw(u32, lock, .Xchg, 1, .acquire) == 1) {
        asm volatile ("pause");
    }
}

fn spin_unlock_vga(lock: *volatile u32) void {
    @atomicStore(u32, lock, 0, .release);
}

pub export fn zig_print_char(c: u8) void {
    if (!vga_initialized) init_dimensions();

    const eflags = interrupts_save_vga();
    spin_lock_vga(&vga_lock);
    defer {
        spin_unlock_vga(&vga_lock);
        interrupts_restore_vga(eflags);
    }

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
            lfb.fill_rect(bx, by, 8, 14, 0x000000);
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
            lfb.draw_char(c, char_x, char_y, vga_attr_to_rgb(attr), vga_attr_to_rgb(attr >> 4), 1);
        }

        cursor_col += 1;
        if (cursor_col >= MAX_COLS) {
            internal_newline();
        }
    }
    // NOTE: No swap_buffers here - flush happens at cursor update (end of batch)
}

pub export fn zig_clear_line(row: u8) void {
    if (row >= MAX_ROWS) return;
    const py = @as(u32, row) * 14;

    // Quick clear via rect
    lfb.fill_rect(0, py, @as(u32, MAX_COLS) * 8, 14, 0x000000);

    // Also clear the VIDEO_MEMORY buffer
    var col: usize = 0;
    while (col < MAX_COLS) : (col += 1) {
        VIDEO_MEMORY[@as(usize, row) * MAX_COLS + col] = DEFAULT_ATTR | ' ';
    }
    // No flush here - flushed by the caller (scroll or manual)
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
            const bx = @as(u32, col) * 8;
            const by = @as(u32, row) * 14;
            lfb.fill_rect(bx, by, 8, 14, 0x000000);
        }

        col += 1;
        if (col >= MAX_COLS) {
            col = 0;
            row += 1;
        }
    }
    // No early flush, wait for shell to redraw chars and flush collectively via cursor update
}

pub export fn zig_draw_char_at(row: u8, col: u8, c: u8) void {
    if (row >= MAX_ROWS or col >= MAX_COLS) return;
    const attr = current_color;
    const idx = @as(usize, row) * MAX_COLS + col;
    VIDEO_MEMORY[idx] = attr | @as(u16, c);

    if (lfb.initialized) {
        const bx = @as(u32, col) * 8;
        const by = @as(u32, row) * 14;
        lfb.draw_char(c, bx, by, vga_attr_to_rgb(attr), vga_attr_to_rgb(attr >> 4), 1);
    }
    // No per-char flush - caller (editor's draw_ui) flushes after all chars are drawn
}

pub export fn draw_indicator(col: u8, attr: u16, c: u8) void {
    const row = 0; // Fixed top row for indicators
    if (col >= MAX_COLS) return;

    const idx = @as(usize, row) * MAX_COLS + col;
    VIDEO_MEMORY[idx] = attr | @as(u16, c);

    if (lfb.initialized) {
        const bx = @as(u32, col) * 8;
        const by = @as(u32, row) * 14;
        lfb.draw_char(c, bx, by, vga_attr_to_rgb(attr), vga_attr_to_rgb(attr >> 4), 1);
    }
    // Indicators drawn in batch, flushed at cursor update
}

// Internal version that assumes lock is already held
fn erase_vga_cursor_internal() void {
    if (!vga_initialized or !cursor_visible) return;
    const r = prev_cursor_row;
    const c = prev_cursor_col;
    if (r >= MAX_ROWS or c >= MAX_COLS) return;

    const idx = @as(usize, r) * MAX_COLS + c;
    const attr_char = VIDEO_MEMORY[idx];
    const char = @as(u8, @intCast(attr_char & 0xFF));
    const attr = attr_char & 0xFF00;

    if (lfb.initialized) {
        const bx = @as(u32, c) * 8;
        const by = @as(u32, r) * 14;
        lfb.draw_char(char, bx, by, vga_attr_to_rgb(attr), vga_attr_to_rgb(attr >> 4), 1);
    }
    cursor_visible = false;
    // flush happens in update_vga_cursor after drawing new cursor position
}

pub export fn erase_vga_cursor() void {
    const eflags = interrupts_save_vga();
    spin_lock_vga(&vga_lock);
    defer {
        spin_unlock_vga(&vga_lock);
        interrupts_restore_vga(eflags);
    }
    erase_vga_cursor_internal();
    lfb.swap_buffers(); // flush after erase
}

pub export fn update_vga_cursor() void {
    if (!vga_initialized) return;

    // Use lock to prevent racing with other core draws
    const eflags = interrupts_save_vga();
    spin_lock_vga(&vga_lock);
    defer {
        spin_unlock_vga(&vga_lock);
        interrupts_restore_vga(eflags);
    }

    if (cursor_visible) erase_vga_cursor_internal();

    const r = cursor_row;
    const c = cursor_col;
    if (r >= MAX_ROWS or c >= MAX_COLS) return;

    const idx = @as(usize, r) * MAX_COLS + c;
    const attr_char = VIDEO_MEMORY[idx];
    var char = @as(u8, @intCast(attr_char & 0xFF));

    // Draw inverted cursor
    if (lfb.initialized) {
        const bx = @as(u32, c) * 8;
        const by = @as(u32, r) * 14;

        // If char is non-printable, draw a block (char 219 often works, or just solid)
        if (char < 32) char = ' '; // Fallback to space for drawing inverted block

        // Invert foreground and background for the cursor block
        lfb.draw_char(char, bx, by, 0x000000, 0xFFFFFF, 1);
    }

    prev_cursor_row = r;
    prev_cursor_col = c;
    cursor_visible = true;
    lfb.swap_buffers();
}

pub export fn update_hardware_cursor() void {
    update_vga_cursor(); // already calls swap_buffers internally
}

pub export fn vga_flush() void {
    lfb.swap_buffers();
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
