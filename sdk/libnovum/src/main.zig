// libnovum - NovumOS Universal SDK
// Implements syscall wrappers for C, C#, and Zig

/// --- Syscall Internal Wrappers ---
inline fn syscall0(num: u32) u32 {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> u32),
        : [num] "{eax}" (num),
    );
}

inline fn syscall1(num: u32, arg1: u32) u32 {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> u32),
        : [num] "{eax}" (num),
          [arg1] "{ebx}" (arg1),
    );
}

inline fn syscall2(num: u32, arg1: u32, arg2: u32) u32 {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> u32),
        : [num] "{eax}" (num),
          [arg1] "{ebx}" (arg1),
          [arg2] "{ecx}" (arg2),
    );
}

/// --- C Exported API ---
pub export fn nv_exit(code: i32) noreturn {
    _ = syscall1(0, @as(u32, @bitCast(code)));
    while (true) {}
}

pub export fn nv_print(str: [*]const u8) void {
    _ = syscall1(1, @intFromPtr(str));
}

pub export fn nv_getchar() u8 {
    return @intCast(syscall0(2));
}

pub export fn nv_set_cursor(row: u8, col: u8) void {
    _ = syscall2(3, row, col);
}

pub export fn nv_get_cursor(row_ptr: *u8, col_ptr: *u8) void {
    const res = syscall0(4);
    row_ptr.* = @intCast(res >> 8);
    col_ptr.* = @intCast(res & 0xFF);
}

pub export fn nv_clear_screen() void {
    _ = syscall0(5);
}

/// --- Zig Idiomatic API ---
pub fn print(str: []const u8) void {
    // We need a null-terminated string for Syscall 1 currently.
    // In a real SDK, we'd either change the syscall to take length OR wrap it.
    // For now, let's assume Syscall 1 is PrintZ (null-terminated).
    nv_print(str.ptr);
}

pub fn exit(code: i32) noreturn {
    nv_exit(code);
}

pub fn getChar() u8 {
    return nv_getchar();
}
