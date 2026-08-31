const std = @import("std");
const assert = std.debug.assert;

const common = @import("common.zig");
const Arena = common.Arena;

pub fn ArrayRealloc(T: type, comptime size: usize) type {
    return struct {
        const Self = @This();

        arena: *Arena = undefined,
        data: []T = undefined,
        used: usize = 0,

        pub fn slice(self: *Self) []T {
            return self.data[0..self.used];
        }

        pub fn reset(self: *Self) void {
            self.used = 0;
        }

        pub fn reserve(self: *Self, len: usize) void {
            assert(self.used == 0);
            self.data = self.arena.alloc(T, len);
        }

        pub fn append(self: *Self, value: T) void {
            if (self.used == 0 or self.used >= self.data.len) {
                @branchHint(.unlikely);
                // realloc
                const new = self.arena.alloc(T, self.used / size + size);
                @memcpy(new, self.data);
                self.data = new;
            }
            self.data[self.used] = value;
            self.used += 1;
        }
    };
}
