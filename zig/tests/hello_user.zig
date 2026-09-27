fn print_z(str: [*:0]const u8) void {
    var cx: u32 = undefined;
    var dx: u32 = undefined;
    asm volatile (
        \\pushl $0
        \\pushl $0
        \\pushfl
        \\movl %esp, %ecx
        \\call 1f
        \\1:
        \\popl %edx
        \\sysenter
        : [cx] "={ecx}" (cx),
          [dx] "={edx}" (dx),
        : [sys] "{eax}" (@as(u32, 1)),
          [str] "{ebx}" (@intFromPtr(str)),
    );
}

// Simple test program for NovumOS ELF loader
// This program will use Syscall 1 (PrintZ) and Syscall 0 (Exit)
// Syscall 1 expects a pointer to a null-terminated string in EBX.

pub fn main() noreturn {
    // In Zig, string literals are null-terminated by default (*const [N:0]u8).
    // They safely coerce to [*:0]const u8, which matches what our syscall expects.
    print_z("Hello from Ring 3 ELF!\n");
    print_z("Testing memory bounds and syscall isolation...\n");
    print_z("Exiting...\n");

    // Exit syscall (0)
    var cx: u32 = undefined;
    var dx: u32 = undefined;
    asm volatile (
        \\pushl $0
        \\pushl $0
        \\pushfl
        \\movl %esp, %ecx
        \\call 1f
        \\1:
        \\popl %edx
        \\sysenter
        : [cx] "={ecx}" (cx),
          [dx] "={edx}" (dx),
        : [sys] "{eax}" (@as(u32, 0)),
    );
    while (true) {}
}

export fn _start() noreturn {
    main();
}
