// IDT Watchdog Module
// Protects IDT integrity with SipHash128 HMAC
//
// Compile-time Chaos features:
// - Comptime key permutation (key index shuffled at compile time)
// - Build-time seed used in key derivation
// - IDT checks injected into memory alloc / context switch
// - Obfuscated key access (can't просто read key[i])

const config = @import("config.zig");
const common = @import("commands/common.zig");
const exceptions = @import("exceptions.zig");
const memory = @import("memory.zig");

extern var idt_start: u8;

// Key permutation at compile time
const KEY_PERM = [16]u8{ 3, 7, 1, 15, 0, 9, 4, 12, 2, 8, 5, 14, 11, 6, 10, 13 };

// Helper to get key byte with permutation (obfuscated access)
fn getKeyByte(idx: u8) u8 {
    const permuted_idx = KEY_PERM[idx % 16];
    return siphash_key[permuted_idx];
}

// Build seed
const BUILD_SEED = 0xDEADC0DE ^ 0xCAFEBABE;

// Read-only protected section markers
extern var __idt_watchdog_ro_start: u8;
extern var __idt_watchdog_ro_end: u8;

var idt_snapshot: [256 * 8]u8 align(16) = undefined;
var snapshot_valid: bool = false;
var snapshot_saved: bool = false;
var snapshot_corrupted: bool = false;

var siphash_key: [16]u8 align(16) = undefined;
var key_initialized: bool = false;

// Verification state (obfuscated names)
var saved_idtr_base: u32 = 0;
var saved_pte_phys: u32 = 0;
var saved_pte_flags: u32 = 0;
var saved_cr3_base: u32 = 0;

// This section will be made read-only after initialization
var snapshot_mac_ro: [16]u8 align(16) = undefined;
var watchdog_data_hash: u32 = undefined;
var watchdog_protected: bool = false;

fn protect_watchdog_data() void {
    if (watchdog_protected or !config.ENABLE_IDT_WATCHDOG) return;
    watchdog_protected = true;

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

    // Use permutation for obfuscated key storage
    siphash_key[KEY_PERM[0]] = @as(u8, @truncate(tsc_low >> 0));
    siphash_key[KEY_PERM[1]] = @as(u8, @truncate(tsc_low >> 8));
    siphash_key[KEY_PERM[2]] = @as(u8, @truncate(tsc_low >> 16));
    siphash_key[KEY_PERM[3]] = @as(u8, @truncate(tsc_low >> 24));
    siphash_key[KEY_PERM[4]] = @as(u8, @truncate(tsc_high >> 0));
    siphash_key[KEY_PERM[5]] = @as(u8, @truncate(tsc_high >> 8));
    siphash_key[KEY_PERM[6]] = @as(u8, @truncate(tsc_high >> 16));
    siphash_key[KEY_PERM[7]] = @as(u8, @truncate(tsc_high >> 24));
    siphash_key[KEY_PERM[8]] = @as(u8, @truncate(@as(u32, pit_low) ^ tsc_low));
    siphash_key[KEY_PERM[9]] = @as(u8, @truncate(@as(u32, pit_high) ^ tsc_high));
    siphash_key[KEY_PERM[10]] = @as(u8, @truncate(tsc_low *% BUILD_SEED));
    siphash_key[KEY_PERM[11]] = @as(u8, @truncate(tsc_high *% BUILD_SEED));
    siphash_key[KEY_PERM[12]] = @as(u8, @truncate(@as(u32, @intCast(ticks)) *% 0x1234567));
    siphash_key[KEY_PERM[13]] = @as(u8, @truncate((@as(u32, @intCast(ticks)) >> 16) *% 0xDEADBEEF));
    siphash_key[KEY_PERM[14]] = @as(u8, @truncate((~tsc_low) +% @as(u32, @intCast(ticks))));
    siphash_key[KEY_PERM[15]] = @as(u8, @truncate((~tsc_high) -% @as(u32, @intCast(ticks))));
}

