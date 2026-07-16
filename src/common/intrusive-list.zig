const std = @import("std");
const assert = std.debug.assert;

const Arena = @import("arena.zig").Arena;

pub fn IntrusiveList(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Item = struct {
            next: ?*Item = null,
            value: T = undefined,
        };

        arena: *Arena = undefined,
        head: ?*Item = null,
        tail: ?*Item = null,

        pub fn append(self: *Self, t: T) void {
            const item = &self.arena.alloc(Item, 1)[0];
            item.* = .{
                .value = t,
            };
            if (self.head == null) {
                @branchHint(.unlikely);
                self.head = item;
                self.tail = item;
            } else {
                self.tail.?.next = item;
                self.tail = item;
            }
        }

        pub fn sublist(self: *Self) Self {
            return .{
                .arena = self.arena,
            };
        }

        pub fn join_right(self: *Self, sub: *Self) void {
            self.tail.?.next = sub.head;
            self.tail = sub.tail;
        }

        pub fn pop(self: *Self) ?T {
            if (self.head == null) {
                return null;
            }
            const res = self.head.?.value;
            self.head = self.head.?.next;
            return res;
        }
    };
}
