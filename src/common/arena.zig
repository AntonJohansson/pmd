const std = @import("std");
const assert = std.debug.assert;

pub const Arena = struct {
    memory: []u8,
    top: usize = 0,
    const Self = @This();

    pub fn alloc_aligned(self: *Self, comptime T: type, len: usize, comptime al: usize) []align(al) T {
        const size = @sizeOf(T) * len;
        const top = al * @divTrunc(self.top + al - 1, al);
        assert(size < self.memory.len - top);
        const aligned: []align(al) u8 = @alignCast(self.memory[top .. top + size]);
        const res: []align(al) T = @ptrCast(aligned);
        self.top = top + size;
        return @ptrCast(res);
    }

    pub fn alloc(self: *Self, comptime T: type, len: usize) []T {
        return self.alloc_aligned(T, len, @alignOf(T));
    }
};
