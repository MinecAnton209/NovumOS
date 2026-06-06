const config = @import("../config.zig");
const common = @import("../commands/common.zig");
const timer = @import("timer.zig");
const smp = @import("../smp.zig");
const logger = @import("../logger.zig");

const PIT_COMMAND = 0x43;
const PIT_CHANNEL2 = 0x42;
const PPI_PORT_B = 0x61;
const PIT_BASE_FREQ = 1193182;
const FREQ_MIN = 20;
const FREQ_MAX = 20000;

pub const NOTE_C3 = 131;
pub const NOTE_CSH3 = 139;
pub const NOTE_D3 = 147;
pub const NOTE_DSH3 = 156;
pub const NOTE_E3 = 165;
pub const NOTE_F3 = 175;
pub const NOTE_FSH3 = 185;
pub const NOTE_G3 = 196;
pub const NOTE_GSH3 = 208;
pub const NOTE_A3 = 220;
pub const NOTE_ASH3 = 233;
pub const NOTE_B3 = 247;

pub const NOTE_C4 = 262;
pub const NOTE_CSH4 = 277;
pub const NOTE_D4 = 294;
pub const NOTE_DSH4 = 311;
pub const NOTE_E4 = 330;
pub const NOTE_F4 = 349;
pub const NOTE_FSH4 = 370;
pub const NOTE_G4 = 392;
pub const NOTE_GSH4 = 415;
pub const NOTE_A4 = 440;
pub const NOTE_ASH4 = 466;
pub const NOTE_B4 = 494;

pub const NOTE_C5 = 523;
pub const NOTE_CSH5 = 554;
pub const NOTE_D5 = 587;
pub const NOTE_DSH5 = 622;
pub const NOTE_E5 = 659;
pub const NOTE_F5 = 698;
pub const NOTE_FSH5 = 740;
pub const NOTE_G5 = 784;
pub const NOTE_GSH5 = 831;
pub const NOTE_A5 = 880;
pub const NOTE_ASH5 = 932;
pub const NOTE_B5 = 988;

pub const NOTE_C6 = 1047;
pub const NOTE_CSH6 = 1109;
pub const NOTE_D6 = 1175;
pub const NOTE_DSH6 = 1245;
pub const NOTE_E6 = 1319;
pub const NOTE_F6 = 1397;
pub const NOTE_FSH6 = 1480;
pub const NOTE_G6 = 1568;
pub const NOTE_GSH6 = 1661;
pub const NOTE_A6 = 1760;
pub const NOTE_ASH6 = 1865;
pub const NOTE_B6 = 1976;

var speaker_lock: u32 = 0;
var saved_port_b: u8 = 0;

pub fn init() void {
    saved_port_b = common.inb(PPI_PORT_B);
    saved_port_b &= ~@as(u8, 0x03);
    common.outb(PPI_PORT_B, saved_port_b);
}

pub fn on(freq: u32) void {
    if (freq < FREQ_MIN or freq > FREQ_MAX) return;
    smp.spin_lock(&speaker_lock);

    const divisor = PIT_BASE_FREQ / freq;
    common.outb(PIT_COMMAND, 0xB6);
    common.outb(PIT_CHANNEL2, @intCast(divisor & 0xFF));
    common.outb(PIT_CHANNEL2, @intCast((divisor >> 8) & 0xFF));

    saved_port_b = common.inb(PPI_PORT_B);
    common.outb(PPI_PORT_B, saved_port_b | 0x03);

    smp.spin_unlock(&speaker_lock);
}

pub fn off() void {
    smp.spin_lock(&speaker_lock);
    saved_port_b = common.inb(PPI_PORT_B);
    saved_port_b &= ~@as(u8, 0x03);
    common.outb(PPI_PORT_B, saved_port_b);
    smp.spin_unlock(&speaker_lock);
}

pub fn frequency(freq: u32) void {
    if (freq < FREQ_MIN or freq > FREQ_MAX) return;
    if (!is_playing()) return;

    smp.spin_lock(&speaker_lock);
    const divisor = PIT_BASE_FREQ / freq;
    common.outb(PIT_COMMAND, 0xB6);
    common.outb(PIT_CHANNEL2, @intCast(divisor & 0xFF));
    common.outb(PIT_CHANNEL2, @intCast((divisor >> 8) & 0xFF));
    smp.spin_unlock(&speaker_lock);
}

