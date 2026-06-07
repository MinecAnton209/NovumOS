// zig/syscalls/console.zig
// Console-related syscalls: print, input, cursor positioning, character drawing.

const common = @import("../commands/common.zig");
const vga = @import("../drivers/vga.zig");
const keyboard = @import("../keyboard_isr.zig");
const user = @import("../user.zig");
const logger = @import("../logger.zig");
const syscalls = @import("mod.zig");

/// Syscall 1: PrintZ(EBX = string_ptr) — print null-terminated string
pub fn printZ(regs: *user.Registers) void {
    if (syscalls.safe_str_from_user(regs.ebx, syscalls.MAX_SYSCALL_STR_LEN)) |str| {
        common.printZ(str);
    } else {
        logger.security("Invalid user string in syscall 1");
    }
}

/// Syscall 2: GetChar() -> EAX — block until keypress, return ASCII
pub fn getChar(regs: *user.Registers) void {
    regs.eax = @intCast(keyboard.keyboard_wait_char());
}

/// Syscall 3: SetCursor(EBX = row, ECX = col)
pub fn setCursor(regs: *user.Registers) void {
    vga.zig_set_cursor(@intCast(regs.ebx), @intCast(regs.ecx));
}

/// Syscall 4: GetCursor() -> EAX (row << 8 | col)
pub fn getCursor(regs: *user.Registers) void {
    const row = vga.zig_get_cursor_row();
    const col = vga.zig_get_cursor_col();
    regs.eax = (@as(u32, row) << 8) | col;
}

/// Syscall 5: ClearScreen()
pub fn clearScreen(_: *user.Registers) void {
    vga.clear_screen();
}

/// Syscall 18: DrawCharAt(EBX=row, ECX=col, EDX=char, ESI=attr)
pub fn drawCharAt(regs: *user.Registers) void {
    const old_color = vga.current_color;
    vga.current_color = @intCast(regs.esi);
    vga.zig_draw_char_at(@intCast(regs.ebx), @intCast(regs.ecx), @intCast(regs.edx));
    vga.current_color = old_color;
}
