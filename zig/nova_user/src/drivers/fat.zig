// compat: FAT driver interface via syscalls 45-52 (Ring 3).
// All file ops go through kernel's permission-checked syscalls.
// BPB/drive/cluster params are accepted for signature compat but ignored.

const ata = @import("ata.zig");

// Helper syscalls
fn syscall1(n: u32, a1: u32) u32 {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> u32),
        : [num] "{eax}" (n),
          [a1] "{ebx}" (a1),
    );
}
fn syscall2(n: u32, a1: u32, a2: u32) u32 {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> u32),
        : [num] "{eax}" (n),
          [a1] "{ebx}" (a1),
          [a2] "{ecx}" (a2),
    );
}
fn syscall3(n: u32, a1: u32, a2: u32, a3: u32) u32 {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> u32),
        : [num] "{eax}" (n),
          [a1] "{ebx}" (a1),
          [a2] "{ecx}" (a2),
          [a3] "{edx}" (a3),
    );
}

// Re-export ATA Drive for callers
pub const Drive = ata.Drive;

// Minimal BPB stub (accepted as arg but ignored — file syscalls handle it)
pub const BPB = struct {
    bytes_per_sector: u16 = 512,
};
pub const DirEntry = struct {
    name: [8]u8 = [_]u8{0} ** 8,
    ext: [3]u8 = [_]u8{0} ** 3,
    attr: u8 = 0,
    reserved: u8 = 0,
    creation_time_tenth: u8 = 0,
    creation_time: u16 = 0,
    creation_date: u16 = 0,
    last_access_date: u16 = 0,
    first_cluster_high: u16 = 0,
    write_time: u16 = 0,
    write_date: u16 = 0,
    first_cluster_low: u16 = 0,
    file_size: u32 = 0,
};
pub const PathResolution = struct { dir_cluster: u32, file_name: []const u8 };
pub const ResolvedPath = struct {
    cluster: u32,
    is_dir: bool,
    path: [256]u8,
    path_len: usize,
};

// StatResult from syscall 49 (16 bytes)
const StatResult = extern struct {
    size: u32,
    is_dir: u8,
    reserved: [11]u8,
};

/// Read entire file contents. Uses syscall 45 ReadFile.
pub fn read_file(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8, output: [*]u8) i32 {
    _ = drive;
    _ = bpb;
    _ = dir_cluster;
    // Use a WriteBuf to print the path first (debug), then do ReadFile
    const result = syscall3(45, @intFromPtr(path.ptr), @intFromPtr(output), 0x10000);
    if (result == 0xFFFFFFFF) return -1;
    return @as(i32, @intCast(result));
}

/// Write (create/replace) file. Uses syscall 46 WriteFile.
pub fn write_file(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8, data: []const u8) bool {
    _ = drive;
    _ = bpb;
    _ = dir_cluster;
    const result = syscall3(46, @intFromPtr(path.ptr), @intFromPtr(data.ptr), @intCast(data.len));
    return result != 0xFFFFFFFF;
}

/// Delete file. Uses syscall 47 Delete.
pub fn delete_file(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8) bool {
    _ = drive;
    _ = bpb;
    _ = dir_cluster;
    return syscall1(47, @intFromPtr(path.ptr)) != 0xFFFFFFFF;
}

/// Rename file. Uses syscall 48 Rename.
pub fn rename_file(drive: ata.Drive, bpb: BPB, dir_cluster: u32, old_path: []const u8, new_path: []const u8) bool {
    _ = drive;
    _ = bpb;
    _ = dir_cluster;
    return syscall2(48, @intFromPtr(old_path.ptr), @intFromPtr(new_path.ptr)) != 0xFFFFFFFF;
}

/// Copy file. Uses syscall 52 Copy.
pub fn copy_file(drive: ata.Drive, bpb: BPB, dir_cluster: u32, src_path: []const u8, dest_path: []const u8) bool {
    _ = drive;
    _ = bpb;
    _ = dir_cluster;
    return syscall2(52, @intFromPtr(src_path.ptr), @intFromPtr(dest_path.ptr)) != 0xFFFFFFFF;
}

/// Find entry (check existence + get size). Uses syscall 49 Stat + 51 Exists.
pub fn find_entry(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8) ?DirEntry {
    _ = drive;
    _ = bpb;
    _ = dir_cluster;
    // First check if it exists (syscall 51)
    const exists = syscall1(51, @intFromPtr(path.ptr));
    if (exists == 0) return null;
    // Get stat info (syscall 49)
    var stat: StatResult = undefined;
    const stat_result = syscall2(49, @intFromPtr(path.ptr), @intFromPtr(&stat));
    if (stat_result == 0xFFFFFFFF) return null;
    return DirEntry{
        .file_size = stat.size,
        .attr = if (stat.is_dir != 0) 0x10 else 0,
        .name = genName(path),
        .ext = genExt(path),
        .first_cluster_low = 0,
        .first_cluster_high = 0,
        .write_time = 0,
        .write_date = 0,
        .creation_time = 0,
        .creation_date = 0,
        .last_access_date = 0,
        .reserved = 0,
        .creation_time_tenth = 0,
    };
}

