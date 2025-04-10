const math = @import("math.zig");
const res = @import("common.zig").res;
const v2 = math.v2;
const v3 = math.v3;
const m4 = math.m4;

pub const voxel_dim = 8;
pub const chunk_dim = 64;

pub const Voxel = enum(u8) {
    air,
    grass,
    stone,
    wood,
};

pub const VoxelTransform = struct {
    pub const FaceDir = enum(u8) { up, down, back, front, left, right };

    pos: [3]u8,
    face: FaceDir,

    kind: Voxel,
    dummy: [3]u8 = .{ 0, 0, 0 },
};

pub const VoxelChunk = struct {
    origin_x: i16 = 0,
    origin_y: i16 = 0,
    origin_z: i16 = 0,
    voxels: []VoxelTransform,
    dirty: u1 = 0,
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
    transform: m4,
    mesh_index: u32,
    model_id: res.Id,
};

pub const Camera3d = struct {
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

pub const Plane = struct {
    model: m4,
};

pub const Vector = struct {
    dir: v3,
    pos: v3,
    scale: f32,
};

//pub const Texture  = struct {
//};
