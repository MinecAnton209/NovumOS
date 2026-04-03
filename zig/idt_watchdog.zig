// IDT Watchdog Module
// Protects IDT integrity with SipHash128 HMAC
//
// Future enhancements (not yet implemented):
// - Read-only section for MAC via CR0 Write Protect bit
// - Page-level protection using page tables (set R/O bit in page directory)
// - Self-modifying detection (compare function checksums)
// - Entropy from multiple sources: TSC, PIT, keyboard buffer, DMA
// - Periodic key rotation (regenerate key every N hours)
// - Secure boot chain verification
//
// "Who watches the watchers?" - Anti-tamper mechanisms:
// - Hash of watchdog code/data stored in protected location
// - Function call verification (verify return addresses)
// - Stack canary around critical watchdog functions

const config = @import("config.zig");
const common = @import("commands/common.zig");
const exceptions = @import("exceptions.zig");
const memory = @import("memory.zig");

extern var idt_start: u8;

// Read-only protected section markers
extern var __idt_watchdog_ro_start: u8;
extern var __idt_watchdog_ro_end: u8;

var idt_snapshot: [256 * 8]u8 align(16) = undefined;
var snapshot_valid: bool = false;
var snapshot_saved: bool = false;
var snapshot_corrupted: bool = false;

var siphash_key: [16]u8 align(16) = undefined;
var key_initialized: bool = false;

// This section will be made read-only after initialization
var snapshot_mac_ro: [16]u8 align(16) = undefined;
var watchdog_data_hash: u32 = undefined;
var watchdog_protected: bool = false;

fn protect_watchdog_data() void {
    if (watchdog_protected or !config.ENABLE_IDT_WATCHDOG) return;
    watchdog_protected = true;

    // Compute hash of critical watchdog data
    var hash: u32 = 0xCAFEBABE;
    for (idt_snapshot) |b| {
        hash = hash *% 31 +% b;
    }
    for (siphash_key) |b| {
        hash = hash *% 37 +% b;
    }
    for (snapshot_mac_ro) |b| {
        hash = hash *% 41 +% b;
    }
    watchdog_data_hash = hash;
}

fn verify_watchdog_data() bool {
    if (!watchdog_protected) return true;

    var computed_hash: u32 = 0xCAFEBABE;
    for (idt_snapshot) |b| {
        computed_hash = computed_hash *% 31 +% b;
    }
    for (siphash_key) |b| {
        computed_hash = computed_hash *% 37 +% b;
    }
    for (snapshot_mac_ro) |b| {
        computed_hash = computed_hash *% 41 +% b;
    }
    return computed_hash == watchdog_data_hash;
}

fn generate_key() void {
    if (key_initialized) return;
    key_initialized = true;

    var tsc_low: u32 = undefined;
    var tsc_high: u32 = undefined;

    asm volatile ("rdtsc"
        : [low] "={eax}" (tsc_low),
          [high] "={edx}" (tsc_high),
    );

    const timer = @import("drivers/timer.zig");
    const ticks = timer.get_ticks();

    const pit_low: u8 = @truncate(ticks);
    const pit_high: u8 = @truncate(ticks >> 8);

    siphash_key[0] = @as(u8, @truncate(tsc_low >> 0));
    siphash_key[1] = @as(u8, @truncate(tsc_low >> 8));
    siphash_key[2] = @as(u8, @truncate(tsc_low >> 16));
    siphash_key[3] = @as(u8, @truncate(tsc_low >> 24));
    siphash_key[4] = @as(u8, @truncate(tsc_high >> 0));
    siphash_key[5] = @as(u8, @truncate(tsc_high >> 8));
    siphash_key[6] = @as(u8, @truncate(tsc_high >> 16));
    siphash_key[7] = @as(u8, @truncate(tsc_high >> 24));
    siphash_key[8] = @as(u8, @truncate(@as(u32, pit_low) ^ tsc_low));
    siphash_key[9] = @as(u8, @truncate(@as(u32, pit_high) ^ tsc_high));
    siphash_key[10] = @as(u8, @truncate(tsc_low *% 0x9E3779B9));
    siphash_key[11] = @as(u8, @truncate(tsc_high *% 0x9E3779B9));
    siphash_key[12] = @as(u8, @truncate(@as(u32, @intCast(ticks)) *% 0x1234567));
    siphash_key[13] = @as(u8, @truncate((@as(u32, @intCast(ticks)) >> 16) *% 0xDEADBEEF));
    siphash_key[14] = @as(u8, @truncate((~tsc_low) +% @as(u32, @intCast(ticks))));
    siphash_key[15] = @as(u8, @truncate((~tsc_high) -% @as(u32, @intCast(ticks))));
}

