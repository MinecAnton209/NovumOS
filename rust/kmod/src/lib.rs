#![no_std]

unsafe extern "C" {
    fn zig_console_write(ptr: *const u8, len: usize);
}

fn console_write(s: &[u8]) {
    unsafe { zig_console_write(s.as_ptr(), s.len()) }
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_hello() {
    console_write(b"Hello from Rust to cubeOS Team!\n");
}

#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}
