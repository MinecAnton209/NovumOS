// File Manipulation Commands
const common = @import("../commands/common.zig");
const fat = @import("../drivers/fat.zig");
const ata = @import("../drivers/ata.zig");
const memory = @import("../memory.zig");

pub fn cmd_cp(args: []const u8) void {
    var argv: [8][]const u8 = undefined;
    const argc = common.parseArgs(args, &argv);
    if (argc < 2) {
        common.printZ("Usage: cp <source> <dest>\n");
        return;
    }
    const src = argv[0];
    const dest = argv[1];

    // 1. Initialize FS
    const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
    const bpb = fat.read_bpb(drive) orelse {
        common.printZ("Error: Could not read filesystem\n");
        return;
    };

    // 2. Resolve source
    const entry = fat.find_entry(drive, bpb, common.current_dir_cluster, src) orelse {
        common.printZ("Error: Source not found\n");
        return;
    };

    const is_dir = (entry.attr & 0x10) != 0;

    if (is_dir) {
        if (fat.copy_directory(drive, bpb, common.current_dir_cluster, src, dest)) {
            common.printZ("Directory copied recursively.\n");
        } else {
            common.printZ("Error: Failed to copy directory.\n");
        }
    } else {
        if (fat.copy_file(drive, bpb, common.current_dir_cluster, src, dest)) {
            common.printZ("File copied successfully.\n");
        } else {
            common.printZ("Error: Failed to copy file.\n");
        }
    }
}

pub fn cmd_mv(args: []const u8) void {
    cmd_rename(args);
}

pub fn cmd_rename(args: []const u8) void {
    var argv: [8][]const u8 = undefined;
    const argc = common.parseArgs(args, &argv);
    if (argc < 2) {
        common.printZ("Usage: rename <old> <new>\n");
        return;
    }
    const src = argv[0];
    const dest = argv[1];

    const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
    const bpb = fat.read_bpb(drive) orelse {
        common.printZ("Error: Could not read filesystem\n");
        return;
    };

    if (fat.rename_file(drive, bpb, common.current_dir_cluster, src, dest)) {
        common.printZ("File renamed.\n");
    } else {
        common.printZ("Error: Failed to rename (check if source exists and dest is unique)\n");
    }
}

// Format progress callback
fn format_progress(current: u32, total: u32) void {
    const percent = (current * 100) / total;
    if (current % 5 == 0 or current == total) {
        // Redraw line
        common.print_char('\r');
        common.printZ("Formatting: [");

        // 20 chars for 100%
        const filled = percent / 5;
        var i: u32 = 0;
        while (i < 20) : (i += 1) {
            if (i < filled) common.print_char('#') else common.print_char(' ');
        }
        common.printZ("] ");
        common.printNum(@intCast(percent));
        common.printZ("%");
    }
}

extern fn shell_clear_history() void;

pub fn cmd_format(args: []const u8) void {
    var drive_idx: i32 = -1;
    var force = false;

    var argv: [8][]const u8 = undefined;
    const argc = common.parseArgs(args, &argv);

    for (argv[0..argc]) |arg| {
        if (common.std_mem_eql(arg, "--force")) {
            force = true;
        } else if (arg.len == 1 and arg[0] >= '0' and arg[0] <= '9') {
            drive_idx = @intCast(arg[0] - '0');
        }
    }

    if (!force or drive_idx == -1) {
        common.printZ("ERROR: Drive ID and --force flag are required.\n");
        common.printZ("Usage: format <drive_id> --force\n");
        common.printZ("Example: format 1 --force\n");
        common.printZ("Current selected disk: ");
        common.printNum(common.selected_disk);
        common.printZ("\n");
        return;
    }

    // Determine drive
    if (drive_idx == 0) {
        common.printZ("ERROR: Drive 0 is BUSY (Occupied by OS System).\n");
        common.printZ("Access denied: Someone else (the Kernel) is using this disk.\n");
        return;
    }
    const drive = ata.Drive.Slave; // Since 0 is blocked, only Slave (1) is formattable for now

    common.printZ("Formatting Drive ");
    common.printNum(drive_idx);
    common.printZ("... (Sectors range check)\n");

    const bpb = fat.read_bpb(drive) orelse {
        common.printZ("Error: Could not read disk BPB. Is it an uninitialized disk?\n");
        // For truly uninitialized disks, we'd need to write a new BPB first.
        // For now, we only format existing FAT disks.
        return;
    };

    if (fat.format(drive, bpb, format_progress)) {
        common.printZ("\nFormat complete on Drive ");
        common.printNum(drive_idx);
        common.printZ(".\n");

        // Clear history if we just formatted the disk we are using
        if (common.selected_disk == drive_idx) {
            shell_clear_history();
            common.printZ("Shell history cleared in memory.\n");
        }
    } else {
        common.printZ("\nFormat failed.\n");
    }
}

pub fn cmd_mkfs(args: []const u8) void {
    cmd_format(args);
}
