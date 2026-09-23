pub fn std_mem_eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, 0..) |item, i| {
        if (item != b[i]) return false;
    }
    return true;
}

pub fn startsWith(a: []const u8, b: []const u8) bool {
    if (a.len < b.len) return false;
    return std_mem_eql(a[0..b.len], b);
}

pub fn endsWith(a: []const u8, b: []const u8) bool {
    if (a.len < b.len) return false;
    return std_mem_eql(a[a.len - b.len ..], b);
}

pub fn asciiLower(c: u8) u8 {
    if (c >= 'A' and c <= 'Z') return c + 32;
    return c;
}

pub fn startsWithIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len < b.len) return false;
    for (0..b.len) |i| {
        if (asciiLower(a[i]) != asciiLower(b[i])) return false;
    }
    return true;
}

pub fn lastIndexOf(slice: []const u8, c: u8) ?usize {
    var i: usize = slice.len;
    while (i > 0) {
        i -= 1;
        if (slice[i] == c) return i;
    }
    return null;
}

pub fn copy(dest: []u8, src: []const u8) void {
    const len = @min(dest.len, src.len);
    for (0..len) |i| dest[i] = src[i];
}

pub fn math_abs(n: i32) i32 {
    return if (n < 0) -n else n;
}

pub fn math_max(a: i32, b: i32) i32 {
    return if (a > b) a else b;
}

pub fn math_min(a: i32, b: i32) i32 {
    return if (a < b) a else b;
}
