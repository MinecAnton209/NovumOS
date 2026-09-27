fn syscall1(n: u32, a1: u32) u32 {
    var cx: u32 = undefined;
    var dx: u32 = undefined;
    return asm volatile (
        \\pushl $0
        \\pushl $0
        \\pushfl
        \\movl %esp, %ecx
        \\call 1f
        \\1:
        \\popl %edx
        \\sysenter
        : [ret] "={eax}" (-> u32),
          [cx] "={ecx}" (cx),
          [dx] "={edx}" (dx),
        : [num] "{eax}" (n),
          [a1] "{ebx}" (a1),
    );
}

// compat: user_malloc/user_free via syscall 30/31 (inline asm)

pub fn user_malloc(size: usize) ?[*]u8 {
    const res = syscall1(30, @intCast(size));
    if (res == 0) return null;
    return @ptrFromInt(res);
}

pub fn user_free(ptr: [*]u8) void {
    _ = syscall1(31, @intFromPtr(ptr));
}
