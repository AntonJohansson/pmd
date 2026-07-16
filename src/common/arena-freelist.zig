const std = @import("std");
const assert = std.debug.assert;
const Arena = @import("arena.zig").Arena;

pub const ArenaFreelist = struct {
    const Self = @This();

    const Header = struct {
        next: ?* Header = null,
        size: usize,
    };

    arena: *Arena,
    freelist: ?*Header = null,

    pub fn alloc(self: *Self, comptime T: type, len: usize) []T {
        var maybe = &self.freelist;
        var prev = &self.freelist;
        const size = len * @sizeOf(T);
        while (maybe.* != null) {
            const ptr = maybe.*.?;
            if (ptr.size >= size) {
                prev.* = ptr.next;
                return @as([*]T, @ptrFromInt(@intFromPtr(ptr) + @sizeOf(Header)))[0..len];
            }
            prev = maybe;
            maybe = &ptr.next;
        }

        const memory = self.arena.alloc_aligned(u8, size + @sizeOf(Header), @alignOf(Header));
        const header: *Header = @ptrCast(memory.ptr);
        header.* = .{
            .size = size,
        };
        return @as([*]T, @ptrFromInt(@intFromPtr(header) + @sizeOf(Header)))[0..len];
    }

    pub fn free(self: *Self, memory: anytype) void {
        const ti = @typeInfo(@TypeOf(memory));
        if (ti != .pointer or ti.pointer.size != .slice) {
            @compileError("can only free slices");
        }
        const ptr: [*]u8 = @ptrCast(memory.ptr);
        const header: *Header = @alignCast(@ptrCast(ptr - @sizeOf(Header)));
        const size = memory.len * @sizeOf(ti.pointer.child);
        if (self.freelist != null and @as([*]u8, @ptrCast(self.freelist.?)) == ptr + size) {
            @branchHint(.unlikely);
            header.size += self.freelist.?.size;
            header.next = self.freelist.?.next;
            self.freelist = @alignCast(header);
        } else {
            header.next = self.freelist;
            self.freelist = @alignCast(header);
        }
    }

    pub fn realloc(self: *Self, memory: anytype, newlen: usize) []@typeInfo(@TypeOf(memory)).pointer.child {
        const ti = @typeInfo(@TypeOf(memory));
        if (ti != .pointer or ti.pointer.size != .slice) {
            @compileError("can only free slices");
        }
        assert(newlen > memory.len);
        const T = ti.pointer.child;
        const newmemory = self.alloc(T, newlen);
        if (memory.len > 0) {
            @branchHint(.likely);
            @memcpy(newmemory[0..memory.len], memory);
            self.free(memory);
        }
        return newmemory;
    }
};
