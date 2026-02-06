// Sysinfo command with ASCII art
const common = @import("common.zig");
const vga = @import("../drivers/vga.zig");
const versioning = @import("../versioning.zig");
const config = @import("../config.zig");
const build_config = @import("build_config");
const memory = @import("../memory.zig");

const ata = @import("../drivers/ata.zig");

pub fn execute() void {
    const COLOR_LOGO = 11; // Bright Yellow
    const COLOR_LABEL = 15; // White
    const COLOR_VALUE = 7; // Light Grey
    const COLOR_BG = 0; // Black
    const COLOR_SECTION = 14; // Yellow

    vga.set_color(COLOR_LOGO, COLOR_BG);
    common.printZ("  _   _  _____      __ _    _ __  __ \n");
    common.printZ(" | \\ | |/ _ \\ \\    / /| |  | |  \\/  |\n");
    common.printZ(" |  \\| | | | \\ \\  / / | |  | | \\  / |\n");
    common.printZ(" | . ` | | | |\\ \\/ /  | |  | | |\\/| |\n");
    common.printZ(" | |\\  | |_| | \\  /   | |__| | |  | |\n");
    common.printZ(" |_| \\_|\\___/   \\/     \\____/|_|  |_|\n");
    common.printZ("\n");

    const history_size = if (build_config.history_size) |h| h else config.HISTORY_SIZE;

    // --- System ---
    vga.set_color(COLOR_SECTION, COLOR_BG);
    common.printZ(" [ System ]\n");

    print_entry("OS Version", versioning.NOVUMOS_VERSION, COLOR_LABEL, COLOR_VALUE, COLOR_BG);
    print_entry("Kernel", "Zig + x86 ASM", COLOR_LABEL, COLOR_VALUE, COLOR_BG);

    // --- Hardware ---
    vga.set_color(COLOR_SECTION, COLOR_BG);
    common.printZ(" [ Hardware ]\n");

    // CPU
    var vendor_buf: [13]u8 = [_]u8{0} ** 13;
    get_cpu_vendor(&vendor_buf);
    print_entry("CPU Vendor", &vendor_buf, COLOR_LABEL, COLOR_VALUE, COLOR_BG);

    // RAM
    vga.set_color(COLOR_LABEL, COLOR_BG);
    common.printZ("  RAM Total   : ");
    vga.set_color(COLOR_VALUE, COLOR_BG);
    common.printNum(@as(i32, @intCast(memory.DETECTED_MEMORY / (1024 * 1024))));
    common.printZ(" MB (Detected)\n");

    // Disk
    vga.set_color(COLOR_LABEL, COLOR_BG);
    common.printZ("  Disk (P)    : ");
    vga.set_color(COLOR_VALUE, COLOR_BG);
    const sectors_m = ata.identify(.Master);
    if (sectors_m > 0) {
        common.printNum(@intCast(sectors_m * 512 / 1024));
        common.printZ(" KB");
    } else {
        common.printZ("Not Detected");
    }
    common.printZ("\n");

    vga.set_color(COLOR_LABEL, COLOR_BG);
    common.printZ("  Disk (S)    : ");
    vga.set_color(COLOR_VALUE, COLOR_BG);
    const sectors_s = ata.identify(.Slave);
    if (sectors_s > 0) {
        common.printNum(@intCast(sectors_s * 512 / 1024));
        common.printZ(" KB");
    } else {
        common.printZ("Not Detected");
    }
    common.printZ("\n");

    vga.set_color(COLOR_SECTION, COLOR_BG);
    common.printZ(" [ Config ]\n");

    print_entry("Resolution", "80x25 VGA Text", COLOR_LABEL, COLOR_VALUE, COLOR_BG);

    vga.set_color(COLOR_LABEL, COLOR_BG);
    common.printZ("  Heap Size   : ");
    vga.set_color(COLOR_VALUE, COLOR_BG);
    common.printNum(config.HEAP_INITIAL_SIZE / 1024);
    common.printZ(" KB\n");

    vga.set_color(COLOR_LABEL, COLOR_BG);
    common.printZ("  Cmd History : ");
    vga.set_color(COLOR_VALUE, COLOR_BG);
    common.printNum(@intCast(history_size));
    common.printZ(" entries\n");

    common.printZ("\n");
    vga.reset_color();
}

