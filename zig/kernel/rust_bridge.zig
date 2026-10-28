const common = @import("../commands/common.zig");

// Rust kernel module (rust/kmod/src/lib.rs), linked as a static library.
extern fn rust_hello() void;

/// Entry point into the Rust module for the `rust` shell command.
pub fn hello() void {
    rust_hello();
}

/// Console sink imported by the Rust module via `extern "C"`.
export fn zig_console_write(ptr: [*]const u8, len: usize) void {
    common.printBuf(ptr[0..len]);
}