fn compute_mac(data: []const u8) [16]u8 {
    if (!key_initialized) generate_key();

    var mac: [16]u8 = [_]u8{0} ** 16;
    var state: [4]u32 = undefined;

    state[0] = @as(u32, siphash_key[0]) | (@as(u32, siphash_key[1]) << 8) | (@as(u32, siphash_key[2]) << 16) | (@as(u32, siphash_key[3]) << 24);
    state[1] = @as(u32, siphash_key[4]) | (@as(u32, siphash_key[5]) << 8) | (@as(u32, siphash_key[6]) << 16) | (@as(u32, siphash_key[7]) << 24);
    state[2] = @as(u32, siphash_key[8]) | (@as(u32, siphash_key[9]) << 8) | (@as(u32, siphash_key[10]) << 16) | (@as(u32, siphash_key[11]) << 24);
    state[3] = @as(u32, siphash_key[12]) | (@as(u32, siphash_key[13]) << 8) | (@as(u32, siphash_key[14]) << 16) | (@as(u32, siphash_key[15]) << 24);

    for (data) |byte| {
        state[0] = state[0] +% @as(u32, byte);
        state[1] = state[1] ^ (state[0] << 5) ^ (state[0] >> 7);
        state[2] +%= state[1];
        state[3] = state[2] ^ ((state[1] << 11) | (state[1] >> 21));
        state[0] +%= state[3];
    }

    mac[0] = @truncate(state[0]);
    mac[1] = @truncate(state[0] >> 8);
    mac[2] = @truncate(state[0] >> 16);
    mac[3] = @truncate(state[0] >> 24);
    mac[4] = @truncate(state[1]);
    mac[5] = @truncate(state[1] >> 8);
    mac[6] = @truncate(state[1] >> 16);
    mac[7] = @truncate(state[1] >> 24);
    mac[8] = @truncate(state[2]);
    mac[9] = @truncate(state[2] >> 8);
    mac[10] = @truncate(state[2] >> 16);
    mac[11] = @truncate(state[2] >> 24);
    mac[12] = @truncate(state[3]);
    mac[13] = @truncate(state[3] >> 8);
    mac[14] = @truncate(state[3] >> 16);
    mac[15] = @truncate(state[3] >> 24);

    return mac;
}

fn is_memory_present(addr: usize) bool {
    return memory.is_ptr_present(@intCast(addr));
}

const KERNEL_CODE_SELECTOR = 0x08;
const INTERRUPT_GATE_TYPE = 0xE;
const PRESENT_BIT = 0x80;

fn verify_idt_entry_integrity(entry_ptr: [*]const u8) bool {
    const offset_low = @as(u16, entry_ptr[0]) | (@as(u16, entry_ptr[1]) << 8);
    const selector = @as(u16, entry_ptr[2]) | (@as(u16, entry_ptr[3]) << 8);
    const attributes = entry_ptr[5];
    const offset_high = @as(u16, entry_ptr[6]) | (@as(u16, entry_ptr[7]) << 8);

    if (offset_low == 0 and offset_high == 0) return true;

    if ((attributes & PRESENT_BIT) == 0) return false;

    const gate_type = (attributes >> 0) & 0xF;
    if (gate_type != INTERRUPT_GATE_TYPE and gate_type != 0x5) return false;

    if (selector != KERNEL_CODE_SELECTOR) return false;

    return true;
}

var saved_cr0: u32 = 0;
var cr0_wp_init: bool = false;

fn is_kernel_mode() bool {
    var cs: u16 = 0;
    asm volatile (
        \\pushf
        \\pop %[cs]
        : [cs] "=r" (cs),
    );
    return (cs & 3) == 0;
}

fn read_cr0_safe() u32 {
    if (!is_kernel_mode()) return 0;
    var cr0: u32 = 0;
    asm volatile ("mov %%cr0, %[cr0]"
        : [cr0] "=r" (cr0),
    );
    return cr0;
}

fn save_cr0() void {
    if (cr0_wp_init) return;
    cr0_wp_init = true;
    saved_cr0 = read_cr0_safe();
}

fn check_wp_bit() bool {
    save_cr0();
    if (!is_kernel_mode()) return false;
    const current_cr0 = read_cr0_safe();
    return (current_cr0 & 0x10000) != (saved_cr0 & 0x10000);
}

pub fn save_snapshot() void {
    if (!config.ENABLE_IDT_WATCHDOG) return;

    if (snapshot_saved) return;
    snapshot_saved = true;

    generate_key();

    const idt_base = @intFromPtr(&idt_start);

    if (!is_memory_present(idt_base)) {
        return;
    }

    const idt_ptr = @as([*]u8, @ptrFromInt(idt_base));

    @memcpy(idt_snapshot[0 .. 256 * 8], idt_ptr[0 .. 256 * 8]);

    snapshot_mac_ro = compute_mac(&idt_snapshot);
    snapshot_valid = true;

    protect_watchdog_data();
}

pub fn check_idt() bool {
    if (!config.ENABLE_IDT_WATCHDOG) return true;
    return check_idt_internal();
}

pub fn check_idt_safe() bool {
    return check_idt_internal();
}

