const std = @import("std");

fn memory_size_of_int_type(comptime T: type) usize {
    return @divFloor(@typeInfo(T).int.bits + 7, 8);
}

fn read_int(comptime T: type, bytes: []u8, offset: *usize) T {
    const size = comptime memory_size_of_int_type(T);
    const b: *[size]u8 = @ptrCast(bytes.ptr + offset.*);
    const NewT = std.meta.Int(@typeInfo(T).int.signedness, 8 * size);
    const value = std.mem.readInt(NewT, b, .little);
    offset.* += size;
    return @truncate(value);
}

pub fn memory_read_type(allocator: std.mem.Allocator, comptime T: type, bytes: []u8, offset: *usize, value: anytype) void {
    const ti = @typeInfo(T);
    switch (ti) {
        .bool => {
            const b: *u8 = @ptrCast(bytes.ptr + offset.*);
            value.* = (b.* != 0);
            offset.* += memory_size_of_int_type(u8);
        },
        .int => {
            value.* = read_int(T, bytes, offset);
        },
        .@"enum" => |e| {
            value.* = @enumFromInt(read_int(e.tag_type, bytes, offset));
        },
        .float => |f| {
            const IntT = std.meta.Int(.unsigned, f.bits);
            value.* = @as(T, @bitCast(read_int(IntT, bytes, offset)));
        },
        .pointer => |ptr| {
            std.debug.assert(ptr.size == .slice);

            const len = read_int(u64, bytes, offset);

            if (@typeInfo(ptr.child) == .int or @typeInfo(ptr.child) == .float) {
                offset.* = align_int_to(offset.*, @alignOf(ptr.child));
                const src_ptr: [*]align(@alignOf(ptr.child)) u8 = @ptrCast(@alignCast(bytes[offset.*..]));
                value.* = @as([*]ptr.child, @ptrCast(src_ptr))[0..len];
                offset.* += len * @sizeOf(ptr.child);
            } else {
                const slice = allocator.alloc(ptr.child, len) catch unreachable;
                for (slice) |*v| {
                    memory_read_type(allocator, ptr.child, bytes, offset, v);
                }
                value.* = slice;
            }
        },
        .array => |arr| {
            for (value) |*v| {
                memory_read_type(allocator, arr.child, bytes, offset, v);
            }
        },
        .@"struct" => |s| {
            inline for (s.fields) |field| {
                memory_read_type(allocator, field.type, bytes, offset, &@field(value, field.name));
            }
        },
        .optional => |o| {
            const nonnull = read_int(u8, bytes, offset);
            if (nonnull != 0) {
                var tmp: o.child = undefined;
                memory_read_type(allocator, o.child, bytes, offset, &tmp);
                value.* = tmp;
            } else {
                value.* = null;
            }
        },
        else => @compileError("Unhandled type in reading data " ++ @typeName(T)),
    }
}

pub fn memory_write_type(builder: *StringBuilder, value: anytype) !void {
    const base_type = @TypeOf(value);
    const ti = @typeInfo(base_type);

    switch (ti) {
        .bool => {
            try builder.write_int(u8, @intFromBool(value));
        },
        .int => {
            try builder.write_int(base_type, value);
        },
        .float => {
            try builder.write_float(base_type, value);
        },
        .@"enum" => |e| {
            try builder.write_int(e.tag_type, @intFromEnum(value));
        },
        .pointer => |ptr| {
            std.debug.assert(ptr.size == .slice);
            try builder.write_int(u64, @as(u64, @intCast(value.len)));

            if (@typeInfo(ptr.child) == .int or @typeInfo(ptr.child) == .float) {
                const num_bytes = @sizeOf(ptr.child) * value.len;
                const byte_slice: [*]const u8 = @ptrCast(value.ptr);
                try builder.align_to(@alignOf(ptr.child));
                try builder.write_bytes(byte_slice[0..num_bytes]);
            } else {
                for (value) |v| {
                    try memory_write_type(builder, v);
                }
            }
        },
        .array => {
            for (value) |v| {
                try memory_write_type(builder, v);
            }
        },
        .@"struct" => |s| {
            inline for (s.fields) |field| {
                try memory_write_type(builder, @field(value, field.name));
            }
        },
        .optional => {
            if (value != null) {
                try builder.write_int(u8, 1);
                try memory_write_type(builder, value.?);
            } else {
                try builder.write_int(u8, 0);
            }
        },
        else => @compileError("Unhandled type in writing data " ++ @typeName(base_type)),
    }
}

fn align_int_to(value: usize, alignment: u8) usize {
    return alignment * @divFloor(value + alignment - 1, alignment);
}

const Segment = struct {
    used: usize = undefined,
    data: []u8 = undefined,
    num_writes: u16 = 0,
};

