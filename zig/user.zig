const common = @import("commands/common.zig");
const exceptions = @import("exceptions.zig");

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

// Export strlen as it might be needed by the kernel for strings passed from Ring 3
export fn strlen(s: [*]const u8) usize {
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {}
    return i;
}

// System call handler exported for linker
export fn handle_syscall_zig(regs: *Registers) void {
    // Syscall 1: PrintZ(EBX = string_ptr)
    if (regs.eax == 1) {
        const ptr = @as([*]const u8, @ptrFromInt(regs.ebx));
        const len = strlen(ptr);
        common.printZ(ptr[0..len]);
    } else {
        common.printZ("Unknown syscall from user mode\n");
    }
}

// Link to the assembly implementation
extern fn jump_to_ring3() noreturn;

pub fn jump_to_user_mode() noreturn {
    // Ensure TSS is ready for interrupts coming from Ring 3
    exceptions.main_tss.ss0 = 0x10;
    exceptions.main_tss.esp0 = 0x500000;

    common.printZ("Jumping to Ring 3...\n");

    // Call the stable assembly transition
    jump_to_ring3();
}
