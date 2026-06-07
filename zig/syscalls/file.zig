// zig/syscalls/file.zig
// File system syscalls (45-52) for Ring 3 processes.
// Uses FAT driver via absolute paths. All paths validated by path_policy.

const common = @import("../commands/common.zig");
const fat = @import("../drivers/fat/fat.zig");
const ata = @import("../drivers/ata.zig");
const user = @import("../user.zig");
const logger = @import("../logger.zig");
const path_policy = @import("../path_policy.zig");
const syscalls = @import("mod.zig");

/// StatResult returned by syscall 49 (16 bytes, user-allocated)
const StatResult = extern struct {
    size: u32,
    is_dir: u8,
    reserved: [11]u8,
};

/// Helper: get FAT drive & BPB from current disk selection
fn get_fat_state() ?struct { ata.Drive, fat.BPB } {
    const drive: ata.Drive = if (common.selected_disk == 0) .Master else .Slave;
    const bpb = fat.read_bpb(drive) orelse {
        logger.security("File syscall: no FAT filesystem on disk");
        return null;
    };
    return .{ drive, bpb };
}

/// Helper: validate path from user, check policy, resolve via FAT.
/// Returns the resolved PathResolution on success.
fn resolve_user_path(path_ptr: u32) ?fat.PathResolution {
    const path = syscalls.safe_str_from_user(path_ptr, syscalls.MAX_SYSCALL_PATH_LEN) orelse {
        logger.security("File syscall: invalid path string");
        return null;
    };
    if (path.len == 0 or (path[0] != '/' and path[0] != '\\')) {
        logger.security("File syscall: path must be absolute");
        return null;
    }
    if (!path_policy.is_path_allowed(path)) {
        logger.security("File syscall: path blocked by policy");
        return null;
    }
    const state = get_fat_state() orelse return null;
    return fat.resolve_path(state[0], state[1], 0, path);
}

/// Syscall 45: ReadFile(EBX=path, ECX=buf, EDX=buf_size) -> EAX (bytes read or -1)
pub fn readFile(regs: *user.Registers) void {
    const path = syscalls.safe_str_from_user(regs.ebx, syscalls.MAX_SYSCALL_PATH_LEN) orelse {
        regs.eax = 0xFFFFFFFF;
        return;
    };
    if (path.len == 0 or (path[0] != '/' and path[0] != '\\')) {
        regs.eax = 0xFFFFFFFF;
        return;
    }
    if (!path_policy.is_path_allowed(path)) {
        regs.eax = 0xFFFFFFFF;
        return;
    }
    const state = get_fat_state() orelse {
        regs.eax = 0xFFFFFFFF;
        return;
    };
    if (!syscalls.is_safe_user_range(regs.ecx, regs.edx)) {
        logger.security("ReadFile: invalid output buffer");
        regs.eax = 0xFFFFFFFF;
        return;
    }
    const bytes = fat.read_file(state[0], state[1], 0, path, @ptrFromInt(regs.ecx));
    if (bytes < 0) {
        regs.eax = 0xFFFFFFFF;
    } else {
        regs.eax = @as(u32, @intCast(bytes));
    }
}

/// Syscall 46: WriteFile(EBX=path, ECX=data, EDX=data_len) -> EAX (0=success, -1=error)
pub fn writeFile(regs: *user.Registers) void {
    const path = syscalls.safe_str_from_user(regs.ebx, syscalls.MAX_SYSCALL_PATH_LEN) orelse {
        regs.eax = 0xFFFFFFFF;
        return;
    };
    if (path.len == 0 or (path[0] != '/' and path[0] != '\\')) {
        regs.eax = 0xFFFFFFFF;
        return;
    }
    if (!path_policy.is_path_allowed(path)) {
        regs.eax = 0xFFFFFFFF;
        return;
    }
    if (!syscalls.is_safe_user_range(regs.ecx, regs.edx)) {
        logger.security("WriteFile: invalid data buffer");
        regs.eax = 0xFFFFFFFF;
        return;
    }
    const data = @as([*]const u8, @ptrFromInt(regs.ecx))[0..regs.edx];
    const state = get_fat_state() orelse {
        regs.eax = 0xFFFFFFFF;
        return;
    };
    if (fat.write_file(state[0], state[1], 0, path, data)) {
        regs.eax = 0;
    } else {
        regs.eax = 0xFFFFFFFF;
    }
}

/// Syscall 47: Delete(EBX=path) -> EAX (0=success, -1=error)
pub fn deleteFile(regs: *user.Registers) void {
    const path = syscalls.safe_str_from_user(regs.ebx, syscalls.MAX_SYSCALL_PATH_LEN) orelse {
        regs.eax = 0xFFFFFFFF;
        return;
    };
    if (path.len == 0 or (path[0] != '/' and path[0] != '\\')) {
        regs.eax = 0xFFFFFFFF;
        return;
    }
    if (!path_policy.is_path_allowed(path)) {
        regs.eax = 0xFFFFFFFF;
        return;
    }
    const state = get_fat_state() orelse {
        regs.eax = 0xFFFFFFFF;
        return;
    };
    if (fat.delete_file(state[0], state[1], 0, path)) {
        regs.eax = 0;
    } else {
        regs.eax = 0xFFFFFFFF;
    }
}

