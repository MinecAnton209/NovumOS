// Test module placed inside zig/kernel/ so that path_policy's relative
// imports (../config.zig, ../kernel/logger.zig, ../commands/common.zig)
// resolve to the stub modules configured in build.zig via addAnonymousImport.
//
// The actual test logic lives here; build.zig overrides "config", "logger",
// and "common" with stubs so we can run fully host-native.

const std = @import("std");

// This import resolves to ../kernel/path_policy.zig relative to our location
const path_policy = @import("path_policy");

// === canonicalize tests ===

test "canonicalize: empty string" {
    var buf: [256]u8 = undefined;
    const result = path_policy.canonicalize("", &buf);
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqualSlices(u8, r, "");
    }
}

test "canonicalize: root only" {
    var buf: [256]u8 = undefined;
    const result = path_policy.canonicalize("/", &buf);
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqualSlices(u8, r, "/");
    }
}

test "canonicalize: simple path" {
    var buf: [256]u8 = undefined;
    const result = path_policy.canonicalize("/foo/bar", &buf);
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqualSlices(u8, r, "/foo/bar");
    }
}

test "canonicalize: backslash separators" {
    var buf: [256]u8 = undefined;
    const result = path_policy.canonicalize("\\foo\\bar", &buf);
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqualSlices(u8, r, "/foo/bar");
    }
}

test "canonicalize: collapse repeated slashes" {
    var buf: [256]u8 = undefined;
    const result = path_policy.canonicalize("//foo///bar", &buf);
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqualSlices(u8, r, "/foo/bar");
    }
}

test "canonicalize: dot components removed" {
    var buf: [256]u8 = undefined;
    const result = path_policy.canonicalize("/foo/./bar", &buf);
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqualSlices(u8, r, "/foo/bar");
    }
}

test "canonicalize: parent traversal rejected" {
    var buf: [256]u8 = undefined;
    const result = path_policy.canonicalize("/foo/../bar", &buf);
    try std.testing.expect(result == null);
}

test "canonicalize: parent at start rejected" {
    var buf: [256]u8 = undefined;
    const result = path_policy.canonicalize("../bar", &buf);
    try std.testing.expect(result == null);
}

test "canonicalize: trailing slash removed" {
    var buf: [256]u8 = undefined;
    const result = path_policy.canonicalize("/foo/bar/", &buf);
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqualSlices(u8, r, "/foo/bar");
    }
}

test "canonicalize: buffer overflow returns null" {
    var buf: [5]u8 = undefined;
    const result = path_policy.canonicalize("/very/long/path", &buf);
    try std.testing.expect(result == null);
}

test "canonicalize: mixed separators with dots" {
    var buf: [256]u8 = undefined;
    const result = path_policy.canonicalize("\\foo/.\\bar", &buf);
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqualSlices(u8, r, "/foo/bar");
    }
}

test "canonicalize: relative path (not rooted)" {
    var buf: [256]u8 = undefined;
    const result = path_policy.canonicalize("foo/bar", &buf);
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqualSlices(u8, r, "foo/bar");
    }
}

test "canonicalize: relative with dot" {
    var buf: [256]u8 = undefined;
    const result = path_policy.canonicalize("foo/./bar", &buf);
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqualSlices(u8, r, "foo/bar");
    }
}

test "canonicalize: double root path" {
    var buf: [256]u8 = undefined;
    const result = path_policy.canonicalize("//foo", &buf);
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqualSlices(u8, r, "/foo");
    }
}

test "canonicalize: trailing dot only" {
    var buf: [256]u8 = undefined;
    const result = path_policy.canonicalize("/foo/bar/.", &buf);
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqualSlices(u8, r, "/foo/bar");
    }
}

test "canonicalize: multiple dot components" {
    var buf: [256]u8 = undefined;
    const result = path_policy.canonicalize("/foo/./bar/./baz", &buf);
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqualSlices(u8, r, "/foo/bar/baz");
    }
}

test "canonicalize: root with dot" {
    var buf: [256]u8 = undefined;
    const result = path_policy.canonicalize("/.", &buf);
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqualSlices(u8, r, "/");
    }
}

test "canonicalize: backslash to root" {
    var buf: [256]u8 = undefined;
    const result = path_policy.canonicalize("\\", &buf);
    try std.testing.expect(result != null);
    if (result) |r| {
        try std.testing.expectEqualSlices(u8, r, "/");
    }
}

// === is_path_allowed tests (requires NOVA_PATH_POLICY_ENABLED=true in config stub) ===

test "is_path_allowed: allowed path" {
    try std.testing.expect(path_policy.is_path_allowed("/home/user/file.txt"));
}

test "is_path_allowed: blocked exact /kernel.zig" {
    try std.testing.expect(!path_policy.is_path_allowed("/kernel.zig"));
}

test "is_path_allowed: blocked exact /kernel.bin" {
    try std.testing.expect(!path_policy.is_path_allowed("/kernel.bin"));
}

test "is_path_allowed: blocked exact /boot/" {
    try std.testing.expect(!path_policy.is_path_allowed("/boot/"));
}

test "is_path_allowed: blocked prefix /boot/" {
    try std.testing.expect(!path_policy.is_path_allowed("/boot/loader"));
}

test "is_path_allowed: blocked prefix /.system/" {
    try std.testing.expect(!path_policy.is_path_allowed("/.system/admin"));
}

test "is_path_allowed: blocked prefix /efi/" {
    try std.testing.expect(!path_policy.is_path_allowed("/efi/vars"));
}

test "is_path_allowed: blocked prefix /initrd/" {
    try std.testing.expect(!path_policy.is_path_allowed("/initrd/img"));
}

test "is_path_allowed: blocked prefix /zig/" {
    try std.testing.expect(!path_policy.is_path_allowed("/zig/build"));
}

test "is_path_allowed: case-insensitive blocking /BOOT/" {
    try std.testing.expect(!path_policy.is_path_allowed("/BOOT/loader"));
}

test "is_path_allowed: case-insensitive blocking /Boot/" {
    try std.testing.expect(!path_policy.is_path_allowed("/Boot/loader"));
}

test "is_path_allowed: case-insensitive exact /KERNEL.BIN" {
    try std.testing.expect(!path_policy.is_path_allowed("/KERNEL.BIN"));
}

test "is_path_allowed: prefix without trailing slash" {
    try std.testing.expect(!path_policy.is_path_allowed("/boot"));
}

test "is_path_allowed: path containing blocked prefix as substring" {
    try std.testing.expect(path_policy.is_path_allowed("/my-boot/loader"));
}

test "is_path_allowed: path under allowed directory" {
    try std.testing.expect(path_policy.is_path_allowed("/usr/bin/app"));
    try std.testing.expect(path_policy.is_path_allowed("/var/log/log.txt"));
    try std.testing.expect(path_policy.is_path_allowed("/tmp/cache"));
}

test "is_path_allowed: root path allowed" {
    try std.testing.expect(path_policy.is_path_allowed("/"));
}

test "is_path_allowed: empty path" {
    try std.testing.expect(path_policy.is_path_allowed(""));
}

test "is_path_allowed: dot-dot path blocked (canonicalize rejects)" {
    try std.testing.expect(!path_policy.is_path_allowed("/foo/../bar"));
}

test "is_path_allowed: backslash variant of blocked prefix" {
    try std.testing.expect(!path_policy.is_path_allowed("\\boot\\loader"));
}

test "is_path_allowed: mixed separators in blocked path" {
    try std.testing.expect(!path_policy.is_path_allowed("/boot\\loader"));
}
