const std = @import("std");
const primitive = @import("primitive.zig");

pub const PrimitiveKind = blk: {
    const ti = @typeInfo(primitive);
    std.debug.assert(ti == .@"struct");
    std.debug.assert(ti.@"struct".fields.len < 1 << 8 * @sizeOf(u8));

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

pub fn mapPrimitiveToKind(comptime T: type) PrimitiveKind {
    comptime var type_name = @typeName(T);
    comptime var index = 0;
    inline for (type_name, 0..) |c, i| {
        if (c == '.') {
            index = i;
            break;
        }
    }
    const name = type_name[index + 1 ..];
    inline for (@typeInfo(PrimitiveKind).@"enum".fields) |f| {
        if (std.mem.eql(u8, f.name, name)) {
            return @enumFromInt(f.value);
        }
    }

    unreachable;
    //@compileError("Failed mapping type " ++ name);
}

pub fn mapKindToPrimitive(comptime kind: PrimitiveKind) type {
    return @field(primitive, @tagName(kind));
}

pub fn getMessageSize(kind: PrimitiveKind) usize {
    inline for (@typeInfo(PrimitiveKind).@"enum".fields) |f| {
        if (kind == @as(PrimitiveKind, @enumFromInt(f.value))) {
            return @sizeOf(mapKindToPrimitive(@enumFromInt(f.value)));
        }
    }
    unreachable;
}
