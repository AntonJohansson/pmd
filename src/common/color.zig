const primitive = @import("primitive.zig");
const Color = primitive.Color;

fn f(h: f32, s: f32, v: f32, n: f32) f32 {
    const k = @mod(n + h / 60.0, 6.0);
    return v - v * s * @max(0.0, @min(@min(k, 4 - k), 1));
}

pub fn hsv_to_rgb(h: f32, s: f32, v: f32) Color {
    return .{
        .r = @intFromFloat(255.0 * f(h, s, v, 5.0)),
        .g = @intFromFloat(255.0 * f(h, s, v, 3.0)),
        .b = @intFromFloat(255.0 * f(h, s, v, 1.0)),
        .a = 255,
    };
}
