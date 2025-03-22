const std = @import("std");

const common = @import("common.zig");
const profile = common.profile;
const primitive = common.primitive;
const math = common.math;

const logging = common.logging;
var log: logging.Log = .{
    .mirror_to_stdio = true,
};

const c = @cImport({
    @cInclude("./stb_image.c");
    @cDefine("STB_VORBIS_HEADER_ONLY", "");
    @cInclude("./stb_vorbis.c");
});

//
// Generic
//

// Directories
pub const dir_res = "./res/";
pub const dir_audio = dir_res ++ "audio/";

// Memory
pub var mem: common.MemoryAllocators = .{};

pub fn id(comptime path: []const u8) u32 {
    return comptime blk: {
        break :blk std.hash.Murmur3_32.hash(path);
    };
}

pub fn readFileToMemory(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    const size = (try file.stat()).size;
    const buf = try file.readToEndAllocOptions(allocator, size, null, @alignOf(u64), null);
    return buf;
}

//
// Images
//

pub const Image = struct {
    pixels: []u8 = undefined,
    width: u32 = 0,
    height: u32 = 0,
    channels: u32 = 0,
};

pub const Text = struct {
    bytes: []u8 = undefined,
};

pub const FontChar = struct {
    x0: u16,
    y0: u16,
    x1: u16,
    y1: u16,
    xoff: f32,
    yoff: f32,
    xadvance: f32,
    xoff2: f32,
    yoff2: f32,
};

pub const Font = struct {
    chars: []FontChar = undefined,
    pixels: []u8 = undefined,
    width: u16 = 0,
    height: u16 = 0,
    size: u8 = 0,
};

pub const Shader = struct {
    vs_bytes: []u8 = undefined,
    fs_bytes: []u8 = undefined,
};

pub const Cubemap = struct {
    bytes: []u8 = undefined,
    width: u32 = 0,
    height: u32 = 0,
    channels: u32 = 0,

    pub fn faceSlice(cm: *const Cubemap, face: usize) []u8 {
        const bytes = cm.width * cm.height * cm.channels;
        return cm.bytes[face * bytes .. (face + 1) * bytes];
    }
};

pub const Audio = struct {
    samples: []f32 = undefined,
};

const CubemapFaceInfo = struct {
    pixels: []u8,
    path: []const u8,
};

//
// Audio
//

const SoundType = common.SoundType;

const SoundInfo = struct {
    path: []const u8,
    samples: []f32 = undefined,
    volume: f32 = 1.0,
};

const sound_info_map = blk: {
    var map: [@typeInfo(SoundType).Enum.fields.len]SoundInfo = undefined;
    map[@intFromEnum(.death)] = .{ .path = dir_audio ++ "kill.ogg", .volume = 0.7 };
    map[@intFromEnum(.slide)] = .{ .path = dir_audio ++ "slide.ogg", .volume = 0.7 };
    map[@intFromEnum(.sniper)] = .{ .path = dir_audio ++ "sniper.ogg", .volume = 0.7 };
    map[@intFromEnum(.weapon_switch)] = .{ .path = dir_audio ++ "switch.ogg", .volume = 0.2 };
    map[@intFromEnum(.step)] = .{ .path = dir_audio ++ "step.ogg", .volume = 0.7 };
    map[@intFromEnum(.pip)] = .{ .path = dir_audio ++ "pip.ogg", .volume = 0.7 };
    map[@intFromEnum(.explosion)] = .{ .path = dir_audio ++ "explosion.ogg", .volume = 0.7 };
    map[@intFromEnum(.doink)] = .{ .path = dir_audio ++ "doink.ogg", .volume = 0.7 };
    break :blk map;
};

pub fn loadAudio(st: SoundType) !void {
    const info = sound_info_map[@intFromEnum(st)];
    const buf = try readFileToMemory(info.path);

    var err: c_int = undefined;
    const vorbis = c.stb_vorbis_open_memory(buf.ptr, @intCast(buf.len), &err, null) orelse {
        log.err("Failed to decode file: {s}", .{info.path});
        return;
    };
    std.debug.assert(err == 0);

    const vorbis_info = c.stb_vorbis_get_info(vorbis);
    const num_samples: usize = @as(c_uint, @intCast(vorbis_info.channels)) * c.stb_vorbis_stream_length_in_samples(vorbis);
    info.samples = try mem.persistent.alloc(f32, num_samples);
    const samples_per_channel = c.stb_vorbis_get_samples_float_interleaved(vorbis, vorbis_info.channels, &info.samples[0], @intCast(num_samples));
    std.debug.assert(samples_per_channel * 2 == num_samples);
}

//
// Model
//

pub const VertexAttribute = enum(u8) {
    position = 0,
    normal = 1,
    texcoord = 2,
    color0 = 3,
};
const SLOT_tex = 0;
const SLOT_smp = 0;
const SLOT_vs_params = 0;

pub const bt_position: u8 = 1;
pub const bt_normals: u8 = 2;
pub const bt_texcoords: u8 = 4;
pub const bt_indices: u8 = 8;

pub const ModelNode = struct {
    root_entry_relative_index: i32 = 0,
    mesh_index: ?u32 = 0,
    transform: math.m4 = undefined,
};

pub const MaterialIndex = u16;

pub const Mesh = struct {
    primitives: []MeshPrimitive = undefined,
};

pub const MeshPrimitive = struct {
    buffer_types: u8 = 0,
    pos: ?[]u8 = null,
    normals: ?[]u8 = null,
    texcoords: ?[]u8 = null,
    indices: ?[]u8 = null,
    material_index: MaterialIndex = 0,
};

pub const Model = struct {
    id: u64 = undefined,
    binary_data: []u8 = undefined,
    meshes: []Mesh = undefined,
    materials: []Material = undefined,
    nodes: []u32 = undefined,
};

pub const Material = struct {
    // metallic
    base_color: math.v4 = .{},
    has_image: bool = false,
    image: Image = undefined,

};
