// compat: user_malloc/user_free via syscall 30/31 (inline asm)

fn syscall1(n: u32, a1: u32) u32 {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> u32),
        : [num] "{eax}" (n),
          [a1] "{ebx}" (a1),
    );
}

pub fn user_malloc(size: usize) ?[*]u8 {
    const res = syscall1(30, @intCast(size));
    if (res == 0) return null;
    return @ptrFromInt(res);
}

pub fn user_free(ptr: [*]u8) void {
    _ = syscall1(31, @intFromPtr(ptr));
}
