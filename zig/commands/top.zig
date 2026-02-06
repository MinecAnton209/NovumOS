const common = @import("common.zig");
const smp = @import("../smp.zig");
const vga = @import("../drivers/vga.zig");
const keyboard = @import("../keyboard_isr.zig");
const timer = @import("../drivers/timer.zig");

pub fn cmd_top() void {
    vga.clear_screen();

    while (true) {
        // Move cursor to top-left (assuming 0,0 is start of VGA)
        vga.zig_set_cursor(0, 0);

        common.printZ("=== NovumOS CPU Monitor (TOP) ===\n");
        common.printZ("Cores Online: ");
        common.printNum(@intCast(smp.detected_cores));
        common.printZ(" | Press 'q' to exit\n\n");

        common.printZ("Core | Status | Queue | Total Tasks | Load\n");
        common.printZ("-------------------------------------------\n");

        var i: u32 = 0;
        while (i < smp.detected_cores) : (i += 1) {
            const core = &smp.cores[i];

            // Core ID
            common.printNum(@intCast(i));
            common.printZ("    | ");

            // Status
            if (core.is_busy) {
                common.printZ("BUSY  ");
            } else {
                common.printZ("IDLE  ");
            }
            common.printZ(" | ");

            // Pending in Queue
            common.printNum(@intCast(core.task_count));
            common.printZ("     | ");

            // Total tasks processed
            common.printNum(@intCast(core.total_tasks));
            common.printZ("           | ");

            // Simple visual load bar
            if (core.is_busy) {
                common.printZ("[#####]");
            } else {
                common.printZ("[     ]");
            }
            common.printZ("\n");
        }

        // Delay for a bit
        timer.sleep(250);

        // Check for 'q' to exit
        if (keyboard.keyboard_has_data()) {
            const c = keyboard.keyboard_getchar();
            if (c == 'q' or c == 'Q' or c == 27) break;
        }
    }

    vga.clear_screen();
}
