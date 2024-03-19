const std = @import("std");
const res = @import("res.zig");

const format_version = 1;
const magic: u32 = 'g' | ('o' << 8) | ('s' << 16) | ('e' << 24);

pub const Header = struct {
    magic: u32 = magic,
    format_version: u8 = format_version,
    file_iteration: u16 = 0,
    entry_table_count: u16 = 0,
    entry_table_offset: u32 = 0,
};

pub const Entry = struct {
    type: ResourceType,
    offset: u32,
    size: u32 = 0,
    name: []const u8,
};

pub const Resource = union {
    text: res.Text,
    image: res.Image,
    cubemap: res.Cubemap,
    audio: res.Audio,
};

pub const ResourceType = enum(u8) {
    text,
    audio,
    cubemap,
    texture,
    shader,
    directory,
};

pub const Pack = struct {
    header: Header = .{},
    resources: ?std.ArrayList(Resource) = null,
    resource_dirty: ?std.ArrayList(bool) = null,
    entries: ?std.ArrayList(Entry) = null,
    bytes: ?[]u8 = null,
};

var frame: std.mem.Allocator = undefined;
var persistent: std.mem.Allocator = undefined;
pub fn setAllocators(_frame: std.mem.Allocator, _persistent: std.mem.Allocator) void {
    frame = _frame;
    persistent = _persistent;
}

pub fn init() Pack {
    var pack = Pack{};
    pack.resources      = std.ArrayList(Resource).init(persistent);
    pack.entries        = std.ArrayList(Entry).init(persistent);
    pack.resource_dirty = std.ArrayList(bool).init(persistent);
    return pack;
}

const DiskError = error {
    EmptyFile,
    InvalidMagic,
};

pub fn load(pack: *Pack, bytes: []u8) !void {
    var offset: usize = 0;
    memoryReadType(bytes, &offset, &pack.header);
    pack.header.file_iteration += 1;

    if (pack.header.magic != magic) {
        std.log.err("Invalid magic {}, expected {}", .{pack.header.magic, magic});
        return error.InvalidMagic;
    }

    if (pack.header.entry_table_count > 0) {
        var entries = try pack.entries.?.addManyAsSlice(pack.header.entry_table_count);
        try pack.resource_dirty.?.appendNTimes(false, pack.header.entry_table_count);
        offset = pack.header.entry_table_offset;
        for (entries) |*e| {
            memoryReadType(bytes, &offset, e);
        }
    }

    pack.bytes = bytes;
}

pub fn saveToMemory(pack: *Pack) !StringBuilder {
    var builder = StringBuilder.init(persistent);

    const header_size = memorySizeOfType(pack.header);
    if (pack.entries != null) {
        for (pack.entries.?.items, 0..) |*e, i| {
            if (pack.resource_dirty.?.items[i]) {
                const resource = pack.resources.?.items[e.offset];
                e.offset = @intCast(header_size + builder.getOffset());
                switch (e.type) {
                    .text    => try memoryWriteType(&builder, resource.text),
                    .texture => try memoryWriteType(&builder, resource.image),
                    .cubemap => try memoryWriteType(&builder, resource.cubemap),
                    .audio   => try memoryWriteType(&builder, resource.audio),
                    .shader  => unreachable,
                    else => unreachable,
                }
                e.size = @as(u32, @intCast(header_size + builder.getOffset())) - e.offset;
            } else if (pack.bytes) |bytes| {
                try builder.writeBytes(bytes[e.offset..(e.offset+e.size)]);
            } else {
                unreachable;
            }
        }

        pack.header.entry_table_count = @intCast(pack.entries.?.items.len);
        pack.header.entry_table_offset = @intCast(header_size + builder.getOffset());
        for (pack.entries.?.items) |e| {
            try memoryWriteType(&builder, e);
        }
    }

    // this is not working I believe
    builder.insert = 0;
    builder.append = false;
    try memoryWriteType(&builder, pack.header);

    return builder;
}

pub fn saveToFile(pack: *Pack, path: []const u8) !void {
    var builder = try saveToMemory(pack);
    defer builder.deinit();
    try builder.dumpToFile(path);
}


pub fn getResource(pack: *Pack, id: usize) Resource {
    const entry = pack.entries.?.items[id];
    var offset: usize = @intCast(entry.offset);
    var resource: Resource = undefined;
    switch (entry.type) {
        .text    => {resource = Resource{.text=.{}};    memoryReadType(pack.bytes.?, &offset, &resource.text);},
        .texture => {resource = Resource{.image=.{}};   memoryReadType(pack.bytes.?, &offset, &resource.image);},
        .cubemap => {resource = Resource{.cubemap=.{}}; memoryReadType(pack.bytes.?, &offset, &resource.cubemap);},
        .audio   => {resource = Resource{.audio=.{}};   memoryReadType(pack.bytes.?, &offset, &resource.audio);},
        else => unreachable,
    }
    return resource;
}

