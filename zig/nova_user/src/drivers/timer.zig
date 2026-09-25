const syscall = @import("../syscall.zig");

// compat: timer via syscall 11 GetTicks

pub fn get_ticks() u64 {
    return syscall.syscall0(11);
}