/// Get file size. Uses syscall 50 GetRes.
pub fn fat_size(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8) u32 {
    _ = drive;
    _ = bpb;
    _ = dir_cluster;
    const result = syscall1(50, @intFromPtr(path.ptr));
    if (result == 0xFFFFFFFF) return 0;
    return result;
}

/// Stub: BPB not available from Ring 3
pub fn read_bpb(drive: ata.Drive) ?BPB {
    _ = drive;
    return BPB{};
}

/// Stub: path resolution handled by kernel
pub fn resolve_path(drive: ata.Drive, bpb: BPB, start_dir: u32, path: []const u8) ?PathResolution {
    _ = drive;
    _ = bpb;
    _ = start_dir;
    return PathResolution{ .dir_cluster = 0, .file_name = path };
}

pub fn resolve_full_path(drive: ata.Drive, bpb: BPB, start_cluster: u32, start_path: []const u8, input_path: []const u8) ?ResolvedPath {
    _ = drive;
    _ = bpb;
    _ = start_cluster;
    _ = start_path;
    _ = input_path;
    return null; // Return null to fall back to direct path usage
}

pub fn find_entry_literal(drive: ata.Drive, bpb: BPB, dir_cluster: u32, name: []const u8) ?DirEntry {
    return find_entry(drive, bpb, dir_cluster, name);
}

pub fn find_entry_location(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8) ?EntryLocation {
    _ = drive;
    _ = bpb;
    _ = dir_cluster;
    _ = path;
    return null;
}

pub fn find_entry_location_literal(drive: ata.Drive, bpb: BPB, dir_cluster: u32, name: []const u8) ?EntryLocation {
    _ = drive;
    _ = bpb;
    _ = dir_cluster;
    _ = name;
    return null;
}

pub const EntryLocation = struct { sector: u32, offset: u32 };

pub fn delete_directory(drive: ata.Drive, bpb: BPB, parent_cluster: u32, path: []const u8, recursive: bool) bool {
    _ = drive;
    _ = bpb;
    _ = parent_cluster;
    _ = path;
    _ = recursive;
    return false; // Not supported from Ring 3
}

pub fn create_directory(drive: ata.Drive, bpb: BPB, dir_cluster: u32, path: []const u8) bool {
    _ = drive;
    _ = bpb;
    _ = dir_cluster;
    _ = path;
    return false; // Not supported from Ring 3
}

pub fn copy_directory(drive: ata.Drive, bpb: BPB, parent_cluster: u32, src_path: []const u8, dest_path: []const u8) bool {
    _ = drive;
    _ = bpb;
    _ = parent_cluster;
    _ = src_path;
    _ = dest_path;
    return false; // Not supported from Ring 3
}

pub fn is_directory_empty(drive: ata.Drive, bpb: BPB, dir_cluster: u32) bool {
    _ = drive;
    _ = bpb;
    _ = dir_cluster;
    return true; // Safe default
}

pub fn list_directory(drive: ata.Drive, bpb: BPB, dir_cluster: u32, show_hidden: bool) void {
    _ = drive;
    _ = bpb;
    _ = dir_cluster;
    _ = show_hidden;
}

fn genName(path: []const u8) [8]u8 {
    var result: [8]u8 = [_]u8{0x20} ** 8;
    const slash = lastIndexOf(path, '/') orelse return result;
    const name = path[slash + 1 ..];
    const dot = indexOf(name, '.') orelse name.len;
    const n = @min(dot, 8);
    for (name[0..n], 0..) |c, i| {
        result[i] = c;
    }
    return result;
}

fn genExt(path: []const u8) [3]u8 {
    var result: [3]u8 = [_]u8{0x20} ** 3;
    const slash = lastIndexOf(path, '/') orelse return result;
    const name = path[slash + 1 ..];
    const dot = indexOf(name, '.') orelse return result;
    const ext = name[dot + 1 ..];
    const n = @min(ext.len, 3);
    for (ext[0..n], 0..) |c, i| {
        result[i] = c;
    }
    return result;
}

fn lastIndexOf(slice: []const u8, c: u8) ?usize {
    var i = slice.len;
    while (i > 0) {
        i -= 1;
        if (slice[i] == c) return i;
    }
    return null;
}

fn indexOf(slice: []const u8, c: u8) ?usize {
    for (slice, 0..) |ch, i| {
        if (ch == c) return i;
    }
    return null;
}
