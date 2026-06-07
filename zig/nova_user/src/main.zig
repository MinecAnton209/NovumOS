// zig/nova_user/src/main.zig
// Nova user-space ELF entry point (Ring 3).
// No kernel imports — everything via syscall inline asm.

fn syscall0(n: u32) u32 {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> u32),
        : [num] "{eax}" (n),
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

fn print(msg: []const u8) void {
    _ = syscall2(43, @intFromPtr(msg.ptr), @intCast(msg.len));
}

export fn _start() noreturn {
    const msg = "Nova ELF: Ring 3 VM loaded\n";
    print(msg);

    _ = syscall0(0); // Exit
    unreachable;
}
