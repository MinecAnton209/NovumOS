// zig/syscalls/mod.zig
// Syscall dispatch table + shared validation helpers.
// Each category file (console, port, time, memory, etc.) implements a
// subset of handlers; this file dispatches by syscall number (regs.eax).
//
// All user pointers passed to handlers MUST be validated with
// is_safe_user_range() or safe_str_from_user() before dereferencing.

const common = @import("../commands/common.zig");
const memory = @import("../memory.zig");
const user = @import("../user.zig");
const logger = @import("../logger.zig");

/// All syscall handlers implement this signature
pub const Handler = fn (regs: *user.Registers) void;
pub const HandlerPtr = *const Handler;

/// User space boundary (3GB/1GB split on x86)
pub const USER_SPACE_TOP: usize = 0xC0000000;

/// Maximum syscall string length (PrintZ, WriteBuf, etc.)
pub const MAX_SYSCALL_STR_LEN: usize = 4096;

/// Maximum path length (file syscalls)
pub const MAX_SYSCALL_PATH_LEN: usize = 256;

/// Check if [addr..addr+len) is fully in user space AND every page
/// touched by the range is mapped with USER bit set.
///
/// This is defense in depth:
///   1. addr < USER_SPACE_TOP (rejects kernel pointers)
///   2. end = addr + len <= USER_SPACE_TOP (no overflow into kernel)
///   3. end >= addr (no wraparound)
///   4. EVERY page in [addr, addr+len) has USER bit (not just first/last)
///
/// The 4th check is critical: a buffer spanning 3 pages with the middle
/// page unmapped would pass a naive first+last check, but reading it in
/// the kernel would cause a Page Fault in Ring 0 → Kernel Panic.
pub fn is_safe_user_range(addr: usize, len: usize) bool {
    if (len == 0) return true;
    if (addr >= USER_SPACE_TOP) return false;
    const end = addr + len;
    if (end > USER_SPACE_TOP) return false;
    if (end < addr) return false; // wraparound

    var page = addr & ~@as(usize, 0xFFF);
    const end_page = (end - 1) & ~@as(usize, 0xFFF);
    while (page <= end_page) : (page += 0x1000) {
        if (!memory.is_user_ptr(page)) return false;
    }
    return true;
}

/// Safely read a null-terminated user string. Returns the slice
/// (within a stack buffer) on success, null if the string is not
/// properly null-terminated within max_len or fails range checks.
///
/// NOTE: the returned slice points into a static 4KB buffer; copy
/// the data if you need to keep it across calls.
pub fn safe_str_from_user(ptr: usize, max_len: usize) ?[]const u8 {
    if (max_len == 0) return null;
    if (ptr >= USER_SPACE_TOP) return null;
    if (!memory.is_user_ptr(ptr)) return null;
    if (!memory.is_user_ptr(ptr + max_len - 1)) return null;

    const p = @as([*]const u8, @ptrFromInt(ptr));
    var i: usize = 0;
    while (i < max_len) : (i += 1) {
        if (p[i] == 0) return p[0..i];
    }
    return null; // not null-terminated within max_len
}

