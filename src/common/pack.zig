const std = @import("std");
const res = @import("res.zig");
const build_options = @import("build_options");
const disk = if (build_options.options.debug) @import("pack-disk") else struct {};
const common = @import("common.zig");
const StringBuilder = common.serialize.StringBuilder;

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
    resources: []Resource = &.{},
    resource_dirty: []bool = &.{},
    entries: []Entry = &.{},
    bytes: []u8 = &.{},
};

pub var arena_frame: *common.Arena = undefined;
pub var arena_persistent: *common.ArenaFreelist = undefined;

pub fn load(pack: *Pack, bytes: []u8) !void {
    var offset: usize = 0;
    memoryReadType(Header, bytes, &offset, &pack.header);
    pack.header.file_iteration += 1;

    if (pack.header.magic != magic) {
        std.log.err("Invalid magic {}, expected {}", .{ pack.header.magic, magic });
        return error.InvalidMagic;
    }

    if (pack.header.entry_table_count > 0) {
        pack.entries = arena_persistent.alloc(Entry, pack.header.entry_table_count);
        pack.resource_dirty = arena_persistent.alloc(bool, pack.header.entry_table_count);
        @memset(pack.resource_dirty, false);
        offset = pack.header.entry_table_offset;
        for (pack.entries) |*e| {
            memoryReadType(@TypeOf(e.*), bytes, &offset, e);
        }
    }

    pack.bytes = bytes;
}

pub fn save_to_memory(pack: *Pack) StringBuilder {
    var builder = StringBuilder{
        .segments = .{ .arena = arena_frame },
        .base_offset = memorySizeOfType(pack.header),
    };

    if (pack.entries.len > 0) {
        for (pack.entries, 0..) |*e, i| {
            if (pack.resource_dirty[i]) {
                const resource = pack.resources[e.offset];
                e.offset = @intCast(builder.get_offset());
                switch (e.type) {
                    .text => memoryWriteType(&builder, resource.text),
                    .shader => memoryWriteType(&builder, resource.shader),
                    .texture => memoryWriteType(&builder, resource.image),
                    .cubemap => memoryWriteType(&builder, resource.cubemap),
                    .audio => memoryWriteType(&builder, resource.audio),
                    .font => memoryWriteType(&builder, resource.font),
                    .model => memoryWriteType(&builder, resource.model),
                    .model_node => memoryWriteType(&builder, resource.model_node),
                    .animation => memoryWriteType(&builder, resource.animation),
                    else => unreachable,
                }
                e.size = @as(u32, @intCast(builder.get_offset())) - e.offset;
            } else if (pack.bytes.len > 0) {
                const offset: u32 = @intCast(builder.get_offset());
                builder.write_bytes(pack.bytes[e.offset..(e.offset + e.size)]);
                e.offset = offset;
            } else {
                unreachable;
            }
        }

        pack.header.entry_table_count = @intCast(pack.entries.len);
        pack.header.entry_table_offset = @intCast(builder.get_offset());
        for (pack.entries) |e| {
            memoryWriteType(&builder, e);
        }
    }

    var header_builder = builder.subbuilder();
    memoryWriteType(&header_builder, pack.header);
    header_builder.segments.join_right(&builder.segments);

    return header_builder;
}

pub fn save_to_file(pack: *Pack, path: []const u8) !void {
    var builder = save_to_memory(pack);
    try builder.dump_to_file(path);
}

