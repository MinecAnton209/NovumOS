const std = @import("std");

// We port the core logic of hash_table.zig and test it with a host allocator.
// VariablesType and VariableValue are identical to production.

pub const VariableType = enum {
    string,
    int,
    float,
    function,
};

pub const VariableValue = struct {
    vtype: VariableType,
    str_val: []const u8 = "",
    int_val: i32 = 0,
    float_val: f32 = 0.0,
    func_ptr: usize = 0,
};

pub const Entry = struct {
    key: []const u8,
    value: VariableValue,
    occupied: bool = false,
};

const HashTable = struct {
    entries: []Entry,
    size: usize,
    count: usize,

    fn hash(key: []const u8) u32 {
        var h: u32 = 5381;
        for (key) |c| {
            h = (h << 5) +% h +% @as(u32, c);
        }
        return h;
    }

    fn init(alloc: std.mem.Allocator, initial_size: usize) HashTable {
        const entries = alloc.alloc(Entry, initial_size) catch {
            return .{ .entries = &[_]Entry{}, .size = 0, .count = 0 };
        };
        for (entries) |*e| {
            e.key = "";
            e.value = undefined;
            e.occupied = false;
        }
        return .{ .entries = entries, .size = initial_size, .count = 0 };
    }

    fn deinit(self: *HashTable, alloc: std.mem.Allocator) void {
        if (self.size > 0) {
            for (0..self.size) |i| {
                if (self.entries[i].occupied) {
                    alloc.free(@constCast(self.entries[i].key));
                }
            }
            alloc.free(self.entries);
        }
    }

    fn resize(self: *HashTable, alloc: std.mem.Allocator, new_size: usize) void {
        const old_entries = self.entries;
        const old_size = self.size;

        self.entries = alloc.alloc(Entry, new_size) catch return;
        self.size = new_size;
        self.count = 0;

        for (self.entries) |*e| {
            e.key = "";
            e.occupied = false;
        }

        for (0..old_size) |i| {
            if (old_entries[i].occupied) {
                self.put_internal(alloc, old_entries[i].key, old_entries[i].value);
            }
        }
        alloc.free(old_entries);
    }

    fn put_internal(self: *HashTable, alloc: std.mem.Allocator, key: []const u8, value: VariableValue) void {
        _ = alloc;
        var index = hash(key) % self.size;
        while (self.entries[index].occupied) {
            index = (index + 1) % self.size;
        }
        self.entries[index].key = key;
        self.entries[index].value = value;
        self.entries[index].occupied = true;
        self.count += 1;
    }

    pub fn put(self: *HashTable, alloc: std.mem.Allocator, key: []const u8, value: VariableValue) void {
        if (self.count * 10 > self.size * 7) {
            self.resize(alloc, self.size * 2);
        }

        var index = hash(key) % self.size;
        while (self.entries[index].occupied) {
            if (streq(self.entries[index].key, key)) {
                self.entries[index].value = value;
                return;
            }
            index = (index + 1) % self.size;
        }

        const key_copy = alloc.dupe(u8, key) catch return;
        self.entries[index].key = key_copy;
        self.entries[index].value = value;
        self.entries[index].occupied = true;
        self.count += 1;
    }

    pub fn get(self: *const HashTable, key: []const u8) ?VariableValue {
        if (self.size == 0) return null;
        var index = hash(key) % self.size;
        const start_index = index;

        while (self.entries[index].occupied) {
            if (streq(self.entries[index].key, key)) {
                return self.entries[index].value;
            }
            index = (index + 1) % self.size;
            if (index == start_index) break;
        }
        return null;
    }

    fn remove(self: *HashTable, alloc: std.mem.Allocator, key: []const u8) bool {
        if (self.size == 0) return false;
        var index = hash(key) % self.size;
        const start_index = index;

        while (self.entries[index].occupied) {
            if (streq(self.entries[index].key, key)) {
                alloc.free(@constCast(self.entries[index].key));
                self.entries[index].occupied = false;
                self.count -= 1;
                return true;
            }
            index = (index + 1) % self.size;
            if (index == start_index) break;
        }
        return false;
    }

    fn streq(a: []const u8, b: []const u8) bool {
        if (a.len != b.len) return false;
        for (a, b) |ca, cb| {
            if (ca != cb) return false;
        }
        return true;
    }
};

