// zig/nova_user/src/main.zig
// Nova user-space ELF entry point (Ring 3).
// No kernel imports — everything via syscall inline asm.

const interpreter = @import("nova_legacy/interpreter.zig");

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
    const msg = "Nova ELF v0.2 — Ring 3 VM\n";
    print(msg);

    // If there's a script path as argv[1], run it
    // argv is at [esp+4] per ELF convention, but we'd need a new syscall
    // to read it properly. For now, start the REPL.
    interpreter.start(null);

    _ = syscall0(0); // Exit
    unreachable;
}
