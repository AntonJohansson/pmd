const std = @import("std");
const res = @import("res.zig");
const build_options = @import("build_options");
const disk = if (build_options.options.debug) @import("pack-disk") else struct {};

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
    id: res.Id,
    children: ?[]i32 = null,
    parent: ?i32 = null,

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
    animation: res.Animation,
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
    map_voxel,
    animation,
};

const DiskError = error{
    EmptyFile,
    InvalidMagic,
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
    pack.resources = std.ArrayList(Resource){};
    pack.entries = std.ArrayList(Entry){};
    pack.resource_dirty = std.ArrayList(bool){};
    return pack;
}

pub fn load(pack: *Pack, bytes: []u8) !void {
    var offset: usize = 0;
    memoryReadType(Header, bytes, &offset, &pack.header);
    pack.header.file_iteration += 1;

    if (pack.header.magic != magic) {
        std.log.err("Invalid magic {}, expected {}", .{ pack.header.magic, magic });
        return error.InvalidMagic;
    }

    if (pack.header.entry_table_count > 0) {
        const entries = try pack.entries.?.addManyAsSlice(persistent, pack.header.entry_table_count);
        try pack.resource_dirty.?.appendNTimes(persistent, false, pack.header.entry_table_count);
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
                    .animation => try memoryWriteType(&builder, resource.animation),
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
        .animation => {
            resource = Resource{ .animation = .{} };
            memoryReadType(res.Animation, pack.bytes.?, &offset, &resource.animation);
        },
        else => unreachable,
    }
    return resource;
}

pub const EntryInfo = struct {
    index: usize,
    entry: Entry,
};

pub fn entry_lookup_id(pack: *Pack, id: res.Id) ?EntryInfo {
    for (pack.entries.?.items, 0..) |e, i| {
        if (e.id == id) {
            return .{ .index = i, .entry = e };
        }
    }
    return null;
}

pub fn entry_lookup(pack: *Pack, name: []const u8) ?EntryInfo {
    // TODO: Use stringmap lookup
    for (pack.entries.?.items, 0..) |e, i| {
        if (std.mem.eql(u8, e.name, name)) {
            return .{ .index = i, .entry = e };
        }
    }
    return null;
}

pub fn resource_lookup(pack: *Pack, name: []const u8) ?Resource {
    const ei = entry_lookup(pack, name) orelse return null;
    return getResource(pack, ei.index);
}

pub fn resource_append(pack: *Pack, srcs: []EntrySrc, name: []const u8, res_type: ResourceType, resource: Resource, parent: ?i32, children: ?[]i32) !Entry {
    const index = pack.entries.?.items.len;
    const entry = try pack.entries.?.addOne(persistent);
    entry.offset = @intCast(pack.resources.?.items.len);

    // TODO: nasty
    try pack.resource_dirty.?.ensureTotalCapacity(persistent, index + 1);
    const start = pack.resource_dirty.?.items.len;
    pack.resource_dirty.?.expandToCapacity();
    for (start..pack.resource_dirty.?.capacity) |i| {
        pack.resource_dirty.?.items[i] = false;
    }
    pack.resource_dirty.?.items[index] = true;

    entry.type = res_type;
    entry.name = name;
    entry.id = res.runtime_pack_id(name);
    entry.parent = parent;
    entry.children = children;

    entry.srcs = srcs;
    for (entry.srcs) |*s| {
        s.mtime = try getFileMTime(s.path);
    }

    try pack.resources.?.append(persistent, resource);

    return entry.*;
}

pub fn entry_delete(pack: *Pack, entry: Entry) void {
    var i: usize = 0;
    while (i < pack.entries.?.items.len) {
        const e = pack.entries.?.items[i];
        if (std.mem.eql(u8, e.name, entry.name)) {
            _ = pack.entries.?.orderedRemove(i);
            return;
        } else {
            i += 1;
        }
    }
}

