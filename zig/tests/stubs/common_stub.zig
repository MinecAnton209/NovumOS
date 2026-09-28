// Minimal stub of common.zig for host testing path_policy.zig
// path_policy only uses common.std_mem_eql and common.startsWith
const std = @import("std");

fn memEql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (ca != cb) return false;
    }
    return true;
}

fn startsWithFn(a: []const u8, b: []const u8) bool {
    if (a.len < b.len) return false;
    return memEql(a[0..b.len], b);
}

pub const std_mem_eql = memEql;
pub const startsWith = startsWithFn;
