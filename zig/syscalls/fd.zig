const ata = @import("../drivers/ata.zig");
const fat = @import("../drivers/fat/fat.zig");
const user = @import("../user.zig");
const logger = @import("../logger.zig");
const memory = @import("../memory.zig");
const path_policy = @import("../path_policy.zig");
const syscalls = @import("mod.zig");
const scheduler = @import("../scheduler.zig");
const common = @import("../commands/common.zig");

const MAX_GLOBAL_HANDLES = 128;
const MAX_FD = scheduler.FD_TABLE_SIZE;
const SEEK_SET = 0;
const SEEK_CUR = 1;
const SEEK_END = 2;

var global_handles: [MAX_GLOBAL_HANDLES]?fat.FileHandle = [_]?fat.FileHandle{null} ** MAX_GLOBAL_HANDLES;

fn alloc_global_handle(handle: fat.FileHandle) ?u16 {
    for (&global_handles, 0..) |*slot, i| {
        if (slot.* == null) {
            slot.* = handle;
            return @intCast(i);
        }
    }
    return null;
}

fn free_global_handle(idx: u16) void {
    if (idx < MAX_GLOBAL_HANDLES) {
        global_handles[idx] = null;
    }
}

fn get_handle(fd: u32) ?*fat.FileHandle {
    if (fd >= MAX_FD) return null;
    const p = scheduler.current_process orelse return null;
    const gi = p.fd_table[@intCast(fd)];
    if (gi < 0 or gi >= MAX_GLOBAL_HANDLES) return null;
    if (global_handles[@intCast(gi)]) |*h| return h;
    return null;
}

fn resolve_fat_state() ?struct { ata.Drive, fat.BPB } {
    const drive: ata.Drive = if (common.selected_disk == 0) .Master else .Slave;
    const bpb = fat.read_bpb(drive) orelse return null;
    return .{ drive, bpb };
}

fn read_raw(handle: *fat.FileHandle, buf: [*]u8, count: u32) i32 {
    if (handle.offset >= handle.size) return 0;
    var bytes_read: u32 = 0;
    const cluster_size = @as(u32, handle.bpb.sectors_per_cluster) * 512;
    while (bytes_read < count and handle.offset < handle.size) {
        const sector_lba = handle.bpb.first_data_sector + (handle.cluster - 2) * @as(u32, handle.bpb.sectors_per_cluster);
        const offset_in_cluster = handle.offset % cluster_size;
        const sector_num = offset_in_cluster / 512;
        const lba = sector_lba + sector_num;
        var sector_buf: [512]u8 = undefined;
        ata.read_sector(handle.drive, @intCast(lba), &sector_buf);
        const offset_in_sector = offset_in_cluster % 512;
        const avail = @min(512 - offset_in_sector, count - bytes_read);
        const actual = @min(avail, handle.size - handle.offset);
        @memcpy(buf[bytes_read..bytes_read + actual], sector_buf[offset_in_sector..offset_in_sector + actual]);
        bytes_read += actual;
        handle.offset += actual;
        if (actual < avail) break;
        const next = fat.get_fat_entry(handle.drive, handle.bpb, handle.cluster);
        const eof_val: u32 = switch (handle.bpb.fat_type) { .FAT12 => 0xFF8, .FAT16 => 0xFFF8, .FAT32 => 0x0FFFFFF8, else => 0xFFF8 };
        if (next >= eof_val) break;
        handle.cluster = next;
    }
    return @intCast(bytes_read);
}

/// Syscall 100: open(EBX=path, ECX=flags, EDX=mode) -> EAX=fd or -1
pub fn open(regs: *user.Registers) void {
    const path = syscalls.safe_str_from_user(regs.ebx, syscalls.MAX_SYSCALL_PATH_LEN) orelse {
        regs.eax = 0xFFFFFFFF; return;
    };
    if (path.len == 0 or (path[0] != '/' and path[0] != '\\') or !path_policy.is_path_allowed(path)) {
        regs.eax = 0xFFFFFFFF; return;
    }
    const state = resolve_fat_state() orelse { regs.eax = 0xFFFFFFFF; return; };
    const p = scheduler.current_process orelse { regs.eax = 0xFFFFFFFF; return; };
    const cwd_cluster: u32 = 0;
    const handle = fat.fat_open(state[0], state[1], cwd_cluster, path) orelse {
        regs.eax = 0xFFFFFFFF; return;
    };
    const gi = alloc_global_handle(handle) orelse {
        regs.eax = 0xFFFFFFFF; return;
    };
    for (&p.fd_table, 0..) |*slot, i| {
        if (slot.* == -1) {
            slot.* = @intCast(gi);
            regs.eax = @intCast(i);
            return;
        }
    }
    free_global_handle(gi);
    regs.eax = 0xFFFFFFFF;
}