pub fn cmd_fetch() void {
    const COLOR_LOGO = 14;
    const COLOR_LABEL = 15;
    const COLOR_VALUE = 7;
    const COLOR_BG = 0;

    const logo = [_][]const u8{
        "   _  _ ___ _   _ __  __ ",
        "  | \\| | _ \\ | | |  \\/  |",
        "  | . ` | | | |_| | |\\/| |",
        "  | |\\  | |_| | |_| |  | |",
        "  |_| \\_\\___/\\___/|_|  |_|",
    };

    var vendor_buf: [13]u8 = [_]u8{0} ** 13;
    get_cpu_vendor(&vendor_buf);

    common.printZ("\n");
    for (logo, 0..) |line, i| {
        vga.set_color(COLOR_LOGO, COLOR_BG);
        common.printZ(line);
        common.printZ("   ");

        vga.set_color(COLOR_LABEL, COLOR_BG);
        switch (i) {
            0 => {
                common.printZ("OS: ");
                vga.set_color(COLOR_VALUE, COLOR_BG);
                common.printZ("NovumOS ");
                common.printZ(versioning.NOVUMOS_VERSION);
            },
            1 => {
                common.printZ("Kernel: ");
                vga.set_color(COLOR_VALUE, COLOR_BG);
                common.printZ("Zig + x86 ASM");
            },
            2 => {
                common.printZ("CPU: ");
                vga.set_color(COLOR_VALUE, COLOR_BG);
                common.printZ(&vendor_buf);
            },
            3 => {
                common.printZ("RAM: ");
                vga.set_color(COLOR_VALUE, COLOR_BG);
                common.printNum(@as(i32, @intCast(memory.DETECTED_MEMORY / (1024 * 1024))));
                common.printZ(" MB");
            },
            4 => {
                const sectors_m = ata.identify(.Master);
                common.printZ("Disk: ");
                vga.set_color(COLOR_VALUE, COLOR_BG);
                if (sectors_m > 0) {
                    common.printNum(@intCast(sectors_m * 512 / (1024 * 1024)));
                    common.printZ(" MB");
                } else {
                    common.printZ("None");
                }
            },
            else => {},
        }
        common.printZ("\n");
    }
    common.printZ("\n");
    vga.reset_color();
}

fn get_cpu_vendor(buffer: *[13]u8) void {
    var ebx: u32 = 0;
    var edx: u32 = 0;
    var ecx: u32 = 0;

    asm volatile ("cpuid"
        : [ebx] "={ebx}" (ebx),
          [edx] "={edx}" (edx),
          [ecx] "={ecx}" (ecx),
        : [eax] "{eax}" (0),
        : "eax");

    // EBX
    buffer[0] = @intCast(ebx & 0xFF);
    buffer[1] = @intCast((ebx >> 8) & 0xFF);
    buffer[2] = @intCast((ebx >> 16) & 0xFF);
    buffer[3] = @intCast((ebx >> 24) & 0xFF);

    // EDX
    buffer[4] = @intCast(edx & 0xFF);
    buffer[5] = @intCast((edx >> 8) & 0xFF);
    buffer[6] = @intCast((edx >> 16) & 0xFF);
    buffer[7] = @intCast((edx >> 24) & 0xFF);

    // ECX
    buffer[8] = @intCast(ecx & 0xFF);
    buffer[9] = @intCast((ecx >> 8) & 0xFF);
    buffer[10] = @intCast((ecx >> 16) & 0xFF);
    buffer[11] = @intCast((ecx >> 24) & 0xFF);
}

fn print_entry(label: []const u8, value: []const u8, col_lbl: u8, col_val: u8, bg: u8) void {
    vga.set_color(col_lbl, bg);
    common.printZ("  ");
    common.printZ(label);

    // Padding
    var i: usize = label.len;
    while (i < 12) : (i += 1) common.print_char(' ');

    common.printZ(": ");
    vga.set_color(col_val, bg);
    common.printZ(value);
    common.printZ("\n");
}
