const std = @import("std");
const packet = @import("packet.zig");
const common = @import("common");

pub const MessageKind = blk: {
    const ti = @typeInfo(packet);
    std.debug.assert(ti == .@"struct");
    std.debug.assert(ti.@"struct".fields.len < (1 << 8 * @sizeOf(u8)) - 1);

    const num_decls = ti.@"struct".decls.len;

    var enum_count = 0;
    var field_names: [num_decls][]const u8 = undefined;
    var field_values: [num_decls]u8 = undefined;

    for (ti.@"struct".decls) |d| {
        field_names[enum_count] = d.name;
        field_values[enum_count] = enum_count;
        enum_count += 1;
    }

    break :blk @Enum(u8, .exhaustive, &field_names, &field_values);
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

pub fn decode_kind(arena: *common.Arena, data: []u8, offset: *usize, kind: MessageKind) []u8 {
    switch (kind) {
        inline else => |k| {
            const size = getMessageSize(k);
            const output = arena.alloc(u8, size);
            const T = mapKindToMessage(k);
            var message_data: T = undefined;
            common.serialize.memory_read_type(arena, T, data, offset, &message_data);
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
