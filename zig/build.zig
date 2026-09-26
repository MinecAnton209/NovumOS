const std = @import("std");

pub fn build(b: *std.Build) void {
    const kconfig = @import("kconfig.zig");
    const cfg_schema = @import("config_schema.zig");

    const Cfg = struct { text: []const u8, source: []const u8 };
    const cfg: Cfg = blk: {
        const handle = b.build_root.handle;
        const read = struct {
            fn go(h: @TypeOf(handle), io: anytype, path: []const u8, alloc: std.mem.Allocator) ?[]const u8 {
                return h.readFileAlloc(io, path, alloc, .limited(1024 * 1024)) catch |err| switch (err) {
                    error.FileNotFound => null,
                    else => {
                        std.log.err("cannot read {s}: {s}", .{ path, @errorName(err) });
                        std.process.exit(1);
                    },
                };
            }
        }.go;
        if (read(handle, b.graph.io, "../.config", b.allocator)) |t|
            break :blk Cfg{ .text = t, .source = ".config" };
        if (read(handle, b.graph.io, "../defconfig", b.allocator)) |t|
            break :blk Cfg{ .text = t, .source = "defconfig" };
        break :blk Cfg{ .text = "", .source = "(schema defaults)" };
    };

    if (kconfig.validate(&cfg_schema.schema, cfg.text)) |d| {
        if (d.first_line) |fl| {
            std.log.err("invalid config in {s} at line {d}: duplicate key '{s}' (first at line {d})", .{ cfg.source, d.line, d.key, fl });
        } else {
            std.log.err("invalid config in {s} at line {d}: {s} key '{s}' detail '{s}'", .{ cfg.source, d.line, @tagName(d.kind), d.key, d.detail });
        }
        std.process.exit(1);
    }

    const nova_on = kconfig.flag(&cfg_schema.schema, cfg.text, "ENABLE_NOVA");

    const arch = b.option([]const u8, "arch", "Target architecture (supported: x86)") orelse "x86";
    if (!std.mem.eql(u8, arch, "x86")) {
        std.log.err("unsupported -Darch={s}; supported: x86", .{arch});
        return;
    }

    // Target: i386 freestanding (no OS)
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .none,
        .ofmt = .elf,
        .cpu_features_sub = std.Target.x86.featureSet(&[_]std.Target.x86.Feature{
            .mmx,
            .sse,
            .sse2,
            .sse3,
            .ssse3,
            .sse4_1,
            .sse4_2,
            .avx,
            .avx2,
        }),
    });

    const optimize = .ReleaseSmall;

    // Create the kernel module first
    const kernel_mod = b.createModule(.{
        .root_source_file = b.path("kernel.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Build options
    const history_size = b.option(u32, "history_size", "Number of commands to keep in history");
    const options = b.addOptions();
    options.addOption([]const u8, "target_arch", arch);
    options.addOption(?u32, "history_size", history_size);
    options.addOption([]const u8, "config_text", cfg.text);
    kernel_mod.addOptions("build_config", options);

    // Build the kernel object file
    const kernel = b.addObject(.{
        .name = "kernel",
        .root_module = kernel_mod,
    });

    // Install the object file to ../build
    const install_kernel = b.addInstallArtifact(kernel, .{
        .dest_dir = .{ .override = .{ .custom = "../build" } },
    });

    b.default_step.dependOn(&install_kernel.step);

    // Kernel binary: NASM objects + link (flags from validated config)
    var flag_buf1: [64]u8 = undefined;
    var flag_buf2: [64]u8 = undefined;
    const serial_flag = kconfig.nasmDefine(&flag_buf1, &cfg_schema.schema, cfg.text, "ENABLE_SERIAL_DEBUG");
    const lfb_flag = kconfig.nasmDefine(&flag_buf2, &cfg_schema.schema, cfg.text, "ENABLE_EARLY_LFB_DEBUG");

    var flag_buf3: [64]u8 = undefined;
    const mouse_flag = kconfig.nasmDefine(&flag_buf3, &cfg_schema.schema, cfg.text, "ENABLE_MOUSE");

    const nasm_k32 = b.addSystemCommand(&.{ "nasm", "-f", "elf32" });
    nasm_k32.addPrefixedDirectoryArg("-i", b.path("../arch/x86"));
    // The -i directory arg is hashed by path only, so content-track every
    // file %included through it: add new entries here when kernel32.asm
    // grows includes, or edits to them build a silently stale kernel.
    nasm_k32.addFileInput(b.path("../arch/x86/idt.asm"));
    nasm_k32.addFileArg(b.path("../arch/x86/kernel32.asm"));
    nasm_k32.addArg(b.fmt("-D{s}", .{serial_flag}));
    nasm_k32.addArg(b.fmt("-D{s}", .{lfb_flag}));
    nasm_k32.addArg(b.fmt("-D{s}", .{mouse_flag}));
    nasm_k32.addArg("-o");
    const k32_o = nasm_k32.addOutputFileArg("kernel32.o");

    const nasm_um = b.addSystemCommand(&.{ "nasm", "-f", "elf32" });
    nasm_um.addFileArg(b.path("../arch/x86/user_mode.asm"));
    nasm_um.addArg("-o");
    const um_o = nasm_um.addOutputFileArg("user_mode.o");

    const nasm_tr = b.addSystemCommand(&.{ "nasm", "-f", "bin" });
    nasm_tr.addFileArg(b.path("arch/x86/smp_trampoline.asm"));
    nasm_tr.addArg("-o");
    const tramp_bin = nasm_tr.addOutputFileArg("trampoline.bin");

    const link_cmd = b.addSystemCommand(&.{ "zig", "ld.lld", "-m", "elf_i386", "-T" });
    link_cmd.addFileArg(b.path("../arch/x86/linker.ld"));
    link_cmd.addArg("--strip-all");
    link_cmd.addArg("-o");
    const kernel_elf = link_cmd.addOutputFileArg("kernel32.elf");
    link_cmd.addFileArg(k32_o);
    link_cmd.addFileArg(um_o);
    link_cmd.addFileArg(kernel.getEmittedBin());

    const install_elf = b.addInstallFileWithDir(kernel_elf, .{ .custom = "../../build" }, "kernel32.elf");
    const install_tramp = b.addInstallFileWithDir(tramp_bin, .{ .custom = "../../build" }, "trampoline.bin");
    b.default_step.dependOn(&install_elf.step);
    b.default_step.dependOn(&install_tramp.step);

    // Config facade tests (build_config with a non-empty override)
    const config_test_mod = b.createModule(.{
        .root_source_file = b.path("config.zig"),
        .target = b.resolveTargetQuery(.{}),
        .optimize = .Debug,
    });
    const test_options = b.addOptions();
    test_options.addOption([]const u8, "target_arch", arch);
    test_options.addOption(?u32, "history_size", null);
    test_options.addOption([]const u8, "config_text", "CONFIG_HISTORY_SIZE=7");
    config_test_mod.addOptions("build_config", test_options);
    const config_tests = b.addTest(.{ .root_module = config_test_mod });
    const run_config_tests = b.addRunArtifact(config_tests);
    const test_step = b.step("test", "Run config facade tests");
    test_step.dependOn(&run_config_tests.step);

    // cfg_write merge tests: its ../ imports leave the main module root in
    // Zig 0.16, so resolve them as named modules. config_schema.zig keeps its
    // own relative @import("kconfig.zig") and resolves it file-locally, which
    // is why it must NOT also be wired as a separate "kconfig" module.
    const cfg_write_mod = b.createModule(.{
        .root_source_file = b.path("tools/cfg_write.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    cfg_write_mod.addAnonymousImport("config_schema", .{
        .root_source_file = b.path("config_schema.zig"),
        .imports = &.{},
    });
    const cfg_write_tests = b.addTest(.{ .root_module = cfg_write_mod });
    const run_cfg_write_tests = b.addRunArtifact(cfg_write_tests);
    const cfg_write_test_step = b.step("test-cfg-write", "Run cfg_write merge tests");
    cfg_write_test_step.dependOn(&run_cfg_write_tests.step);

    // menuconfig TUI: host dev tool, deliberately not part of default_step
    const vaxis_dep = b.dependency("vaxis", .{
        .target = b.graph.host,
        .optimize = .Debug,
    });
    const menuconfig_mod = b.createModule(.{
        .root_source_file = b.path("tools/menuconfig.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    menuconfig_mod.addImport("vaxis", vaxis_dep.module("vaxis"));
    menuconfig_mod.addAnonymousImport("config_schema", .{
        .root_source_file = b.path("config_schema.zig"),
        .imports = &.{},
    });
    const menuconfig_exe = b.addExecutable(.{
        .name = "menuconfig",
        .root_module = menuconfig_mod,
    });
    const run_menuconfig = b.addRunArtifact(menuconfig_exe);
    run_menuconfig.stdio = .inherit;
    run_menuconfig.setCwd(b.path(".."));
    const menuconfig_step = b.step("menuconfig", "Edit .config in an interactive TUI");
    menuconfig_step.dependOn(&run_menuconfig.step);

    // menuconfig TUI logic tests (same module graph as the exe, run as a test)
    const menuconfig_test_mod = b.createModule(.{
        .root_source_file = b.path("tools/menuconfig.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    menuconfig_test_mod.addImport("vaxis", vaxis_dep.module("vaxis"));
    menuconfig_test_mod.addAnonymousImport("config_schema", .{
        .root_source_file = b.path("config_schema.zig"),
        .imports = &.{},
    });
    const menuconfig_tests = b.addTest(.{ .root_module = menuconfig_test_mod });
    const run_menuconfig_tests = b.addRunArtifact(menuconfig_tests);
    const menuconfig_test_step = b.step("test-menuconfig", "Run menuconfig TUI tests");
    menuconfig_test_step.dependOn(&run_menuconfig_tests.step);

    // Nova User-Space ELF
    if (nova_on) {
        const nova_mod = b.createModule(.{
            .root_source_file = b.path("nova_user/src/main.zig"),
            .target = target,
            .optimize = .ReleaseSmall,
        });
        // Shared string/math helpers used by both kernel and nova_user.
        nova_mod.addAnonymousImport("str", .{ .root_source_file = b.path("kernel/str.zig") });
        const nova_exe = b.addExecutable(.{
            .name = "nova",
            .root_module = nova_mod,
        });
        nova_exe.setLinkerScript(b.path("nova_user/linker.ld"));

        // Install nova.elf next to the kernel
        const install_nova = b.addInstallArtifact(nova_exe, .{
            .dest_dir = .{ .override = .{ .custom = "../build" } },
        });
        b.default_step.dependOn(&install_nova.step);

        // Make kernel compile depend on nova install (for @embedFile)
        kernel.step.dependOn(&install_nova.step);
    }

    // Developer Commands

    // 1. Run the OS without disk
    const run_cmd = b.addSystemCommand(&[_][]const u8{
        "qemu-system-i386",
        "-drive",
        "format=raw,file=../build/os-image.bin",
        "-serial",
        "stdio",
        "-vga",
        "std",
    });
    // Require the kernel to be built (though full OS build still needs build.bat/sh)
    run_cmd.step.dependOn(&install_kernel.step);

    const run_step = b.step("run", "Run the OS in QEMU (no disk)");
    run_step.dependOn(&run_cmd.step);

    // Option for disk size (e.g., 1M, 2G). Default 32M.
    const disk_size_opt = b.option([]const u8, "disk_size", "Size of disk image (e.g., 1M, 2G). Default: 32M");
    const disk_size = disk_size_opt orelse "32M";

    // 2. Create a disk image of configurable size
    const mkdisk_cmd = b.addSystemCommand(&[_][]const u8{
        "qemu-img", "create", "-f", "raw", "../disk.img", disk_size,
    });
    const mkdisk_step = b.step("mkdisk", "Create a raw disk image (size configurable via --disk-size)");
    mkdisk_step.dependOn(&mkdisk_cmd.step);

    // 3. Run the OS with the disk attached
    const run_disk_cmd = b.addSystemCommand(&[_][]const u8{
        "qemu-system-i386",
        "-drive",
        "format=raw,file=../build/os-image.bin",
        "-drive",
        "format=raw,file=../disk.img",
        "-serial",
        "stdio",
        "-vga",
        "std",
    });
    run_disk_cmd.step.dependOn(&install_kernel.step);

    const run_disk_step = b.step("run-disk", "Run the OS in QEMU with disk.img attached");
    run_disk_step.dependOn(&run_disk_cmd.step);
}
