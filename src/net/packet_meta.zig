const std = @import("std");
const packet = @import("packet.zig");

pub const MessageKind = blk: {
    const ti = @typeInfo(packet);
    std.debug.assert(ti == .Struct);
    std.debug.assert(ti.Struct.fields.len < (1 << 8*@sizeOf(u8))-1);

    comptime var num_decls = ti.Struct.decls.len;

    var enum_count = 0;
    var enum_fields: [num_decls] std.builtin.Type.EnumField = undefined;

    inline for (ti.Struct.decls) |d| {
        enum_fields[enum_count] = .{.name = d.name, .value = enum_count};
        enum_count += 1;
    }

    break :blk @Type(std.builtin.Type {
        .Enum = std.builtin.Type.Enum {
            .tag_type = u8,
            .fields = &enum_fields,
            .decls = &[_]std.builtin.Type.Declaration {},
            .is_exhaustive = true,
        },
    });
};

pub fn mapMessageToKind(comptime T: type) MessageKind {
    comptime var type_name = @typeName(T);
    comptime var index = 0;
    inline for (type_name, 0..) |c,i| {
        if (c == '.') {
            index = i;
            break;
        }
    }
    comptime var name = type_name[index+1..];
    inline for (@typeInfo(MessageKind).Enum.fields) |f| {
        if (std.mem.eql(u8, f.name, name)) {
            return @enumFromInt(f.value);
        }
    }

    unreachable;
    //@compileError("Failed mapping type " ++ name);
}

pub fn mapKindToMessage(comptime kind: MessageKind) type {
    comptime var T: type = @field(packet, @tagName(kind));
    return T;
}

pub fn getMessageSize(kind: MessageKind) usize {
    const ti = @typeInfo(MessageKind);
    std.debug.assert(@intFromEnum(kind) < ti.Enum.fields.len);
    inline for (@typeInfo(MessageKind).Enum.fields) |f| {
        if (kind == @as(MessageKind, @enumFromInt(f.value))) {
            return @sizeOf(mapKindToMessage(@enumFromInt(f.value)));
        }
    }
    unreachable;
}
