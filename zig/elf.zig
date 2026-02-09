// ELF Loader for NovumOS
const common = @import("commands/common.zig");
const memory = @import("memory.zig");
const user = @import("user.zig");

pub const Elf32_Addr = u32;
pub const Elf32_Off = u32;
pub const Elf32_Half = u16;
pub const Elf32_Word = u32;

pub const Header = extern struct {
    ident: [16]u8,
    etype: Elf32_Half,
    machine: Elf32_Half,
    version: Elf32_Word,
    entry: Elf32_Addr,
    phoff: Elf32_Off,
    shoff: Elf32_Off,
    flags: Elf32_Word,
    ehsize: Elf32_Half,
    phentsize: Elf32_Half,
    phnum: Elf32_Half,
    shentsize: Elf32_Half,
    shnum: Elf32_Half,
    shstrndx: Elf32_Half,
};

pub const Phdr = extern struct {
    ptype: Elf32_Word,
    offset: Elf32_Off,
    vaddr: Elf32_Addr,
    paddr: Elf32_Addr,
    filesz: Elf32_Word,
    memsz: Elf32_Word,
    flags: Elf32_Word,
    align_val: Elf32_Word,
};

pub const PT_LOAD = 1;

pub fn load_and_run(data: []const u8) !noreturn {
    if (data.len < @sizeOf(Header)) return error.InvalidElfHeader;

    // Ensure alignment for the Header struct
    const header_ptr = @as([*]const u8, @ptrCast(data.ptr));
    const header = @as(*const Header, @ptrCast(@alignCast(header_ptr)));

    // Verify ELF Magic: \x7fELF
    if (header.ident[0] != 0x7f or header.ident[1] != 'E' or header.ident[2] != 'L' or header.ident[3] != 'F') {
        return error.NotAnElf;
    }

    // Verify it's 32-bit (1) and Little Endian (1)
    if (header.ident[4] != 1 or header.ident[5] != 1) {
        return error.UnsupportedArchitecture;
    }

    common.printZ("[Kernel] Loading ELF entry at ");
    var buf: [16]u8 = undefined;
    common.printZ(common.intToHex(header.entry, &buf));
    common.printZ("\n");

    const ph_ptr = @as([*]const Phdr, @ptrCast(@alignCast(data.ptr + header.phoff)));

    for (0..header.phnum) |i| {
        const ph = ph_ptr[i];
        if (ph.ptype == PT_LOAD) {
            common.printZ("  Phdr: Mapping segment at ");
            common.printZ(common.intToHex(ph.vaddr, &buf));
            common.printZ(" size ");
            common.printZ(common.intToString(@intCast(ph.memsz), &buf));
            common.printZ("\n");

            // In a real OS, we'd allocate pages here.
            // For now, we assume the program fits in our shared 64MB user space.
            // We just copy the data to the virtual address.

            // SECURITY WARNING: This copies data directly to virtual addresses.
            // We should ideally use map_page to ensure memory is allocated and user-accessible.
            // Since our memory init already mapped 0-64MB as user-mode, we can copy.

            const dest = @as([*]u8, @ptrFromInt(ph.vaddr));
            @memcpy(dest[0..ph.filesz], data[ph.offset .. ph.offset + ph.filesz]);

            // Zero out remaining memsz (BSS)
            if (ph.memsz > ph.filesz) {
                @memset(dest[ph.filesz..ph.memsz], 0);
            }
        }
    }

    common.printZ("[Kernel] Jumping to ELF entry...\n");
    user.jump_to_user_mode_with_entry(header.entry);
}
