// Shell Commands Module
// Bridges high-level command logic with individual command implementations.

const ls = @import("commands/ls.zig");
const cat = @import("commands/cat.zig");
const touch = @import("commands/touch.zig");
const rm = @import("commands/rm.zig");
const echo = @import("commands/echo.zig");
const common = @import("commands/common.zig");
const timer = @import("drivers/timer.zig");
const disk_cmds = @import("commands/disk_cmds.zig");
const fat = @import("drivers/fat.zig");
const ata = @import("drivers/ata.zig");
const edit = @import("commands/edit.zig");
const rtc = @import("drivers/rtc.zig");
const sysinfo = @import("commands/sysinfo.zig");
const keyboard_isr = @import("keyboard_isr.zig");
const file_utils = @import("commands/file_utils.zig");
const docs = @import("commands/docs.zig");
const config = @import("config.zig");
const exceptions = @import("exceptions.zig");
const memory = @import("memory.zig");
const cpuinfo = @import("commands/cpuinfo.zig");
const smp = @import("smp.zig");
const vga = @import("drivers/vga.zig");

var viewer_buffer: [16384]u8 = undefined;
var viewer_lines: [1024]struct { start: usize, len: usize, original_num: usize } = undefined;

extern fn shell_clear_history() void;

pub fn clear_shell_history() void {
    shell_clear_history();
}

pub export fn cmd_docs(args: [*]const u8, args_len: u32) void {
    docs.execute(args[0..args_len]);
}

pub export fn cmd_pwd() void {
    if (common.selected_disk >= 0) {
        common.print_char(@intCast(@as(u8, @intCast(common.selected_disk)) + '0'));
        common.print_char(':');
    }
    if (common.current_path_len == 0) {
        common.printZ("/");
    } else {
        common.printZ(common.current_path[0..common.current_path_len]);
    }
    common.printZ("\n");
}

pub export fn cmd_cp(args_ptr: [*]const u8, args_len: u32) void {
    file_utils.cmd_cp(args_ptr[0..args_len]);
}

pub export fn cmd_mv(args_ptr: [*]const u8, args_len: u32) void {
    file_utils.cmd_mv(args_ptr[0..args_len]);
}

pub export fn cmd_rename(args_ptr: [*]const u8, args_len: u32) void {
    file_utils.cmd_rename(args_ptr[0..args_len]);
}

pub export fn cmd_format(args_ptr: [*]const u8, args_len: u32) void {
    file_utils.cmd_format(args_ptr[0..args_len]);
}

pub export fn cmd_mkfs(args_ptr: [*]const u8, args_len: u32) void {
    file_utils.cmd_mkfs(args_ptr[0..args_len]);
}

/// Execute 'ls' command
pub export fn cmd_ls(args_ptr: [*]const u8, args_len: u32) void {
    const raw_args = args_ptr[0..args_len];

    var argv: [8][]const u8 = undefined;
    const argc = common.parseArgs(raw_args, &argv);

    var show_hidden = false;
    var path_arg: ?[]const u8 = null;

    var i: usize = 0;
    while (i < argc) : (i += 1) {
        if (common.std_mem_eql(argv[i], "-a")) {
            show_hidden = true;
        } else if (path_arg == null) {
            path_arg = argv[i];
        }
    }

    if (common.selected_disk < 0) {
        ls.execute();
    } else {
        const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
        if (fat.read_bpb(drive)) |bpb| {
            if (path_arg == null) {
                fat.list_directory(drive, bpb, common.current_dir_cluster, show_hidden);
            } else {
                if (fat.resolve_full_path(drive, bpb, common.current_dir_cluster, common.current_path[0..common.current_path_len], path_arg.?)) |res| {
                    if (res.is_dir) {
                        fat.list_directory(drive, bpb, res.cluster, show_hidden);
                    } else {
                        common.printZ("ls: cannot access ");
                        common.printZ(path_arg.?);
                        common.printZ(": Not a directory\n");
                    }
                } else {
                    common.printZ("ls: cannot access ");
                    common.printZ(path_arg.?);
                    common.printZ(": No such file or directory\n");
                }
            }
        } else {
            common.printError("Error: Disk not formatted\n");
        }
    }
}

/// Execute 'cat' command for a given filename
pub export fn cmd_cat(name_ptr: [*]const u8, name_len: u32) void {
    var argv: [8][]const u8 = undefined;
    const argc = common.parseArgs(name_ptr[0..name_len], &argv);
    if (argc == 0) {
        common.printZ("Usage: cat <file>\n");
        return;
    }
    const name = argv[0];

    if (common.selected_disk < 0) {
        cat.execute(name.ptr, @intCast(name.len));
    } else {
        const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
        if (fat.read_bpb(drive)) |bpb| {
            if (!fat.stream_to_console(drive, bpb, common.current_dir_cluster, name)) {
                common.printError("Error: File not found\n");
            }
        }
    }
}

/// Execute 'touch' command to create a file
pub export fn cmd_touch(name_ptr: [*]const u8, name_len: u32) void {
    var argv: [8][]const u8 = undefined;
    const argc = common.parseArgs(name_ptr[0..name_len], &argv);
    if (argc == 0) {
        common.printZ("Usage: touch <file>\n");
        return;
    }
    const name = argv[0];

    if (common.selected_disk < 0) {
        touch.execute(name.ptr, @intCast(name.len));
    } else {
        const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
        if (fat.read_bpb(drive)) |bpb| {
            if (!fat.write_file(drive, bpb, common.current_dir_cluster, name, "")) {
                common.printError("Error: Failed to create file on disk\n");
            }
        } else {
            common.printError("Error: Disk not formatted\n");
        }
    }
}

