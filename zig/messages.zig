// System Messages Module
const common = @import("commands/common.zig");
const vga = @import("drivers/vga.zig");
const versioning = @import("versioning.zig");

pub export fn print_welcome() void {
    vga.set_color(11, 0); // Light Cyan on Black
    common.printZ(
        \\
        \\  _   _                             ___  ____  
        \\ | \ | | _____   _ _   _ _ __ ___  / _ \/ ___| 
        \\ |  \| |/ _ \ \ / / | | | '_ ` _ \| | | \___ \ 
        \\ | |\  | (_) \ V /| |_| | | | | | | |_| |___) |
        \\ |_| \_|\___/ \_/  \__,_|_| |_| |_|\___/|____/ 
        \\
        \\
    );
    vga.set_color(15, 0); // White on Black
    common.printZ("=== NovumOS v" ++ versioning.NOVUMOS_VERSION ++ " 32-bit Console ===\n");
    common.printZ("Type \"help\" for commands\n\n");
}
