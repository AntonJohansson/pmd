const std = @import("std");

pub fn BoundedArray(T: type, N: usize) type {
    return struct {
        data: [N]T = undefined,
        used: usize = 0,

        const Self = @This();

        pub fn append(self: *Self, t: T) void {
            std.debug.assert(self.used < self.data.len);
            self.data[self.used] = t;
            self.used += 1;
        }

        pub fn slice(self: *Self) []T {
            return self.data[0..self.used];
        }

        pub fn swap_remove(self: *Self, index: usize) T {
            std.debug.assert(index < self.used);
            const tmp = self.data[index];
            self.data[index] = self.data[self.used - 1];
            self.used -= 1;
            return tmp;
        }

        pub fn last(self: *Self) *T {
            std.debug.assert(self.used > 0);
            return &self.data[self.used - 1];
        }
    };
}
