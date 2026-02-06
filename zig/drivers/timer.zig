// PIT (Programmable Interval Timer) Driver
const common = @import("../commands/common.zig");

// PIT Ports
const PIT_COMMAND = 0x43;
const PIT_CHANNEL0 = 0x40;

// PIT Frequency
const PIT_FREQ = 1193182;
const TARGET_FREQ = 1000; // 1 tick = 1ms

var ticks: usize = 0;

/// Initialize PIT to 1000Hz
pub fn init() void {
    const divisor = PIT_FREQ / TARGET_FREQ;

    // Command byte:
    // Channel 0 (00), Access Mode: LSB/MSB (11), Mode 2: Rate Generator (010), Binary (0)
    // 00 11 010 0 = 0x34
    outb(PIT_COMMAND, 0x34);
    outb(PIT_CHANNEL0, @intCast(divisor & 0xFF));
    outb(PIT_CHANNEL0, @intCast((divisor >> 8) & 0xFF));
}

/// IRQ0 Timer Handler (called from ASM)
pub export fn isr_timer() void {
    const ptr = @as(*volatile usize, &ticks);
    ptr.* += 1;

    // Poll serial for input to support -nographic
    const serial = @import("serial.zig");
    if (serial.serial_has_data()) {
        const c = serial.serial_getchar();
        if (c != 0) {
            const keyboard = @import("../keyboard_isr.zig");
            keyboard.serial_inject_char(c);
        }
    }
}

/// Get elapsed seconds since boot
pub fn get_uptime() usize {
    const ptr = @as(*volatile usize, &ticks);
    return ptr.* / 1000;
}

/// Get elapsed ticks (ms) since boot
pub fn get_ticks() usize {
    return ticks;
}

/// Precise sleep for a number of milliseconds
pub fn sleep(ms: usize) void {
    const ptr = @as(*volatile usize, &ticks);
    const start_ticks = ptr.*;
    while (ptr.* - start_ticks < ms) {
        // Wait for next interrupt
        asm volatile ("sti");
        asm volatile ("hlt");
    }
}

// I/O port functions
fn outb(port: u16, val: u8) void {
    asm volatile ("outb %[val], %[port]"
        :
        : [val] "{al}" (val),
          [port] "{dx}" (port),
    );
}