pub fn entry_delete_child_tree(p: *Pack, start_id: usize) !void {
    var entry = p.entries.?.items[start_id];

    // If the selected node has a parent, find the parent so we can
    // properly delete the entire tree of nodes. Child offsets of
    // other nodes in the same tree would be incorrect, and it
    // doesn't make much sense to add residual nodes.
    var root_id: i64 = @intCast(start_id);
    var delete_original_entry = false;
    if (entry.parent != null) {
        var parent: ?i32 = entry.parent;
        while (parent != null) {
            root_id = root_id + parent.?;
            const parent_entry = p.entries.?.items[@intCast(root_id)];
            parent = parent_entry.parent;
        }

        entry = p.entries.?.items[@intCast(root_id)];
    } else {
        // If we don't have a parent, go ahead and delete the current entry,
        // if we had a parent and updated the root entry the selected entry
        // would be handled by the child loop below.
        delete_original_entry = true;
    }

    // If the entry has children we need to make sure to recursively
    // delete them as well, as to not leave entries behind that
    // originated from the same file.
    if (entry.children) |root_children| {
        var child_queue = std.ArrayList(i32){};
        defer child_queue.deinit(frame);

        for (root_children) |rc| {
            try child_queue.append(frame, @intCast(root_id + @as(i64, @intCast(rc))));
        }

        while (child_queue.items.len > 0) {
            const child_id = child_queue.pop();
            const child_entry = p.entries.?.items[@intCast(child_id.?)];

            if (child_entry.children) |entry_children| {
                for (entry_children) |ec| {
                    try child_queue.append(frame, @intCast(child_id.? + @as(i64, @intCast(ec))));
                }
            }

            entry_delete(p, child_entry);
        }
    }

    if (delete_original_entry) {
        entry_delete(p, entry);
    }
}

pub fn getFileMTime(path: []const u8) !u64 {
    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    const stat = try f.stat();
    return @intCast(@divTrunc(stat.mtime, 1000000));
}

