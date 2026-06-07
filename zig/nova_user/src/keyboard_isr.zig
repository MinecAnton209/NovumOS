// compat: keyboard via syscalls 2 (GetChar) and 32 (CheckCtrlC)

fn syscall0(n: u32) u32 {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> u32),
        : [num] "{eax}" (n),
    );
}

fn syscall1(n: u32, a1: u32) u32 {
    return asm volatile ("int $0x80"
        : [ret] "={eax}" (-> u32),
        : [num] "{eax}" (n),
          [a1] "{ebx}" (a1),
    );
}

pub const KEY_UP = 0x80;
pub const KEY_DOWN = 0x81;
pub const KEY_LEFT = 0x82;
pub const KEY_RIGHT = 0x83;
pub const KEY_INSERT = 0x84;
pub const KEY_HOME = 0x85;
pub const KEY_END = 0x86;
pub const KEY_DELETE = 0x87;
pub const KEY_CAPS = 0x88;
pub const KEY_NUM = 0x89;
pub const KEY_F1 = 0x90;
pub const KEY_F2 = 0x91;
pub const KEY_F10 = 0x99;
pub const KEY_PGUP = 0x8A;
pub const KEY_PGDN = 0x8B;
pub const KEY_ESC = 27;

pub export fn keyboard_wait_char() u8 {
    return @intCast(syscall1(2, 0));
}

pub fn check_ctrl_c() bool {
    return syscall0(32) != 0;
}
