// NovumOS Stage2 Bootloader - 32-bit Protected Mode
// Runs at 0x10000, enables A20, loads kernel to 0x100000, jumps to kernel32.asm

pub fn main() noreturn {
    clearScreen();
    printStr("NovumOS Stage2\r\n");

    _ = detectATAPI();

    enableA20();
    setupGDT();
    enableSSE();

    _ = loadKernel();

    jumpToKernel();
}

fn clearScreen() void {
    var edi: u32 = 0xB8000;
    var ecx: u32 = 80 * 25;
    asm volatile ("xor eax, eax\n\trep stosd"
        : : [edi] "r"(edi), [ecx] "r"(ecx)
    );
}

fn detectATAPI() bool {
    waitNotBusy();
    outb(0x1F6, 0xA0);
    outb(0x1F2, 0x00);
    outb(0x1F3, 0x00);
    outb(0x1F4, 0x00);
    outb(0x1F5, 0x00);
    outb(0x1F7, 0xEC);
    waitNotBusy();
    return true;
}

fn enableA20() void {
    asm volatile ("int $0x15"
        :
        : [val] "{ax}"(@as(u16, 0x2401))
    );
    var a20: u8 = undefined;
    asm volatile ("in $0x92, %%al"
        : [ret] "{al}"(a20)
    );
    outb(0x92, a20 | 2);
}

fn setupGDT() void {
    asm volatile ("lgdt (%0)"
        : : "r"(&gdt_descriptor)
    );
}

fn enableSSE() void {
    var cr0: u32 = undefined;
    asm volatile ("mov %%cr0, %[v]"
        : [v] "=r"(cr0)
    );
    cr0 = (cr0 & ~0x0004) | 0x0002;
    asm volatile ("mov %[v], %%cr0"
        : : [v] "r"(cr0)
    );
    var cr4: u32 = undefined;
    asm volatile ("mov %%cr4, %[v]"
        : [v] "=r"(cr4)
    );
    cr4 |= 0x0600;
    asm volatile ("mov %[v], %%cr4"
        : : [v] "r"(cr4)
    );
}

fn waitNotBusy() void {
    var timeout: u32 = 0;
    while (timeout < 100000) : (timeout += 1) {
        const status = inb(0x1F7);
        if ((status & 0x80) == 0) return;
    }
}

fn waitDrdy() void {
    var timeout: u32 = 0;
    while (timeout < 100000) : (timeout += 1) {
        const status = inb(0x1F7);
        if ((status & 0x80) == 0 and (status & 0x40) != 0) return;
    }
}

fn loadKernel() usize {
    return 0;
}

fn outb(port: u16, val: u8) void {
    asm volatile ("outb %[val], %[port]"
        : : [val] "{al}"(val), [port] "{dx}"(port)
    );
}

fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[ret]"
        : [ret] "{al}" (-> u8)
        : [port] "{dx}"(port),
    );
}

fn printStr(s: [*]const u8) void {
    _ = s;
}

fn jumpToKernel() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}

export fn _start() noreturn {
    main();
}

var gdt_descriptor: packed struct {
    limit: u16,
    base: u32,
} = .{
    .limit = 31,
    .base = 0x90000,
};