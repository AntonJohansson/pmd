const std = @import("std");
const packet = @import("packet.zig");
const common = @import("common");

pub const MessageKind = blk: {
    const ti = @typeInfo(packet);
    std.debug.assert(ti == .@"struct");
    std.debug.assert(ti.@"struct".fields.len < (1 << 8 * @sizeOf(u8)) - 1);

    const num_decls = ti.@"struct".decls.len;

    var enum_count = 0;
    var enum_fields: [num_decls]std.builtin.Type.EnumField = undefined;

    for (ti.@"struct".decls) |d| {
        enum_fields[enum_count] = .{ .name = d.name, .value = enum_count };
        enum_count += 1;
    }

    break :blk @Type(std.builtin.Type{
        .@"enum" = std.builtin.Type.Enum{
            .tag_type = u8,
            .fields = &enum_fields,
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_exhaustive = true,
        },
    });
};

pub fn mapMessageToKind(comptime T: type) MessageKind {
    comptime var type_name = @typeName(T);
    comptime var index = 0;
    inline for (type_name, 0..) |c, i| {
        if (c == '.') {
            index = i;
            break;
        }
    }
    const name = comptime type_name[index + 1 ..];
    inline for (@typeInfo(MessageKind).@"enum".fields) |f| {
        if (std.mem.eql(u8, f.name, name)) {
            return @enumFromInt(f.value);
        }
    }

    unreachable;
    //@compileError("Failed mapping type " ++ name);
}

pub fn mapKindToMessage(comptime kind: MessageKind) type {
    return @field(packet, @tagName(kind));
}

pub fn decodeKind(allocator: std.mem.Allocator, data: []u8, offset: *usize, kind: MessageKind) ![]u8 {
    switch (kind) {
        inline else => |k| {
            const size = getMessageSize(k);
            const output = try allocator.alloc(u8, size);
            const T = mapKindToMessage(k);
            var message_data: T = undefined;
            common.serialize.memory_read_type(allocator, T, data, offset, &message_data);
            @memcpy(output, @as([*]u8, @ptrCast(&message_data))[0..size]);
            return output;
        },
    }
}

pub fn getMessageSize(kind: MessageKind) usize {
    const ti = @typeInfo(MessageKind);
    std.debug.assert(@intFromEnum(kind) < ti.@"enum".fields.len);
    inline for (@typeInfo(MessageKind).@"enum".fields) |f| {
        if (kind == @as(MessageKind, @enumFromInt(f.value))) {
            return @sizeOf(mapKindToMessage(@enumFromInt(f.value)));
        }
    }
    unreachable;
}