pub fn lookup(pack: *Pack, name: []const u8) Resource {
    // TODO(anjo): Use stringmap lookup
    for (pack.entries.?.items, 0..) |e,i| {
        if (std.mem.eql(u8, e.name, name)) {
            return getResource(pack, i);
        }
    }

    unreachable;
}

pub fn addResource(pack: *Pack, path: []const u8, res_type: ResourceType, resource: Resource) !void {
    const entry = try pack.entries.?.addOne();
    entry.offset = @intCast(pack.resources.?.items.len);
    try pack.resource_dirty.?.append(true);
    entry.type = res_type;
    entry.name = path;
    try pack.resources.?.append(resource);
}

//
// StringBuilder
//

const Segment = struct {
    used: usize = undefined,
    data: []u8 = undefined,
};

const StringBuilder = struct {
    segments: std.ArrayList(Segment),
    arena: std.heap.ArenaAllocator,
    insert: usize = 0,
    last_segment: ?Segment = null,
    append: bool = true,

    fn init(allocator: std.mem.Allocator) StringBuilder {
        return StringBuilder {
            .segments = std.ArrayList(Segment).init(allocator),
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    fn deinit(self: *StringBuilder) void {
        self.segments.deinit();
        self.arena.deinit();
    }

    fn addSegmentBySlice(self: *StringBuilder, bytes: []u8) !void {
        try self.segments.insert(self.insert, Segment{
            .data = bytes,
            .used = bytes.len,
        });
        if (self.segments.items.len > 0) {
            self.insert += 1;
        }
        self.append = true;
    }

    fn addSegmentBySize(self: *StringBuilder, size: usize) !void {
        //const rounded_size = 8*@divFloor(size + 8 - 1, 8);
        const slice = try self.arena.allocator().alloc(u8, size);
        try self.segments.insert(self.insert, Segment{
            .data = slice,
            .used = 0,
        });
        if (self.segments.items.len > 0) {
            self.insert += 1;
        }
        self.append = true;
    }
    
    fn getLastSegment(self: *StringBuilder) ?*Segment {
        const len = self.segments.items.len;
        if (len == 0 or self.insert > len or self.insert == 0 or !self.append and self.segments.items[self.insert-1].used > 0) {
            return null;
        }
        std.debug.assert(self.insert > 0);
        return &self.segments.items[self.insert-1];
    }

    fn getOffset(self: *StringBuilder) usize {
        var offset: usize = 0;
        for (self.segments.items) |s| {
            offset += s.used;
        }
        return offset;
    }

    fn getMemory(self: *StringBuilder, size: usize) ![]u8 {
        if (self.getLastSegment()) |last| {
            const free = last.data.len - last.used;
            if (free >= size) {
                const bytes = last.data[last.used..(last.used+size)];
                last.used += size;
                return bytes;
            }
        }

        // If we get to here, we need to allocate another segment
        const segment_size = 4096;
        std.debug.assert(size <= segment_size);
        try self.addSegmentBySize(segment_size);
        const last = self.getLastSegment() orelse unreachable;
        last.used += size;
        return last.data[0..size];
    }

    fn alignTo(self: *StringBuilder, alignment: u8) !void {
        if (self.getLastSegment()) |last| {
            if (last.used % alignment != 0) {
                const next = alignIntTo(last.used, alignment);
                if (next < last.data.len) {
                    last.used = next;
                } else {
                    last.used = last.data.len;
                }
            }
        }
    }

    fn writeBytes(self: *StringBuilder, bytes: []const u8) !void {
        // If the last segment has space, fill it as much as possible
        var start_offset: usize = 0;
        if (self.getLastSegment()) |last| {
            const free = @min(last.data.len - last.used, bytes.len);
            @memcpy(last.data[last.used..(last.used+free)], bytes[0..free]);
            last.used += free;
            start_offset += free;
        }

        if (start_offset < bytes.len) {
            // Write remaining bytes to new segment
            const remaining = bytes.len - start_offset;
            try self.addSegmentBySize(remaining);
            const last = self.getLastSegment() orelse unreachable;
            @memcpy(last.data, bytes[start_offset..]);
            last.used = remaining;
        }
    }

    fn writeInt(self: *StringBuilder, comptime T: type, value: T) !void {
        const size = @divFloor(@typeInfo(T).Int.bits + 7, 8);
        const bytes = try self.getMemory(size);
        std.mem.writeIntLittle(T, @ptrCast(bytes.ptr), value);
    }

    fn writeFloat(self: *StringBuilder) void {
        _ = self;
    }

    fn writePointer(self: *StringBuilder) void {
        _ = self;
    }

    fn dumpToFile(self: *StringBuilder, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        const writer = file.writer();
        defer file.close();
        for (self.segments.items) |s| {
            try writer.writeAll(s.data[0..s.used]);    
        }
    }
};

//
// Helpers for reading/writing types to memory
//

fn memorySizeOfIntType(comptime T: type) usize {
    return @divFloor(@typeInfo(T).Int.bits + 7, 8);
}

fn memorySizeOfType(value: anytype) usize {
    const base_type = @TypeOf(value);
    const ti = @typeInfo(base_type);
    switch (ti) {
        .Int => {
            return memorySizeOfIntType(base_type);
        },
        //.Float => {
        //    try writer.writeFloat(base_type, value, .Little);
        //},
        .Enum => |e| {
            return memorySizeOfIntType(e.tag_type);
        },
        .Pointer => |ptr| {
            const num_bytes = @sizeOf(ptr.child) * value.len;
            return memorySizeOfIntType(u64) + num_bytes;
        },
        .Struct => |s| {
            var sum: usize = 0;
            inline for (s.fields) |field| {
                sum += memorySizeOfType(@field(value, field.name));
            }
            return sum;
        },
        else => @compileError("Unhandled type in writing data" ++ @typeName(base_type)),
    }
}

fn memoryReadType(bytes: []u8, offset: *usize, value: anytype) void {
    const base_type = @typeInfo(@TypeOf(value)).Pointer.child;
    const ti = @typeInfo(base_type);
    switch (ti) {
        .Int => {
            var b: *[@sizeOf(base_type)]u8 = @ptrCast(bytes.ptr + offset.*);
            value.* = std.mem.readIntLittle(base_type, b);
            offset.* += memorySizeOfIntType(base_type);
        },
        .Enum => |e| {
            var b: *[@sizeOf(base_type)]u8 = @ptrCast(bytes.ptr + offset.*);
            const i = std.mem.readIntLittle(e.tag_type, b);
            value.* = @enumFromInt(i);
            offset.* += memorySizeOfIntType(e.tag_type);
        },
        .Pointer => |ptr| {
            std.debug.assert(ptr.size == .Slice);

            var b: *[@sizeOf(u64)]u8 = @ptrCast(bytes.ptr + offset.*);
            const len = std.mem.readIntLittle(u64, b);
            offset.* += memorySizeOfIntType(u64);

            offset.* = alignIntTo(offset.*, @alignOf(ptr.child));
            const src_ptr: [*]align(@alignOf(ptr.child)) u8 = @alignCast(@ptrCast(bytes[offset.*..]));
            value.* = @as([*] ptr.child, @ptrCast(src_ptr))[0..len];
            std.debug.assert(value.len == len);
            offset.* += len * @sizeOf(ptr.child);
        },
        .Struct => |s| {
            inline for (s.fields) |field| {
                memoryReadType(bytes, offset, &@field(value, field.name));
            }
        },
        else => std.log.err("Unhandled type in writing entities: {}", .{ti}),
    }
}

fn memoryWriteType(builder: *StringBuilder, value: anytype) !void {
    const base_type = @TypeOf(value);
    const ti = @typeInfo(base_type);
    switch (ti) {
        .Int => {
            try builder.writeInt(base_type, value);
        },
        //.Float => {
        //    try writer.writeFloat(base_type, value, .Little);
        //},
        .Enum => |e| {
            try builder.writeInt(e.tag_type, @intFromEnum(value));
        },
        .Pointer => |ptr| {
            std.debug.assert(ptr.size == .Slice);
            try builder.writeInt(u64, @as(u64, @intCast(value.len)));

            const num_bytes = @sizeOf(ptr.child) * value.len;
            const byte_slice: [*]const u8 = @ptrCast(value.ptr);
            try builder.alignTo(@alignOf(ptr.child));
            try builder.writeBytes(byte_slice[0..num_bytes]);
        },
        .Struct => |s| {
            inline for (s.fields) |field| {
                try memoryWriteType(builder, @field(value, field.name));
            }
        },
        else => @compileError("Unhandled type in writing data" ++ @typeName(base_type)),
    }
}

fn alignIntTo(value: usize, alignment: u8) usize {
    return alignment*@divFloor(value + alignment-1, alignment);
}