/// Execute 'rm' command to delete a file or directory
pub export fn cmd_rm(args_ptr: [*]const u8, args_len: u32) void {
    if (common.selected_disk < 0) {
        rm.execute(args_ptr, @intCast(args_len));
        return;
    }

    const args_raw = args_ptr[0..args_len];
    var argv: [8][]const u8 = undefined;
    const argc = common.parseArgs(args_raw, &argv);

    if (argc == 0) {
        common.printZ("Usage: rm [-d] [-r] <file|*>\n");
        return;
    }

    var recursive = false;
    var delete_dirs = false;
    var sure = false;
    var target: []const u8 = "";

    for (argv[0..argc]) |arg| {
        if (common.std_mem_eql(arg, "-r")) {
            recursive = true;
        } else if (common.std_mem_eql(arg, "-d")) {
            delete_dirs = true;
        } else if (common.std_mem_eql(arg, "-rd") or common.std_mem_eql(arg, "-dr")) {
            recursive = true;
            delete_dirs = true;
        } else if (common.std_mem_eql(arg, "--yes-i-am-sure")) {
            sure = true;
        } else if (arg.len > 0 and arg[0] != '-') {
            target = arg;
        }
    }

    if (target.len == 0) {
        common.printError("Error: No target specified\n");
        return;
    }

    // Confirmation logic for rm *
    if (common.std_mem_eql(target, "*")) {
        if (!recursive or !delete_dirs or !sure) {
            common.printZ("Are you sure? I worked so hard on these files...\n");
            common.printZ("To delete EVERYTHING (files & folders), use: rm -dr * --yes-i-am-sure\n");
            return;
        }
    }

    const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
    if (fat.read_bpb(drive)) |bpb| {
        var prefix: []const u8 = "";
        var is_wildcard = false;
        var wildcard_dir_path: []const u8 = "";

        if (common.std_mem_eql(target, "*")) {
            is_wildcard = true;
            wildcard_dir_path = ".";
            prefix = "";
        } else if (common.std_mem_eql(target, ".*")) {
            is_wildcard = true;
            wildcard_dir_path = ".";
            prefix = ".";
        } else if (common.endsWith(target, "/*")) {
            is_wildcard = true;
            wildcard_dir_path = target[0 .. target.len - 2];
            if (wildcard_dir_path.len == 0) wildcard_dir_path = "/";
            prefix = "";
        } else if (common.endsWith(target, "/.*")) {
            is_wildcard = true;
            wildcard_dir_path = target[0 .. target.len - 3];
            if (wildcard_dir_path.len == 0) wildcard_dir_path = "/";
            prefix = ".";
        }

        if (is_wildcard) {
            if (prefix.len == 0 and (!recursive or !delete_dirs or !sure)) {
                common.printZ("Are you sure? I worked so hard on these files...\n");
                common.printZ("To delete EVERYTHING in '");
                common.printZ(wildcard_dir_path);
                common.printZ("' (files & folders), use: rm -dr ");
                common.printZ(target);
                common.printZ(" --yes-i-am-sure\n");
                return;
            }

            if (fat.resolve_full_path(drive, bpb, common.current_dir_cluster, common.current_path[0..common.current_path_len], wildcard_dir_path)) |res| {
                if (res.is_dir) {
                    fat.delete_all_in_directory(drive, bpb, res.cluster, recursive, delete_dirs, prefix);
                    common.printZ("Target contents deleted.\n");
                } else {
                    common.printError("Error: Not a directory: ");
                    common.printZ(wildcard_dir_path);
                    common.printZ("\n");
                }
            } else {
                common.printError("Error: Directory not found: ");
                common.printZ(wildcard_dir_path);
                common.printZ("\n");
            }
        } else {
            // Handle single target (can be a path)
            var parent_cluster = common.current_dir_cluster;
            var final_name = target;

            if (common.lastIndexOf(target, '/')) |idx| {
                const parent_path = if (idx == 0) "/" else target[0..idx];
                final_name = target[idx + 1 ..];
                if (final_name.len == 0) {
                    common.printError("Error: Invalid target name\n");
                    return;
                }
                if (fat.resolve_full_path(drive, bpb, common.current_dir_cluster, common.current_path[0..common.current_path_len], parent_path)) |res| {
                    if (res.is_dir) {
                        parent_cluster = res.cluster;
                    } else {
                        common.printError("Error: Not a directory: ");
                        common.printZ(parent_path);
                        common.printZ("\n");
                        return;
                    }
                } else {
                    common.printError("Error: Parent path not found: ");
                    common.printZ(parent_path);
                    common.printZ("\n");
                    return;
                }
            }

            if (recursive or delete_dirs) {
                if (fat.delete_directory(drive, bpb, parent_cluster, final_name, recursive)) {
                    common.printZ("Deleted: ");
                    common.printZ(target);
                    common.printZ("\n");
                } else {
                    common.printError("Error: Failed to delete directory (not empty? use -r)\n");
                }
            } else {
                // Check if it's a directory before deleting as file
                if (fat.find_entry(drive, bpb, parent_cluster, final_name)) |entry| {
                    if ((entry.attr & 0x10) != 0) {
                        common.printError("Error: Target is a directory (use -d)\n");
                        return;
                    }
                }

                if (fat.delete_file(drive, bpb, parent_cluster, final_name)) {
                    common.printZ("Deleted: ");
                    common.printZ(target);
                    common.printZ("\n");
                } else {
                    common.printError("Error: File not found\n");
                }
            }
        }
    }
}

