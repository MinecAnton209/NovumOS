// Nova Language - Hash Table for Symbol Storage
const common = @import("common.zig");
const memory = @import("../memory.zig");

pub const Entry = struct {
    key: []const u8,
    value: VariableValue,
    occupied: bool = false,
};

pub const VariableType = enum {
    string,
    int,
    float,
    function, // For function pointers (token index)
};

pub const VariableValue = struct {
    vtype: VariableType,
    str_val: []const u8 = "",
    int_val: i32 = 0,
    float_val: f32 = 0.0,
    func_ptr: usize = 0, // Index in token list
};

pub const HashTable = struct {
    entries: [*]Entry,
    size: usize,
    count: usize,

    pub fn init(initial_size: usize) HashTable {
        const ptr = memory.heap.alloc(initial_size * @sizeOf(Entry)) orelse {
            return .{ .entries = undefined, .size = 0, .count = 0 };
        };
        const entries: [*]Entry = @ptrCast(@alignCast(ptr));
        for (0..initial_size) |i| {
            entries[i] = .{ .key = "", .value = undefined, .occupied = false };
        }
        return .{
            .entries = entries,
            .size = initial_size,
            .count = 0,
        };
    }

    fn hash(key: []const u8) u32 {
        var h: u32 = 5381;
        for (key) |c| {
            h = (h << 5) +% h +% @as(u32, c); // djb2
        }
        return h;
    }

    pub fn put(self: *HashTable, key: []const u8, value: VariableValue) void {
        // Expand if load factor > 70%
        if (self.count * 10 > self.size * 7) {
            self.resize(self.size * 2);
        }

        var index = hash(key) % self.size;
        while (self.entries[index].occupied) {
            if (common.streq(self.entries[index].key, key)) {
                self.entries[index].value = value;
                return;
            }
            index = (index + 1) % self.size;
        }

        // Copy key to heap to ensure it's persistent
        // In a real VM, we might have a string pool. For now, we'll alloc.
        const key_copy_ptr = memory.heap.alloc(key.len) orelse return;
        const key_copy = key_copy_ptr[0..key.len];
        common.copy(key_copy, key);

        self.entries[index].key = key_copy;
        self.entries[index].value = value;
        self.entries[index].occupied = true;
        self.count += 1;
    }

    pub fn get(self: *HashTable, key: []const u8) ?VariableValue {
        if (self.size == 0) return null;
        var index = hash(key) % self.size;
        const start_index = index;

        while (self.entries[index].occupied) {
            if (common.streq(self.entries[index].key, key)) {
                return self.entries[index].value;
            }
            index = (index + 1) % self.size;
            if (index == start_index) break;
        }
        return null;
    }

    fn resize(self: *HashTable, new_size: usize) void {
        const old_entries = self.entries;
        const old_size = self.size;

        const ptr = memory.heap.alloc(new_size * @sizeOf(Entry)) orelse return;
        self.entries = @ptrCast(@alignCast(ptr));
        self.size = new_size;
        self.count = 0;

        for (0..new_size) |i| {
            self.entries[i] = .{ .key = "", .value = undefined, .occupied = false };
        }

        for (0..old_size) |i| {
            if (old_entries[i].occupied) {
                self.put_internal(old_entries[i].key, old_entries[i].value);
            }
        }

        memory.heap.free(@ptrCast(old_entries));
    }

    // Put for resize - doesn't copy key again
    fn put_internal(self: *HashTable, key: []const u8, value: VariableValue) void {
        var index = hash(key) % self.size;
        while (self.entries[index].occupied) {
            index = (index + 1) % self.size;
        }
        self.entries[index].key = key;
        self.entries[index].value = value;
        self.entries[index].occupied = true;
        self.count += 1;
    }

    pub fn deinit(self: *HashTable) void {
        if (self.size > 0) {
            // We should also free the keys we allocated
            for (0..self.size) |i| {
                if (self.entries[i].occupied) {
                    memory.heap.free(@ptrCast(@constCast(self.entries[i].key.ptr)));
                }
            }
            memory.heap.free(@ptrCast(self.entries));
        }
    }
};
