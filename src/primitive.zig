const math = @import("math.zig");
const v2 = math.v2;
const v3 = math.v3;

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub const Text = struct {
    pos: v2,
    str: [128]u8,
    len: usize,
    size: f32,
    cursor_index: ?usize = null,
};

pub const Line = struct {
    start: v2,
    end: v2,
    thickness: f32,
};

pub const Circle = struct {
    pos: v2,
    radius: f32,
};

pub const Rectangle = struct {
    pos: v2,
    size: v2,
};

pub const Cube = struct {
    pos: v3,
    size: v3,
};

pub const Camera3d = struct {
    pos: v3,
    dir: v3,
};
pub const Camera2d = struct {
    target: v2,
    zoom: f32,
};
pub const End3d = struct {};
pub const End2d = struct {};