/// Execute 'echo' command to print text
pub export fn cmd_echo(text_ptr: [*]const u8, text_len: u32) void {
    if (text_len == 0 and common.pipe_read_active) {
        common.printZ(common.pipe_buffer[0..common.pipe_pos]);
        common.printZ("\r\n");
    } else {
        echo.execute(text_ptr, @intCast(text_len));
    }
}

/// Execute system 'reboot'
pub export fn cmd_reboot() void {
    common.reboot();
}

/// Execute system 'shutdown'
pub export fn cmd_shutdown() void {
    common.shutdown();
}

/// Execute 'uptime' command
pub export fn cmd_uptime() void {
    const s = timer.get_uptime();
    common.printZ("System Ticks Uptime: ");
    common.printNum(@intCast(s));
    common.printZ(" seconds\n");

    const dt = rtc.get_datetime();
    common.printZ("Current RTC Time: ");
    common.printNum(dt.hour);
    common.printZ(":");
    if (dt.minute < 10) common.printZ("0");
    common.printNum(dt.minute);
    common.printZ(":");
    if (dt.second < 10) common.printZ("0");
    common.printNum(dt.second);
    common.printZ("\r\n");
}

pub export fn cmd_time() void {
    const dt = rtc.get_datetime();
    common.printZ("Date: ");
    common.printNum(dt.day);
    common.printZ(".");
    common.printNum(dt.month);
    common.printZ(".");
    common.printNum(dt.year);
    common.printZ("  Time: ");
    common.printNum(dt.hour);
    common.printZ(":");
    if (dt.minute < 10) common.printZ("0");
    common.printNum(dt.minute);
    common.printZ(":");
    if (dt.second < 10) common.printZ("0");
    common.printNum(dt.second);
    common.printZ("\n");
}

/// Execute 'lsdsk' command
pub export fn cmd_lsdsk() void {
    disk_cmds.lsdsk();
}

/// Execute 'mkfs-fat12' command
pub export fn cmd_mkfs_fat12(drive_num_ptr: [*]const u8, drive_num_len: u32) void {
    if (drive_num_len == 0) {
        common.printZ("Usage: mkfs-fat12 <drive_num>\n");
        return;
    }
    const drive_num = drive_num_ptr[0] - '0';
    disk_cmds.mkfs_fat12(@intCast(drive_num));
}

/// Execute 'mkfs-fat16' command
pub export fn cmd_mkfs_fat16(drive_num_ptr: [*]const u8, drive_num_len: u32) void {
    if (drive_num_len == 0) {
        common.printZ("Usage: mkfs-fat16 <drive_num>\n");
        return;
    }
    const drive_num = drive_num_ptr[0] - '0';
    disk_cmds.mkfs_fat16(@intCast(drive_num));
}

/// Execute 'mkfs-fat32' command
pub export fn cmd_mkfs_fat32(drive_num_ptr: [*]const u8, drive_num_len: u32) void {
    if (drive_num_len == 0) {
        common.printZ("Usage: mkfs-fat32 <drive_num>\n");
        return;
    }
    const drive_num = drive_num_ptr[0] - '0';
    disk_cmds.mkfs_fat32(@intCast(drive_num));
}

/// Global initialization for Zig-based modules (FS, etc.)
pub export fn zig_init() void {
    common.fs_init();

    // Auto-select only Disk 1 (Slave) by default if it exists and is formatted,
    // leave Disk 0 (Master/System) unmounted for safety.
    if (ata.identify(.Slave) > 0) {
        if (fat.read_bpb(.Slave) != null) {
            common.selected_disk = 1;
        }
    }
}

/// Execute 'mount' command
pub export fn cmd_mount(disk_num_ptr: [*]const u8, disk_num_len: u32) void {
    if (disk_num_len == 0) {
        common.printZ("Usage: mount <disk_num|ram>\n");
        return;
    }

    const arg = disk_num_ptr[0..disk_num_len];
    if (common.std_mem_eql(arg, "ram")) {
        common.selected_disk = -1;
        common.printZ("Switched to RAM FS\n");
        return;
    }

    const disk_num = disk_num_ptr[0] - '0';
    if (disk_num > 1) {
        common.printError("Error: Invalid disk (0 or 1)\n");
        return;
    }

    const drive = if (disk_num == 0) ata.Drive.Master else ata.Drive.Slave;
    if (fat.read_bpb(drive) == null) {
        common.printError("Error: Disk not formatted\n");
        return;
    }

    common.selected_disk = @intCast(disk_num);
    common.current_dir_cluster = 0; // Reset to Root
    common.current_path_len = 0;
    common.printZ("Disk ");
    common.printNum(disk_num);
    common.printZ(" mounted\n");
}

