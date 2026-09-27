pub fn syscall0(n: u32) u32 {
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
    );
}

pub fn syscall1(n: u32, a1: u32) u32 {
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

pub fn syscall2(n: u32, a1: u32, a2: u32) u32 {
    var cx: u32 = undefined;
    var dx: u32 = undefined;
    return asm volatile (
        \\pushl %esi
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
          [a2] "{esi}" (a2),
    );
}

pub fn syscall3(n: u32, a1: u32, a2: u32, a3: u32) u32 {
    var cx: u32 = undefined;
    var dx: u32 = undefined;
    return asm volatile (
        \\pushl %esi
        \\pushl %edi
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
          [a2] "{esi}" (a2),
          [a3] "{edi}" (a3),
    );
}

pub fn syscall4(n: u32, a1: u32, a2: u32, a3: u32, a4: u32) u32 {
    var cx: u32 = undefined;
    var dx: u32 = undefined;
    var si: u32 = undefined;
    return asm volatile (
        \\pushl %esi
        \\pushl %edi
        \\movl %ebp, %esi
        \\pushfl
        \\movl %esp, %ecx
        \\call 1f
        \\1:
        \\popl %edx
        \\sysenter
        : [ret] "={eax}" (-> u32),
          [cx] "={ecx}" (cx),
          [dx] "={edx}" (dx),
          [si] "={esi}" (si),
        : [num] "{eax}" (n),
          [a1] "{ebx}" (a1),
          [a2] "{esi}" (a2),
          [a3] "{edi}" (a3),
          [a4] "{ebp}" (a4),
    );
}
