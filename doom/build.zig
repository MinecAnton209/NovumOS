const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .none,
        .ofmt = .elf,
        .cpu_features_sub = std.Target.x86.featureSet(&[_]std.Target.x86.Feature{
            .mmx, .sse, .sse2, .sse3, .ssse3,
            .sse4_1, .sse4_2, .avx, .avx2,
        }),
    });

    const opt = .ReleaseSmall;
    const m = "../libs/mlibc";

    const mod = b.createModule(.{
        .target = target,
        .optimize = opt,
    });

    const cflags = &.{
        "-DNORMALUNIX", "-DLINUX", "-D_DEFAULT_SOURCE", "-D_GNU_SOURCE",
        "-DDOOMGENERIC_RESX=640", "-DDOOMGENERIC_RESY=400",
        "-Wall", "-Wno-unused-parameter", "-Wno-pointer-sign",
    };

    mod.addCSourceFiles(.{
        .files = &.{
            "doomgeneric/doomgeneric/am_map.c",
            "doomgeneric/doomgeneric/doomdef.c",
            "doomgeneric/doomgeneric/doomstat.c",
            "doomgeneric/doomgeneric/dstrings.c",
            "doomgeneric/doomgeneric/d_event.c",
            "doomgeneric/doomgeneric/d_items.c",
            "doomgeneric/doomgeneric/d_iwad.c",
            "doomgeneric/doomgeneric/d_loop.c",
            "doomgeneric/doomgeneric/d_main.c",
            "doomgeneric/doomgeneric/d_mode.c",
            "doomgeneric/doomgeneric/d_net.c",
            "doomgeneric/doomgeneric/doomgeneric.c",
            "doomgeneric/doomgeneric/dummy.c",
            "doomgeneric/doomgeneric/f_finale.c",
            "doomgeneric/doomgeneric/f_wipe.c",
            "doomgeneric/doomgeneric/g_game.c",
            "doomgeneric/doomgeneric/hu_lib.c",
            "doomgeneric/doomgeneric/hu_stuff.c",
            "doomgeneric/doomgeneric/i_endoom.c",
            "doomgeneric/doomgeneric/i_input.c",
            "doomgeneric/doomgeneric/i_joystick.c",
            "doomgeneric/doomgeneric/i_scale.c",
            "doomgeneric/doomgeneric/i_sound.c",
            "doomgeneric/doomgeneric/i_system.c",
            "doomgeneric/doomgeneric/i_timer.c",
            "doomgeneric/doomgeneric/i_video.c",
            "doomgeneric/doomgeneric/info.c",
            "doomgeneric/doomgeneric/memio.c",
            "doomgeneric/doomgeneric/m_argv.c",
            "doomgeneric/doomgeneric/m_bbox.c",
            "doomgeneric/doomgeneric/m_cheat.c",
            "doomgeneric/doomgeneric/m_config.c",
            "doomgeneric/doomgeneric/m_controls.c",
            "doomgeneric/doomgeneric/m_fixed.c",
            "doomgeneric/doomgeneric/m_menu.c",
            "doomgeneric/doomgeneric/m_misc.c",
            "doomgeneric/doomgeneric/m_random.c",
            "doomgeneric/doomgeneric/mus2mid.c",
            "doomgeneric/doomgeneric/p_ceilng.c",
            "doomgeneric/doomgeneric/p_doors.c",
            "doomgeneric/doomgeneric/p_enemy.c",
            "doomgeneric/doomgeneric/p_floor.c",
            "doomgeneric/doomgeneric/p_inter.c",
            "doomgeneric/doomgeneric/p_lights.c",
            "doomgeneric/doomgeneric/p_map.c",
            "doomgeneric/doomgeneric/p_maputl.c",
            "doomgeneric/doomgeneric/p_mobj.c",
            "doomgeneric/doomgeneric/p_plats.c",
            "doomgeneric/doomgeneric/p_pspr.c",
            "doomgeneric/doomgeneric/p_saveg.c",
            "doomgeneric/doomgeneric/p_setup.c",
            "doomgeneric/doomgeneric/p_sight.c",
            "doomgeneric/doomgeneric/p_spec.c",
            "doomgeneric/doomgeneric/p_switch.c",
            "doomgeneric/doomgeneric/p_telept.c",
            "doomgeneric/doomgeneric/p_tick.c",
            "doomgeneric/doomgeneric/p_user.c",
            "doomgeneric/doomgeneric/r_bsp.c",
            "doomgeneric/doomgeneric/r_data.c",
            "doomgeneric/doomgeneric/r_draw.c",
            "doomgeneric/doomgeneric/r_main.c",
            "doomgeneric/doomgeneric/r_plane.c",
            "doomgeneric/doomgeneric/r_segs.c",
            "doomgeneric/doomgeneric/r_sky.c",
            "doomgeneric/doomgeneric/r_things.c",
            "doomgeneric/doomgeneric/sha1.c",
            "doomgeneric/doomgeneric/sounds.c",
            "doomgeneric/doomgeneric/statdump.c",
            "doomgeneric/doomgeneric/st_lib.c",
            "doomgeneric/doomgeneric/st_stuff.c",
            "doomgeneric/doomgeneric/s_sound.c",
            "doomgeneric/doomgeneric/tables.c",
            "doomgeneric/doomgeneric/v_video.c",
            "doomgeneric/doomgeneric/wi_stuff.c",
            "doomgeneric/doomgeneric/w_checksum.c",
            "doomgeneric/doomgeneric/w_file.c",
            "doomgeneric/doomgeneric/w_file_stdc.c",
            "doomgeneric/doomgeneric/w_main.c",
            "doomgeneric/doomgeneric/w_wad.c",
            "doomgeneric/doomgeneric/z_zone.c",
            "doomgeneric_novumos.c",
        },
        .flags = cflags,
    });

    inline for (&.{
        "doomgeneric/doomgeneric",
        m ++ "",
        m ++ "/options/internal/include",
        m ++ "/options/ansi/include",
        m ++ "/options/posix/include",
        m ++ "/options/glibc/include",
        m ++ "/sysdeps/novumos/include",
        m ++ "/subprojects/freestnd-c-hdrs/i686/include",
        m ++ "/build-novumos",
    }) |inc| {
        mod.addIncludePath(b.path(inc));
    }

    mod.addObjectFile(b.path(m ++ "/build-novumos/sysdeps/novumos/crt1.o"));
    mod.addObjectFile(b.path(m ++ "/build-novumos/libc.a"));
    mod.addObjectFile(b.path(m ++ "/build-novumos/libm.a"));
    mod.addObjectFile(b.path(m ++ "/build-novumos/libpthread.a"));

    const exe = b.addExecutable(.{
        .name = "doom",
        .root_module = mod,
    });
    exe.setLinkerScript(b.path("doom.ld"));

    b.installArtifact(exe);

    // --- Test mlibc executable ---
    const test_mod = b.createModule(.{
        .target = target,
        .optimize = opt,
    });
    test_mod.addCSourceFile(.{ .file = b.path("test_mlibc.c"), .flags = cflags });
    inline for (&.{
        "doomgeneric/doomgeneric",
        m ++ "",
        m ++ "/options/internal/include",
        m ++ "/options/ansi/include",
        m ++ "/options/posix/include",
        m ++ "/options/glibc/include",
        m ++ "/sysdeps/novumos/include",
        m ++ "/subprojects/freestnd-c-hdrs/i686/include",
        m ++ "/build-novumos",
    }) |inc| {
        test_mod.addIncludePath(b.path(inc));
    }
    test_mod.addObjectFile(b.path(m ++ "/build-novumos/sysdeps/novumos/crt1.o"));
    test_mod.addObjectFile(b.path(m ++ "/build-novumos/libc.a"));
    test_mod.addObjectFile(b.path(m ++ "/build-novumos/libm.a"));
    const test_exe = b.addExecutable(.{
        .name = "test_mlibc",
        .root_module = test_mod,
    });
    test_exe.setLinkerScript(b.path("doom.ld"));
    b.installArtifact(test_exe);

    // --- Sysdeps coverage executable ---
    const sysdeps_mod = b.createModule(.{
        .target = target,
        .optimize = opt,
    });
    sysdeps_mod.addCSourceFile(.{ .file = b.path("test_sysdeps.c"), .flags = cflags });
    inline for (&.{
        m ++ "",
        m ++ "/options/internal/include",
        m ++ "/options/ansi/include",
        m ++ "/options/posix/include",
        m ++ "/options/glibc/include",
        m ++ "/sysdeps/novumos/include",
        m ++ "/subprojects/freestnd-c-hdrs/i686/include",
        m ++ "/build-novumos",
    }) |inc| {
        sysdeps_mod.addIncludePath(b.path(inc));
    }
    sysdeps_mod.addObjectFile(b.path(m ++ "/build-novumos/sysdeps/novumos/crt1.o"));
    sysdeps_mod.addObjectFile(b.path(m ++ "/build-novumos/libc.a"));
    sysdeps_mod.addObjectFile(b.path(m ++ "/build-novumos/libm.a"));
    const sysdeps_exe = b.addExecutable(.{
        .name = "test_sysdeps",
        .root_module = sysdeps_mod,
    });
    sysdeps_exe.setLinkerScript(b.path("doom.ld"));
    b.installArtifact(sysdeps_exe);
}
