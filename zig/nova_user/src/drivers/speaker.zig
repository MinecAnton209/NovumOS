// compat: speaker via syscall 42

fn syscall4(n: u32, a1: u32, a2: u32, a3: u32, a4: u32) u32 {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> u32),
        : [num] "{eax}" (n),
          [a1] "{ebx}" (a1),
          [a2] "{ecx}" (a2),
          [a3] "{edx}" (a3),
          [a4] "{esi}" (a4),
    );
}

pub fn beep_async(freq: u32, duration_ms: u32) void {
    _ = syscall4(42, 0, freq, duration_ms, 0);
}

pub fn beep_async_check() void {
    _ = syscall4(42, 1, 0, 0, 0);
}

pub fn beep_async_is_pending() bool {
    return syscall4(42, 1, 0, 0, 0) != 0;
}

pub fn beep_pattern_async(freq: u32, duration_ms: u32, gap_ms: u32) void {
    _ = syscall4(42, 2, freq, duration_ms, gap_ms);
}
