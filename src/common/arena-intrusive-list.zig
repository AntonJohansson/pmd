const common = @import("common");
const Arena = common.Arena;

const std = @import("std");
const assert = std.debug.assert;

const ArenaIntrusiveList = struct {
    const Self = @This();

    const Header = struct {
        next: ?*Header = null,
        size: usize,
    };

    arena: *Arena,
    head: ?*align(1) Header = null,
    tail: ?*align(1) Header = null,
        
    pub fn alloc(self: *Self, size: usize) []u8 {
        const total_size = @sizeOf(Header) + size;

        if (total_size < self.arena.memory.len - self.arena.top) {
            const memory = self.arena.alloc(u8, total_size);
            const header: *align(1) Header = @ptrCast(memory.ptr);
            header.* = .{
                .size = size,
            };

            if (self.head == null) {
                @branchHint(.unlikely);
                self.head = header;
                self.tail = header;
            } else {
                self.tail.next = header;
                self.tail = header;
            }

            return memory[@sizeOf(Header)..];
        } else {
            @branchHint(.unlikely);
            self.arena.top = 0;
            // Drop data from head until we fit
            var maybe = self.head;
            while (maybe) |ptr| {
                if (self.arena.memory.ptr + total_size < ptr) {
                    break;
                }
                maybe = ptr.next;
            }

            const memory = self.arena.alloc(u8, total_size);
            const header: *align(1) Header = @ptrCast(memory.ptr);
            header.* = .{
                .size = size,
            };
            self.tail.next = header;
            self.tail = header;

            return memory[@sizeOf(Header)..];
        }
    }

    pub fn pop(self: *Self) []u8 {
        assert(self.head != null);
        const head = self.head;
        self.head = self.head.next;
        const ptr: [*]u8 = @ptrCast(self.head);
        return ptr[@sizeOf(Header)..head.size+@sizeOf(Header)];
    }
};
