const math = @import("math.zig");
const v2 = math.v2;
const v3 = math.v3;
const m4 = math.m4;

pub const VoxelTransform = struct {
    pub const FaceDir = enum(u8) {
        up,
        down,
        back,
        front,
        left,
        right
    };

    x: u8,
    y: u8,
    z: u8,
    face: FaceDir,
};

pub const VoxelChunk = struct {
    dim: u8 = 16,
    voxels: []VoxelTransform,
};

pub const Color = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 0,
};

pub const Text = struct {
    pos: v2,
    str: [128:0]u8,
    len: usize,
    size: f32,
    cursor_index: ?usize = null,
    bg: math.v4,
    fg: math.v4,
};

pub const Line = struct {
    start: v2,
    end: v2,
    thickness: f32,
};

pub const Circle = struct {
    model: m4,
};

pub const Rectangle = struct {
    pos: v2,
    size: v2,
};

pub const Cube = struct {
    model: m4,
};

pub const CubeOutline = struct {
    model: m4,
    thickness: f32 = 0.05,
};

pub const Mesh = struct {
    model: m4,
    name: []const u8,
    draw_children: bool = false,
};

pub const Camera3d = extern struct {
    pos: v3 = .{},
    dir: v3 = .{},
    proj: m4 = math.m4_identity,
    view: m4 = math.m4_identity,
};

pub const Camera2d = struct {
    target: v2,
    zoom: f32,
    scale: v2 = .{ .x = 0.5, .y = 0.5 },
    offset: v2 = .{ .x = 0, .y = 0 },
};

pub const End3d = struct {};
pub const End2d = struct {};

pub const Plane = extern struct {
    model: m4,
};

pub const Vector = struct {
    dir: v3,
    pos: v3,
    scale: f32,
};

//pub const Texture  = struct {
//};
