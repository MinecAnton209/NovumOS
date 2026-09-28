// Stub user module for host testing hash_table.zig
// Provides user_malloc and user_free that delegate to host allocator
var gpa = @import("std").heap.GeneralPurposeAllocator(.{}){};
var allocator = gpa.allocator();

pub fn user_malloc(size: usize) ?[*]u8 {
    const ptr = allocator.alloc(u8, size) catch return null;
    return @ptrCast(ptr.ptr);
}

pub fn user_free(ptr: ?[*]u8) void {
    if (ptr) |p| {
        const slice = @as([*]u8, p)[0..0]; // We don't know size in this stub
        _ = slice;
        // In real code we'd free by size; for tests, we use a simple arena fallback
        // This is a best-effort stub for testing
    }
}
