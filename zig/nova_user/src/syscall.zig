// Centralized syscall helpers for Ring 3 (user mode).
// All user-mode drivers call int 0x80 with the same register layout.

pub fn syscall0(n: u32) u32 {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> u32),
        : [num] "{eax}" (n),
    );
}

pub fn syscall1(n: u32, a1: u32) u32 {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> u32),
        : [num] "{eax}" (n),
          [a1] "{ebx}" (a1),
    );
}

pub fn syscall2(n: u32, a1: u32, a2: u32) u32 {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> u32),
        : [num] "{eax}" (n),
          [a1] "{ebx}" (a1),
          [a2] "{ecx}" (a2),
    );
}

pub fn syscall3(n: u32, a1: u32, a2: u32, a3: u32) u32 {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> u32),
        : [num] "{eax}" (n),
          [a1] "{ebx}" (a1),
          [a2] "{ecx}" (a2),
          [a3] "{edx}" (a3),
    );
}

pub fn syscall4(n: u32, a1: u32, a2: u32, a3: u32, a4: u32) u32 {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> u32),
        : [num] "{eax}" (n),
          [a1] "{ebx}" (a1),
          [a2] "{ecx}" (a2),
          [a3] "{edx}" (a3),
          [a4] "{esi}" (a4),
    );
}
