// Host-test stub for zig/commands/common.zig: console output is discarded and the
// string helpers match zig/kernel/str.zig.
pub var current_path: [256]u8 = @splat(0);
pub var current_path_len: usize = 0;

pub fn print_char(c: u8) void {
    _ = c;
}

pub fn printZ(s: []const u8) void {
    _ = s;
}

pub fn printError(s: []const u8) void {
    _ = s;
}

pub fn printNum(n: i32) void {
    _ = n;
}

pub fn std_mem_eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (ca != cb) return false;
    }
    return true;
}

pub fn startsWith(a: []const u8, b: []const u8) bool {
    if (a.len < b.len) return false;
    return std_mem_eql(a[0..b.len], b);
}

pub fn copy(dest: []u8, src: []const u8) void {
    const n = @min(dest.len, src.len);
    @memcpy(dest[0..n], src[0..n]);
}