pub export fn cmd_mkdir(name_ptr: [*]const u8, name_len: u32) void {
    if (common.selected_disk < 0) {
        common.printError("Error: mkdir only supported on Disk FS\n");
        return;
    }

    var argv: [8][]const u8 = undefined;
    const argc = common.parseArgs(name_ptr[0..name_len], &argv);
    if (argc == 0) {
        common.printZ("Usage: mkdir <name>\n");
        return;
    }

    const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
    if (fat.read_bpb(drive)) |bpb| {
        if (!fat.create_directory(drive, bpb, common.current_dir_cluster, argv[0])) {
            common.printError("Error: Failed to create directory\n");
        }
    }
}

pub export fn cmd_cd(args_ptr: [*]const u8, args_len: u32) void {
    if (common.selected_disk < 0) {
        common.printError("Error: cd only supported on Disk FS\n");
        return;
    }

    var argv: [8][]const u8 = undefined;
    const argc = common.parseArgs(args_ptr[0..args_len], &argv);

    const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
    const bpb = fat.read_bpb(drive) orelse {
        common.printError("Error: Disk not formatted\n");
        return;
    };

    if (argc == 0 or common.std_mem_eql(argv[0], "/")) {
        common.current_dir_cluster = 0;
        common.current_path_len = 0;
        return;
    }

    const path = argv[0];
    if (common.std_mem_eql(path, ".")) {
        common.printZ("Wow, you're already here!\n");
        return;
    }

    if (fat.resolve_full_path(drive, bpb, common.current_dir_cluster, common.current_path[0..common.current_path_len], path)) |res| {
        if (res.is_dir) {
            common.current_dir_cluster = res.cluster;
            common.current_path_len = res.path_len;
            for (res.path[0..res.path_len], 0..) |c, i| {
                common.current_path[i] = c;
            }
        } else {
            common.printZ("cd: Not a directory: ");
            common.printZ(path);
            common.printZ("\n");
        }
    } else {
        common.printZ("cd: no such directory: ");
        common.printZ(path);
        common.printZ("\n");
    }
}

pub export fn cmd_tree() void {
    if (common.selected_disk < 0) {
        common.printError("Error: tree only supported on Disk FS\n");
        return;
    }
    const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
    if (fat.read_bpb(drive)) |bpb| {
        common.printZ(".\n");
        tree_node(drive, bpb, common.current_dir_cluster, 1);
    }
}

fn tree_node(drive: ata.Drive, bpb: fat.BPB, dir_cluster: u32, depth: usize) void {
    // We need a way to list directory but instead of printing, we recurse.
    // For now, let's just make it print with indentation if we had a way to iterate.
    // Let's add an iterator or just uses a simplified version.

    var buffer: [512]u8 = undefined;
    var lfn: fat.LfnState = .{ .buf = [_]u8{0} ** 256, .active = false, .checksum = 0 };

    if (dir_cluster == 0) {
        if (bpb.fat_type == .FAT32) {
            tree_node(drive, bpb, bpb.root_cluster, depth);
            return;
        }
        var sector = bpb.first_root_dir_sector;
        while (sector < bpb.first_data_sector) : (sector += 1) {
            ata.read_sector(drive, sector, &buffer);
            if (!tree_sector(drive, bpb, &buffer, depth, &lfn)) break;
        }
    } else {
        var current = dir_cluster;
        const eof_val = switch (bpb.fat_type) {
            .FAT12 => @as(u32, 0xFF8),
            .FAT16 => @as(u32, 0xFFF8),
            .FAT32 => @as(u32, 0x0FFFFFF8),
            else => @as(u32, 0xFFF8),
        };
        while (current < eof_val) {
            const lba = bpb.first_data_sector + (current - 2) * bpb.sectors_per_cluster;
            var s: u32 = 0;
            while (s < bpb.sectors_per_cluster) : (s += 1) {
                ata.read_sector(drive, lba + s, &buffer);
                if (!tree_sector(drive, bpb, &buffer, depth, &lfn)) break;
            }
            current = fat.get_fat_entry(drive, bpb, current);
            if (current < 2 or current >= eof_val) break;
        }
    }
}

fn tree_sector(drive: ata.Drive, bpb: fat.BPB, buffer: *[512]u8, depth: usize, lfn: *fat.LfnState) bool {
    var i: u32 = 0;
    while (i < 512) : (i += 32) {
        if (buffer[i] == 0) return false;

        if (buffer[i] == 0xE5) {
            lfn.active = false;
            continue;
        }

        // LFN Entry
        if (buffer[i + 11] == 0x0F) {
            const seq = buffer[i];
            const chk = buffer[i + 13];

            if ((seq & 0x40) != 0) {
                lfn.active = true;
                lfn.checksum = chk;
                @memset(&lfn.buf, 0);
            } else if (!lfn.active or lfn.checksum != chk) {
                lfn.active = false;
                continue;
            }

            var index = (seq & 0x1F);
            if (index < 1) index = 1;
            const offset = (index - 1) * 13;

            if (offset < 240) {
                fat.extract_lfn_part(buffer, i + 1, 5, &lfn.buf, offset);
                fat.extract_lfn_part(buffer, i + 14, 6, &lfn.buf, offset + 5);
                fat.extract_lfn_part(buffer, i + 28, 2, &lfn.buf, offset + 11);
            }
            continue;
        }

        const name = fat.get_name_from_raw(buffer[i .. i + 32]);
        if (common.std_mem_eql(name.buf[0..name.len], ".") or common.std_mem_eql(name.buf[0..name.len], "..")) {
            lfn.active = false;
            continue;
        }

        // Checksum for LFN match
        var sum: u8 = 0;
        for (0..11) |k| {
            const is_odd = (sum & 1) != 0;
            sum = (sum >> 1) + (if (is_odd) @as(u8, 0x80) else 0);
            sum = sum +% buffer[i + k];
        }

        var print_name: []const u8 = name.buf[0..name.len];
        if (lfn.active and lfn.checksum == sum) {
            var len: usize = 0;
            while (len < 256 and lfn.buf[len] != 0) : (len += 1) {}
            print_name = lfn.buf[0..len];
        }
        lfn.active = false;

        for (0..depth) |_| common.printZ("  ");
        common.printZ("|- ");
        common.printZ(print_name);
        common.printZ("\n");

        if ((buffer[i + 11] & 0x10) != 0) { // Directory
            const cluster = @as(u32, buffer[i + 26]) | (@as(u32, buffer[i + 27]) << 8) |
                (@as(u32, buffer[i + 20]) << 16) | (@as(u32, buffer[i + 21]) << 24);
            if (cluster != 0) tree_node(drive, bpb, cluster, depth + 1);
        }
    }
    return true;
}

