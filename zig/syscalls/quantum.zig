const user = @import("../user.zig");
const syscalls = @import("mod.zig");
const quantum = @import("../quantum.zig");

/// Syscall 55: return one quantum-random byte in EAX.
pub fn qrand(regs: *user.Registers) void {
    regs.eax = quantum.randByte();
}

/// Syscall 56: fill a user-space buffer (EBX) of len ECX with random bytes.
pub fn qrandBuf(regs: *user.Registers) void {
    const ptr = regs.ebx;
    const len: usize = @intCast(regs.ecx);
    if (len > 0 and len <= syscalls.MAX_SYSCALL_STR_LEN and syscalls.is_safe_user_range(ptr, len)) {
        const buf = @as([*]u8, @ptrFromInt(ptr))[0..len];
        quantum.fillBuf(buf);
    }
}

/// Syscall 57: return an entangled pair — low byte = first qubit reading,
/// high byte = second (correlated) reading, packed in EAX.
pub fn qrandEntangle(regs: *user.Registers) void {
    const pair = quantum.entangledPair();
    regs.eax = @as(u32, @intCast(pair[0])) | (@as(u32, @intCast(pair[1])) << 8);
}