pub const StringBuilder = struct {
    segments: std.ArrayList(Segment) = undefined,
    allocator: std.mem.Allocator = undefined,
    arena: std.heap.ArenaAllocator = undefined,
    insert: usize = 0,
    last_segment: ?Segment = null,
    append: bool = true,
    base_offset: usize = 0,
    segment_size: usize = 4096,

    pub fn init(allocator: std.mem.Allocator) StringBuilder {
        return StringBuilder{
            .segments = std.ArrayList(Segment){},
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *StringBuilder) void {
        self.segments.deinit(self.allocator);
        self.arena.deinit();
    }

    pub fn clear(self: *StringBuilder) void {
        self.segments.clear();
        self.arena.clear();
        const arena = self.arena;
        const segments = self.arena;
        const allocator = self.allocator;
        self.* = .{
            .segments = segments,
            .allocator = allocator,
            .arena = arena,
        };
    }

    fn addSegmentBySlice(self: *StringBuilder, bytes: []u8) !void {
        try self.segments.insert(self.allocator, self.insert, Segment{
            .data = bytes,
            .used = bytes.len,
        });
        if (self.segments.items.len > 0) {
            self.insert += 1;
        }
        self.append = true;
    }

    fn add_segment_by_size(self: *StringBuilder, size: usize) !*Segment {
        const actual_size = @max(size, self.segment_size);
        std.log.info("add_segment_by_size: {} {}", .{ size, actual_size });
        const slice = try self.arena.allocator().alloc(u8, actual_size);
        try self.segments.insert(self.allocator, self.insert, Segment{
            .data = slice,
            .used = 0,
        });
        if (self.segments.items.len > 0) {
            self.insert += 1;
        }
        self.append = true;
        return &self.segments.items[self.insert - 1];
    }

    fn get_last_segment(self: *StringBuilder) ?*Segment {
        const len = self.segments.items.len;
        if (len == 0 or self.insert > len or self.insert == 0 or !self.append and self.segments.items[self.insert - 1].used > 0) {
            return null;
        }
        std.debug.assert(self.insert > 0);
        return &self.segments.items[self.insert - 1];
    }

    pub fn get_size(self: *StringBuilder) usize {
        var size: usize = 0;
        for (self.segments.items) |s| {
            size += s.used;
        }
        return size;
    }

    pub fn get_offset(self: *StringBuilder) usize {
        var offset: usize = self.base_offset;
        for (self.segments.items[0..self.insert]) |s| {
            offset += s.used;
        }
        return offset;
    }

    fn align_to(self: *StringBuilder, alignment: u8) !void {
        if (self.get_last_segment()) |last| {
            const offset = self.get_offset();
            const start = offset - last.used;
            if (offset % alignment != 0) {
                const next = align_int_to(offset, alignment);
                const next_offset = next - start;
                std.debug.assert(next_offset < last.data.len);
                last.used = next_offset;
            }
        }
    }

    fn get_segment_fitting(self: *StringBuilder, size: usize) !*Segment {
        if (self.get_last_segment()) |last| {
            const free = last.data.len - last.used;
            if (size <= free) {
                std.log.info("Returning last segment {}/{}!", .{ last.used, last.data.len });
                return last;
            }
        }

        return try self.add_segment_by_size(size);
    }

    pub fn write_bytes(self: *StringBuilder, bytes: []const u8) !void {
        const segment = try self.get_segment_fitting(bytes.len);
        @memcpy(segment.data[segment.used..(segment.used + bytes.len)], bytes);
        segment.num_writes += 1;
        segment.used += bytes.len;
    }

    fn write_int(self: *StringBuilder, comptime T: type, value: T) !void {
        const size = comptime memory_size_of_int_type(T);
        var buf: [size]u8 = undefined;
        std.mem.writeInt(std.meta.Int(@typeInfo(T).int.signedness, 8 * size), &buf, value, .little);
        try self.write_bytes(&buf);
    }

    fn write_float(self: *StringBuilder, comptime T: type, value: T) !void {
        const IntT = std.meta.Int(.unsigned, @typeInfo(T).float.bits);
        try self.write_int(IntT, @bitCast(value));
    }

    pub fn dump_to_buffer(self: *StringBuilder, allocator: std.mem.Allocator) ![]u8 {
        const size = self.get_size();
        std.debug.assert(size > 0);
        const slice = try allocator.alloc(u8, size);
        var i: usize = 0;
        for (self.segments.items) |s| {
            @memcpy(slice[i..(s.used + i)], s.data[0..s.used]);
            i += s.used;
        }
        return slice;
    }

    pub fn dump_to_file(self: *StringBuilder, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        const writer = file.writer();
        defer file.close();
        for (self.segments.items) |s| {
            try writer.writeAll(s.data[0..s.used]);
        }
    }
};
