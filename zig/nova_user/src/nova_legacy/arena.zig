const user = @import("../user.zig");

pub const Arena = struct {
    const CHUNK_SIZE = 64 * 1024;

    const Chunk = struct {
        data: []u8,
        offset: usize,
        next: ?*Chunk,
    };

    head: *Chunk,
    current: *Chunk,

    pub fn init() Arena {
        const chunk_ptr = user.user_malloc(@sizeOf(Chunk)) orelse unreachable;
        const data_ptr = user.user_malloc(CHUNK_SIZE) orelse unreachable;
        const chunk: *Chunk = @ptrCast(@alignCast(chunk_ptr));
        chunk.* = .{
            .data = data_ptr[0..CHUNK_SIZE],
            .offset = 0,
            .next = null,
        };
        return .{
            .head = chunk,
            .current = chunk,
        };
    }

    fn grow(self: *Arena) void {
        const chunk_ptr = user.user_malloc(@sizeOf(Chunk)) orelse unreachable;
        const data_ptr = user.user_malloc(CHUNK_SIZE) orelse unreachable;
        const chunk: *Chunk = @ptrCast(@alignCast(chunk_ptr));
        chunk.* = .{
            .data = data_ptr[0..CHUNK_SIZE],
            .offset = 0,
            .next = null,
        };
        self.current.next = chunk;
        self.current = chunk;
    }

    fn alignForward(addr: usize, alignment: usize) usize {
        return (addr + alignment - 1) & ~(alignment - 1);
    }

    pub fn alloc(self: *Arena, comptime T: type) *T {
        const aligned = alignForward(self.current.offset, @alignOf(T));
        if (aligned + @sizeOf(T) > self.current.data.len) {
            self.grow();
            return self.alloc(T);
        }
        const ptr: *T = @ptrCast(@alignCast(self.current.data.ptr + aligned));
        self.current.offset = aligned + @sizeOf(T);
        return ptr;
    }

    pub fn allocBytes(self: *Arena, size: usize) []u8 {
        if (self.current.offset + size > self.current.data.len) {
            self.grow();
            return self.allocBytes(size);
        }
        const slice = self.current.data[self.current.offset..][0..size];
        self.current.offset += size;
        return slice;
    }

    pub fn reset(self: *Arena) void {
        var maybe: ?*Chunk = self.head;
        while (maybe) |chunk| {
            const next = chunk.next;
            user.user_free(chunk.data.ptr);
            user.user_free(@ptrCast(chunk));
            maybe = next;
        }
    }
};
