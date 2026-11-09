const std = @import("std");
const math = @import("math.zig");
const primitive = @import("primitive.zig");
const Color = primitive.Color;

pub const HSV = [3]f32;

fn f(col: HSV, n: f32) f32 {
    const k = @mod(n + col[0] / 60.0, 6.0);
    return col[2] - col[2] * col[1] * @max(0.0, @min(@min(k, 4 - k), 1));
}

pub fn hsv_to_rgb(col: HSV) Color {
    return .{
        .r = @intFromFloat(255.0 * f(col, 5.0)),
        .g = @intFromFloat(255.0 * f(col, 3.0)),
        .b = @intFromFloat(255.0 * f(col, 1.0)),
        .a = 255,
    };
}

pub fn scale_v(col: HSV, s: f32) HSV {
    return .{
        col[0],
        col[1],
        std.math.clamp(col[2]*s, 0.0, 1.0),
    };
}

pub fn darken(col: HSV) HSV {
    return scale_v(col, 0.75);
}

pub fn brighten(col: HSV) HSV {
    return scale_v(col, 1.25);
}

pub fn rgb_to_v4(col: Color) math.v4 {
    return .{
        .x = @as(f32, @floatFromInt(col.r)) / 255.0,
        .y = @as(f32, @floatFromInt(col.g)) / 255.0,
        .z = @as(f32, @floatFromInt(col.b)) / 255.0,
        .w = @as(f32, @floatFromInt(col.a)) / 255.0,
    };
}