// --- VariableValue tests ---

test "VariableValue: string type" {
    const v = VariableValue{
        .vtype = .string,
        .str_val = "hello world",
    };
    try std.testing.expectEqual(v.vtype, VariableType.string);
    try std.testing.expectEqualSlices(u8, v.str_val, "hello world");
}

test "VariableValue: int type" {
    const v = VariableValue{
        .vtype = .int,
        .int_val = -42,
    };
    try std.testing.expectEqual(v.vtype, VariableType.int);
    try std.testing.expectEqual(v.int_val, -42);
}

test "VariableValue: float type" {
    const v = VariableValue{
        .vtype = .float,
        .float_val = 3.14,
    };
    try std.testing.expectEqual(v.vtype, VariableType.float);
    try std.testing.expectApproxEqAbs(v.float_val, 3.14, 0.001);
}

test "VariableValue: function type" {
    const v = VariableValue{
        .vtype = .function,
        .func_ptr = 0x12345,
    };
    try std.testing.expectEqual(v.vtype, VariableType.function);
    try std.testing.expectEqual(v.func_ptr, 0x12345);
}

test "VariableValue: int zero value" {
    const v = VariableValue{ .vtype = .int };
    try std.testing.expectEqual(v.int_val, 0);
}

test "VariableValue: negative boundary" {
    const v = VariableValue{ .vtype = .int, .int_val = -2147483647 - 1 };
    try std.testing.expectEqual(v.int_val, -2147483647 - 1);
}

// --- Entry tests ---

test "Entry: default occupied is false" {
    const e = Entry{
        .key = "test",
        .value = VariableValue{ .vtype = .int },
    };
    try std.testing.expect(!e.occupied);
}

test "Entry: occupied set to true" {
    const e = Entry{
        .key = "test",
        .value = VariableValue{ .vtype = .int },
        .occupied = true,
    };
    try std.testing.expect(e.occupied);
}

// --- djb2 hash function tests ---

test "hash function: empty string returns djb2 initial value" {
    const h = HashTable.hash("");
    try std.testing.expectEqual(h, 5381);
}

test "hash function: same key produces same hash" {
    const h1 = HashTable.hash("test");
    const h2 = HashTable.hash("test");
    try std.testing.expectEqual(h1, h2);
}

test "hash function: different keys produce different hashes" {
    const h1 = HashTable.hash("test");
    const h2 = HashTable.hash("test2");
    try std.testing.expect(h1 != h2);
}

test "hash function: single char" {
    const h = HashTable.hash("a");
    try std.testing.expectEqual(h, (5381 << 5) +% 5381 +% @as(u32, 'a'));
}

test "hash function: two-char string AB" {
    const h = HashTable.hash("AB");
    // djb2: h = 5381; h = (h << 5) + h + 'A'; h = (h << 5) + h + 'B'
    // With u32 wrapping: 5381*33+65 = 177738; 177738*33+66 = 5862120
    try std.testing.expectEqual(h, 5862120);
}

// --- HashTable tests ---

test "HashTable: put and get single key" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var ht = HashTable.init(alloc, 8);
    defer ht.deinit(alloc);

    ht.put(alloc, "key", VariableValue{ .vtype = .int, .int_val = 42 });

    const result = ht.get("key");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(result.?.int_val, 42);
}

test "HashTable: get non-existent key returns null" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var ht = HashTable.init(alloc, 8);
    defer ht.deinit(alloc);

    try std.testing.expect(ht.get("nonexistent") == null);
}