/// Syscall 101: close(EBX=fd) -> EAX=0 or -1
pub fn close(regs: *user.Registers) void {
    const p = scheduler.current_process orelse { regs.eax = 0xFFFFFFFF; return; };
    if (regs.ebx >= MAX_FD) { regs.eax = 0xFFFFFFFF; return; }
    const gi = p.fd_table[regs.ebx];
    if (gi < 0) { regs.eax = 0xFFFFFFFF; return; }
    free_global_handle(@intCast(gi));
    p.fd_table[regs.ebx] = -1;
    regs.eax = 0;
}

/// Syscall 102: read(EBX=fd, ECX=buf, EDX=count) -> EAX=bytes_read or -1
pub fn read(regs: *user.Registers) void {
    const handle = get_handle(regs.ebx) orelse { regs.eax = 0xFFFFFFFF; return; };
    if (!syscalls.is_safe_user_range(regs.ecx, regs.edx)) { regs.eax = 0xFFFFFFFF; return; }
    regs.eax = @as(u32, @bitCast(read_raw(handle, @ptrFromInt(regs.ecx), regs.edx)));
}

/// Syscall 103: write(EBX=fd, ECX=buf, EDX=count) -> EAX=bytes_written or -1
pub fn write(regs: *user.Registers) void {
    const handle = get_handle(regs.ebx) orelse { regs.eax = 0xFFFFFFFF; return; };
    if (!syscalls.is_safe_user_range(regs.ecx, regs.edx)) { regs.eax = 0xFFFFFFFF; return; }
    const data = @as([*]const u8, @ptrFromInt(regs.ecx))[0..regs.edx];
    const ret = fat.fat_puts(handle, data.ptr, @intCast(data.len));
    regs.eax = @as(u32, @bitCast(ret));
}

/// Syscall 104: lseek(EBX=fd, ECX=offset, EDX=whence) -> EAX=new_pos or -1
pub fn lseek(regs: *user.Registers) void {
    const handle = get_handle(regs.ebx) orelse { regs.eax = 0xFFFFFFFF; return; };
    const result = fat.fat_lseek(handle, @as(i64, @intCast(regs.ecx)), @intCast(regs.edx));
    regs.eax = @as(u32, @bitCast(@as(i32, @intCast(result))));
}

const KernelStat = extern struct {
    size: u64,
    mode: u32,
    uid: u32,
    gid: u32,
    atime_sec: i64,
    atime_nsec: i64,
    mtime_sec: i64,
    mtime_nsec: i64,
    ctime_sec: i64,
    ctime_nsec: i64,
    dev: u64,
    ino: u64,
    nlink: u32,
    blksize: u32,
    blocks: u32,
};

fn stat_impl(path_ptr: u32, stat_ptr: u32) bool {
    const path = syscalls.safe_str_from_user(path_ptr, syscalls.MAX_SYSCALL_PATH_LEN) orelse return false;
    if (path.len == 0 or (path[0] != '/' and path[0] != '\\') or !path_policy.is_path_allowed(path)) return false;
    if (!syscalls.is_safe_user_range(stat_ptr, @sizeOf(KernelStat))) return false;
    const state = resolve_fat_state() orelse return false;
    const entry = fat.find_entry(state[0], state[1], 0, path) orelse return false;
    const s = @as(*KernelStat, @ptrFromInt(stat_ptr));
    s.* = .{
        .size = entry.file_size,
        .mode = if ((entry.attr & 0x10) != 0) 0x41ED else 0x81A4,
        .uid = 0,
        .gid = 0,
        .atime_sec = 0, .atime_nsec = 0,
        .mtime_sec = 0, .mtime_nsec = 0,
        .ctime_sec = 0, .ctime_nsec = 0,
        .dev = 0, .ino = 0,
        .nlink = 1,
        .blksize = 512,
        .blocks = (entry.file_size + 511) / 512,
    };
    return true;
}

/// Syscall 105: stat(EBX=path, ECX=stat_buf) -> EAX=0 or -1
pub fn stat(regs: *user.Registers) void {
    regs.eax = if (stat_impl(regs.ebx, regs.ecx)) 0 else 0xFFFFFFFF;
}

/// Syscall 106: fstat(EBX=fd, ECX=stat_buf) -> EAX=0 or -1
pub fn fstat(regs: *user.Registers) void {
    const handle = get_handle(regs.ebx) orelse { regs.eax = 0xFFFFFFFF; return; };
    if (!syscalls.is_safe_user_range(regs.ecx, @sizeOf(KernelStat))) { regs.eax = 0xFFFFFFFF; return; }
    const s = @as(*KernelStat, @ptrFromInt(regs.ecx));
    s.* = .{
        .size = handle.size,
        .mode = 0x81A4,
        .uid = 0, .gid = 0,
        .atime_sec = 0, .atime_nsec = 0,
        .mtime_sec = 0, .mtime_nsec = 0,
        .ctime_sec = 0, .ctime_nsec = 0,
        .dev = 0, .ino = 0,
        .nlink = 1,
        .blksize = 512,
        .blocks = (handle.size + 511) / 512,
    };
    regs.eax = 0;
}
