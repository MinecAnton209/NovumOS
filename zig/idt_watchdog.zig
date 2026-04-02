const config = @import("config.zig");
const common = @import("commands/common.zig");
const exceptions = @import("exceptions.zig");
const memory = @import("memory.zig");

extern var idt_start: u8;

var idt_snapshot: [256 * 8]u8 align(16) = undefined;
var snapshot_valid: bool = false;
var snapshot_saved: bool = false;
var snapshot_corrupted: bool = false;

const KERNEL_CODE_SELECTOR = 0x08;
const INTERRUPT_GATE_TYPE = 0xE;
const PRESENT_BIT = 0x80;

fn is_memory_present(addr: usize) bool {
    return memory.is_ptr_present(@intCast(addr));
}

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

    const idt_base = @intFromPtr(&idt_start);

    if (!is_memory_present(idt_base)) {
        return;
    }

    const idt_ptr = @as([*]u8, @ptrFromInt(idt_base));

    @memcpy(idt_snapshot[0 .. 256 * 8], idt_ptr[0 .. 256 * 8]);
    snapshot_valid = true;
}

pub fn check_idt() bool {
    if (!config.ENABLE_IDT_WATCHDOG) return true;

    if (snapshot_corrupted) return false;

    if (!snapshot_valid) return true;

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

    if (check_idt()) {
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
