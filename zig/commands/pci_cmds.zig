const common = @import("common.zig");
const pci = @import("../drivers/pci.zig");

pub fn execute() void {
    common.printZ("Scanning PCI bus...\n\n");
    common.printZ("Bus:Slot.Func  Vendor:Device  Class  Description\n");
    common.printZ("----------------------------------------------------------------\n");

    var bus: u16 = 0;
    while (bus < 256) : (bus += 1) {
        var slot: u8 = 0;
        while (slot < 32) : (slot += 1) {
            const vendor_id = pci.getVendorID(@intCast(bus), slot, 0);
            if (vendor_id == 0xFFFF) continue;

            const header_type = pci.getHeaderType(@intCast(bus), slot, 0);
            const num_funcs: u8 = if ((header_type & 0x80) != 0) 8 else 1;

            var func: u8 = 0;
            while (func < num_funcs) : (func += 1) {
                const v_id = pci.getVendorID(@intCast(bus), slot, func);
                if (v_id == 0xFFFF) continue;

                const d_id = pci.getDeviceID(@intCast(bus), slot, func);
                const class = pci.getClassCode(@intCast(bus), slot, func);
                const subclass = pci.getSubclass(@intCast(bus), slot, func);

                // Print Bus:Slot.Func
                if (bus < 100) common.print_char(' ');
                if (bus < 10) common.print_char(' ');
                common.printNum(@intCast(bus));
                common.print_char(':');
                if (slot < 10) common.print_char('0');
                common.printNum(@intCast(slot));
                common.print_char('.');
                common.printNum(@intCast(func));
                common.printZ("    ");

                // Print Vendor:Device
                printHexNoPrefix(v_id, 4);
                common.print_char(':');
                printHexNoPrefix(d_id, 4);
                common.printZ("  ");

                // Print Class
                printHexNoPrefix(@intCast(class), 2);
                common.printZ("   ");

                // Print Description
                common.printZ(pci.getClassDescription(class, subclass));
                common.printZ(" (");
                common.printZ(pci.getDeviceName(v_id, d_id));
                common.printZ(")\n");
            }
        }
    }
}

fn printHexNoPrefix(val: u32, digits: u8) void {
    const chars = "0123456789ABCDEF";
    var i: i8 = @intCast(digits);
    i -= 1;

    while (i >= 0) : (i -= 1) {
        const nibble = (val >> @as(u5, @intCast(i * 4))) & 0xF;
        common.print_char(chars[nibble]);
    }
}
