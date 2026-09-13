// compat: timer via syscall 11 GetTicks
const syscall = @import("../syscall.zig");

pub fn get_ticks() u64 {
    return syscall.syscall0(11);
}
