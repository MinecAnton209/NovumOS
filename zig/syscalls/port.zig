// zig/syscalls/port.zig
// I/O port syscalls (inb/outb/inw/outw/inl/outl).
// Gated by is_io_port_allowed() — whitelist blocks sensitive ports
// (PIC, PIT, PS/2, CMOS, DMA, ATA, PCI config). Production-hardening
// would use a bitmap or per-process capability bitmap.

const common = @import("../commands/common.zig");
const user = @import("../user.zig");
const logger = @import("../logger.zig");

/// Whitelist of I/O ports accessible from Ring 3.
fn is_io_port_allowed(port: u16) bool {
    // Block PIC
    if (port == 0x20 or port == 0x21 or port == 0xA0 or port == 0xA1) return false;
    // Block PIT
    if (port >= 0x40 and port <= 0x43) return false;
    // Block PS/2 Keyboard Controller
    if (port == 0x60 or port == 0x64) return false;
    // Block CMOS / RTC
    if (port == 0x70 or port == 0x71) return false;
    // Block DMA Controllers
    if (port <= 0x1F or (port >= 0xC0 and port <= 0xDF)) return false;
    // Block Primary/Secondary ATA (Hard Disk)
    if (port >= 0x1F0 and port <= 0x1F7) return false;
    if (port == 0x3F6) return false;
    // Block PCI Configuration Ports
    if (port == 0xCF8 or port == 0xCFC) return false;
    // Allow everything else (VGA, Serial COM1/COM2)
    return true;
}

/// Syscall 6: InB(EBX = port) -> EAX
pub fn inB(regs: *user.Registers) void {
    const port: u16 = @intCast(regs.ebx);
    if (is_io_port_allowed(port)) {
        regs.eax = common.inb(port);
    } else {
        var buf: [32]u8 = undefined;
        logger.security("Unauthorized InB to port");
        logger.debug(common.intToHex(port, &buf));
        regs.eax = 0xFF;
    }
}

/// Syscall 7: OutB(EBX = port, ECX = val)
pub fn outB(regs: *user.Registers) void {
    const port: u16 = @intCast(regs.ebx);
    if (is_io_port_allowed(port)) {
        common.outb(port, @intCast(regs.ecx));
    } else {
        var buf: [32]u8 = undefined;
        logger.security("Unauthorized OutB to port");
        logger.debug(common.intToHex(port, &buf));
    }
}

/// Syscall 8: InW(EBX = port) -> EAX
pub fn inW(regs: *user.Registers) void {
    const port: u16 = @intCast(regs.ebx);
    if (is_io_port_allowed(port)) {
        regs.eax = common.inw(port);
    } else {
        var buf: [32]u8 = undefined;
        logger.security("Unauthorized InW to port");
        logger.debug(common.intToHex(port, &buf));
        regs.eax = 0xFFFF;
    }
}

/// Syscall 9: OutW(EBX = port, ECX = val)
pub fn outW(regs: *user.Registers) void {
    const port: u16 = @intCast(regs.ebx);
    if (is_io_port_allowed(port)) {
        common.outw(port, @intCast(regs.ecx));
    } else {
        var buf: [32]u8 = undefined;
        logger.security("Unauthorized OutW to port");
        logger.debug(common.intToHex(port, &buf));
    }
}

/// Syscall 16: InL(EBX = port) -> EAX
pub fn inL(regs: *user.Registers) void {
    const port: u16 = @intCast(regs.ebx);
    if (is_io_port_allowed(port)) {
        regs.eax = common.inl(port);
    } else {
        var buf: [32]u8 = undefined;
        logger.security("Unauthorized InL to port");
        logger.debug(common.intToHex(port, &buf));
        regs.eax = 0xFFFFFFFF;
    }
}

/// Syscall 17: OutL(EBX = port, ECX = val)
pub fn outL(regs: *user.Registers) void {
    const port: u16 = @intCast(regs.ebx);
    if (is_io_port_allowed(port)) {
        common.outl(port, regs.ecx);
    } else {
        var buf: [32]u8 = undefined;
        logger.security("Unauthorized OutL to port");
        logger.debug(common.intToHex(port, &buf));
    }
}
