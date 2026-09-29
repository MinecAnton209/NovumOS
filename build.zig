const std = @import("std");

pub fn build(b: *std.Build) void {
    const kconfig = @import("zig/kconfig.zig");
    const cfg_schema = @import("zig/config_schema.zig");

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
        if (read(handle, b.graph.io, ".config", b.allocator)) |t|
            break :blk Cfg{ .text = t, .source = ".config" };
        if (read(handle, b.graph.io, "defconfig", b.allocator)) |t|
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

    const smp_on = kconfig.flag(&cfg_schema.schema, cfg.text, "ENABLE_SMP");
    const acpi_on = kconfig.flag(&cfg_schema.schema, cfg.text, "ENABLE_ACPI");
    const speaker_on = kconfig.flag(&cfg_schema.schema, cfg.text, "ENABLE_SPEAKER");
    const boot_beep_on = kconfig.flag(&cfg_schema.schema, cfg.text, "ENABLE_BOOT_BEEP");
    const error_beep_on = kconfig.flag(&cfg_schema.schema, cfg.text, "ENABLE_ERROR_BEEP");

    if (smp_on and !acpi_on) {
        std.log.err("config conflict: ENABLE_SMP=y requires ENABLE_ACPI=y (SMP uses ACPI MADT for core discovery)", .{});
        std.process.exit(1);
    }
    if (boot_beep_on and !speaker_on) {
        std.log.err("config conflict: ENABLE_BOOT_BEEP=y requires ENABLE_SPEAKER=y", .{});
        std.process.exit(1);
    }
    if (error_beep_on and !speaker_on) {
        std.log.err("config conflict: ENABLE_ERROR_BEEP=y requires ENABLE_SPEAKER=y", .{});
        std.process.exit(1);
    }

    const embedded_elfs_on = kconfig.flag(&cfg_schema.schema, cfg.text, "ENABLE_EMBEDDED_ELFS");
    const builtin_scripts_on = kconfig.flag(&cfg_schema.schema, cfg.text, "ENABLE_BUILTIN_SCRIPTS");
    const doomfire_on = kconfig.flag(&cfg_schema.schema, cfg.text, "ENABLE_DOOMFIRE");
    const quantum_on = kconfig.flag(&cfg_schema.schema, cfg.text, "ENABLE_QUANTUM");
    const idt_wd_on = kconfig.flag(&cfg_schema.schema, cfg.text, "ENABLE_IDT_WATCHDOG");
    const idt_snap_on = kconfig.flag(&cfg_schema.schema, cfg.text, "ENABLE_IDT_WATCHDOG_SNAPSHOT");
    if (embedded_elfs_on and !nova_on) {
        std.log.err("config conflict: ENABLE_EMBEDDED_ELFS=y requires ENABLE_NOVA=y", .{});
        std.process.exit(1);
    }
    if (builtin_scripts_on and !nova_on) {
        std.log.err("config conflict: ENABLE_BUILTIN_SCRIPTS=y requires ENABLE_NOVA=y", .{});
        std.process.exit(1);
    }
    if (doomfire_on and !quantum_on) {
        std.log.err("config conflict: ENABLE_DOOMFIRE=y requires ENABLE_QUANTUM=y", .{});
        std.process.exit(1);
    }
    if (idt_snap_on and !idt_wd_on) {
        std.log.err("config conflict: ENABLE_IDT_WATCHDOG_SNAPSHOT=y requires ENABLE_IDT_WATCHDOG=y", .{});
        std.process.exit(1);
    }

    // Shell/Display dependencies
    const clock_on = kconfig.flag(&cfg_schema.schema, cfg.text, "ENABLE_CLOCK_IN_PROMPT");
    const status_ind_on = kconfig.flag(&cfg_schema.schema, cfg.text, "ENABLE_STATUS_INDICATORS");
    const vga_text_on = kconfig.flag(&cfg_schema.schema, cfg.text, "ENABLE_VGA_TEXT");
    const serial_input_on = kconfig.flag(&cfg_schema.schema, cfg.text, "ENABLE_SERIAL_INPUT");

    if (clock_on and !serial_input_on) {
        std.log.err("config conflict: ENABLE_CLOCK_IN_PROMPT=y requires ENABLE_SERIAL_INPUT=y (clock uses serial mirror)", .{});
        std.process.exit(1);
    }
    if (status_ind_on and !vga_text_on) {
        std.log.err("config conflict: ENABLE_STATUS_INDICATORS=y requires ENABLE_VGA_TEXT=y (indicators draw to VGA text buffer)", .{});
        std.process.exit(1);
    }

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

    // Generate a cryptographically secure build hash via the OS CSPRNG
    // (getrandom on Linux, BCryptGenRandom on Windows, etc.).
    // Ensures watchdog patterns are unpredictable across builds.
    const build_hash: u32 = blk: {
        var buf: [4]u8 = undefined;
        std.Io.randomSecure(b.graph.io, &buf) catch {
            // If OS entropy unavailable, fall back to a deterministic hash
            // of config text to at least vary per config.
            const Hasher = std.hash.XxHash32;
            var h = Hasher.init(0x9e3779b9);
            h.update(cfg.text);
            break :blk h.final();
        };
        break :blk std.mem.readInt(u32, &buf, .little);
    };

    // Create the kernel module first
    const kernel_mod = b.createModule(.{
        .root_source_file = b.path("zig/kernel.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Build options
    const history_size = b.option(u32, "history_size", "Number of commands to keep in history");
    const options = b.addOptions();
    options.addOption([]const u8, "target_arch", arch);
    options.addOption(?u32, "history_size", history_size);
    options.addOption([]const u8, "config_text", cfg.text);
    options.addOption(u32, "build_hash", build_hash);
    kernel_mod.addOptions("build_config", options);

    // Build the kernel object file
    const kernel = b.addObject(.{
        .name = "kernel",
        .root_module = kernel_mod,
    });

    // Install the object file to build/
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
    nasm_k32.addPrefixedDirectoryArg("-i", b.path("arch/x86"));
    // The -i directory arg is hashed by path only, so content-track every
    // file %included through it: add new entries here when kernel32.asm
    // grows includes, or edits to them build a silently stale kernel.
    nasm_k32.addFileInput(b.path("arch/x86/idt.asm"));
    nasm_k32.addFileArg(b.path("arch/x86/kernel32.asm"));
    nasm_k32.addArg(b.fmt("-D{s}", .{serial_flag}));
    nasm_k32.addArg(b.fmt("-D{s}", .{lfb_flag}));
    nasm_k32.addArg(b.fmt("-D{s}", .{mouse_flag}));
    nasm_k32.addArg("-o");
    const k32_o = nasm_k32.addOutputFileArg("kernel32.o");

    const nasm_um = b.addSystemCommand(&.{ "nasm", "-f", "elf32" });
    nasm_um.addFileArg(b.path("arch/x86/user_mode.asm"));
    nasm_um.addArg("-o");
    const um_o = nasm_um.addOutputFileArg("user_mode.o");

    const nasm_tr = b.addSystemCommand(&.{ "nasm", "-f", "bin" });
    nasm_tr.addFileArg(b.path("zig/arch/x86/smp_trampoline.asm"));
    nasm_tr.addArg("-o");
    const tramp_bin = nasm_tr.addOutputFileArg("trampoline.bin");

    const link_cmd = b.addSystemCommand(&.{ "zig", "ld.lld", "-m", "elf_i386", "-T" });
    link_cmd.addFileArg(b.path("arch/x86/linker.ld"));
    link_cmd.addArg("--strip-all");
    link_cmd.addArg("-o");
    const kernel_elf = link_cmd.addOutputFileArg("kernel32.elf");
    link_cmd.addFileArg(k32_o);
    link_cmd.addFileArg(um_o);
    link_cmd.addFileArg(kernel.getEmittedBin());

    const install_elf = b.addInstallFileWithDir(kernel_elf, .{ .custom = "../build" }, "kernel32.elf");
    const install_tramp = b.addInstallFileWithDir(tramp_bin, .{ .custom = "../build" }, "trampoline.bin");
    b.default_step.dependOn(&install_elf.step);
    b.default_step.dependOn(&install_tramp.step);

    // Config facade tests (build_config with a non-empty override)
    const config_test_mod = b.createModule(.{
        .root_source_file = b.path("zig/config.zig"),
        .target = b.resolveTargetQuery(.{}),
        .optimize = .Debug,
    });
    const test_options = b.addOptions();
    test_options.addOption([]const u8, "target_arch", arch);
    test_options.addOption(?u32, "history_size", null);
    test_options.addOption([]const u8, "config_text", "CONFIG_HISTORY_SIZE=7");
    test_options.addOption(u32, "build_hash", 0xDEADBEEF);
    config_test_mod.addOptions("build_config", test_options);
    const config_tests = b.addTest(.{ .root_module = config_test_mod });
    const run_config_tests = b.addRunArtifact(config_tests);
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_config_tests.step);

    // cfg_write merge tests: resolved as named module config_schema.
    const cfg_write_mod = b.createModule(.{
        .root_source_file = b.path("zig/tools/cfg_write.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    cfg_write_mod.addAnonymousImport("config_schema", .{
        .root_source_file = b.path("zig/config_schema.zig"),
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
        .root_source_file = b.path("zig/tools/menuconfig.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    menuconfig_mod.addImport("vaxis", vaxis_dep.module("vaxis"));
    menuconfig_mod.addAnonymousImport("config_schema", .{
        .root_source_file = b.path("zig/config_schema.zig"),
        .imports = &.{},
    });
    const menuconfig_exe = b.addExecutable(.{
        .name = "menuconfig",
        .root_module = menuconfig_mod,
    });
    const run_menuconfig = b.addRunArtifact(menuconfig_exe);
    run_menuconfig.stdio = .inherit;
    const menuconfig_step = b.step("menuconfig", "Edit .config in an interactive TUI");
    menuconfig_step.dependOn(&run_menuconfig.step);

    // menuconfig TUI logic tests (same module graph as the exe, run as a test)
    const menuconfig_test_mod = b.createModule(.{
        .root_source_file = b.path("zig/tools/menuconfig.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    menuconfig_test_mod.addImport("vaxis", vaxis_dep.module("vaxis"));
    menuconfig_test_mod.addAnonymousImport("config_schema", .{
        .root_source_file = b.path("zig/config_schema.zig"),
        .imports = &.{},
    });
    const menuconfig_tests = b.addTest(.{ .root_module = menuconfig_test_mod });
    const run_menuconfig_tests = b.addRunArtifact(menuconfig_tests);
    const menuconfig_test_step = b.step("test-menuconfig", "Run menuconfig TUI tests");
    menuconfig_test_step.dependOn(&run_menuconfig_tests.step);

    // config show: host tool printing resolved .config
    const config_show_mod = b.createModule(.{
        .root_source_file = b.path("zig/tools/config_show.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    config_show_mod.addOptions("build_config", options);
    const kconfig_mod = b.createModule(.{
        .root_source_file = b.path("zig/kconfig.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    // config_schema.zig does `@import("kconfig.zig")` — redirect that name
    // to the single kconfig_mod so the file is registered once.
    const config_schema_mod = b.createModule(.{
        .root_source_file = b.path("zig/config_schema.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
        .imports = &.{
            .{ .name = "kconfig.zig", .module = kconfig_mod },
        },
    });
    config_show_mod.addImport("kconfig", kconfig_mod);
    config_show_mod.addImport("config_schema", config_schema_mod);
    const config_show_exe = b.addExecutable(.{
        .name = "config-show",
        .root_module = config_show_mod,
    });
    const run_config_show = b.addRunArtifact(config_show_exe);
    run_config_show.stdio = .inherit;
    const config_show_step = b.step("config", "Show resolved kernel configuration");
    config_show_step.dependOn(&run_config_show.step);
    // Nova User-Space ELF
    if (nova_on) {
        const nova_mod = b.createModule(.{
            .root_source_file = b.path("zig/nova_user/src/main.zig"),
            .target = target,
            .optimize = .ReleaseSmall,
        });
        // Shared string/math helpers used by both kernel and nova_user.
        nova_mod.addAnonymousImport("str", .{ .root_source_file = b.path("zig/kernel/str.zig") });
        const nova_exe = b.addExecutable(.{
            .name = "nova",
            .root_module = nova_mod,
        });
        nova_exe.setLinkerScript(b.path("zig/nova_user/linker.ld"));

        // Install nova.elf to zig/build for @embedFile in zig/kernel/elf.zig
        const install_nova = b.addInstallArtifact(nova_exe, .{
            .dest_dir = .{ .override = .{ .custom = "../zig/build" } },
        });
        const install_nova_root = b.addInstallArtifact(nova_exe, .{
            .dest_dir = .{ .override = .{ .custom = "../build" } },
        });
        b.default_step.dependOn(&install_nova.step);
        b.default_step.dependOn(&install_nova_root.step);

        // Make kernel compile depend on nova install (for @embedFile)
        kernel.step.dependOn(&install_nova.step);
    }

    // --- Host-native test suites ---

    // Stubs for gdt.zig host tests (redirects ../../config.zig and
    // ../../kernel/logger.zig imports to host-safe no-ops)
    const wx_config_stub = b.createModule(.{
        .root_source_file = b.path("zig/tests/stubs/wx_config_stub.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    const wx_logger_stub = b.createModule(.{
        .root_source_file = b.path("zig/tests/stubs/wx_logger_stub.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });

    // gdt.zig: pure W^X limit-packing logic (host-safe stubs for config/logger)
    const gdt_test_mod = b.createModule(.{
        .root_source_file = b.path("zig/arch/x86/gdt.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
        .imports = &.{
            .{ .name = "../../config.zig", .module = wx_config_stub },
            .{ .name = "../../kernel/logger.zig", .module = wx_logger_stub },
        },
    });
    const gdt_tests = b.addTest(.{ .root_module = gdt_test_mod });
    const run_gdt_tests = b.addRunArtifact(gdt_tests);
    const gdt_test_step = b.step("test-gdt", "Run GDT W^X limit-packing tests");
    gdt_test_step.dependOn(&run_gdt_tests.step);
    test_step.dependOn(&run_gdt_tests.step);

    const str_test_mod = b.createModule(.{
        .root_source_file = b.path("zig/tests/test_str.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    str_test_mod.addAnonymousImport("str", .{
        .root_source_file = b.path("zig/kernel/str.zig"),
    });
    const str_tests = b.addTest(.{ .root_module = str_test_mod });
    const run_str_tests = b.addRunArtifact(str_tests);
    const str_test_step = b.step("test-str", "Run str.zig utility tests");
    str_test_step.dependOn(&run_str_tests.step);

    // hash_table.zig tests: self-contained port with host allocator
    const hash_table_test_mod = b.createModule(.{
        .root_source_file = b.path("zig/tests/test_hash_table.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    const hash_table_tests = b.addTest(.{ .root_module = hash_table_test_mod });
    const run_hash_table_tests = b.addRunArtifact(hash_table_tests);
    const hash_table_test_step = b.step("test-hash-table", "Run hash_table.zig tests");
    hash_table_test_step.dependOn(&run_hash_table_tests.step);

    // test_lexer.zig: ported tokenizer with host allocator
    const lexer_test_mod = b.createModule(.{
        .root_source_file = b.path("zig/tests/test_lexer.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    const lexer_tests = b.addTest(.{ .root_module = lexer_test_mod });
    const run_lexer_tests = b.addRunArtifact(lexer_tests);
    const lexer_test_step = b.step("test-lexer", "Run lexer TokenType tests");
    lexer_test_step.dependOn(&run_lexer_tests.step);

    // test_parser.zig: ported statement parser with host allocator
    const parser_test_mod = b.createModule(.{
        .root_source_file = b.path("zig/tests/test_parser.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    const parser_tests = b.addTest(.{ .root_module = parser_test_mod });
    const run_parser_tests = b.addRunArtifact(parser_tests);
    const parser_test_step = b.step("test-parser", "Run parser statement tests");
    parser_test_step.dependOn(&run_parser_tests.step);

    // test_common.zig: pure function tests (parse_int, intToString, etc.)
    const common_test_mod = b.createModule(.{
        .root_source_file = b.path("zig/tests/test_common.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    const common_tests = b.addTest(.{ .root_module = common_test_mod });
    const run_common_tests = b.addRunArtifact(common_tests);
    const common_test_step = b.step("test-common", "Run common.zig utility function tests");
    common_test_step.dependOn(&run_common_tests.step);

    // path_policy.zig tests: canonicalize + blocked path matching
    // path_policy imports "../config.zig", "logger.zig", "../commands/common.zig"
    // We create stub modules for config, logger, common and use `imports` in
    // CreateOptions to redirect path-based @import calls to the stubs.
    const config_stub_mod = b.createModule(.{
        .root_source_file = b.path("zig/tests/stubs/config_stub.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    const logger_stub_mod = b.createModule(.{
        .root_source_file = b.path("zig/tests/stubs/logger_stub.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    const common_stub_mod = b.createModule(.{
        .root_source_file = b.path("zig/tests/stubs/common_stub.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    });
    const path_policy_under_test = b.createModule(.{
        .root_source_file = b.path("zig/kernel/path_policy.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
        .imports = &.{
            .{ .name = "../config.zig", .module = config_stub_mod },
            .{ .name = "logger.zig", .module = logger_stub_mod },
            .{ .name = "../commands/common.zig", .module = common_stub_mod },
        },
    });
    const path_policy_test_mod = b.createModule(.{
        .root_source_file = b.path("zig/kernel/test_path_policy.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
        .imports = &.{
            .{ .name = "path_policy", .module = path_policy_under_test },
        },
    });
    const path_policy_tests = b.addTest(.{ .root_module = path_policy_test_mod });
    const run_path_policy_tests = b.addRunArtifact(path_policy_tests);
    const path_policy_test_step = b.step("test-path-policy", "Run path_policy.zig canonicalization and blocking tests");
    path_policy_test_step.dependOn(&run_path_policy_tests.step);

    // Extended test step for all host-test suites
    test_step.dependOn(&run_str_tests.step);
    test_step.dependOn(&run_hash_table_tests.step);
    test_step.dependOn(&run_common_tests.step);
    test_step.dependOn(&run_lexer_tests.step);
    test_step.dependOn(&run_parser_tests.step);
    test_step.dependOn(&run_path_policy_tests.step);
    test_step.dependOn(&run_cfg_write_tests.step);

    // --- Existing test: config facade ---

    // Developer Commands

    // 1. Run the OS without disk
    const run_cmd = b.addSystemCommand(&[_][]const u8{
        "qemu-system-i386",
        "-drive",
        "format=raw,file=build/os-image.bin",
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
        "qemu-img", "create", "-f", "raw", "disk.img", disk_size,
    });
    const mkdisk_step = b.step("mkdisk", "Create a raw disk image (size configurable via --disk-size)");
    mkdisk_step.dependOn(&mkdisk_cmd.step);

    // 3. Run the OS with the disk attached
    const run_disk_cmd = b.addSystemCommand(&[_][]const u8{
        "qemu-system-i386",
        "-drive",
        "format=raw,file=build/os-image.bin",
        "-drive",
        "format=raw,file=disk.img",
        "-serial",
        "stdio",
        "-vga",
        "std",
    });
    run_disk_cmd.step.dependOn(&install_kernel.step);

    const run_disk_step = b.step("run-disk", "Run the OS in QEMU with disk.img attached");
    run_disk_step.dependOn(&run_disk_cmd.step);
}