/// Execute 'write' operation (create, overwrite or append to file)
pub export fn cmd_write(name_ptr: [*]const u8, name_len: u32, data_ptr: [*]const u8, data_len: u32, append: bool) void {
    if (common.selected_disk < 0) {
        var id = common.fs_find(name_ptr, @intCast(name_len));
        if (id < 0) {
            id = common.fs_create(name_ptr, @intCast(name_len));
        }
        if (id >= 0) {
            _ = common.fs_write(@intCast(id), data_ptr, @intCast(data_len));
        }
    } else {
        const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
        if (fat.read_bpb(drive)) |bpb| {
            const name = name_ptr[0..name_len];
            const data = data_ptr[0..data_len];
            const success = if (append) fat.append_to_file(drive, bpb, common.current_dir_cluster, name, data) else fat.write_file(drive, bpb, common.current_dir_cluster, name, data);

            if (!success) {
                common.printZ("Error: Failed to write file to disk\n");
            }
        }
    }
}

pub export fn cmd_edit(name_ptr: [*]const u8, name_len: u32) void {
    var argv: [8][]const u8 = undefined;
    const argc = common.parseArgs(name_ptr[0..name_len], &argv);
    if (argc == 0) {
        common.printZ("Usage: edit <file>\n");
        return;
    }
    edit.execute(argv[0]);
}

pub export fn cmd_mem(args_ptr: [*]const u8, args_len: u32) void {
    var argv: [8][]const u8 = undefined;
    const argc = common.parseArgs(args_ptr[0..args_len], &argv);

    if (argc > 0 and common.std_mem_eql(argv[0], "--test")) {
        var mb_size: i32 = 40;
        const max_mb = @as(i32, @intCast(memory.MAX_MEMORY / (1024 * 1024)));
        const safe_limit = max_mb - 64; // Leave 64MB for system

        if (argc > 1) {
            if (common.parse_int(argv[1])) |val| {
                if (val > 0 and val <= safe_limit) {
                    mb_size = val;
                } else if (val > safe_limit) {
                    common.printZ("Error: Test size limited to ");
                    common.printNum(safe_limit);
                    common.printZ("MB (system RAM: ");
                    common.printNum(max_mb);
                    common.printZ("MB)\n");
                    return;
                }
            }
        }

        common.printZ("Running Memory Test (");
        common.printNum(mb_size);
        common.printZ("MB allocation)...\n");
        common.printZ("Press Ctrl+C to abort.\n");
        const start_pf = memory.pf_count;

        const size = @as(usize, @intCast(mb_size)) * 1024 * 1024;

        if (memory.heap.alloc(size)) |ptr| {
            common.printZ("Allocation successful at ");
            common.printHex(@as(u32, @intCast(@intFromPtr(ptr))));

            common.printZ("\nPre-mapping memory (Zero CPU Exceptions)... ");
            memory.map_range(@intFromPtr(ptr), size);
            common.printZ("Done.\n");

            common.printZ("Filling memory...\n");

            var aborted = false;
            var i: usize = 0;
            var check_counter: u32 = 0;
            while (i < size) : (i += 4096) {
                // Check Ctrl+C every 1024 iterations (4MB) to improve performance
                check_counter += 1;
                if (check_counter >= 1024) {
                    check_counter = 0;
                    if (keyboard_isr.check_ctrl_c()) {
                        common.printZ("\nAborted by user!\n");
                        aborted = true;
                        break;
                    }
                }
                ptr[i] = @as(u8, @intCast(i % 255));
            }

            if (!aborted) {
                // Final byte
                ptr[size - 1] = 0xAA;
                common.printZ("Memory fill complete.\n");
            }

            const end_pf = memory.pf_count;
            common.printZ("Quiet Page Faults handled: ");
            common.printNum(@intCast(end_pf - start_pf));
            common.printZ("\n");

            // In NovumOS, we often keep the allocation for testing or free it
            // Let's at least trigger GC to show it works
            memory.heap.free(ptr);
            memory.heap.garbage_collect();
        } else {
            common.printError("Error: Failed to allocate ");
            common.printNum(mb_size);
            common.printZ("MB.\n");
        }
    } else {
        common.printZ("Usage: mem --test [MB]\n");
    }
}

