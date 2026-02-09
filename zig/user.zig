const common = @import("commands/common.zig");
const exceptions = @import("exceptions.zig");
const keyboard = @import("keyboard_isr.zig");
const vga = @import("drivers/vga.zig");

// External jump target to return to kernel shell
extern fn kernel_loop() noreturn;

// Register state passed from assembly (matches stack layout)
pub const Registers = extern struct {
    edi: u32,
    esi: u32,
    ebp: u32,
    esp_dummy: u32,
    ebx: u32,
    edx: u32,
    ecx: u32,
    eax: u32,
    ds: u32,
    es: u32,
    fs: u32,
    gs: u32,
};

// Global flag to indicate if we are in user mode (for shared code)
pub var is_user_mode: bool = false;

// Export strlen as it might be needed by the kernel for strings passed from Ring 3
export fn strlen(s: [*]const u8) usize {
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {}
    return i;
}

// System call handler exported for linker
export fn handle_syscall_zig(regs: *Registers) void {
    switch (regs.eax) {
        0 => { // Exit
            common.printZ("[Kernel] User mode process exited. Returning to Shell...\n");

            // Reset Kernel Stack and jump back to main loop
            // We assume safe stack is at 0x500000 (defined in kernel32.asm)
            asm volatile (
                \\ cli
                \\ movl $0x500000, %%esp
                \\ movl %%esp, %%ebp
                \\ jmp kernel_loop
            );
            unreachable;
        },
        1 => { // PrintZ(EBX = string_ptr)
            const ptr = @as([*]const u8, @ptrFromInt(regs.ebx));
            const len = strlen(ptr);
            common.printZ(ptr[0..len]);
        },
        2 => { // GetChar() -> EAX
            regs.eax = keyboard.keyboard_wait_char();
        },
        3 => { // SetCursor(EBX = row, ECX = col)
            vga.zig_set_cursor(@intCast(regs.ebx), @intCast(regs.ecx));
        },
        4 => { // GetCursor() -> EAX (row << 8 | col)
            const row = vga.zig_get_cursor_row();
            const col = vga.zig_get_cursor_col();
            regs.eax = (@as(u32, row) << 8) | col;
        },
        5 => { // ClearScreen()
            vga.clear_screen();
        },
        else => {
            common.printZ("Unknown syscall from user mode\n");
        },
    }
}

// Link to the assembly implementation
extern fn jump_to_ring3_entry(entry: usize) noreturn;
extern fn jump_to_ring3() noreturn;

pub fn jump_to_user_mode() noreturn {
    is_user_mode = true;
    exceptions.main_tss.ss0 = 0x10;
    exceptions.main_tss.esp0 = 0x500000;
    jump_to_ring3();
}

pub fn jump_to_user_mode_with_entry(entry: usize) noreturn {
    is_user_mode = true;

    // Ensure TSS is ready for interrupts coming from Ring 3
    exceptions.main_tss.ss0 = 0x10;
    exceptions.main_tss.esp0 = 0x500000;

    // Call the stable assembly transition
    jump_to_ring3_entry(entry);
}
