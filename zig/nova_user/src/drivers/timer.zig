// compat: timer via syscall 11 GetTicks

fn syscall0(n: u32) u32 {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> u32),
        : [num] "{eax}" (n),
    );
}

pub fn get_ticks() u64 {
    return syscall0(11);
}