pub export fn cmd_sysinfo() void {
    sysinfo.execute();
}

pub export fn cmd_cpuinfo() void {
    cpuinfo.execute();
}

pub export fn cmd_fetch() void {
    sysinfo.cmd_fetch();
}

fn test_task(arg: usize) void {
    common.printZ(" [TASK] Core reporting! Argument: ");
    common.printNum(@intCast(arg));
    common.printZ("\n");
}

pub export fn cmd_smp_test() void {
    if (!config.ENABLE_DEBUG_COMMANDS) return;
    common.printZ("Sending 4 tasks to the global queue...\n");
    _ = smp.push_task(test_task, 101);
    _ = smp.push_task(test_task, 202);
    _ = smp.push_task(test_task, 303);
    _ = smp.push_task(test_task, 404);
}

fn heavy_task(id: usize) void {
    var result: u64 = 0;
    var i: u64 = 0;
    const total: u64 = 200_000_000; // Heavier tasks for better demo

    while (i < total) : (i += 1) {
        result = result +% (i *% 3 +% 7);
    }

    smp.lock_print();
    common.printZ(" [OK] Task #");
    common.printNum(@intCast(id));
    common.printZ(" done.\n");
    smp.unlock_print();
}

pub export fn cmd_stress_test() void {
    if (!config.ENABLE_DEBUG_COMMANDS) return;
    if (smp.get_online_cores() < 2) {
        common.printZ("Error: No secondary cores online.\n");
        return;
    }

    common.printZ("Flood: Sending 100 tasks to the balancer...\n");
    var tasks_sent: u32 = 0;
    while (tasks_sent < 100) : (tasks_sent += 1) {
        _ = smp.push_task(heavy_task, tasks_sent);
    }

    common.printZ("All tasks deployed. Use 'top' to monitor CPU load!\n");
}

extern fn test_divide_by_zero() void;

comptime {
    if (config.ENABLE_DEBUG_CRASH_COMMANDS) {
        @export(&cmd_panic, .{ .name = "cmd_panic" });
        @export(&cmd_abort, .{ .name = "cmd_abort" });
        @export(&cmd_invalid_op, .{ .name = "cmd_invalid_op" });
        @export(&cmd_stack_overflow, .{ .name = "cmd_stack_overflow" });
        @export(&cmd_page_fault, .{ .name = "cmd_page_fault" });
        @export(&cmd_gpf, .{ .name = "cmd_gpf" });
    }
}

pub fn cmd_panic() callconv(.c) void {
    test_divide_by_zero();
}

pub fn cmd_abort() callconv(.c) void {
    exceptions.crash_abort();
}

pub fn cmd_invalid_op() callconv(.c) void {
    exceptions.crash_invalid_op();
}

pub fn cmd_stack_overflow() callconv(.c) void {
    exceptions.crash_stack_overflow();
}

pub fn cmd_page_fault() callconv(.c) void {
    exceptions.crash_page_fault();
}

pub fn cmd_gpf() callconv(.c) void {
    exceptions.crash_gpf();
}

pub export fn cmd_matrix() void {
    vga.clear_screen();
    var row_offsets: [80]u8 = [_]u8{0} ** 80;

    // Randomize initial offsets
    var seed: u32 = @intCast(timer.get_ticks());
    for (0..80) |i| {
        seed = seed *% 1103515245 +% 12345;
        row_offsets[i] = @intCast(seed % 25);
    }

    common.printZ("Entering the NovumOS Matrix... (Press Ctrl+C to exit)\n");
    timer.sleep(1000);
    vga.clear_screen();

    while (!keyboard_isr.check_ctrl_c()) {
        for (0..80) |x| {
            seed = seed *% 1103515245 +% 12345;
            if (seed % 5 == 0) {
                const y = row_offsets[x];

                const c: u8 = @intCast(33 + (seed % 94));
                const idx = @as(usize, y) * 80 + @as(usize, x);

                // Light Green for head
                vga.VIDEO_MEMORY[idx] = 0x0A00 | @as(u16, c);

                // Dim previous ones if we had a trail, but let's keep it simple:
                // Clear the one way above to make it feel like a falling line
                const tail_idx = (@as(usize, (y + 25 - 5) % 25)) * 80 + @as(usize, x);
                vga.VIDEO_MEMORY[tail_idx] = 0x0000 | ' ';

                row_offsets[x] = (y + 1) % 25;
            }
        }
        timer.sleep(30);
    }
    vga.clear_screen();
}
fn print_hexdump_line(offset: u32, data: []const u8) void {
    // Print Offset
    var i: i8 = 7;
    while (i >= 0) : (i -= 1) {
        const nibble = @as(u8, @intCast((offset >> @as(u5, @intCast(i * 4))) & 0xF));
        const char = if (nibble < 10) '0' + nibble else 'A' + (nibble - 10);
        common.print_char(char);
    }
    common.printZ(": ");

    // Print Hex
    for (0..16) |j| {
        if (j < data.len) {
            const b = data[j];
            const hex_chars = "0123456789ABCDEF";
            common.print_char(hex_chars[b >> 4]);
            common.print_char(hex_chars[b & 0x0F]);
        } else {
            common.printZ("  ");
        }
        common.print_char(' ');
    }

    common.printZ("| ");
    // Print ASCII
    for (0..16) |j| {
        if (j < data.len) {
            const b = data[j];
            if (b >= 32 and b <= 126) {
                common.print_char(b);
            } else {
                common.print_char('.');
            }
        } else {
            common.print_char(' ');
        }
    }
    common.printZ("\n");
}

