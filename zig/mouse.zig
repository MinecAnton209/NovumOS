const events = @import("events.zig");
const config = @import("config.zig");

pub var initialized: bool = false;
pub var last_buttons: u8 = 0;
pub var packet_count: u32 = 0;
pub var init_debug: u32 = 0;

var cycle: u8 = 0;
var packet: [3]u8 = undefined;

fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[ret]"
        : [ret] "={al}" (-> u8),
        : [port] "{dx}" (port),
    );
}

fn outb(port: u16, val: u8) void {
    asm volatile ("outb %[val], %[port]"
        :
        : [val] "{al}" (val),
          [port] "{dx}" (port),
    );
}

fn wait_ack() bool {
    var i: u32 = 0;
    while (i < 10000) : (i += 1) {
        if ((inb(0x64) & 1) != 0) {
            return inb(0x60) == 0xFA;
        }
    }
    return false;
}

fn wait_input_empty() bool {
    var i: u32 = 0;
    while (i < 10000) : (i += 1) {
        if ((inb(0x64) & 2) == 0) return true;
    }
    return false;
}

fn mouse_write(cmd: u8) bool {
    if (!wait_input_empty()) return false;
    outb(0x64, 0xD4); // Tell controller: next byte goes to mouse
    if (!wait_input_empty()) return false;
    outb(0x60, cmd);
    return wait_ack();
}

fn pic_mask_irq12(mask: bool) void {
    const cur = inb(0xA1);
    if (mask) {
        outb(0xA1, cur | 0x10);
    } else {
        outb(0xA1, cur & 0xEF);
    }
}

pub fn init() void {
    const common = @import("commands/common.zig");

    // Mask IRQ12 during init so the ISR doesn't steal ACK bytes
    pic_mask_irq12(true);
    defer pic_mask_irq12(false);

    // Flush any stale data from PS/2 output buffer
    var i: u32 = 0;
    while (i < 100 and (inb(0x64) & 1) != 0) : (i += 1) {
        _ = inb(0x60);
    }

    // Wait for controller ready
    init_debug = 1;
    if (!wait_input_empty()) { init_debug = 10; if (config.MOUSE_DEBUG) common.printZ("mouse: wait empty fail\n"); return; }

    // Enable the auxiliary device (mouse) — controller command, no ACK
    init_debug = 2;
    outb(0x64, 0xA8);
    if (config.MOUSE_DEBUG) common.printZ("mouse: aux enabled\n");

    // Set PS/2 controller command byte directly: enable both devices, IRQ12, standard translation
    // 0x47 = bit 0 (keyboard IRQ) | bit 1 (mouse IRQ) | bit 2 (system) | bit 6 (translate)
    init_debug = 3;
    if (!wait_input_empty()) { init_debug = 30; if (config.MOUSE_DEBUG) common.printZ("mouse: wait empty before cmd byte\n"); return; }
    outb(0x64, 0x60);
    if (!wait_input_empty()) { init_debug = 31; if (config.MOUSE_DEBUG) common.printZ("mouse: wait empty before data\n"); return; }
    outb(0x60, 0x47);

    // Set default settings
    init_debug = 5;
    if (!mouse_write(0xF6)) { init_debug = 50; if (config.MOUSE_DEBUG) common.printZ("mouse: 0xF6 no ack\n"); return; }

    // Set resolution: 8 counts/mm
    init_debug = 6;
    if (!mouse_write(0xE8)) { init_debug = 60; if (config.MOUSE_DEBUG) common.printZ("mouse: 0xE8 no ack\n"); return; }
    if (!mouse_write(0x03)) { init_debug = 61; if (config.MOUSE_DEBUG) common.printZ("mouse: 0x03 no ack\n"); return; }

    // Set sample rate: 40 reports/sec
    init_debug = 7;
    if (!mouse_write(0xF3)) { init_debug = 70; if (config.MOUSE_DEBUG) common.printZ("mouse: 0xF3 no ack\n"); return; }
    if (!mouse_write(0x28)) { init_debug = 71; if (config.MOUSE_DEBUG) common.printZ("mouse: 0x28 no ack\n"); return; }

    // Enable data reporting
    init_debug = 8;
    if (!mouse_write(0xF4)) { init_debug = 80; if (config.MOUSE_DEBUG) common.printZ("mouse: 0xF4 no ack\n"); return; }

    init_debug = 9;
    if (config.MOUSE_DEBUG) common.printZ("mouse: initialized!\n");
    initialized = true;
}

pub export fn isr_mouse() void {
    const data = inb(0x60);

    // Bit 3 must be 1 on first byte (sync anchor)
    if (cycle == 0 and (data & 0x08) == 0) return;

    packet[cycle] = data;
    cycle += 1;

    if (cycle < 3) return;
    cycle = 0;
    packet_count += 1;

    const b0 = packet[0];
    var dx: i32 = packet[1];
    var dy: i32 = packet[2];

    // Two's complement unpack for 9-bit signed values
    if ((b0 & 0x10) != 0) dx -= 256;
    if ((b0 & 0x20) != 0) dy -= 256;

    const buttons = b0 & 0x07;
    const prev = last_buttons;
    last_buttons = buttons;

    // Button transitions
    if (prev != buttons) {
        if ((buttons & 1) != 0 and (prev & 1) == 0)
            events.push(4, 1, 0, 0, buttons); // left down
        if ((buttons & 1) == 0 and (prev & 1) != 0)
            events.push(5, 1, 0, 0, buttons); // left up
        if ((buttons & 2) != 0 and (prev & 2) == 0)
            events.push(4, 2, 0, 0, buttons); // right down
        if ((buttons & 2) == 0 and (prev & 2) != 0)
            events.push(5, 2, 0, 0, buttons); // right up
        if ((buttons & 4) != 0 and (prev & 4) == 0)
            events.push(4, 3, 0, 0, buttons); // middle down
        if ((buttons & 4) == 0 and (prev & 4) != 0)
            events.push(5, 3, 0, 0, buttons); // middle up
    }

    // Mouse move event (Y inverted for screen coords)
    events.push(3, 0, dx, -dy, buttons);
}