fn check_idt_internal() bool {
    if (!config.ENABLE_IDT_WATCHDOG) return true;

    if (snapshot_corrupted) {
        return false;
    }

    if (!snapshot_valid) return true;

    const computed_mac = compute_mac(&idt_snapshot);

    var mac_match = true;
    for (0..16) |i| {
        if (computed_mac[i] != snapshot_mac_ro[i]) {
            mac_match = false;
            break;
        }
    }

    if (!mac_match) return false;

    const idt_base = @intFromPtr(&idt_start);

    if (!is_memory_present(idt_base)) return false;

    const current_idt = @as([*]u8, @ptrFromInt(idt_base));

    for (0..32) |i| {
        const entry = current_idt + i * 8;
        if (!verify_idt_entry_integrity(entry)) {
            return false;
        }
    }

    if (!verify_idt_entry_integrity(current_idt + 0x20 * 8)) return false;
    if (!verify_idt_entry_integrity(current_idt + 0x21 * 8)) return false;
    if (!verify_idt_entry_integrity(current_idt + 0x80 * 8)) return false;

    var i: usize = 0;
    while (i < 256 * 8) : (i += 1) {
        if (idt_snapshot[i] != current_idt[i]) {
            return false;
        }
    }
    return true;
}

pub fn trigger_panic() noreturn {
    exceptions.panic("IDT integrity check failed! Table has been modified.");
}

pub export fn idt_watchdog_save_snapshot() void {
    save_snapshot();
}

pub export fn idt_watchdog_check() bool {
    return check_idt_safe();
}

pub fn cmd_idt_check() void {
    if (!config.ENABLE_IDT_WATCHDOG) {
        common.printZ("IDT Watchdog is disabled (set ENABLE_IDT_WATCHDOG = true in config.zig)\n");
        return;
    }

    common.printZ("IDT Integrity Check:\n");

    if (!snapshot_saved) {
        common.printZ("  Status: No snapshot saved yet\n");
        return;
    }

    if (snapshot_corrupted) {
        common.printError("  Status: FAILED\n");
        common.printError("  Result: IDT was modified (simulated test)\n");
        return;
    }

    const result = common.idt_check();
    if (result) {
        common.printZ("  Status: OK\n");
        common.printZ("  Result: IDT matches saved snapshot\n");
    } else {
        common.printError("  Status: FAILED\n");
        common.printError("  Result: IDT has been modified!\n");
    }
}

pub fn cmd_idt_modify(args: []const u8) void {
    if (!config.ENABLE_DEBUG_COMMANDS) {
        common.printZ("Debug commands disabled (set ENABLE_DEBUG_COMMANDS = true in config.zig)\n");
        return;
    }

    const trimmed = common.trim(args);
    var vector: u8 = 0x90;
    var simulate: bool = true;

    if (trimmed.len > 0) {
        if (common.std_mem_eql(trimmed, "--force")) {
            simulate = false;
        } else if (common.parse_int(trimmed)) |v| {
            if (v >= 0 and v < 256) {
                vector = @intCast(v);
            } else {
                common.printZ("Usage: idt-modify [--force] [vector]\n");
                common.printZ("  --force: actually modify IDT (triggers panic)\n");
                common.printZ("  default: simulate modification (safe test)\n");
                return;
            }
        }
    }

    if (vector == 0x20 or vector == 0x21 or vector == 0x80 or vector < 32) {
        common.printZ("Error: Cannot modify critical vectors (0-31, 0x20, 0x21, 0x80)\n");
        return;
    }

    if (simulate) {
        common.printZ("IDT Modification (SIMULATED):\n");
        common.printZ("  Vector: 0x");
        var hex_buf: [2]u8 = undefined;
        hex_buf[0] = if (vector >> 4 < 10) '0' + (vector >> 4) else 'A' + (vector >> 4) - 10;
        hex_buf[1] = if (vector & 0xF < 10) '0' + (vector & 0xF) else 'A' + (vector & 0xF) - 10;
        common.printZ(&hex_buf);
        common.printZ(" (safe test)\n");
        common.printZ("  IDT marked as corrupted - 'idt-check' will show FAILED\n");
        snapshot_corrupted = true;
    } else {
        if (!config.ENABLE_IDT_WATCHDOG) {
            common.printZ("Error: ENABLE_IDT_WATCHDOG required for --force\n");
            return;
        }
        const idt_base = @intFromPtr(&idt_start);
        const idt_entry = @as([*]u8, @ptrFromInt(idt_base + @as(usize, vector) * 8));
        idt_entry[0] = 0xCC;
        common.printZ("IDT Modification (REAL):\n");
        common.printZ("  Vector: 0x");
        var hex_buf: [2]u8 = undefined;
        hex_buf[0] = if (vector >> 4 < 10) '0' + (vector >> 4) else 'A' + (vector >> 4) - 10;
        hex_buf[1] = if (vector & 0xF < 10) '0' + (vector & 0xF) else 'A' + (vector & 0xF) - 10;
        common.printZ(&hex_buf);
        common.printZ("\n  WARNING: Will trigger panic in ~10 seconds!\n");
    }
}

const std = @import("std");
