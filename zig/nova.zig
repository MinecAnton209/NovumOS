// Nova Language - Main export module
const interpreter = @import("nova/interpreter.zig");
const user = @import("user.zig");

// Global storage for arguments when jumping to Ring 3
pub var ring3_arg_ptr: [*]const u8 = undefined;
pub var ring3_arg_len: usize = 0;
pub var has_arg: bool = false;

// This function will be the entry point in User Mode
export fn nova_ring3_entry() noreturn {
    if (has_arg) {
        interpreter.start(ring3_arg_ptr[0..ring3_arg_len]);
    } else {
        interpreter.start(null);
    }

    // After interpreter exits, we must syscall exit (Syscall 0: Exit)
    asm volatile ("int $0x80"
        :
        : [sys] "{eax}" (@as(u32, 0)),
    );
    while (true) {}
}

// Export nova_start for ASM/Shell - now jumps to Ring 3
pub export fn nova_start(arg_ptr: [*]const u8, arg_len: usize) void {
    if (arg_len == 0) {
        has_arg = false;
    } else {
        ring3_arg_ptr = arg_ptr;
        ring3_arg_len = arg_len;
        has_arg = true;
    }

    // Jump to Ring 3 and start Nova there at the specified entry point
    user.jump_to_user_mode_with_entry(@intFromPtr(&nova_ring3_entry));
}
