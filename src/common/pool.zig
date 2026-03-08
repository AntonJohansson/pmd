const std = @import("std");
const Arena = @import("arena.zig").Arena;

pub fn Pool(comptime T: type) type {
    return struct {
        const Ptr = *align(@alignOf(T)) anyopaque;
        const Self = @This();

        arena: Arena = undefined,
        freelist: ?Ptr = null,

        pub fn alloc(self: *Self) *T {
            if (self.freelist) |ptr| {
                self.freelist = @as(*?Ptr, @ptrCast(ptr)).*;
                return @ptrCast(ptr);
            }
            return @ptrCast(self.arena.alloc(T, 1).ptr);
        }

        pub fn free(self: *Self, ptr: *T) void {
            const listptr: *?Ptr = @ptrCast(ptr);
            listptr.* = self.freelist;
            self.freelist = @ptrCast(listptr);
        }
    };
}