pub fn has_entry_been_modified(entry: Entry) bool {
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

pub const StringBuilder = struct {
    segments: std.ArrayList(Segment),
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    insert: usize = 0,
    last_segment: ?Segment = null,
    append: bool = true,
    base_offset: usize = 0,

    fn init(allocator: std.mem.Allocator) StringBuilder {
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

    fn addSegmentBySize(self: *StringBuilder, size: usize) !void {
        //const rounded_size = 8*@divFloor(size + 8 - 1, 8);
        const slice = try self.arena.allocator().alloc(u8, size);
        try self.segments.insert(self.allocator, self.insert, Segment{
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
        const size = comptime memorySizeOfIntType(T);
        const bytes = try self.getMemory(size);
        var buf: [size]u8 = undefined;
        std.mem.writeInt(std.meta.Int(@typeInfo(T).int.signedness, 8 * size), &buf, value, .little);
        @memcpy(bytes, &buf);
    }

    fn writeFloat(self: *StringBuilder, comptime T: type, value: T) !void {
        const IntT = std.meta.Int(.unsigned, @typeInfo(T).float.bits);
        try self.writeInt(IntT, @bitCast(value));
    }

    fn writePointer(self: *StringBuilder) void {
        _ = self;
    }

    pub fn dumpToBuffer(self: *StringBuilder, allocator: std.mem.Allocator) ![]u8 {
        var size: usize = 0;
        for (self.segments.items) |s| {
            size += s.used;
        }
        const slice = try allocator.alloc(u8, size);
        var i: usize = 0;
        for (self.segments.items) |s| {
            @memcpy(slice[i..(s.used + i)], s.data[0..s.used]);
            i += s.used;
        }
        return slice;
    }

    pub fn dumpToFile(self: *StringBuilder, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        var buffer: [1024]u8 = undefined;
        var file_writer = file.writer(&buffer);
        const writer = &file_writer.interface;
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
    return @divFloor(@typeInfo(T).int.bits + 7, 8);
}

fn memorySizeOfType(value: anytype) usize {
    const base_type = @TypeOf(value);
    const ti = @typeInfo(base_type);
    switch (ti) {
        .int => {
            return memorySizeOfIntType(base_type);
        },
        .float => |f| {
            const IntT = std.meta.Int(.unsigned, f.bits);
            return memorySizeOfIntType(IntT);
        },
        .@"enum" => |e| {
            return memorySizeOfIntType(e.tag_type);
        },
        .pointer => |ptr| {
            if (@typeInfo(ptr.child) == .int or @typeInfo(ptr.child) == .float) {
                const num_bytes = @sizeOf(ptr.child) * value.len;
                return memorySizeOfIntType(u64) + num_bytes;
            } else {
                unreachable;
            }
        },
        .@"struct" => |s| {
            var sum: usize = 0;
            inline for (s.fields) |field| {
                sum += memorySizeOfType(@field(value, field.name));
            }
            return sum;
        },
        else => @compileError("Unhandled type in writing data" ++ @typeName(base_type)),
    }
}

fn read_int(comptime T: type, bytes: []u8, offset: *usize) T {
    const size = comptime memorySizeOfIntType(T);
    const b: *[size]u8 = @ptrCast(bytes.ptr + offset.*);
    const NewT = std.meta.Int(@typeInfo(T).int.signedness, 8 * size);
    const value = std.mem.readInt(NewT, b, .little);
    offset.* += size;
    return @truncate(value);
}

fn memoryReadType(comptime T: type, bytes: []u8, offset: *usize, value: anytype) void {
    const ti = @typeInfo(T);
    switch (ti) {
        .bool => {
            const b: *u8 = @ptrCast(bytes.ptr + offset.*);
            value.* = (b.* != 0);
            offset.* += memorySizeOfIntType(u8);
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
                offset.* = alignIntTo(offset.*, @alignOf(ptr.child));
                const src_ptr: [*]align(@alignOf(ptr.child)) u8 = @ptrCast(@alignCast(bytes[offset.*..]));
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
        .array => |arr| {
            for (value) |*v| {
                memoryReadType(arr.child, bytes, offset, v);
            }
        },
        .@"struct" => |s| {
            inline for (s.fields) |field| {
                memoryReadType(field.type, bytes, offset, &@field(value, field.name));
            }
        },
        .optional => |o| {
            const nonnull = read_int(u8, bytes, offset);
            if (nonnull != 0) {
                var tmp: o.child = undefined;
                memoryReadType(o.child, bytes, offset, &tmp);
                value.* = tmp;
            } else {
                value.* = null;
            }
        },
        else => @compileError("Unhandled type in reading data " ++ @typeName(T)),
    }
}

fn memoryWriteType(builder: *StringBuilder, value: anytype) !void {
    const base_type = @TypeOf(value);
    const ti = @typeInfo(base_type);

    switch (ti) {
        .bool => {
            try builder.writeInt(u8, @intFromBool(value));
        },
        .int => {
            try builder.writeInt(base_type, value);
        },
        .float => {
            try builder.writeFloat(base_type, value);
        },
        .@"enum" => |e| {
            try builder.writeInt(e.tag_type, @intFromEnum(value));
        },
        .pointer => |ptr| {
            std.debug.assert(ptr.size == .slice);
            try builder.writeInt(u64, @as(u64, @intCast(value.len)));

            if (@typeInfo(ptr.child) == .int or @typeInfo(ptr.child) == .float) {
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
        .array => {
            for (value) |v| {
                try memoryWriteType(builder, v);
            }
        },
        .@"struct" => |s| {
            inline for (s.fields) |field| {
                try memoryWriteType(builder, @field(value, field.name));
            }
        },
        .optional => {
            if (value != null) {
                try builder.writeInt(u8, 1);
                try memoryWriteType(builder, value.?);
            } else {
                try builder.writeInt(u8, 0);
            }
        },
        else => @compileError("Unhandled type in writing data " ++ @typeName(base_type)),
    }
}

fn alignIntTo(value: usize, alignment: u8) usize {
    return alignment * @divFloor(value + alignment - 1, alignment);
}
