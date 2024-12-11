const std = @import("std");
const res = @import("res.zig");

const format_version = 1;
const magic: u32 = 'g' | ('o' << 8) | ('s' << 16) | ('e' << 24);

// TODO:
// - alignment?

pub const Header = struct {
    magic: u32 = magic,
    format_version: u8 = format_version,
    file_iteration: u16 = 0,
    entry_table_count: u16 = 0,
    entry_table_offset: u32 = 0,
};

// @debug
pub const EntrySrc = struct {
    path: []const u8,
    mtime: u64 = 0,
};

pub const Entry = struct {
    type: ResourceType,
    offset: u32,
    size: u32 = 0,
    name: []const u8,
    children: ?[]u32 = null,
    parent: ?u32 = null,

    srcs: []EntrySrc,
};

pub const Resource = union {
    text: res.Text,
    shader: res.Shader,
    image: res.Image,
    cubemap: res.Cubemap,
    audio: res.Audio,
    font: res.Font,
    model: res.Model,
    model_node: res.ModelNode,
};

pub const ResourceType = enum(u8) {
    text,
    audio,
    cubemap,
    texture,
    shader,
    font,
    model,
    model_node,
    model_binary,
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
    pack.resources = std.ArrayList(Resource).init(persistent);
    pack.entries = std.ArrayList(Entry).init(persistent);
    pack.resource_dirty = std.ArrayList(bool).init(persistent);
    return pack;
}

const DiskError = error{
    EmptyFile,
    InvalidMagic,
};

pub fn load(pack: *Pack, bytes: []u8) !void {
    var offset: usize = 0;
    memoryReadType(Header, bytes, &offset, &pack.header);
    pack.header.file_iteration += 1;

    if (pack.header.magic != magic) {
        std.log.err("Invalid magic {}, expected {}", .{ pack.header.magic, magic });
        return error.InvalidMagic;
    }

    if (pack.header.entry_table_count > 0) {
        const entries = try pack.entries.?.addManyAsSlice(pack.header.entry_table_count);
        try pack.resource_dirty.?.appendNTimes(false, pack.header.entry_table_count);
        offset = pack.header.entry_table_offset;
        for (entries) |*e| {
            memoryReadType(@TypeOf(e.*), bytes, &offset, e);
        }
    }

    pack.bytes = bytes;
}

pub fn saveToMemory(pack: *Pack) !StringBuilder {
    var builder = StringBuilder.init(persistent);

    const header_size = memorySizeOfType(pack.header);
    builder.base_offset = header_size;
    if (pack.entries != null) {
        for (pack.entries.?.items, 0..) |*e, i| {
            if (pack.resource_dirty.?.items[i]) {
                const resource = pack.resources.?.items[e.offset];
                e.offset = @intCast(builder.getOffset());
                switch (e.type) {
                    .text => try memoryWriteType(&builder, resource.text),
                    .shader => try memoryWriteType(&builder, resource.shader),
                    .texture => try memoryWriteType(&builder, resource.image),
                    .cubemap => try memoryWriteType(&builder, resource.cubemap),
                    .audio => try memoryWriteType(&builder, resource.audio),
                    .font => try memoryWriteType(&builder, resource.font),
                    .model => try memoryWriteType(&builder, resource.model),
                    .model_node => try memoryWriteType(&builder, resource.model_node),
                    else => unreachable,
                }
                e.size = @as(u32, @intCast(builder.getOffset())) - e.offset;
            } else if (pack.bytes) |bytes| {
                const offset: u32 = @intCast(builder.getOffset());
                try builder.writeBytes(bytes[e.offset..(e.offset + e.size)]);
                e.offset = offset;
            } else {
                unreachable;
            }
        }

        pack.header.entry_table_count = @intCast(pack.entries.?.items.len);
        pack.header.entry_table_offset = @intCast(builder.getOffset());
        for (pack.entries.?.items) |e| {
            try memoryWriteType(&builder, e);
        }
    }

    // this is not working I believe
    builder.insert = 0;
    builder.append = false;
    builder.base_offset = 0;
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
        .text => {
            resource = Resource{ .text = .{} };
            memoryReadType(res.Text, pack.bytes.?, &offset, &resource.text);
        },
        .shader => {
            resource = Resource{ .shader = .{} };
            memoryReadType(res.Shader, pack.bytes.?, &offset, &resource.shader);
        },
        .texture => {
            resource = Resource{ .image = .{} };
            memoryReadType(res.Image, pack.bytes.?, &offset, &resource.image);
        },
        .cubemap => {
            resource = Resource{ .cubemap = .{} };
            memoryReadType(res.Cubemap, pack.bytes.?, &offset, &resource.cubemap);
        },
        .audio => {
            resource = Resource{ .audio = .{} };
            memoryReadType(res.Audio, pack.bytes.?, &offset, &resource.audio);
        },
        .font => {
            resource = Resource{ .font = .{} };
            memoryReadType(res.Font, pack.bytes.?, &offset, &resource.font);
        },
        .model_node => {
            resource = Resource{ .model_node = .{} };
            memoryReadType(res.ModelNode, pack.bytes.?, &offset, &resource.model_node);
        },
        .model => {
            resource = Resource{ .model = .{} };
            memoryReadType(res.Model, pack.bytes.?, &offset, &resource.model);
        },
        else => unreachable,
    }
    return resource;
}