fn pager_wait() bool {
    if (common.pipe_active or common.redirect_active) return true;
    const row = vga.zig_get_cursor_row();
    const col = vga.zig_get_cursor_col();
    vga.set_color(0, 7); // Black on Light Gray
    common.printZ("-- More --");
    vga.reset_color();

    const key = keyboard_isr.keyboard_wait_char();

    // Clear the message
    vga.zig_set_cursor(row, col);
    var i: usize = 0;
    while (i < 10) : (i += 1) common.print_char(' ');
    vga.zig_set_cursor(row, col);

    if (key == 'q' or key == 'Q' or key == 3) return false;
    return true;
}

pub export fn cmd_hexdump(name_ptr: [*]const u8, name_len: u32) void {
    var argv: [8][]const u8 = undefined;
    const argc = common.parseArgs(name_ptr[0..name_len], &argv);
    if (argc == 0) {
        common.printZ("Usage: hexdump <file>\n");
        return;
    }
    const name = argv[0];

    if (common.selected_disk < 0) {
        common.printError("hexdump: Not supported on RAM FS yet\n");
        return;
    }

    const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
    const bpb = fat.read_bpb(drive) orelse {
        common.printError("Error: Disk not formatted\n");
        return;
    };

    const entry = fat.find_entry(drive, bpb, common.current_dir_cluster, name) orelse {
        common.printError("Error: File not found\n");
        return;
    };

    var current_cluster = @as(u32, entry.first_cluster_low);
    var bytes_processed: u32 = 0;
    const total_size = entry.file_size;
    const eof_val = if (bpb.fat_type == .FAT12) @as(u32, 0xFF8) else @as(u32, 0xFFF8);

    var line_count: usize = 0;
    var line_buf: [16]u8 = undefined;
    var line_pos: usize = 0;

    while (current_cluster < eof_val and bytes_processed < total_size) {
        const lba = bpb.first_data_sector + (current_cluster - 2) * bpb.sectors_per_cluster;
        var s: u32 = 0;
        while (s < bpb.sectors_per_cluster and bytes_processed < total_size) : (s += 1) {
            var sector_buf: [512]u8 = undefined;
            ata.read_sector(drive, lba + s, &sector_buf);

            const to_process = @min(total_size - bytes_processed, 512);
            for (0..to_process) |j| {
                line_buf[line_pos] = sector_buf[j];
                line_pos += 1;
                bytes_processed += 1;

                if (line_pos == 16) {
                    print_hexdump_line(bytes_processed - 16, &line_buf);
                    line_pos = 0;
                    line_count += 1;
                    if (line_count >= 24) {
                        if (!pager_wait()) return;
                        line_count = 0;
                    }
                }
            }
        }
        current_cluster = fat.get_fat_entry(drive, bpb, current_cluster);
        if (current_cluster == 0) break;
    }

    if (line_pos > 0) {
        print_hexdump_line(bytes_processed - @as(u32, @intCast(line_pos)), line_buf[0..line_pos]);
    }
}

