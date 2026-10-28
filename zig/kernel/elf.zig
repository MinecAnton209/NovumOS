const common = @import("../commands/common.zig");
const memory = @import("memory.zig");
const user = @import("../arch/mod.zig").user;
const logger = @import("logger.zig");
const config = @import("../config.zig");
const aslr = @import("aslr.zig");

// ELF Loader for NovumOS

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
const ET_DYN = 3;

fn dbgStr(msg: []const u8) void {
    common.printError(msg);
}

fn dbgNum(label: []const u8, v: u32) void {
    var buf: [8]u8 = undefined;
    for (0..8) |i| {
        const nib: u4 = @truncate(v >> @intCast((7 - i) * 4));
        buf[i] = "0123456789ABCDEF"[nib];
    }
    common.printError(label);
    common.printError(&buf);
    common.printError(" ");
}
pub fn load_and_run(data: []const u8) !noreturn {
    dbgNum("[elf] len=", @intCast(data.len));
    dbgStr("\n");
    user.set_is_privileged(false);
    if (data.len < @sizeOf(Header)) return error.InvalidElfHeader;

    // Ensure alignment for the Header struct
    const header_ptr = @as([*]const u8, @ptrCast(data.ptr));
    const header = @as(*const Header, @ptrCast(@alignCast(header_ptr)));

    // Verify ELF Magic: \x7fELF
    if (header.ident[0] != 0x7f or header.ident[1] != 'E' or header.ident[2] != 'L' or header.ident[3] != 'F') {
        dbgStr("[elf] bad magic\n");
        return error.NotAnElf;
    }

    // Verify it's 32-bit (1) and Little Endian (1)
    if (header.ident[4] != 1 or header.ident[5] != 1) {
        dbgStr("[elf] bad class/endian\n");
        return error.UnsupportedArchitecture;
    }

    logger.info("Loading ELF executable...");
    // ET_EXEC images are linked at fixed addresses and carry no relocations, so sliding them breaks absolute references.
    const slide: usize = if (header.etype == ET_DYN) aslr.elfSlide() else 0;


    // Validate Program Headers table fits in data
    const ph_table_end = @as(usize, header.phoff) + (@as(usize, header.phnum) * @as(usize, header.phentsize));
    dbgNum("[elf] phoff=", header.phoff);
    dbgNum("phnum=", header.phnum);
    dbgNum("entry=", header.entry);
    dbgStr("\n");
    if (ph_table_end > data.len) {
        logger.err("ELF Error: Program Headers out of bounds");
        return error.InvalidProgramHeaders;
    }

    const ph_ptr = @as([*]const Phdr, @ptrCast(@alignCast(data.ptr + header.phoff)));

    for (0..header.phnum) |i| {
        const ph = ph_ptr[i];
        if (ph.ptype == PT_LOAD) {
            // Security: Validate offsets and sizes
            dbgNum("[elf] seg vaddr=", ph.vaddr);
            dbgNum("memsz=", ph.memsz);
            dbgNum("filesz=", ph.filesz);
            dbgNum("off=", ph.offset);
            dbgStr("\n");
            if (ph.filesz > ph.memsz) {
                logger.err("ELF Error: filesz > memsz");
                return error.InvalidSegmentSize;
            }
            if (@as(usize, ph.offset) + @as(usize, ph.filesz) > data.len) {
                logger.err("ELF Error: Segment data exceeds file size");
                return error.SegmentOutOfBounds;
            }

            // Security: Validate virtual address boundaries
            const end_vaddr = @as(usize, ph.vaddr) + @as(usize, ph.memsz);
            if (end_vaddr < ph.vaddr) { // Check for overflow
                logger.err("ELF Error: Virtual address overflow");
                return error.VirtualAddressOverflow;
            }
            // User space is 0x00000000–0xBFFFFFFF (3GB)
            if (end_vaddr >= 0xC0000000) {
                logger.err("ELF Error: Virtual address too high (kernel space)");
                return error.VirtualAddressTooHigh;
            }

            logger.debug("Mapping ELF Segment");

            // map_range handles Ring 3 → Ring 0 transition via syscall 15
            // when called from the shell (running in Ring 3).
            // This avoids #GP on privileged instructions like invlpg.
            memory.map_range(ph.vaddr + slide, ph.memsz, true);

            // Copy file data to segment
            const dest = @as([*]u8, @ptrFromInt(ph.vaddr + slide));
            @memcpy(dest[0..ph.filesz], data[ph.offset .. ph.offset + ph.filesz]);

            // Zero BSS (pages already mapped by the loop above)
            if (ph.memsz > ph.filesz) {
                @memset(dest[ph.filesz..ph.memsz], 0);
            }
        }
    }

    logger.info("Jumping to Ring 3 ELF...");
    dbgNum("[elf] jump entry=", header.entry + slide);
    dbgNum("slide=", slide);
    dbgStr("\n");
    user.jump_to_user_mode_with_entry(header.entry + slide, false);
}

/// Load and run the embedded nova_legacy.elf (backward compat, same binary).
pub fn load_and_run_nova_legacy() !noreturn {
    return load_and_run_nova();
}

/// Load and run the embedded nova.elf (Ring 3 Nova VM).
/// Debug output controlled by NOVA_DEBUG in config.zig.
pub fn load_and_run_nova() !noreturn {
    if (!config.ENABLE_NOVA) return error.NovaDisabled;
    const data = @embedFile("../build/nova");
    if (config.NOVA_DEBUG) {
        common.printZ("[nova] Loading embedded nova.elf (");
        common.printNum(@as(i32, @intCast(data.len)));
        common.printZ(" bytes)...\n");

        const hdr = @as(*const Header, @ptrCast(@alignCast(data.ptr)));
        common.printZ("[nova] ELF: entry=");
        common.printHex(hdr.entry);
        common.printZ(" phoff=");
        common.printHex(hdr.phoff);
        common.printZ(" phnum=");
        common.printNum(hdr.phnum);
        common.printZ(" phentsize=");
        common.printNum(hdr.phentsize);
        common.printZ("\n");
    }
    return load_and_run(data);
}