pub const EntryInfo = struct {
    index: usize,
    entry: Entry,
};

pub fn lookupEntry(pack: *Pack, name: []const u8) ?EntryInfo {
    // TODO: Use stringmap lookup
    for (pack.entries.?.items, 0..) |e, i| {
        if (std.mem.eql(u8, e.name, name)) {
            return .{ .index = i, .entry = e };
        }
    }
    return null;
}

pub fn lookup(pack: *Pack, name: []const u8) ?Resource {
    const ei = lookupEntry(pack, name) orelse return null;
    return getResource(pack, ei.index);
}

pub fn addResource(pack: *Pack, srcs: []EntrySrc, name: []const u8, res_type: ResourceType, resource: Resource, parent: ?u32, children: ?[]u32) !void {
    const index = pack.entries.?.items.len;
    const entry = try pack.entries.?.addOne();
    entry.offset = @intCast(pack.resources.?.items.len);

    // TODO: nasty
    try pack.resource_dirty.?.ensureTotalCapacity(index + 1);
    const start = pack.resource_dirty.?.items.len;
    pack.resource_dirty.?.expandToCapacity();
    for (start..pack.resource_dirty.?.capacity) |i| {
        pack.resource_dirty.?.items[i] = false;
    }
    pack.resource_dirty.?.items[index] = true;

    entry.type = res_type;
    entry.name = name;
    entry.parent = parent;
    entry.children = children;

    entry.srcs = srcs;
    for (entry.srcs) |*s| {
        s.mtime = try getFileMTime(s.path);
    }

    try pack.resources.?.append(resource);
}

pub fn deleteEntry(pack: *Pack, entry: Entry) void {
    var i: usize = 0;
    while (i < pack.entries.?.items.len) {
        const e = pack.entries.?.items[i];
        if (std.mem.eql(u8, e.name, entry.name)) {
            _ = pack.entries.?.orderedRemove(i);
        } else {
            i += 1;
        }
    }
}

pub fn getFileMTime(path: []const u8) !u64 {
    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    const stat = try f.stat();
    return @intCast(@divTrunc(stat.mtime, 1000000));
}