pub export fn cmd_more(name_ptr: [*]const u8, name_len: u32) void {
    var argv: [8][]const u8 = undefined;
    const argc = common.parseArgs(name_ptr[0..name_len], &argv);

    var filename: ?[]const u8 = null;
    var show_numbers = false;
    var squeeze_blank = false;
    var start_line: usize = 0;

    for (0..argc) |i| {
        const arg = argv[i];
        if (common.std_mem_eql(arg, "-n")) {
            show_numbers = true;
        } else if (common.std_mem_eql(arg, "-s")) {
            squeeze_blank = true;
        } else if (arg.len > 1 and arg[0] == '+') {
            const val = common.parse_int(arg[1..]) orelse 0;
            if (val > 0) start_line = @as(usize, @intCast(val)) - 1;
        } else if (filename == null) {
            filename = arg;
        }
    }

    var data_len: usize = 0;
    var display_name: []const u8 = "pipe";

    if (common.pipe_read_active) {
        data_len = @min(common.pipe_pos, 16384);
        common.copy(viewer_buffer[0..data_len], common.pipe_buffer[0..data_len]);
    } else {
        if (filename) |name| {
            display_name = name;
            if (common.selected_disk < 0) {
                common.printError("more: Not supported on RAM FS yet\n");
                return;
            }
            const drive = if (common.selected_disk == 0) ata.Drive.Master else ata.Drive.Slave;
            const bpb = fat.read_bpb(drive) orelse {
                common.printError("Error: Disk not formatted\n");
                return;
            };
            const entry = fat.find_entry(drive, bpb, common.current_dir_cluster, name) orelse {
                common.printError("Error: File not found\n");
                return;
            };

            const to_read = @min(@as(usize, entry.file_size), 16384);
            data_len = @as(usize, @intCast(fat.read_file_literal(drive, bpb, common.current_dir_cluster, name, &viewer_buffer)));
            if (data_len > to_read) data_len = to_read;
        } else {
            common.printZ("Usage: more [options] <file>\n");
            return;
        }
    }

    // Pre-parse into lines
    var line_count: usize = 0;
    var pos_p: usize = 0;
    var raw_line_num: usize = 1;
    var last_line_empty = false;

    const wrap_width: usize = if (show_numbers) 70 else 79;

    while (pos_p < data_len and line_count < 1024) {
        const line_start = pos_p;
        var current_col: usize = 0;

        while (pos_p < data_len and viewer_buffer[pos_p] != '\n' and current_col < wrap_width) : (pos_p += 1) {
            current_col += 1;
        }

        var line_len = pos_p - line_start;
        const hit_newline = (pos_p < data_len and viewer_buffer[pos_p] == '\n');

        if (hit_newline) pos_p += 1;

        if (line_len > 0 and viewer_buffer[line_start + line_len - 1] == '\r') line_len -= 1;

        const is_empty = (line_len == 0);
        if (squeeze_blank and is_empty and last_line_empty and hit_newline) {
            raw_line_num += 1;
            continue;
        }

        viewer_lines[line_count] = .{
            .start = line_start,
            .len = line_len,
            .original_num = if (line_start == 0 or viewer_buffer[line_start - 1] == '\n') raw_line_num else 0,
        };
        line_count += 1;

        if (hit_newline) {
            raw_line_num += 1;
            last_line_empty = is_empty;
        } else {
            last_line_empty = false;
        }
    }

    if (line_count == 0) {
        if (data_len > 0) {
            viewer_lines[0] = .{ .start = 0, .len = data_len, .original_num = 1 };
            line_count = 1;
        } else return;
    }

    var current_line: usize = @min(start_line, line_count - 1);
    const screen_rows: usize = 24;

    var needs_redraw = true;
    while (true) {
        if (needs_redraw) {
            vga.clear_screen();
            vga.zig_set_cursor(0, 0);

            const end_line = @min(current_line + screen_rows, line_count);
            for (current_line..end_line) |i| {
                const line = viewer_lines[i];
                if (show_numbers) {
                    common.vga.set_color(8, 0);
                    if (line.original_num != 0) {
                        common.printNum(@intCast(line.original_num));
                        common.printZ(": ");
                    } else {
                        common.printZ("  : ");
                    }
                    common.vga.reset_color();
                }
                common.printZ(viewer_buffer[line.start .. line.start + line.len]);
                if (i < end_line - 1) common.print_char('\n');
            }

            // Draw status bar using direct memory access to avoid auto-scroll on 80th char
            const status_row: usize = 24;
            const attr_bar: u16 = 0x7000; // Black on Light Gray
            for (0..80) |kc| {
                vga.VIDEO_MEMORY[status_row * 80 + kc] = attr_bar | @as(u16, ' ');
            }

            // Draw text onto the bar
            var bar_pos: usize = 1;
            const write_to_bar = struct {
                fn call(row: usize, start_col: *usize, text: []const u8, attr: u16) void {
                    for (text) |c| {
                        if (start_col.* >= 80) break;
                        vga.VIDEO_MEMORY[row * 80 + start_col.*] = attr | @as(u16, c);
                        start_col.* += 1;
                    }
                }
            }.call;

            // Truncate name and draw
            var name_to_show = display_name;
            if (name_to_show.len > 20) name_to_show = name_to_show[0..20];
            write_to_bar(status_row, &bar_pos, name_to_show, attr_bar);

            if (end_line == line_count) {
                write_to_bar(status_row, &bar_pos, " (END) ", attr_bar);
            } else {
                const pct = (end_line * 100) / line_count;
                write_to_bar(status_row, &bar_pos, " (", attr_bar);
                var num_buf: [4]u8 = undefined;
                const num_str = common.fmt_to_buf(&num_buf, "{d}", .{pct});
                write_to_bar(status_row, &bar_pos, num_str, attr_bar);
                write_to_bar(status_row, &bar_pos, "%) ", attr_bar);
            }
            write_to_bar(status_row, &bar_pos, "[Q]uit [G]oto End [ARROWS] Scroll", attr_bar);
            vga.reset_color();
        }

        needs_redraw = false;
        const key = keyboard_isr.keyboard_wait_char();
        if (key == 'q' or key == 'Q' or key == 27 or key == 3) break;
        if (key == keyboard_isr.KEY_DOWN or key == 10) {
            if (current_line + screen_rows < line_count + 5) {
                current_line += 1;
                needs_redraw = true;
            }
        } else if (key == keyboard_isr.KEY_UP) {
            if (current_line > 0) {
                current_line -= 1;
                needs_redraw = true;
            }
        } else if (key == ' ' or key == keyboard_isr.KEY_PGDN) {
            var next_line = current_line + screen_rows;
            const limit = if (line_count > screen_rows) line_count - screen_rows + 5 else 0;
            if (next_line > limit) next_line = limit;

            if (next_line != current_line) {
                current_line = next_line;
                needs_redraw = true;
            }
        } else if (key == 'b' or key == 'B' or key == keyboard_isr.KEY_PGUP) {
            const next_line = if (current_line > screen_rows) current_line - screen_rows else 0;
            if (next_line != current_line) {
                current_line = next_line;
                needs_redraw = true;
            }
        } else if (key == 'g' or key == 'G') {
            const next_line = if (line_count > screen_rows) line_count - screen_rows else 0;
            if (next_line != current_line) {
                current_line = next_line;
                needs_redraw = true;
            }
        }
    }
    vga.clear_screen();
}