test "HashTable: put overwrites existing value" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var ht = HashTable.init(alloc, 8);
    defer ht.deinit(alloc);

    ht.put(alloc, "key", VariableValue{ .vtype = .int, .int_val = 1 });
    ht.put(alloc, "key", VariableValue{ .vtype = .int, .int_val = 2 });

    const result = ht.get("key");
    try std.testing.expectEqual(result.?.int_val, 2);
}

test "HashTable: multiple distinct keys" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var ht = HashTable.init(alloc, 16);
    defer ht.deinit(alloc);

    ht.put(alloc, "a", VariableValue{ .vtype = .int, .int_val = 1 });
    ht.put(alloc, "b", VariableValue{ .vtype = .int, .int_val = 2 });
    ht.put(alloc, "c", VariableValue{ .vtype = .int, .int_val = 3 });

    try std.testing.expectEqual(ht.get("a").?.int_val, 1);
    try std.testing.expectEqual(ht.get("b").?.int_val, 2);
    try std.testing.expectEqual(ht.get("c").?.int_val, 3);
}

test "HashTable: collision handling with linear probing" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var ht = HashTable.init(alloc, 4);
    defer ht.deinit(alloc);

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var name_buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "key{}", .{i});
        ht.put(alloc, name, VariableValue{ .vtype = .int, .int_val = @intCast(i) });
    }

    var j: usize = 0;
    while (j < 10) : (j += 1) {
        var name_buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "key{}", .{j});
        const result = ht.get(name);
        try std.testing.expect(result != null);
        try std.testing.expectEqual(result.?.int_val, @as(i32, @intCast(j)));
    }
}

test "HashTable: resize triggered by load factor (>70%)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var ht = HashTable.init(alloc, 2);
    defer ht.deinit(alloc);

    var i: usize = 0;
    while (i < 20) : (i += 1) {
        var name_buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "item{}", .{i});
        ht.put(alloc, name, VariableValue{ .vtype = .int, .int_val = @intCast(i * 2) });
    }

    var j: usize = 0;
    while (j < 20) : (j += 1) {
        var name_buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "item{}", .{j});
        const result = ht.get(name);
        try std.testing.expect(result != null);
        try std.testing.expectEqual(result.?.int_val, @as(i32, @intCast(j * 2)));
    }
}

test "HashTable: update value changes vtype" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var ht = HashTable.init(alloc, 8);
    defer ht.deinit(alloc);

    ht.put(alloc, "x", VariableValue{ .vtype = .int, .int_val = 1 });
    ht.put(alloc, "x", VariableValue{ .vtype = .string, .str_val = "hello" });

    const result = ht.get("x");
    try std.testing.expectEqual(result.?.vtype, .string);
    try std.testing.expectEqualSlices(u8, result.?.str_val, "hello");
}

test "HashTable: empty key" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var ht = HashTable.init(alloc, 8);
    defer ht.deinit(alloc);

    ht.put(alloc, "", VariableValue{ .vtype = .int, .int_val = 99 });

    const result = ht.get("");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(result.?.int_val, 99);
}

test "HashTable: string value stored and retrieved" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var ht = HashTable.init(alloc, 8);
    defer ht.deinit(alloc);

    ht.put(alloc, "str", VariableValue{ .vtype = .string, .str_val = "hello" });

    const result = ht.get("str");
    try std.testing.expectEqual(result.?.vtype, VariableType.string);
    try std.testing.expectEqualSlices(u8, result.?.str_val, "hello");
}

test "HashTable: function value stored and retrieved" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var ht = HashTable.init(alloc, 8);
    defer ht.deinit(alloc);

    ht.put(alloc, "fn", VariableValue{ .vtype = .function, .func_ptr = 0xCADE });

    const result = ht.get("fn");
    try std.testing.expectEqual(result.?.vtype, VariableType.function);
    try std.testing.expectEqual(result.?.func_ptr, 0xCADE);
}