pub fn getResource(pack: *Pack, id: usize) Resource {
    const entry = pack.entries[id];
    var offset: usize = @intCast(entry.offset);
    var resource: Resource = undefined;
    switch (entry.type) {
        .text => {
            resource = Resource{ .text = .{} };
            memoryReadType(res.Text, pack.bytes, &offset, &resource.text);
        },
        .shader => {
            resource = Resource{ .shader = .{} };
            memoryReadType(res.Shader, pack.bytes, &offset, &resource.shader);
        },
        .texture => {
            resource = Resource{ .image = .{} };
            memoryReadType(res.Image, pack.bytes, &offset, &resource.image);
        },
        .cubemap => {
            resource = Resource{ .cubemap = .{} };
            memoryReadType(res.Cubemap, pack.bytes, &offset, &resource.cubemap);
        },
        .audio => {
            resource = Resource{ .audio = .{} };
            memoryReadType(res.Audio, pack.bytes, &offset, &resource.audio);
        },
        .font => {
            resource = Resource{ .font = .{} };
            memoryReadType(res.Font, pack.bytes, &offset, &resource.font);
        },
        .model_node => {
            resource = Resource{ .model_node = .{} };
            memoryReadType(res.ModelNode, pack.bytes, &offset, &resource.model_node);
        },
        .model => {
            resource = Resource{ .model = .{} };
            memoryReadType(res.Model, pack.bytes, &offset, &resource.model);
        },
        .animation => {
            resource = Resource{ .animation = .{} };
            memoryReadType(res.Animation, pack.bytes, &offset, &resource.animation);
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
    for (pack.entries, 0..) |e, i| {
        if (e.id == id) {
            return .{ .index = i, .entry = e };
        }
    }
    return null;
}

pub fn entry_lookup(pack: *Pack, name: []const u8) ?EntryInfo {
    // TODO: Use stringmap lookup
    for (pack.entries, 0..) |e, i| {
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
    const index = pack.entries.len;
    pack.entries = arena_persistent.realloc(pack.entries, index + 1);
    const entry = &pack.entries[index];
    entry.offset = @intCast(pack.resources.len);

    // TODO: nasty
    const start = pack.resource_dirty.len;
    pack.resource_dirty = arena_persistent.realloc(pack.resource_dirty, index + 1);
    for (start..pack.resource_dirty.len) |i| {
        pack.resource_dirty[i] = false;
    }
    pack.resource_dirty[index] = true;

    entry.type = res_type;
    entry.name = name;
    entry.id = res.runtime_pack_id(name);
    entry.parent = parent;
    entry.children = children;

    entry.srcs = srcs;
    for (entry.srcs) |*s| {
        s.mtime = try getFileMTime(s.path);
    }

    const res_index = pack.resources.len;
    pack.resources = arena_persistent.realloc(pack.resources, pack.resources.len + 1);
    pack.resources[res_index] = resource;

    return entry.*;
}

pub fn entry_delete(pack: *Pack, entry: Entry) void {
    var i: usize = 0;
    while (i < pack.entries.len) {
        const e = pack.entries[i];
        if (std.mem.eql(u8, e.name, entry.name)) {
            // ordered remove
            @memmove(pack.entries[i .. pack.entries.len - 1], pack.entries[i + 1 ..]);
            pack.entries.len -= 1;
            return;
        } else {
            i += 1;
        }
    }
}

pub fn entry_delete_child_tree(pack: *Pack, start_id: usize) !void {
    var entry = pack.entries[start_id];

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
            const parent_entry = pack.entries[@intCast(root_id)];
            parent = parent_entry.parent;
        }

        entry = pack.entries[@intCast(root_id)];
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
        var child_queue = common.IntrusiveList(i32){
            .arena = arena_frame,
        };

        for (root_children) |rc| {
            child_queue.append(@intCast(root_id + @as(i64, @intCast(rc))));
        }

        while (child_queue.pop()) |child_id| {
            const child_entry = pack.entries[@intCast(child_id)];

            if (child_entry.children) |entry_children| {
                for (entry_children) |ec| {
                    child_queue.append(@intCast(child_id + @as(i64, @intCast(ec))));
                }
            }

            entry_delete(pack, child_entry);
        }
    }

    if (delete_original_entry) {
        entry_delete(pack, entry);
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
                const slice = arena_persistent.alloc(ptr.child, len);
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

fn memoryWriteType(builder: *StringBuilder, value: anytype) void {
    const base_type = @TypeOf(value);
    const ti = @typeInfo(base_type);

    switch (ti) {
        .bool => {
            builder.write_int(u8, @intFromBool(value));
        },
        .int => {
            builder.write_int(base_type, value);
        },
        .float => {
            builder.write_float(base_type, value);
        },
        .@"enum" => |e| {
            builder.write_int(e.tag_type, @intFromEnum(value));
        },
        .pointer => |ptr| {
            std.debug.assert(ptr.size == .slice);
            builder.write_int(u64, @as(u64, @intCast(value.len)));

            if (@typeInfo(ptr.child) == .int or @typeInfo(ptr.child) == .float) {
                const num_bytes = @sizeOf(ptr.child) * value.len;
                const byte_slice: [*]const u8 = @ptrCast(value.ptr);
                builder.align_to(@alignOf(ptr.child));
                builder.write_bytes(byte_slice[0..num_bytes]);
            } else {
                for (value) |v| {
                    memoryWriteType(builder, v);
                }
            }
        },
        .array => {
            for (value) |v| {
                memoryWriteType(builder, v);
            }
        },
        .@"struct" => |s| {
            inline for (s.fields) |field| {
                memoryWriteType(builder, @field(value, field.name));
            }
        },
        .optional => {
            if (value != null) {
                builder.write_int(u8, 1);
                memoryWriteType(builder, value.?);
            } else {
                builder.write_int(u8, 0);
            }
        },
        else => @compileError("Unhandled type in writing data " ++ @typeName(base_type)),
    }
}

fn alignIntTo(value: usize, alignment: u8) usize {
    return alignment * @divFloor(value + alignment - 1, alignment);
}