pub fn is_playing() bool {
    return (common.inb(PPI_PORT_B) & 0x03) == 0x03;
}

pub fn silence() void {
    smp.spin_lock(&speaker_lock);
    saved_port_b = common.inb(PPI_PORT_B);
    saved_port_b &= ~@as(u8, 0x03);
    common.outb(PPI_PORT_B, saved_port_b);
    smp.spin_unlock(&speaker_lock);
}

const BeepState = enum(u8) { idle, on, gap, on2 };
var beep_state: BeepState = .idle;
var beep_off_tick: usize = 0;
var beep2_on_tick: usize = 0;
var beep2_off_tick: usize = 0;
var beep2_freq: u32 = 0;

pub fn beep_async(freq: u32, dur_ms: u32) void {
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 3) {
        asm volatile ("int $0x80"
            :
            : [sys] "{eax}" (@as(u32, 42)),
              [op] "{ebx}" (@as(u32, 0)),
              [f] "{ecx}" (freq),
              [d] "{edx}" (dur_ms),
        );
        return;
    }
    if (freq < FREQ_MIN or freq > FREQ_MAX) {
        logger.warn("speaker: frequency out of range");
        return;
    }
    if (is_playing()) return;
    on(freq);
    beep_state = .on;
    beep_off_tick = timer.get_ticks() + (dur_ms * 100 / 1000 + 1);
    beep2_on_tick = 0;
    beep2_off_tick = 0;
    beep2_freq = 0;
}

pub fn beep_pattern_async(freq: u32, dur_ms: u32, gap_ms: u32) void {
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 3) {
        asm volatile ("int $0x80"
            :
            : [sys] "{eax}" (@as(u32, 42)),
              [op] "{ebx}" (@as(u32, 2)),
              [f] "{ecx}" (freq),
              [d] "{edx}" (dur_ms),
              [g] "{esi}" (gap_ms),
        );
        return;
    }
    if (freq < FREQ_MIN or freq > FREQ_MAX) {
        logger.warn("speaker: frequency out of range");
        return;
    }
    if (is_playing()) return;
    on(freq);
    beep_state = .on;
    beep_off_tick = timer.get_ticks() + (dur_ms * 100 / 1000 + 1);
    beep2_freq = freq;
    beep2_on_tick = beep_off_tick + (gap_ms * 100 / 1000);
    beep2_off_tick = beep2_on_tick + (dur_ms * 100 / 1000 + 1);
}

pub fn beep_async_check() void {
    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 3) {
        asm volatile ("int $0x80"
            :
            : [sys] "{eax}" (@as(u32, 42)),
              [op] "{ebx}" (@as(u32, 1)),
        );
        return;
    }
    const now = timer.get_ticks();
    switch (beep_state) {
        .idle => {
            if (is_playing()) {
                silence();
            }
        },
        .on => {
            if (now >= beep_off_tick) {
                off();
                beep_state = if (beep2_on_tick == 0) .idle else .gap;
            }
        },
        .gap => {
            if (now >= beep2_on_tick) {
                on(beep2_freq);
                beep_state = .on2;
            }
        },
        .on2 => {
            if (now >= beep2_off_tick) {
                off();
                beep_state = .idle;
                beep2_freq = 0;
            }
        },
    }
}

pub fn beep_async_is_pending() bool {
    return beep_state != .idle;
}

/// Tick handler — called from timer ISR (100Hz). Drives async beep state machine.
/// Safety check (silence if stuck on) is NOT done here because blocking beep()
/// legitimately has the speaker on while state is idle.
pub fn beep_async_tick() void {
    if (beep_state == .idle) return;
    beep_async_check();
}

pub fn beep(freq: u32, dur_ms: u32) void {
    if (freq < FREQ_MIN or freq > FREQ_MAX) {
        logger.warn("speaker: frequency out of range");
        return;
    }
    if (is_playing()) return;

    on(freq);
    timer.sleep(dur_ms);
    off();
}

pub const Note = struct {
    freq: u32,
    dur_ms: u32,
};

pub fn play(notes: []const Note) void {
    for (notes) |note| {
        beep(note.freq, note.dur_ms);
    }
}
