const std = @import("std");
const config = @import("../config.zig");
const common = @import("../commands/common.zig");
const SampleTable = @import("profiler_table.zig").SampleTable;
const irq = @import("irq.zig");

// Sampling runs from the PIT IRQ0 handler, so only the boot processor is profiled.
// Addresses are printed raw; scripts/prof-symbolize.py maps kernel addresses to names.

const TABLE_SIZE = 512;
const REPORT_SIZE = 16;
const Table = SampleTable(TABLE_SIZE);

// Frame built by isr_timer_wrapper (arch/x86/idt.asm), in dwords from the esp
// passed to isr_timer: pushad (8), ds/es/fs/gs (4), then the CPU-pushed eip and cs.
const FRAME_EIP_INDEX = 12;
const FRAME_CS_INDEX = 13;

var enabled: bool = false;
var kernel_table: Table = .{};
var user_table: Table = .{};

// Report snapshots live in static storage: a stack copy of two tables would be ~8 KiB.
var snap_kernel: Table = .{};
var snap_user: Table = .{};

/// Records the interrupted instruction pointer. Called from isr_timer with interrupts off.
pub fn on_tick(esp: usize) void {
    if (!enabled) return;
    const frame: [*]const u32 = @ptrFromInt(esp);
    const eip = frame[FRAME_EIP_INDEX];
    const cs = frame[FRAME_CS_INDEX];
    if ((cs & 3) == 3) {
        user_table.record(eip);
    } else {
        kernel_table.record(eip);
    }
}

pub fn start() void {
    enabled = true;
    common.printZ("prof: sampling started (100 Hz, boot processor)\n");
}

pub fn stop() void {
    enabled = false;
    common.printZ("prof: sampling stopped\n");
}

pub fn reset() void {
    const flags = irq.irq_save();
    kernel_table.reset();
    user_table.reset();
    irq.irq_restore(flags);
    common.printZ("prof: counters cleared\n");
}

pub fn report() void {
    const flags = irq.irq_save();
    snap_kernel = kernel_table;
    snap_user = user_table;
    irq.irq_restore(flags);

    const total = snap_kernel.total +| snap_user.total;
    common.printZ("Profile: ");
    common.printNum(@as(i32, @intCast(total)));
    common.printZ(" samples (kernel ");
    common.printNum(@as(i32, @intCast(snap_kernel.total)));
    common.printZ(", user ");
    common.printNum(@as(i32, @intCast(snap_user.total)));
    common.printZ(", dropped ");
    common.printNum(@as(i32, @intCast(snap_kernel.dropped +| snap_user.dropped)));
    common.printZ(")");
    if (enabled) common.printZ(" [still sampling]");
    common.printZ("\n");

    printSection("Kernel", &snap_kernel, total);
    printSection("User", &snap_user, total);
}

pub fn command(args: []const u8) void {
    if (!config.ENABLE_PROFILER) {
        common.printZ("prof: disabled (ENABLE_PROFILER=n)\n");
        return;
    }

    var argv: [2][]const u8 = undefined;
    const argc = common.parseArgs(args, &argv);
    if (argc == 0) {
        common.printZ("Usage: prof <start|stop|reset|report>\n");
        return;
    }

    const sub = argv[0];
    if (std.mem.eql(u8, sub, "start")) {
        start();
    } else if (std.mem.eql(u8, sub, "stop")) {
        stop();
    } else if (std.mem.eql(u8, sub, "reset")) {
        reset();
    } else if (std.mem.eql(u8, sub, "report")) {
        report();
    } else {
        common.printZ("Usage: prof <start|stop|reset|report>\n");
    }
}

fn printSection(title: []const u8, table: *const Table, total: u32) void {
    var top: [REPORT_SIZE]Table.Entry = undefined;
    const n = table.top(&top);

    common.printZ(title);
    common.printZ(" hot addresses:\n");
    if (n == 0) {
        common.printZ("  (none)\n");
        return;
    }
    for (top[0..n]) |e| {
        common.printZ("  ");
        common.printHex(e.addr);
        common.printZ("  ");
        common.printNum(@as(i32, @intCast(e.count)));
        common.printZ("  ");
        common.printNum(@as(i32, @intCast(percent(e.count, total))));
        common.printZ("%\n");
    }
}

fn percent(count: u32, total: u32) u32 {
    if (total == 0) return 0;
    return count * 100 / total;
}

