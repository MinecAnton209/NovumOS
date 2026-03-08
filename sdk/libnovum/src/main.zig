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

inline fn syscall3(num: u32, arg1: u32, arg2: u32, arg3: u32) u32 {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> u32),
        : [num] "{eax}" (num),
          [arg1] "{ebx}" (arg1),
          [arg2] "{ecx}" (arg2),
          [arg3] "{edx}" (arg3),
    );
}

inline fn syscall4(num: u32, arg1: u32, arg2: u32, arg3: u32, arg4: u32) u32 {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> u32),
        : [num] "{eax}" (num),
          [arg1] "{ebx}" (arg1),
          [arg2] "{ecx}" (arg2),
          [arg3] "{edx}" (arg3),
          [arg4] "{esi}" (arg4),
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

pub export fn nv_inb(port: u16) u8 {
    return @intCast(syscall1(6, port));
}

pub export fn nv_outb(port: u16, val: u8) void {
    _ = syscall2(7, port, val);
}

pub export fn nv_inw(port: u16) u16 {
    return @intCast(syscall1(8, port));
}

pub export fn nv_outw(port: u16, val: u16) void {
    _ = syscall2(9, port, val);
}

pub export fn nv_sleep(ms: u32) void {
    _ = syscall1(10, ms);
}

pub export fn nv_get_ticks() u32 {
    return syscall0(11);
}

pub export fn nv_shutdown() void {
    _ = syscall0(13);
}

pub export fn nv_reboot() void {
    _ = syscall0(14);
}

pub export fn nv_mmap_range(vaddr: u32, size: u32) void {
    _ = syscall2(15, vaddr, size);
}

pub export fn nv_inl(port: u16) u32 {
    return syscall1(16, port);
}

pub export fn nv_outl(port: u16, val: u32) void {
    _ = syscall2(17, port, val);
}

pub export fn nv_draw_char_at(row: u8, col: u8, c: u8, attr: u16) void {
    _ = syscall4(18, row, col, c, attr);
}

pub export fn nv_get_datetime(dt_ptr: usize) void {
    _ = syscall1(19, dt_ptr);
}

pub export fn nv_malloc(size: u32) ?[*]u8 {
    const res = syscall1(30, size);
    if (res == 0) return null;
    return @ptrFromInt(res);
}

pub export fn nv_free(ptr: ?[*]u8) void {
    if (ptr) |p| {
        _ = syscall1(31, @intFromPtr(p));
    }
}

pub export fn nv_check_ctrl_c() i32 {
    return @intCast(syscall0(32));
}

/// --- Zig Idiomatic API ---
pub fn print(str: []const u8) void {
    nv_print(str.ptr);
}

pub fn exit(code: i32) noreturn {
    nv_exit(code);
}

pub fn getChar() u8 {
    return nv_getchar();
}

pub fn sleep(ms: u32) void {
    nv_sleep(ms);
}

pub fn getTicks() u32 {
    return nv_get_ticks();
}

pub fn malloc(size: u32) ?[*]u8 {
    return nv_malloc(size);
}

pub fn free(ptr: ?[*]u8) void {
    nv_free(ptr);
}

pub fn reboot() void {
    nv_reboot();
}

pub fn shutdown() void {
    nv_shutdown();
}
