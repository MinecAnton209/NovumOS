// ACPI (Advanced Configuration and Power Interface) Driver
// Features dynamic AML parsing for S5 (Shutdown) state values
const common = @import("../commands/common.zig");

var pm1a_control_block: u16 = 0;
var pm1b_control_block: u16 = 0;
var smi_command_port: u32 = 0;
var acpi_enable_val: u8 = 0;

var slp_typa: u16 = 0;
var slp_typb: u16 = 0;
var slp_en: u16 = 0x2000;
pub var lapic_addr: u32 = 0;
pub var madt_core_count: u32 = 0;
pub var lapic_ids: [16]u8 = [_]u8{0} ** 16;

fn find_rsdp() ?usize {
    const signature = "RSD PTR ";
    var addr: usize = 0x80000;
    while (addr < 0xA0000) : (addr += 16) {
        if (check_signature_at(addr, signature)) return addr;
    }
    addr = 0xE0000;
    while (addr < 0x100000) : (addr += 16) {
        if (check_signature_at(addr, signature)) return addr;
    }
    return null;
}

fn check_signature_at(addr: usize, sig: []const u8) bool {
    const ptr = @as([*]const u8, @ptrFromInt(addr));
    for (sig, 0..) |c, i| if (ptr[i] != c) return false;
    return true;
}

fn read_u32(addr: usize) u32 {
    return @as(*const u32, @ptrFromInt(addr)).*;
}
fn read_u8(addr: usize) u8 {
    return @as(*const u8, @ptrFromInt(addr)).*;
}

pub fn init() bool {
    const rsdp_addr = find_rsdp() orelse return false;
    const rsdt_addr = read_u32(rsdp_addr + 16);
    const rsdt_length = read_u32(rsdt_addr + 4);
    const num_entries = (rsdt_length - 36) / 4;

    var i: u32 = 0;
    var found_facp = false;

    while (i < num_entries) : (i += 1) {
        const table_addr = read_u32(rsdt_addr + 36 + (i * 4));
        if (check_signature_at(table_addr, "FACP")) {
            // 1. Get Power Ports
            smi_command_port = read_u32(table_addr + 48);
            acpi_enable_val = read_u8(table_addr + 52);
            pm1a_control_block = @intCast(read_u32(table_addr + 64) & 0xFFFF);
            pm1b_control_block = @intCast(read_u32(table_addr + 68) & 0xFFFF);

            // 2. Enable ACPI mode
            if (smi_command_port != 0 and acpi_enable_val != 0) {
                outb(@intCast(smi_command_port), acpi_enable_val);
                common.sleep(10);
            }

            // 3. Find DSDT and parse _S5 state
            const dsdt_addr = read_u32(table_addr + 40);
            if (parse_s5(dsdt_addr)) {
                //common.printZ("ACPI: Found _S5 package in DSDT\n");
            } else {
                common.printZ("ACPI: _S5 not found, using failsafe values\n");
                slp_typa = 5 << 10;
                slp_typb = 5 << 10;
            }

            found_facp = true;
        } else if (check_signature_at(table_addr, "APIC")) {
            lapic_addr = read_u32(table_addr + 36);
            parse_madt(table_addr);
        }
    }
    return found_facp;
}

/// Parse MADT (Multiple APIC Description Table) to count cores
fn parse_madt(madt_addr: usize) void {
    const length = read_u32(madt_addr + 4);
    var offset: usize = 44;
    madt_core_count = 0;

    while (offset < length) {
        const entry_type = read_u8(madt_addr + offset);
        const entry_len = read_u8(madt_addr + offset + 1);
        if (entry_len == 0) break; // Safety

        if (entry_type == 0) { // Processor Local APIC
            const lapic_id = read_u8(madt_addr + offset + 3);
            const flags = read_u32(madt_addr + offset + 4);
            if ((flags & 1) != 0) { // Enabled
                if (madt_core_count < 16) {
                    lapic_ids[madt_core_count] = lapic_id;
                }
                madt_core_count += 1;
            }
        }
        offset += entry_len;
    }
}

/// Simple AML parser to find \_S5_ (Shutdown) package
fn parse_s5(dsdt_addr: usize) bool {
    const dsdt_len = read_u32(dsdt_addr + 4);
    const ptr = @as([*]const u8, @ptrFromInt(dsdt_addr));

    // Search for "_S5_" signature in AML bytecode
    var i: usize = 36; // Skip header
    while (i < dsdt_len - 4) : (i += 1) {
        if (ptr[i] == '_' and ptr[i + 1] == 'S' and ptr[i + 2] == '5' and ptr[i + 3] == '_') {
            // Found Name("_S5_", Package(...))
            // Typical pattern: 08 5F 53 35 5F 12 [pkg_len] [num_elements] 0A [val_a] 0A [val_b]

            // Check for NameOp (08) before or after
            const search_idx = i + 4;

            // Search for PackageOp (0x12) within next few bytes
            var j: usize = search_idx;
            while (j < search_idx + 8 and j < dsdt_len) : (j += 1) {
                if (ptr[j] == 0x12) { // PackageOp
                    // Skip PkgLength (1-4 bytes) and NumElements (1 byte)
                    // We'll just look for the FIRST two BytePrefix (0x0A) or small constants
                    var k = j + 1;
                    // Skip PkgLength
                    if ((ptr[k] & 0xC0) == 0) k += 1 else if ((ptr[k] & 0xC0) == 0x40) k += 2 else if ((ptr[k] & 0xC0) == 0x80) k += 3 else k += 4;

                    k += 1; // Skip NumElements

                    // Extract Type A
                    if (ptr[k] == 0x0A) k += 1; // BytePrefix
                    slp_typa = @as(u16, ptr[k]) << 10;
                    k += 1;

                    // Extract Type B
                    if (ptr[k] == 0x0A) k += 1; // BytePrefix
                    slp_typb = @as(u16, ptr[k]) << 10;

                    return true;
                }
            }
        }
    }
    return false;
}

pub fn shutdown() noreturn {
    if (pm1a_control_block != 0) {
        common.outw(pm1a_control_block, slp_typa | slp_en);
        if (pm1b_control_block != 0) common.outw(pm1b_control_block, slp_typb | slp_en);
        common.sleep(100);
        // Fallback Force
        common.outw(pm1a_control_block, slp_en);
    }

    var cs: u16 = 0;
    asm volatile ("mov %%cs, %[cs]"
        : [cs] "=r" (cs),
    );
    if ((cs & 3) == 0) {
        while (true) asm volatile ("hlt");
    } else {
        while (true) {}
    }
}

fn outw(port: u16, value: u16) void {
    common.outw(port, value);
}

fn outb(port: u16, value: u8) void {
    common.outb(port, value);
}
