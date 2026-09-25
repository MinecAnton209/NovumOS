const kernel = @import("kernel/kernel.zig");

// Module entry: must live at zig/ root so the Zig package root covers all kernel sources.

comptime {
    _ = kernel;
}

pub const panic = kernel.panic;