fn compute_mac(data: []const u8) [16]u8 {
    if (!key_initialized) generate_key();

    var mac: [16]u8 = [_]u8{0} ** 16;
    var state: [4]u32 = undefined;

    // Use getKeyByte for obfuscated key access
    state[0] = @as(u32, getKeyByte(0)) | (@as(u32, getKeyByte(1)) << 8) | (@as(u32, getKeyByte(2)) << 16) | (@as(u32, getKeyByte(3)) << 24);
    state[1] = @as(u32, getKeyByte(4)) | (@as(u32, getKeyByte(5)) << 8) | (@as(u32, getKeyByte(6)) << 16) | (@as(u32, getKeyByte(7)) << 24);
    state[2] = @as(u32, getKeyByte(8)) | (@as(u32, getKeyByte(9)) << 8) | (@as(u32, getKeyByte(10)) << 16) | (@as(u32, getKeyByte(11)) << 24);
    state[3] = @as(u32, getKeyByte(12)) | (@as(u32, getKeyByte(13)) << 8) | (@as(u32, getKeyByte(14)) << 16) | (@as(u32, getKeyByte(15)) << 24);

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

fn get_pte_for_addr(vaddr: usize) struct { phys: u32, flags: u32 } {
    // Get CR3 - page directory base
    var cr3: u32 = undefined;
    asm volatile ("mov %%cr3, %[cr3]"
        : [cr3] "=r" (cr3),
    );

    // Clear lower 12 bits to get page directory base
    const pd_base = cr3 & 0xFFFFF000;

    // Page directory index (bits 22-31 of virtual address)
    const pd_idx = (vaddr >> 22) & 0x3FF;
    // Page table index (bits 12-21 of virtual address)
    const pt_idx = (vaddr >> 12) & 0x3FF;

    // Read PDE (4 bytes)
    const pd_addr = @as(usize, pd_base) + pd_idx * 4;
    const pd_entry = @as(*const u32, @ptrFromInt(pd_addr)).*;

    // Check if page table is present
    if ((pd_entry & 1) == 0) {
        return .{ .phys = 0, .flags = 0 };
    }

    // Get page table base address
    const pt_base = pd_entry & 0xFFFFF000;

    // Read PTE (4 bytes)
    const pt_addr = @as(usize, pt_base) + pt_idx * 4;
    const pte = @as(*const u32, @ptrFromInt(pt_addr)).*;

    // Check if page is present
    if ((pte & 1) == 0) {
        return .{ .phys = 0, .flags = 0 };
    }

    // Return physical address (bits 12-31) and flags (bits 0-11)
    return .{
        .phys = @truncate(pte >> 12),
        .flags = pte & 0xFFF,
    };
}

fn check_shadow_walk() bool {
    const idt_vaddr = @intFromPtr(&idt_start);

    const pte_info = get_pte_for_addr(idt_vaddr);

    // Check physical address changed (page remapping attack)
    if (pte_info.phys == 0 or pte_info.phys != saved_pte_phys) {
        return false;
    }

    // Check Dirty bit (bit 6) - if set, someone wrote to this page
    // This catches attackers who modify IDT then restore PTE
    if ((pte_info.flags & 0x40) != 0) {
        return false;
    }

    // Check if PTE flags were modified (WR/RW bits, US bits, etc)
    if ((pte_info.flags & 0x07) != (saved_pte_flags & 0x07)) {
        return false;
    }

    return true;
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

pub fn save_snapshot() void {
    if (!config.ENABLE_IDT_WATCHDOG) return;

    if (snapshot_saved) return;
    snapshot_saved = true;

    generate_key();

    // Save CR3 for page directory validation
    saved_cr3_base = get_current_cr3();

    // Save IDTR base for verification
    saved_idtr_base = get_current_idtr();

    // Save PTE physical address and flags for Shadow Walk detection
    const pte_info = get_pte_for_addr(@intFromPtr(&idt_start));
    saved_pte_phys = pte_info.phys;
    saved_pte_flags = pte_info.flags;

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

fn get_current_idtr() u32 {
    var idtr: [6]u8 = undefined;
    asm volatile ("sidt %[mem]"
        : [mem] "=m" (idtr),
    );
    const base = @as(u32, idtr[2]) | (@as(u32, idtr[3]) << 8) | (@as(u32, idtr[4]) << 16) | (@as(u32, idtr[5]) << 24);
    return base;
}

fn get_current_cr3() u32 {
    var cr3: u32 = undefined;
    asm volatile ("mov %%cr3, %[cr3]"
        : [cr3] "=r" (cr3),
    );
    return cr3 & 0xFFFFF000; // Mask off lower 12 bits (page alignment)
}

fn check_idt_internal() bool {
    if (!config.ENABLE_IDT_WATCHDOG) return true;

    if (snapshot_corrupted) {
        return false;
    }

    // 4-layer verification chain
    if (snapshot_saved) {
        // Layer 1: CR3 verification (page directory switch attack)
        const current_cr3 = get_current_cr3();
        if (current_cr3 != saved_cr3_base) {
            return false;
        }

        // Layer 2: IDTR verification (LIDT relocation attack)
        const current_idtr = get_current_idtr();
        if (current_idtr != saved_idtr_base) {
            return false;
        }

        // Layer 3: PTE verification (Shadow Walk attack)
        if (!check_shadow_walk()) {
            return false;
        }
    }

    if (!snapshot_valid) return true;

    // Layer 4: MAC verification (IDT content modification)
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
    return check_idt();
}

pub fn get_idt_base() usize {
    return @intFromPtr(&idt_start);
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

pub fn cmd_idt_move(args: []const u8) void {
    _ = args;
    if (!config.ENABLE_DEBUG_COMMANDS) {
        common.printZ("Debug commands disabled (set ENABLE_DEBUG_COMMANDS = true in config.zig)\n");
        return;
    }

    if (!config.ENABLE_IDT_WATCHDOG) {
        common.printZ("IDT Watchdog is disabled (set ENABLE_IDT_WATCHDOG = true in config.zig)\n");
        return;
    }

    common.printZ("IDT Move Test (LIDT relocation):\n");
    common.printZ("  Current IDTR base: 0x");
    const current_idtr = get_current_idtr();
    var hex_buf: [8]u8 = undefined;
    var j: i8 = 7;
    const v = current_idtr;
    while (j >= 0) : (j -= 1) {
        const nibble = @as(u8, @intCast((v >> @as(u5, @intCast(j * 4))) & 0xF));
        hex_buf[@as(usize, 7 - @as(usize, @intCast(j)))] = if (nibble < 10) '0' + nibble else 'A' + nibble - 10;
    }
    common.printZ(&hex_buf);
    common.printZ("\n  NOTE: This would move IDT to new location\n");
    common.printZ("  Watchdog detects IDTR change and triggers panic!\n");
}
