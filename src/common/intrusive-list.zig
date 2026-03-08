const std = @import("std");
const assert = std.debug.assert;

const common = @import("common");
const Arena = common.Arena;

pub fn IntrusiveList(comptime T: type) type {
    return struct {
        const Self = @This();

        const Item = struct {
            next: ?*Item = null,
            value: T = undefined,
        };

        arena: *Arena = undefined,
        head: ?*Item = null,
        tail: ?*Item = null,
        
        pub fn append(self: *Self) *T {
            const item = &self.arena.alloc(Item, 1)[0];
            item.* = .{};
            if (self.head == null) {
                @branchHint(.unlikely);
                self.head = item;
                self.tail = item;
            } else {
                self.tail.next = item;
                self.tail = item;
            }
            return &item.value;
        }

        pub fn pop(self: *Self) T {
            assert(self.head);
            const res = self.head.?.value;
            self.head = self.head.next;
            return res;
        }
    };
}
