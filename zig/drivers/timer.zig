// PIT (Programmable Interval Timer) Driver
const common = @import("../commands/common.zig");
const config = @import("../config.zig");
const idt_watchdog = @import("../idt_watchdog.zig");

// PIT Ports
const PIT_COMMAND = 0x43;
const PIT_CHANNEL0 = 0x40;

// PIT Frequency
const PIT_FREQ = 1193182;
const TARGET_FREQ = 100; // 1 tick = 10ms

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
pub export fn isr_timer(esp: u32) u32 {
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

    // IDT watchdog check every 1000 ticks (10 seconds)
    if (ptr.* % 1000 == 0 and ptr.* > 1000) {
        if (!idt_watchdog.check_idt_safe()) {
            idt_watchdog.trigger_panic();
        }
    }

    const scheduler = @import("../scheduler.zig");
    return scheduler.schedule(esp);
}

/// Get elapsed seconds since boot
pub fn get_uptime() usize {
    const ptr = @as(*volatile usize, &ticks);
    return ptr.* / TARGET_FREQ;
}

/// Get elapsed ticks (ms) since boot
pub fn get_ticks() usize {
    return ticks;
}

/// Precise sleep for a number of milliseconds
pub fn sleep(ms: usize) void {
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 3) {
        asm volatile ("int $0x80"
            :
            : [sys] "{eax}" (@as(u32, 10)),
              [val] "{ebx}" (@as(u32, @intCast(ms))),
        );
        return;
    }

    const ptr = @as(*volatile usize, &ticks);
    const start_ticks = ptr.*;
    const ms_per_tick = 1000 / TARGET_FREQ;
    const ticks_to_wait = (ms + ms_per_tick - 1) / ms_per_tick;

    while (ptr.* - start_ticks < ticks_to_wait) {
        // Wait for next interrupt
        asm volatile ("sti");
        asm volatile ("hlt");
    }
}

// I/O port functions
fn outb(port: u16, val: u8) void {
    common.outb(port, val);
}
