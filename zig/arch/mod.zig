const std = @import("std");
const options = @import("build_config");

/// Single seam between the core kernel and a concrete architecture.
/// Adding an architecture: create arch/<name>/ with the five
/// implementations below, register the name in build.zig's -Darch
/// switch, and add a branch per declaration in this file.
fn arch_is(name: []const u8) bool {
    return comptime std.mem.eql(u8, options.target_arch, name);
}

fn unsupported() *const anyopaque {
    @compileError("unsupported target_arch: " ++ options.target_arch ++ "; add a branch in arch/mod.zig and build.zig");
}

pub const exceptions = if (arch_is("x86")) @import("x86/exceptions.zig") else unsupported();
pub const smp = if (arch_is("x86")) @import("x86/smp.zig") else unsupported();
pub const user = if (arch_is("x86")) @import("x86/user.zig") else unsupported();
pub const keyboard_isr = if (arch_is("x86")) @import("x86/keyboard_isr.zig") else unsupported();
pub const idt_watchdog = if (arch_is("x86")) @import("x86/idt_watchdog.zig") else unsupported();