/// Syscall 48: Rename(EBX=old_path, ECX=new_path) -> EAX (0=success, -1=error)
pub fn renameFile(regs: *user.Registers) void {
    const old_path = syscalls.safe_str_from_user(regs.ebx, syscalls.MAX_SYSCALL_PATH_LEN) orelse {
        regs.eax = 0xFFFFFFFF;
        return;
    };
    const new_path = syscalls.safe_str_from_user(regs.ecx, syscalls.MAX_SYSCALL_PATH_LEN) orelse {
        regs.eax = 0xFFFFFFFF;
        return;
    };
    if (old_path.len == 0 or new_path.len == 0) {
        regs.eax = 0xFFFFFFFF;
        return;
    }
    if (!path_policy.is_path_allowed(old_path) or !path_policy.is_path_allowed(new_path)) {
        regs.eax = 0xFFFFFFFF;
        return;
    }
    const state = get_fat_state() orelse {
        regs.eax = 0xFFFFFFFF;
        return;
    };
    if (fat.rename_file(state[0], state[1], 0, old_path, new_path)) {
        regs.eax = 0;
    } else {
        regs.eax = 0xFFFFFFFF;
    }
}

/// Syscall 49: Stat(EBX=path, ECX=StatResult_ptr) -> EAX (0=success, -1=error)
pub fn statFile(regs: *user.Registers) void {
    const path = syscalls.safe_str_from_user(regs.ebx, syscalls.MAX_SYSCALL_PATH_LEN) orelse {
        regs.eax = 0xFFFFFFFF;
        return;
    };
    if (path.len == 0 or (path[0] != '/' and path[0] != '\\')) {
        regs.eax = 0xFFFFFFFF;
        return;
    }
    if (!path_policy.is_path_allowed(path)) {
        regs.eax = 0xFFFFFFFF;
        return;
    }
    if (!syscalls.is_safe_user_range(regs.ecx, @sizeOf(StatResult))) {
        logger.security("StatFile: invalid StatResult pointer");
        regs.eax = 0xFFFFFFFF;
        return;
    }
    const state = get_fat_state() orelse {
        regs.eax = 0xFFFFFFFF;
        return;
    };
    const entry = fat.find_entry(state[0], state[1], 0, path) orelse {
        regs.eax = 0xFFFFFFFF;
        return;
    };
    const result = @as(*StatResult, @ptrFromInt(regs.ecx));
    result.* = .{
        .size = entry.file_size,
        .is_dir = if ((entry.attr & 0x10) != 0) 1 else 0,
        .reserved = [_]u8{0} ** 11,
    };
    regs.eax = 0;
}

/// Syscall 50: GetRes(EBX=path) -> EAX (file size or -1)
/// Returns the size of the file at the given path.
pub fn getRes(regs: *user.Registers) void {
    const path = syscalls.safe_str_from_user(regs.ebx, syscalls.MAX_SYSCALL_PATH_LEN) orelse {
        regs.eax = 0xFFFFFFFF;
        return;
    };
    if (path.len == 0 or (path[0] != '/' and path[0] != '\\')) {
        regs.eax = 0xFFFFFFFF;
        return;
    }
    if (!path_policy.is_path_allowed(path)) {
        regs.eax = 0xFFFFFFFF;
        return;
    }
    const state = get_fat_state() orelse {
        regs.eax = 0xFFFFFFFF;
        return;
    };
    const size = fat.fat_size(state[0], state[1], 0, path);
    if (size == 0) {
        // Could be empty file or not found; try find_entry to disambiguate
        if (fat.find_entry(state[0], state[1], 0, path) == null) {
            regs.eax = 0xFFFFFFFF;
            return;
        }
    }
    regs.eax = size;
}

/// Syscall 51: Exists(EBX=path) -> EAX (1=exists, 0=not found)
pub fn existsFile(regs: *user.Registers) void {
    const path = syscalls.safe_str_from_user(regs.ebx, syscalls.MAX_SYSCALL_PATH_LEN) orelse {
        regs.eax = 0;
        return;
    };
    if (path.len == 0 or (path[0] != '/' and path[0] != '\\')) {
        regs.eax = 0;
        return;
    }
    // Path policy doesn't block existence checks — allow even blocked paths
    // to report existence (no data access). But for safety, apply policy.
    if (!path_policy.is_path_allowed(path)) {
        regs.eax = 0;
        return;
    }
    const state = get_fat_state() orelse {
        regs.eax = 0;
        return;
    };
    if (fat.find_entry(state[0], state[1], 0, path) != null) {
        regs.eax = 1;
    } else {
        regs.eax = 0;
    }
}

/// Syscall 52: Copy(EBX=src_path, ECX=dst_path) -> EAX (0=success, -1=error)
pub fn copyFile(regs: *user.Registers) void {
    const src = syscalls.safe_str_from_user(regs.ebx, syscalls.MAX_SYSCALL_PATH_LEN) orelse {
        regs.eax = 0xFFFFFFFF;
        return;
    };
    const dst = syscalls.safe_str_from_user(regs.ecx, syscalls.MAX_SYSCALL_PATH_LEN) orelse {
        regs.eax = 0xFFFFFFFF;
        return;
    };
    if (src.len == 0 or dst.len == 0) {
        regs.eax = 0xFFFFFFFF;
        return;
    }
    if (!path_policy.is_path_allowed(src) or !path_policy.is_path_allowed(dst)) {
        regs.eax = 0xFFFFFFFF;
        return;
    }
    const state = get_fat_state() orelse {
        regs.eax = 0xFFFFFFFF;
        return;
    };
    if (fat.copy_file(state[0], state[1], 0, src, dst)) {
        regs.eax = 0;
    } else {
        regs.eax = 0xFFFFFFFF;
    }
}
