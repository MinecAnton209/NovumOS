// Detailed Documentation Command
const common = @import("common.zig");
const vga = @import("../drivers/vga.zig");

pub fn execute(args: []const u8) void {
    const COLOR_HEADER = 14; // Yellow
    const COLOR_TEXT = 7; // Light Grey
    const COLOR_BG = 0;

    if (common.std_mem_eql(args, "nova")) {
        vga.set_color(COLOR_HEADER, COLOR_BG);
        common.printZ("=== Nova Language Syntax ===\n\n");

        vga.set_color(COLOR_HEADER, COLOR_BG);
        common.printZ("[ Variables ]\n");
        vga.set_color(COLOR_TEXT, COLOR_BG);
        print_doc("set int x = 10;", "Integer variable (32-bit).");
        print_doc("set string s = \"a\";", "String variable (Max 64 chars).");
        common.printZ("  * Variables are persistent during the session (Max 16).\n");
        common.printZ("  * Assigning Int to String performs auto-casting.\n");

        vga.set_color(COLOR_HEADER, COLOR_BG);
        common.printZ("\n[ Expressions ]\n");
        vga.set_color(COLOR_TEXT, COLOR_BG);
        print_doc("1 + 2 * 3", "L-R eval: result is 9.");
        print_doc("(1 + 2) * 3", "Order control with parens.");
        print_doc("\"Hey \" + name", "String concatenation.");

        vga.set_color(COLOR_HEADER, COLOR_BG);
        common.printZ("\n[ Commands ]\n");
        vga.set_color(COLOR_TEXT, COLOR_BG);
        print_doc("print(a + b);", "Print result to console.");
        print_doc("exit();", "Return to NovumOS Shell.");

        common.printZ("\nStatements MUST end with a semicolon (;).\n");
        vga.reset_color();
        return;
    }

    if (common.std_mem_eql(args, "memory")) {
        vga.set_color(COLOR_HEADER, COLOR_BG);
        common.printZ("=== NovumOS Memory Architecture ===\n\n");

        vga.set_color(COLOR_HEADER, COLOR_BG);
        common.printZ("[ Foundation ]\n");
        vga.set_color(COLOR_TEXT, COLOR_BG);
        print_doc("CMOS Detection", "Low-level BIOS detection for up to 4GB RAM.");
        print_doc("PMM Bitmap", "Handles all 1,048,576 pages (128KB bitmap).");
        print_doc("Kernel Guard", "First 8MB reserved for Code, Stack, and IDT.");

        vga.set_color(COLOR_HEADER, COLOR_BG);
        common.printZ("\n[ Paging & PSE ]\n");
        vga.set_color(COLOR_TEXT, COLOR_BG);
        print_doc("Huge Pages", "4MB Pages (PSE) for RAM. Reduces TLB misses.");
        print_doc("Demand Paging", "Above 64MB, pages map only when accessed.");
        print_doc("Pre-mapping", "map_range() for zero-fault bulk allocation.");

        vga.set_color(COLOR_HEADER, COLOR_BG);
        common.printZ("\n[ Testing & GC ]\n");
        vga.set_color(COLOR_TEXT, COLOR_BG);
        print_doc("mem --test [M]", "Stress test with pre-mapping & PF count.");
        print_doc("Ctrl+C", "Interrupt long memory tests safely.");
        print_doc("GC Tool", "coalesce() merges free blocks after tests.");

        vga.reset_color();
        return;
    }

    const is_page1 = args.len == 0 or common.std_mem_eql(args, "1");
    const is_page2 = common.std_mem_eql(args, "2");

    if (is_page2) {
        vga.set_color(COLOR_HEADER, COLOR_BG);
        common.printZ("=== NovumOS Documentation (Page 2/2) ===\n\n");

        vga.set_color(COLOR_HEADER, COLOR_BG);
        common.printZ("[ File System ]\n");
        vga.set_color(COLOR_TEXT, COLOR_BG);
        print_doc("ls", "List files in the current folder.");
        print_doc("mount <id>", "Select active disk (0/1).");
        print_doc("cp <src> <dst>", "Copy file or directory.");
        print_doc("rm <file>", "Delete file permanently.");

        vga.set_color(COLOR_HEADER, COLOR_BG);
        common.printZ("\n[ Utilities ]\n");
        vga.set_color(COLOR_TEXT, COLOR_BG);
        print_doc("edit <path>", "Built-in text editor.");
        print_doc("nova", "Nova Scripting Interpreter.");
        print_doc("mem --test [M]", "Memory stress test tool.");

        common.printZ("\nUse 'docs 1' to return. Tip: 'docs memory' for deep dive.\n");
        vga.reset_color();
        return;
    }

    // Default: Show Page 1 if nothing else matched
    if (!is_page1) {
        vga.set_color(12, COLOR_BG); // Red
        common.printZ("Topic '");
        common.printZ(args);
        common.printZ("' not found. Showing Index:\n\n");
    }

    vga.set_color(COLOR_HEADER, COLOR_BG);
    common.printZ("=== NovumOS Documentation (Page 1/2) ===\n\n");

    vga.set_color(COLOR_HEADER, COLOR_BG);
    common.printZ("[ System & Info ]\n");
    vga.set_color(COLOR_TEXT, COLOR_BG);
    print_doc("help", "Displays a brief list of all commands.");
    print_doc("docs [n]", "Show this detailed documentation.");
    print_doc("docs <topic>", "Specific help (nova, memory).");
    print_doc("sysinfo", "Hardware, CPU, and RAM detection.");
    print_doc("uptime", "System runtime and RTC stats.");
    print_doc("reboot/shutdown", "Power management commands.");

    common.printZ("\nUse 'docs 2' for File System & Utilities.\n");
    vga.reset_color();
    return;
}

fn print_doc(cmd: []const u8, desc: []const u8) void {
    const COLOR_CMD = 15;
    const COLOR_TEXT = 7;
    const COLOR_BG = 0;

    vga.set_color(COLOR_CMD, COLOR_BG);
    common.printZ("  ");
    common.printZ(cmd);

    // Simple padding
    var i: usize = cmd.len;
    while (i < 20) : (i += 1) common.print_char(' ');

    vga.set_color(COLOR_TEXT, COLOR_BG);
    common.printZ("- ");
    common.printZ(desc);
    common.printZ("\n");
}
