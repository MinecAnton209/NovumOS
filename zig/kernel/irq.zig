/// Masks maskable interrupts on the calling core and returns the previous EFLAGS.
/// Pair with irq_restore so an interrupt-context caller keeps IF cleared.
pub fn irq_save() u32 {
    var flags: u32 = undefined;
    asm volatile ("pushfl; popl %[f]"
        : [f] "=r" (flags),
    );
    asm volatile ("cli");
    return flags;
}

pub fn irq_restore(flags: u32) void {
    asm volatile ("pushl %[f]; popfl"
        :
        : [f] "r" (flags),
        : .{ .memory = true });
}
