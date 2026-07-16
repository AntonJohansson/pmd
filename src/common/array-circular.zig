const std = @import("std");
const assert = std.debug.assert;

const common = @import("common");
const Arena = common.Arena;

pub fn ArrayCircular(T: type) type {
    return struct {
        const Self = @This();

        data: []T,
        end: usize = 0,
        len: usize = 0,

        pub fn advance(self: *Self, index: usize) usize {
            return (index + 1) % self.data.len;
        }

        pub fn start(self: *Self) usize {
            return (self.end + self.data.len - self.len) % self.data.len;
        }

        pub fn push(self: *Self) *T {
            const ptr = &self.data[self.end];
            self.end = self.advance(self.end);
            self.len += if (self.len < self.data.len) 1 else 0;
            return ptr;
        }

        pub fn pop(self: *Self) *T {
            std.debug.assert(self.len > 0);
            const s = self.start();
            const ptr = &self.data[s];
            self.len -= 1;
            return ptr;
        }

        pub fn at(self: *Self, index: usize) *T {
            std.debug.assert(index < self.len);
            return &self.data[(self.start() + index) % self.data.len];
        }

        pub fn swap_remove(self: *Self, index: usize) T {
            const i = (self.start() + index) % self.data.len;
            const value = self.data[i];
            self.data[i] = self.data[(self.end + self.data.len-1) % self.data.len];
            self.len -= 1;
            return value;
        }
    };
}
