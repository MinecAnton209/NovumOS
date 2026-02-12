const common = @import("../commands/common.zig");

pub const PCI_CONFIG_ADDRESS: u16 = 0xCF8;
pub const PCI_CONFIG_DATA: u16 = 0xCFC;

pub const Device = struct {
    bus: u8,
    slot: u8,
    func: u8,
    vendor_id: u16,
    device_id: u16,
    class_code: u8,
    subclass: u8,
    prog_if: u8,
    rev_id: u8,
};

pub fn readConfig32(bus: u8, slot: u8, func: u8, offset: u8) u32 {
    const address = (@as(u32, bus) << 16) | (@as(u32, slot) << 11) | (@as(u32, func) << 8) | (@as(u32, offset) & 0xFC) | 0x80000000;
    common.outl(PCI_CONFIG_ADDRESS, address);
    return common.inl(PCI_CONFIG_DATA);
}

pub fn readConfig16(bus: u8, slot: u8, func: u8, offset: u8) u16 {
    const val = readConfig32(bus, slot, func, offset);
    return if ((offset & 2) != 0) @as(u16, @intCast(val >> 16)) else @as(u16, @intCast(val & 0xFFFF));
}

pub fn readConfig8(bus: u8, slot: u8, func: u8, offset: u8) u8 {
    const val = readConfig32(bus, slot, func, offset);
    return @intCast((val >> @as(u5, @intCast((offset & 3) * 8))) & 0xFF);
}

pub fn getVendorID(bus: u8, slot: u8, func: u8) u16 {
    return readConfig16(bus, slot, func, 0x00);
}

pub fn getDeviceID(bus: u8, slot: u8, func: u8) u16 {
    return readConfig16(bus, slot, func, 0x02);
}

pub fn getClassCode(bus: u8, slot: u8, func: u8) u8 {
    return readConfig8(bus, slot, func, 0x0B);
}

pub fn getSubclass(bus: u8, slot: u8, func: u8) u8 {
    return readConfig8(bus, slot, func, 0x0A);
}

pub fn getProgIF(bus: u8, slot: u8, func: u8) u8 {
    return readConfig8(bus, slot, func, 0x09);
}

pub fn getHeaderType(bus: u8, slot: u8, func: u8) u8 {
    return readConfig8(bus, slot, func, 0x0E);
}

pub fn getDeviceName(vendor_id: u16, device_id: u16) []const u8 {
    // Basic common devices for QEMU / Common hardware
    if (vendor_id == 0x8086) {
        return switch (device_id) {
            0x1237 => "Intel 440FX Chipset",
            0x7000 => "Intel PIIX3 ISA",
            0x7010 => "Intel PIIX3 IDE",
            0x7020 => "Intel PIIX3 USB",
            0x7110 => "Intel PIIX4 ISA",
            0x7111 => "Intel PIIX4 IDE",
            0x7113 => "Intel PIIX4 ACPI",
            0x100E => "Intel Gigabit Ethernet (e1000)",
            0x2922 => "Intel ICH9 SATA (AHCI)",
            0x29C0 => "Intel G31/P35 Express DRAM",
            0x2918 => "Intel ICH9 LPC Interface",
            else => "Intel Device",
        };
    } else if (vendor_id == 0x1234) {
        if (device_id == 0x1111) return "QEMU Virtual Video Controller";
    } else if (vendor_id == 0x10EC) {
        if (device_id == 0x8139) return "Realtek RTL8139 Ethernet";
    } else if (vendor_id == 0x80EE) {
        if (device_id == 0xCAFE) return "VirtualBox Guest Service";
    } else if (vendor_id == 0x1AF4) {
        return switch (device_id) {
            0x1000 => "Virtio Network Device",
            0x1001 => "Virtio Block Device",
            0x1003 => "Virtio Console",
            0x1005 => "Virtio Entropy Source",
            0x1009 => "Virtio GPU",
            else => "Virtio Device",
        };
    } else if (vendor_id == 0x1022) {
        if (device_id == 0x2000) return "AMD PCnet Ethernet";
    } else if (vendor_id == 0x15AD) {
        if (device_id == 0x0405) return "VMware SVGA II Adapter";
    }
    return "Unknown Device";
}

pub fn getClassDescription(class_code: u8, subclass: u8) []const u8 {
    return switch (class_code) {
        0x00 => "Unclassified",
        0x01 => switch (subclass) {
            0x01 => "IDE Controller",
            0x06 => "SATA Controller",
            else => "Mass Storage Controller",
        },
        0x02 => "Network Controller",
        0x03 => "Display Controller",
        0x04 => "Multimedia Controller",
        0x05 => "Memory Controller",
        0x06 => switch (subclass) {
            0x00 => "Host Bridge",
            0x01 => "ISA Bridge",
            0x04 => "PCI-to-PCI Bridge",
            else => "Bridge Device",
        },
        0x07 => "Communication Controller",
        0x08 => "System Peripheral",
        0x09 => "Input Device Controller",
        0x0A => "Docking Station",
        0x0B => "Processor",
        0x0C => switch (subclass) {
            0x03 => "USB Controller",
            0x05 => "SMBus",
            else => "Serial Bus Controller",
        },
        else => "Other",
    };
}