pub fn hasEntryBeenModified(entry: Entry) bool {
    for (entry.srcs) |s| {
        const new_mtime = getFileMTime(s.path) catch return false;
        if (new_mtime != s.mtime) {
            return true;
        }
    }
    return false;
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
    base_offset: usize = 0,

    fn init(allocator: std.mem.Allocator) StringBuilder {
        return StringBuilder{
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
        if (len == 0 or self.insert > len or self.insert == 0 or !self.append and self.segments.items[self.insert - 1].used > 0) {
            return null;
        }
        std.debug.assert(self.insert > 0);
        return &self.segments.items[self.insert - 1];
    }

    fn getOffset(self: *StringBuilder) usize {
        var offset: usize = self.base_offset;
        for (self.segments.items[0..self.insert]) |s| {
            offset += s.used;
        }
        return offset;
    }

    fn getMemory(self: *StringBuilder, size: usize) ![]u8 {
        if (self.getLastSegment()) |last| {
            const free = last.data.len - last.used;
            if (free >= size) {
                const bytes = last.data[last.used..(last.used + size)];
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
            const offset = self.getOffset();
            const start = offset - last.used;
            if (offset % alignment != 0) {
                const next = alignIntTo(offset, alignment);
                const next_offset = next - start;
                if (next_offset < last.data.len) {
                    last.used = next_offset;
                } else {
                    unreachable;
                }
            }
        }
    }

    fn writeBytes(self: *StringBuilder, bytes: []const u8) !void {
        // If the last segment has space, fill it as much as possible
        var start_offset: usize = 0;
        if (self.getLastSegment()) |last| {
            const free = @min(last.data.len - last.used, bytes.len);
            @memcpy(last.data[last.used..(last.used + free)], bytes[0..free]);
            last.used += free;
            start_offset += free;
        }

        if (start_offset < bytes.len) {
            // Write remaining bytes to new segment
            const remaining = bytes.len - start_offset;
            try self.addSegmentBySize(remaining);
            const last = self.getLastSegment() orelse unreachable;
            @memcpy(last.data[0..remaining], bytes[start_offset..]);
            last.used = remaining;
        }
    }

    fn writeInt(self: *StringBuilder, comptime T: type, value: T) !void {
        const size = @divFloor(@typeInfo(T).Int.bits + 7, 8);
        const bytes = try self.getMemory(size);
        std.mem.writeInt(T, @ptrCast(bytes.ptr), value, .little);
    }

    fn writeFloat(self: *StringBuilder, comptime T: type, value: T) !void {
        const IntT = std.meta.Int(.unsigned, @typeInfo(T).Float.bits);
        try self.writeInt(IntT, @bitCast(value));
    }

    fn writePointer(self: *StringBuilder) void {
        _ = self;
    }

    fn dumpToBuffer(self: *StringBuilder) ![]u8 {
        const offset = self.getOffset();
        const slice = try self.arena.allocator().alloc(u8, offset);
        var i: usize = 0;
        for (self.segments.items) |s| {
            @memcpy(slice[i..(s.used + i)], s.data[0..s.used]);
            i += s.used;
        }
        return slice;
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
        .Float => |f| {
            const IntT = std.meta.Int(.unsigned, f.bits);
            return memorySizeOfIntType(IntT);
        },
        .Enum => |e| {
            return memorySizeOfIntType(e.tag_type);
        },
        .Pointer => |ptr| {
            if (@typeInfo(ptr.child) == .Int or @typeInfo(ptr.child) == .Float) {
                const num_bytes = @sizeOf(ptr.child) * value.len;
                return memorySizeOfIntType(u64) + num_bytes;
            } else {
                unreachable;
            }
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

fn memoryReadType(comptime T: type, bytes: []u8, offset: *usize, value: anytype) void {
    const ti = @typeInfo(T);
    switch (ti) {
        .Int => {
            const b: *[@sizeOf(T)]u8 = @ptrCast(bytes.ptr + offset.*);
            value.* = std.mem.readInt(T, b, .little);
            offset.* += memorySizeOfIntType(T);
        },
        .Enum => |e| {
            const b: *[@sizeOf(T)]u8 = @ptrCast(bytes.ptr + offset.*);
            const i = std.mem.readInt(e.tag_type, b, .little);
            value.* = @enumFromInt(i);
            offset.* += memorySizeOfIntType(e.tag_type);
        },
        .Float => |f| {
            const IntT = std.meta.Int(.unsigned, f.bits);
            const b: *[@sizeOf(IntT)]u8 = @ptrCast(bytes.ptr + offset.*);
            value.* = @as(T, @bitCast(std.mem.readInt(IntT, b, .little)));
            offset.* += memorySizeOfIntType(IntT);
        },
        .Pointer => |ptr| {
            std.debug.assert(ptr.size == .Slice);

            const b: *[@sizeOf(u64)]u8 = @ptrCast(bytes.ptr + offset.*);
            const len = std.mem.readInt(u64, b, .little);
            offset.* += memorySizeOfIntType(u64);

            if (@typeInfo(ptr.child) == .Int or @typeInfo(ptr.child) == .Float) {
                offset.* = alignIntTo(offset.*, @alignOf(ptr.child));
                const src_ptr: [*]align(@alignOf(ptr.child)) u8 = @alignCast(@ptrCast(bytes[offset.*..]));
                value.* = @as([*]ptr.child, @ptrCast(src_ptr))[0..len];
                offset.* += len * @sizeOf(ptr.child);
            } else {
                const slice = persistent.alloc(ptr.child, len) catch unreachable;
                for (slice) |*v| {
                    memoryReadType(ptr.child, bytes, offset, v);
                }
                value.* = slice;
            }
        },
        .Array => |arr| {
            for (value) |*v| {
                memoryReadType(arr.child, bytes, offset, v);
            }
        },
        .Struct => |s| {
            inline for (s.fields) |field| {
                memoryReadType(field.type, bytes, offset, &@field(value, field.name));
            }
        },
        .Optional => |o| {
            const b: *[@sizeOf(u8)]u8 = @ptrCast(bytes.ptr + offset.*);
            const nonnull = std.mem.readInt(u8, b, .little);
            offset.* += memorySizeOfIntType(u8);
            if (nonnull != 0) {
                memoryReadType(o.child, bytes, offset, value);
            } else {
                value.* = null;
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
        .Float => {
            try builder.writeFloat(base_type, value);
        },
        .Enum => |e| {
            try builder.writeInt(e.tag_type, @intFromEnum(value));
        },
        .Pointer => |ptr| {
            std.debug.assert(ptr.size == .Slice);
            try builder.writeInt(u64, @as(u64, @intCast(value.len)));

            if (@typeInfo(ptr.child) == .Int or @typeInfo(ptr.child) == .Float) {
                const num_bytes = @sizeOf(ptr.child) * value.len;
                const byte_slice: [*]const u8 = @ptrCast(value.ptr);
                try builder.alignTo(@alignOf(ptr.child));
                try builder.writeBytes(byte_slice[0..num_bytes]);
            } else {
                for (value) |v| {
                    try memoryWriteType(builder, v);
                }
            }
        },
        .Array => {
            for (value) |v| {
                try memoryWriteType(builder, v);
            }
        },
        .Struct => |s| {
            inline for (s.fields) |field| {
                try memoryWriteType(builder, @field(value, field.name));
            }
        },
        .Optional => {
            if (value != null) {
                try builder.writeInt(u8, 1);
                try memoryWriteType(builder, value.?);
            } else {
                try builder.writeInt(u8, 0);
            }
        },
        else => @compileError("Unhandled type in writing data" ++ @typeName(base_type)),
    }
}

fn alignIntTo(value: usize, alignment: u8) usize {
    return alignment * @divFloor(value + alignment - 1, alignment);
}
const TS = struct {
    n: []const u8 = "/a/b/c/d/e/f",
    a: u32 = 0,
    b: ?[]const u64 = &[4]u64{ 1, 2, 3, 4 },
};
pub fn tttt() !void {
    var builder = StringBuilder.init(persistent);
    const ts = TS{};
    try memoryWriteType(&builder, ts);
    const bytes = try builder.dumpToBuffer();
    var ts2 = TS{};
    var offset: usize = 0;
    memoryReadType(TS, bytes, &offset, &ts2);
    std.log.info("{}", .{ts2});
    std.log.info("--------------------------------\n", .{});
}