/// Dispatch table: index = syscall number, value = handler function.
/// Wired in mod.zig so each category file stays self-contained.
pub const HANDLERS: [256]?HandlerPtr = blk: {
    const console_mod = @import("console.zig");
    const port_mod = @import("port.zig");
    const time_mod = @import("time.zig");
    const memory_mod = @import("memory.zig");
    const process_mod = @import("process.zig");
    const control_mod = @import("control.zig");
    const storage_mod = @import("storage.zig");
    const speaker_mod = @import("speaker.zig");
    const debug_mod = @import("debug.zig");
    const file_mod = @import("file.zig");
    const nova_mod = @import("nova.zig");
    const fd_mod = @import("fd.zig");
    const video_mod = @import("video.zig");

    var table: [256]?HandlerPtr = [_]?HandlerPtr{null} ** 256;
    // Console
    table[1] = &console_mod.printZ;
    table[2] = &console_mod.getChar;
    table[3] = &console_mod.setCursor;
    table[4] = &console_mod.getCursor;
    table[5] = &console_mod.clearScreen;
    table[18] = &console_mod.drawCharAt;
    // Port
    table[6] = &port_mod.inB;
    table[7] = &port_mod.outB;
    table[8] = &port_mod.inW;
    table[9] = &port_mod.outW;
    table[16] = &port_mod.inL;
    table[17] = &port_mod.outL;
    // Time
    table[10] = &time_mod.sleep;
    table[11] = &time_mod.getTicks;
    table[19] = &time_mod.getDateTime;
    // Memory
    table[15] = &memory_mod.memoryMapRange;
    table[30] = &memory_mod.malloc;
    table[31] = &memory_mod.free;
    table[44] = &memory_mod.getFreeMemory;
    // Process
    table[0] = &process_mod.exit;
    table[12] = &process_mod.jumpToUser;
    table[40] = &process_mod.execve;
    table[41] = &process_mod.yield;
    // Control (privileged — shell only)
    table[13] = &control_mod.shutdown;
    table[14] = &control_mod.reboot;
    // Storage (privileged ATA)
    table[20] = &storage_mod.ataIdentify;
    table[21] = &storage_mod.ataReadSector;
    table[22] = &storage_mod.ataWriteSector;
    // Speaker
    table[42] = &speaker_mod.speakerOp;
    // Debug
    table[32] = &debug_mod.checkCtrlC;
    table[33] = &debug_mod.idtCheck;
    table[34] = &debug_mod.idtMove;
    table[43] = &debug_mod.writeBuf;
    // File (Ring 3 file syscalls via FAT)
    table[45] = &file_mod.readFile;
    table[46] = &file_mod.writeFile;
    table[47] = &file_mod.deleteFile;
    table[48] = &file_mod.renameFile;
    table[49] = &file_mod.statFile;
    table[50] = &file_mod.getRes;
    table[51] = &file_mod.existsFile;
    table[52] = &file_mod.copyFile;
    // Nova
    table[53] = &nova_mod.shellExec;
    table[54] = &nova_mod.setColor;
    // FD-based file I/O (POSIX-compatible syscalls)
    table[100] = &fd_mod.open;
    table[101] = &fd_mod.close;
    table[102] = &fd_mod.read;
    table[103] = &fd_mod.write;
    table[104] = &fd_mod.lseek;
    table[105] = &fd_mod.stat;
    table[106] = &fd_mod.fstat;
    // Memory mapping
    table[107] = &memory_mod.mmap;
    table[108] = &memory_mod.munmap;
    // Video/Graphics
    table[60] = &video_mod.getVideoMode;
    table[61] = &video_mod.requestFramebuffer;
    table[62] = &video_mod.releaseFramebuffer;
    // Input
    table[63] = &video_mod.pollEvent;
    // Time
    table[110] = &time_mod.clock_gettime;
    table[111] = &time_mod.nanosleep;
    // Process
    table[112] = &process_mod.getpid;
    table[113] = &process_mod.getppid;
    table[114] = &process_mod.uname;
    break :blk table;
};

/// Dispatch a syscall to its handler. Called from user.zig's
/// handle_syscall_zig trampoline.
pub fn dispatch(regs: *user.Registers) void {
    if (regs.eax >= HANDLERS.len) {
        var buf: [32]u8 = undefined;
        logger.err("Unknown syscall (eax out of range)");
        logger.debug(common.intToString(@intCast(regs.eax), &buf));
        return;
    }
    if (HANDLERS[regs.eax]) |handler| {
        handler(regs);
    } else {
        var buf: [32]u8 = undefined;
        logger.err("Unknown syscall");
        logger.debug(common.intToString(@intCast(regs.eax), &buf));
    }
}
