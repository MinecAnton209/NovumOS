const std = @import("std");

pub fn build(b: *std.Build) void {
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
    options.addOption(?u32, "history_size", history_size);
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

    // --- Nova User-Space ELF ---
    const nova_mod = b.createModule(.{
        .root_source_file = b.path("nova_user/src/main.zig"),
        .target = target,
        .optimize = .ReleaseSmall,
    });
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

    // --- Developer Commands ---

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
