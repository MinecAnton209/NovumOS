const std = @import("std");
const config = @import("../config.zig");

// Pages to randomize the user-space ELF slide.  0 means no slide (fallback
// when entropy unavailable).
pub const ASLR_SLIDE_PAGES = 32;

fn randFromBuildHash() usize {
    return config.BUILD_HASH;
}

/// Return a random virtual-address slide for the user-space ELF.
/// Bounded to [0, ASLR_SLIDE_PAGES * PAGE_SIZE) so we never collide with
/// the fixed 0x02000000 base layout or the 3GB boundary.
pub fn elfSlide() usize {
    if (!config.ENABLE_ASLR)
        return 0;
    const seed = randFromBuildHash();
    return (seed % 32) * 4096;
}

/// Pure helper: compute slide from an explicit seed + enable flag.
fn elfSlideFromSeed(seed: u32, aslr_on: bool) usize {
    if (!aslr_on) return 0;
    return (seed % 32) * 4096;
}

test "elfSlideFromSeed: zero when disabled" {
    try std.testing.expectEqual(@as(usize, 0), elfSlideFromSeed(0, false));
    try std.testing.expectEqual(@as(usize, 0), elfSlideFromSeed(0xDEAD, false));
}

test "elfSlideFromSeed: page-aligned and bounded when enabled" {
    var s = elfSlideFromSeed(0, true);
    try std.testing.expectEqual(@as(usize, 0), s);

    s = elfSlideFromSeed(1, true);
    try std.testing.expectEqual(@as(usize, 4096), s);

    s = elfSlideFromSeed(31, true);
    try std.testing.expectEqual(@as(usize, 126976), s); // 31*4096

    s = elfSlideFromSeed(32, true);
    try std.testing.expectEqual(@as(usize, 0), s); // wraps modulo 32

    // Max offset < 32*4096
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        const val = elfSlideFromSeed(i, true);
        try std.testing.expect(val % 4096 == 0);
        try std.testing.expect(val < 128 * 1024);
    }
}
