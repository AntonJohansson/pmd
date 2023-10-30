const std = @import("std");

pub const ByteBufferSlice = struct {
    data: []u8 = undefined,
    top: u32 = 0,
    bottom: u32 = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, comptime N: u32) Self {
        return Self {
            .data = allocator.alloc(u8, N) catch unreachable,
        };
    }

    pub fn clear(self: *Self) void {
        self.top = 0;
        self.bottom = 0;
    }

    pub fn push(self: *Self, data: anytype) void {
        std.debug.assert(self.top + @sizeOf(@TypeOf(data)) <= self.data.len);
        const DataPtr = *align(1) @TypeOf(data);
        @as(DataPtr, @ptrCast(&self.data[self.top])).* = data;
        self.top += @sizeOf(@TypeOf(data));
    }

    pub fn pop(self: *Self, comptime T: type) T {
        std.debug.assert(self.bottom + @sizeOf(T) <= self.top);
        const t = @as(*align(1) T, @ptrCast(&self.data[self.bottom])).*;
        self.bottom += @sizeOf(T);
        return t;
    }

    pub fn size(self: *Self) usize {
        return self.top - self.bottom;
    }

    pub fn remainingSize(self: *Self) usize {
        return self.data.len - self.top;
    }

    pub fn remainingData(self: *Self) []u8 {
        return self.data[self.top..];
    }

    pub fn hasData(self: *Self) bool {
        return self.size() > 0;
    }
};

pub fn ByteBuffer(comptime N: u32) type {
    return struct {
        data: [N]u8 = undefined,
        top: u32 = 0,
        bottom: u32 = 0,

        const Self = @This();

        pub fn clear(self: *Self) void {
            self.top = 0;
            self.bottom = 0;
        }

        pub fn push(self: *Self, data: anytype) void {
            std.debug.assert(self.top + @sizeOf(@TypeOf(data)) <= self.data.len);
            const DataPtr = *align(1) @TypeOf(data);
            @as(DataPtr, @ptrCast(&self.data[self.top])).* = data;
            self.top += @sizeOf(@TypeOf(data));
        }

        pub fn pop(self: *Self, comptime T: type) T {
            std.debug.assert(self.bottom + @sizeOf(T) <= self.top);
            const t = @as(*align(1) T, @ptrCast(&self.data[self.bottom])).*;
            self.bottom += @sizeOf(T);
            return t;
        }

        pub fn size(self: *Self) usize {
            return self.top - self.bottom;
        }

        pub fn remainingSize(self: *Self) usize {
            return self.data.len - self.top;
        }

        pub fn remainingData(self: *Self) []u8 {
            return self.data[self.top..];
        }

        pub fn hasData(self: *Self) bool {
            return self.size() > 0;
        }
    };
}

pub const ByteView = struct {
    data: []u8 = undefined,
    bottom: u16 = 0,

    const Self = @This();

    pub fn pop(self: *Self, comptime T: type) *align(1) const T {
        std.debug.assert(self.bottom + @sizeOf(T) <= self.data.len);
        const ptr = @as(*const align(1) T, @ptrCast(&self.data[self.bottom]));
        self.bottom += @sizeOf(T);
        return ptr;
    }

    pub fn advance(self: *Self, amount: u16) void {
        std.debug.assert(self.bottom + amount <= self.data.len);
        self.bottom += amount;
    }

    pub fn hasData(self: *Self) bool {
        return self.bottom < self.data.len;
    }

    pub fn hasSpaceFor(self: *Self, space: u16) bool {
        return self.bottom + space <= self.data.len;
    }

    pub fn remainingSpace(self: *Self) u16 {
        return @as(u16, @intCast(self.data.len)) - self.bottom;
    }
};

pub fn CircularArray(comptime T: type, comptime size: usize) type {
    return struct {
        data: [size]T = undefined,
        size: usize =  0,
        bottom: usize = 0,

        // Don't like this api
        pub fn push(self: *@This()) *T {
            std.debug.assert(self.size+1 <= self.data.len);
            const index = (self.bottom + self.size) % self.data.len;
            self.size += 1;
            return &self.data[index];
        }

        pub fn pop(self: *@This()) T {
            const element = self.peek();
            self.bottom = (self.bottom + 1) % self.data.len;
            self.size -= 1;
            return element.*;
        }

        pub fn peek(self: *@This()) *T {
            std.debug.assert(self.size > 0);
            return &self.data[self.bottom];
        }
    };
}

pub fn CircularBuffer(comptime T: type, comptime max_len: usize) type {
    return struct {
        data: [max_len]T = undefined,
        top: usize = 0,

        pub fn push(self: *@This(), element: T) void {
            self.top = (self.top + 1) % self.data.len;
            self.data[self.top] = element;
        }

        pub fn peek(self: *@This()) T {
            return self.data[self.top];
        }

        pub fn peekRelative(self: *@This(), offset: i64) T {
            const index: usize = @intCast(@mod(@as(i64, @intCast(self.top)) + @as(i64, @intCast(self.data.len)) + offset, @as(i64, @intCast(self.data.len))));
            return self.data[index];
        }
    };
}

pub fn SequenceBuffer(comptime DataType: type, comptime SequenceType: type, comptime len: usize) type {
    return struct{
        const invalid_sequence_number: SequenceType = ~@as(SequenceType, 0);

        index_map: [len]SequenceType = [_]SequenceType{invalid_sequence_number}**len,
        data: [len]DataType = undefined,

        const Self = @This();

        pub fn set(self: *Self, sequence_number: SequenceType, data: DataType) void {
            const index = sequence_number % self.index_map.len;
            self.index_map[index] = sequence_number;
            self.data[index] = data;
        }

        pub fn get(self: *Self, sequence_number: SequenceType) ?*DataType {
            const index = sequence_number % self.index_map.len;
            if (self.index_map[index] == sequence_number) {
                return &self.data[index];
            } else {
                return null;
            }
        }

        pub fn unset(self: *Self, sequence_number: SequenceType) void {
            const index = sequence_number % self.index_map.len;
            self.index_map[index] = invalid_sequence_number;
        }

        pub fn isset(self: *Self, sequence_number: SequenceType) bool {
            const index = sequence_number % self.index_map.len;
            return self.index_map[index] != invalid_sequence_number;
        }

        pub fn clear(self: *Self) void {
            @memset(&self.index_map, invalid_sequence_number);
        }
    };
}