test "HashTable: float value stored and retrieved" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var ht = HashTable.init(alloc, 8);
    defer ht.deinit(alloc);

    ht.put(alloc, "pi", VariableValue{ .vtype = .float, .float_val = 3.14159 });

    const result = ht.get("pi");
    try std.testing.expectEqual(result.?.vtype, VariableType.float);
    try std.testing.expectApproxEqAbs(result.?.float_val, 3.14159, 0.0001);
}

test "HashTable: long key" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var ht = HashTable.init(alloc, 8);
    defer ht.deinit(alloc);

    const long_key = "this_is_a_very_long_key_name_that_should_work";
    ht.put(alloc, long_key, VariableValue{ .vtype = .int, .int_val = 1 });

    const result = ht.get(long_key);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(result.?.int_val, 1);
}

test "HashTable: case sensitivity" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var ht = HashTable.init(alloc, 8);
    defer ht.deinit(alloc);

    ht.put(alloc, "Key", VariableValue{ .vtype = .int, .int_val = 1 });
    ht.put(alloc, "key", VariableValue{ .vtype = .int, .int_val = 2 });

    try std.testing.expectEqual(ht.get("Key").?.int_val, 1);
    try std.testing.expectEqual(ht.get("key").?.int_val, 2);
}

test "HashTable: count after put" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var ht = HashTable.init(alloc, 16);
    defer ht.deinit(alloc);

    try std.testing.expectEqual(ht.count, 0);
    ht.put(alloc, "a", VariableValue{ .vtype = .int, .int_val = 1 });
    try std.testing.expectEqual(ht.count, 1);
    ht.put(alloc, "b", VariableValue{ .vtype = .int, .int_val = 2 });
    try std.testing.expectEqual(ht.count, 2);
    ht.put(alloc, "a", VariableValue{ .vtype = .int, .int_val = 3 }); // overwrite
    try std.testing.expectEqual(ht.count, 2); // count should not increase on overwrite
}

test "HashTable: remove existing key" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var ht = HashTable.init(alloc, 8);
    defer ht.deinit(alloc);

    ht.put(alloc, "a", VariableValue{ .vtype = .int, .int_val = 1 });
    try std.testing.expect(ht.remove(alloc, "a"));
    try std.testing.expect(ht.get("a") == null);
}

test "HashTable: remove non-existent key" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var ht = HashTable.init(alloc, 8);
    defer ht.deinit(alloc);

    try std.testing.expect(!ht.remove(alloc, "nonexistent"));
}

test "HashTable: remove preserves other keys" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var ht = HashTable.init(alloc, 8);
    defer ht.deinit(alloc);

    ht.put(alloc, "a", VariableValue{ .vtype = .int, .int_val = 1 });
    ht.put(alloc, "b", VariableValue{ .vtype = .int, .int_val = 2 });
    try std.testing.expect(ht.remove(alloc, "a"));

    try std.testing.expect(ht.get("a") == null);
    try std.testing.expectEqual(ht.get("b").?.int_val, 2);
}

test "HashTable: empty table get returns null" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var ht = HashTable.init(alloc, 0);
    // Size 0 — should not crash
    try std.testing.expect(ht.get("anything") == null);
}

test "HashTable: many keys stress test" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var ht = HashTable.init(alloc, 16);
    defer ht.deinit(alloc);

    var i: usize = 0;
    while (i < 50) : (i += 1) {
        var name_buf: [64]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "var_{}", .{i});
        ht.put(alloc, name, VariableValue{ .vtype = .int, .int_val = @intCast(i) });
    }

    var j: usize = 0;
    while (j < 50) : (j += 1) {
        var name_buf: [64]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "var_{}", .{j});
        const result = ht.get(name);
        try std.testing.expect(result != null);
        try std.testing.expectEqual(result.?.int_val, @as(i32, @intCast(j)));
    }
}
