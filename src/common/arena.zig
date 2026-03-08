const std = @import("std");
const assert = std.debug.assert;

pub const Arena = struct {
    memory: []u8,
    top: usize = 0,
    const Self = @This();

    pub fn alloc(self: *Self, comptime T: type, len: usize) []T {
        const size = @sizeOf(T) * len;
        const al = @alignOf(T);
        const top = al*@divTrunc(self.top + al - 1, al);
        assert(size < self.memory.len - top);
        const aligned: []align(@alignOf(T))u8 = @alignCast(self.memory[top..top+size]);
        const res: []T = @ptrCast(aligned);
        self.top = top + size;
        return @ptrCast(res);
    }
};
