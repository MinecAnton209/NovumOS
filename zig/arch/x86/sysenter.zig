const user = @import("user.zig");
const syscalls = @import("../../syscalls/mod.zig");
const process = @import("../../syscalls/process.zig");
const logger = @import("../../kernel/logger.zig");
const config = @import("../../config.zig");

extern fn sysenter_entry() void;

const MSR_SYSENTER_CS: u32 = 0x174;
const MSR_SYSENTER_ESP: u32 = 0x175;
const MSR_SYSENTER_EIP: u32 = 0x176;

const KERNEL_CS: u32 = 0x08;
const BSP_KERNEL_ESP: u32 = 0x500000;

fn wrmsr(msr: u32, lo: u32, hi: u32) void {
    asm volatile ("wrmsr"
        :
        : [lo] "{eax}" (lo),
          [hi] "{edx}" (hi),
          [msr] "{ecx}" (msr),
    );
}

fn cpuid_has_sep() bool {
    var eax: u32 = 1;
    var ebx_: u32 = undefined;
    var ecx_: u32 = undefined;
    var edx: u32 = undefined;
    asm volatile ("cpuid"
        : [eax] "+{eax}" (eax),
          [ebx] "={ebx}" (ebx_),
          [ecx] "={ecx}" (ecx_),
          [edx] "={edx}" (edx),
    );
    return (edx & (1 << 11)) != 0;
}

fn setup(esp: usize) void {
    wrmsr(MSR_SYSENTER_CS, KERNEL_CS, 0);
    wrmsr(MSR_SYSENTER_ESP, @intCast(esp), 0);
    wrmsr(MSR_SYSENTER_EIP, @intFromPtr(&sysenter_entry), 0);
}

/// BSP setup, called once from kmain before any Ring 3 entry.
pub fn init_bsp() void {
    if (!cpuid_has_sep()) {
        logger.err("CPU lacks SYSENTER (SEP); cannot boot");
        while (true) {
            asm volatile ("hlt");
        }
    }
    setup(BSP_KERNEL_ESP);
    logger.info("sysenter: fast syscalls online (BSP)");
}

/// AP setup, called once per secondary core from ap_kernel_entry.
pub fn init_ap(stack_top: usize) void {
    setup(stack_top);
}

/// Refresh the Ring 0 stack SYSENTER switches to. Called whenever
/// tss.esp0 is assigned so both stay identical.
pub fn set_kernel_esp(esp: usize) void {
    wrmsr(MSR_SYSENTER_ESP, @intCast(esp), 0);
}

/// Decimal rendering without imports (common.printZ lives in a module
/// that would close an import cycle here). buf must hold 16 bytes.
fn u32dec(value: u32, buf: []u8) []const u8 {
    if (value == 0) {
        buf[0] = '0';
        return buf[0..1];
    }
    var i = buf.len;
    var v = value;
    while (v > 0) {
        i -= 1;
        buf[i] = '0' + @as(u8, @intCast(v % 10));
        v /= 10;
    }
    return buf[i..];
}

/// Called from the sysenter_entry asm stub, which passes all seven args
/// on the stack — hence the explicit C calling convention.
export fn handle_sysenter_zig(uesp: u32, ueip: u32, num: u32, a1: u32, esi_val: u32, edi_val: u32, ebp_val: u32) callconv(.c) u32 {
    if (!syscalls.is_safe_user_range(uesp, 12)) {
        logger.security("sysenter: bad user stack");
        var dummy: user.Registers = undefined;
        process.exit(&dummy);
        while (true) {
            asm volatile ("hlt");
        }
    }
    const frame = @as([*]const u32, @ptrFromInt(uesp));
    var regs = user.Registers{
        .edi = edi_val,
        .esi = esi_val,
        .ebp = ebp_val,
        .esp_dummy = uesp + 12,
        .ebx = a1,
        .edx = frame[1],
        .ecx = frame[2],
        .eax = num,
        .ds = 0xAB,
        .es = 0xAB,
        .fs = 0xAB,
        .gs = 0xAB,
    };
    if (config.ENABLE_SYSCALL_TRACE) {
        const common = @import("../../commands/common.zig");
        var b0: [16]u8 = undefined;
        var b1: [16]u8 = undefined;
        var b2: [16]u8 = undefined;
        var b3: [16]u8 = undefined;
        var b4: [16]u8 = undefined;
        var b5: [16]u8 = undefined;
        var b6: [16]u8 = undefined;
        common.printZ("[ SYSCALL ] #");
        common.printZ(u32dec(num, &b0));
        common.printZ(" ebx=");
        common.printZ(u32dec(a1, &b1));
        common.printZ(" ecx=");
        common.printZ(u32dec(frame[2], &b2));
        common.printZ(" edx=");
        common.printZ(u32dec(frame[1], &b3));
        common.printZ(" esi=");
        common.printZ(u32dec(esi_val, &b4));
        common.printZ(" ueip=");
        common.printZ(u32dec(ueip, &b5));
        common.printZ(" uesp=");
        common.printZ(u32dec(uesp, &b6));
    }
    syscalls.dispatch(&regs);
    if (config.ENABLE_SYSCALL_TRACE) {
        const common = @import("../../commands/common.zig");
        var br: [16]u8 = undefined;
        common.printZ(" => ");
        common.printZ(u32dec(regs.eax, &br));
        common.printZ("\n");
    }
    return regs.eax;
}
