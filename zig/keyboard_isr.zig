// Keyboard interrupt handler for NovumOS
const std = @import("std");

// Keyboard buffer
const BUFFER_SIZE = 256;
var keyboard_buffer: [BUFFER_SIZE]u8 = undefined;
var buffer_head: usize = 0;
var buffer_tail: usize = 0;

// Extended keys constants (matches kernel32.asm)
pub const KEY_UP = 0x80;
pub const KEY_DOWN = 0x81;
pub const KEY_LEFT = 0x82;
pub const KEY_RIGHT = 0x83;
pub const KEY_INSERT = 0x84;
pub const KEY_HOME = 0x85;
pub const KEY_END = 0x86;
pub const KEY_DELETE = 0x87;
pub const KEY_CAPS = 0x88;
pub const KEY_NUM = 0x89;
pub const KEY_F1 = 0x90;
pub const KEY_F2 = 0x91;
pub const KEY_F10 = 0x99;
pub const KEY_PGUP = 0x8A;
pub const KEY_PGDN = 0x8B;
pub const KEY_ESC = 27;

// Scancode tables
const scancode = [_]u8{
    0, 27, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 8, // 0x00-0x0E
    9, 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', 10, // 0x0F-0x1C
    0, 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', '`', // 0x1D-0x29 (0x1D is Ctrl)
    0, '\\', 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', 0, // 0x2A-0x36 (0x2A is LShift, 0x36 is RShift)
    '*', 0, ' ', // 0x37-0x39 (0x37 is *, 0x38 is Alt)
} ++ [_]u8{0} ** (128 - 58);

const scancode_shift = [_]u8{
    0,   27,  '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+', 8,
    0,   'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', 10,  0,
    'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"', '~', 0,   '|', 'Z',
    'X', 'C', 'V', 'B', 'N', 'M', '<', '>', '?', 0,   '*', 0,   ' ',
} ++ [_]u8{0} ** (128 - 58);

// Keyboard state
var shift_pressed: bool = false;
var ctrl_pressed: bool = false;
var extended_key: bool = false;
var num_lock: bool = true; // Traditionally ON by default
var caps_lock: bool = false;

// I/O port functions
fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[result]"
        : [result] "={al}" (-> u8),
        : [port] "{dx}" (port),
    );
}

// Keyboard interrupt handler (called from ASM wrapper)
pub export fn isr_keyboard() void {
    const scancode_byte = inb(0x60);

    // Handle extended keys prefix
    if (scancode_byte == 0xE0) {
        extended_key = true;
        return;
    }

    // Handle shift keys
    if (scancode_byte == 0x2A or scancode_byte == 0x36) {
        shift_pressed = true;
        return;
    }
    if (scancode_byte == 0xAA or scancode_byte == 0xB6) {
        shift_pressed = false;
        return;
    }

    // Handle ctrl keys
    if (scancode_byte == 0x1D) {
        ctrl_pressed = true;
        return;
    }
    if (scancode_byte == 0x9D) {
        ctrl_pressed = false;
        return;
    }

    // Ignore key releases (high bit set)
    if ((scancode_byte & 0x80) != 0) {
        extended_key = false; // Reset extended key on release too
        return;
    }

    var ascii: u8 = 0;

    if (extended_key) {
        extended_key = false;
        ascii = switch (scancode_byte) {
            0x48 => KEY_UP,
            0x50 => KEY_DOWN,
            0x4B => KEY_LEFT,
            0x4D => KEY_RIGHT,
            0x47 => KEY_HOME,
            0x4F => KEY_END,
            0x53 => KEY_DELETE,
            0x52 => KEY_INSERT,
            0x49 => KEY_PGUP,
            0x51 => KEY_PGDN,
            0x35 => '/', // Numpad / (extended)
            else => 0,
        };
    } else {
        // Handle Caps Lock toggle (scancode 0x3A)
        if (scancode_byte == 0x3A) {
            caps_lock = !caps_lock;
            ascii = KEY_CAPS;
        } else if (scancode_byte == 0x45) {
            // Handle Num Lock toggle (scancode 0x45)
            num_lock = !num_lock;
            ascii = KEY_NUM;
        } else if (scancode_byte >= 0x47 and scancode_byte <= 0x53) {
            // Handle Numpad codes (0x47 to 0x53)
            if (num_lock) {
                ascii = switch (scancode_byte) {
                    0x47 => '7',
                    0x48 => '8',
                    0x49 => '9',
                    0x4B => '4',
                    0x4C => '5',
                    0x4D => '6',
                    0x4F => '1',
                    0x50 => '2',
                    0x51 => '3',
                    0x52 => '0',
                    0x53 => '.',
                    0x4A => '-',
                    0x4E => '+',
                    else => 0,
                };
            } else {
                ascii = switch (scancode_byte) {
                    0x47 => KEY_HOME,
                    0x48 => KEY_UP,
                    0x4B => KEY_LEFT,
                    0x4D => KEY_RIGHT,
                    0x4F => KEY_END,
                    0x50 => KEY_DOWN,
                    0x49 => KEY_PGUP,
                    0x51 => KEY_PGDN,
                    0x52 => KEY_INSERT,
                    0x53 => KEY_DELETE,
                    0x4A => '-',
                    0x4E => '+',
                    else => 0,
                };
            }
        } else if (scancode_byte >= 0x3B and scancode_byte <= 0x44) {
            // Function keys F1-F10
            ascii = KEY_F1 + (scancode_byte - 0x3B);
        } else if (scancode_byte == 0x37) {
            ascii = '*';
        } else if (scancode_byte == 0x4A) {
            ascii = '-';
        } else if (scancode_byte == 0x4E) {
            ascii = '+';
        } else {
            // Convert standard scancode to ASCII
            ascii = if (shift_pressed)
                scancode_shift[scancode_byte]
            else
                scancode[scancode_byte];

            if (ctrl_pressed) {
                if (ascii == 'c' or ascii == 'C') {
                    ascii = 3;
                }
            }

            // Correct Caps Lock logic: it reverses the Shift state for letters
            if (caps_lock) {
                if (ascii >= 'a' and ascii <= 'z') {
                    ascii -= 32;
                } else if (ascii >= 'A' and ascii <= 'Z') {
                    ascii += 32;
                }
            }
        }
    }

    // Add to buffer if valid character
    if (ascii != 0) {
        inject_into_buffer(ascii);
    }
}

var serial_esc_state: u8 = 0;
pub fn serial_inject_char(c: u8) void {
    if (serial_esc_state == 0) {
        if (c == 27) {
            serial_esc_state = 1;
        } else if (c == 127) {
            inject_into_buffer(8);
        } else {
            inject_into_buffer(if (c == 13) 10 else c);
        }
    } else if (serial_esc_state == 1) {
        if (c == '[') {
            serial_esc_state = 2;
        } else {
            inject_into_buffer(27);
            inject_into_buffer(c);
            serial_esc_state = 0;
        }
    } else if (serial_esc_state == 2) {
        var ascii: u8 = 0;
        switch (c) {
            'A' => ascii = KEY_UP,
            'B' => ascii = KEY_DOWN,
            'C' => ascii = KEY_RIGHT,
            'D' => ascii = KEY_LEFT,
            'H' => ascii = KEY_HOME,
            'F' => ascii = KEY_END,
            '3' => {
                serial_esc_state = 3;
                return;
            },
            '1' => {
                serial_esc_state = 4;
                return;
            },
            '4' => {
                serial_esc_state = 5;
                return;
            },
            else => {
                inject_into_buffer(27);
                inject_into_buffer('[');
                inject_into_buffer(c);
                serial_esc_state = 0;
                return;
            },
        }
        if (ascii != 0) inject_into_buffer(ascii);
        serial_esc_state = 0;
    } else if (serial_esc_state == 3) { // ESC [ 3 ...
        if (c == '~') inject_into_buffer(KEY_DELETE);
        serial_esc_state = 0;
    } else if (serial_esc_state == 4) { // ESC [ 1 ...
        if (c == '~') inject_into_buffer(KEY_HOME);
        serial_esc_state = 0;
    } else if (serial_esc_state == 5) { // ESC [ 4 ...
        if (c == '~') inject_into_buffer(KEY_END);
        serial_esc_state = 0;
    }
}

fn inject_into_buffer(ascii: u8) void {
    if (ascii == 0) return;
    const head_ptr = @as(*volatile usize, &buffer_head);
    const tail = @as(*volatile usize, &buffer_tail).*;
    const next_head = (head_ptr.* + 1) % BUFFER_SIZE;
    if (next_head != tail) {
        keyboard_buffer[head_ptr.*] = ascii;
        head_ptr.* = next_head;
    }
}

// Get character from buffer (non-blocking)
pub export fn keyboard_getchar() u8 {
    const head = @as(*volatile usize, &buffer_head).*;
    const tail_ptr = @as(*volatile usize, &buffer_tail);
    if (tail_ptr.* == head) {
        return 0; // Buffer empty
    }

    const ch = keyboard_buffer[tail_ptr.*];
    tail_ptr.* = (tail_ptr.* + 1) % BUFFER_SIZE;
    return ch;
}

// Check if buffer has data
pub export fn keyboard_has_data() bool {
    const head = @as(*volatile usize, &buffer_head).*;
    const tail = @as(*volatile usize, &buffer_tail).*;
    return tail != head;
}

pub export fn keyboard_get_caps_lock() bool {
    return caps_lock;
}
pub export fn keyboard_get_num_lock() bool {
    return num_lock;
}
pub export fn keyboard_get_ctrl() bool {
    return ctrl_pressed;
}

// Wait for character (blocking)
pub export fn keyboard_wait_char() u8 {
    const serial = @import("drivers/serial.zig");
    while (true) {
        if (keyboard_has_data()) return keyboard_getchar();

        // Poll serial port as well
        if (serial.serial_has_data()) {
            serial_inject_char(serial.serial_getchar());
            if (keyboard_has_data()) return keyboard_getchar();
        }

        // Ensure interrupts are enabled and wait briefly
        asm volatile ("sti");
        asm volatile ("hlt");
    }
}

pub fn check_ctrl_c() bool {
    if (keyboard_has_data()) {
        if (keyboard_buffer[buffer_tail] == 3) {
            _ = keyboard_getchar();
            return true;
        }
    }
    return false;
}
