const std = @import("std");
const assert = std.debug.assert;

const common = @import("common");
const Arena = common.Arena;

pub fn ArrayRealloc(T: type) type {
    return struct {
        const Self = @This();

        arena: *Arena,
        data: []T = undefined,
        used: usize = 0,

        pub fn reserve(self: *Self, len: usize) void {
            assert(self.used == 0);
            self.data = self.arena.alloc(T, len);
        }

        pub fn append(self: *Self) *T {
            if (self.used >= self.data.len) {
                @branchHint(.unlikely);
                // realloc
                const new = self.arena.alloc(T, self.data.len);
                @memcpy(new, self.arena.data);
                self.data = new;
            }
            return &self.data[self.used];
        }
    };
}
