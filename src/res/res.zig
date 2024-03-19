const std = @import("std");

const common = @import("common");
const profile = common.profile;

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

pub const Cubemap = struct {
    bytes: []u8 = undefined,
    width: u32 = 0,
    height: u32 = 0,
    channels: u32 = 0,

    pub fn faceSlice(cm: *const Cubemap, face: usize) []u8 {
        const bytes = cm.width*cm.height*cm.channels;
        return cm.bytes[face*bytes..(face+1)*bytes];
    }
};

pub const Audio = struct {
    samples: []f32 = undefined,
};

pub fn loadImage(image: *Image, path: []const u8) !void {
    const buf = try readFileToMemory(path);

    var width: c_int = undefined;
    var height: c_int = undefined;
    var channels: c_int = undefined;
    const desired_channels = 4;

    const pixels = c.stbi_load_from_memory(buf.ptr, @intCast(buf.len), &width, &height, &channels, desired_channels) orelse {
        log.err("Failed to decod image {s}", .{path});
        return;
    };
    defer c.stbi_image_free(pixels);

    const bytes: usize = @intCast(width*height*channels);
    @memcpy(image.pixels, pixels[0..bytes]);

    image.width = @intCast(width);
    image.height = @intCast(height);
    image.channels = @intCast(channels);
}

const CubemapFaceInfo = struct {
    pixels: []u8,
    path: []const u8,
};

fn loadCubemapFace(ptr: *anyopaque) void {
    const info: *CubemapFaceInfo = @alignCast(@ptrCast(ptr));
    var image = Image {
        .pixels = info.pixels,
    };
    loadImage(&image, info.path) catch unreachable;
}

pub fn loadCubemap(width: u32, height: u32, paths: [6][]const u8) !Cubemap {
    const channels = 4;
    const bytes = width * height * channels;

    var cm = Cubemap {
        .bytes = try mem.frame.alloc(u8, 6*bytes),
        .width = width,
        .height = height,
        .channels = channels,
    };

    var info = try mem.frame.alloc(CubemapFaceInfo, 6);
    var work = try mem.frame.alloc(common.threadpool.Work, 6);
    for (paths,0..) |p,i| {
        info[i].pixels = cm.faceSlice(i);
        info[i].path = p;
        work[i].func = loadCubemapFace;
        work[i].user_ptr = &info[i];
    }

    common.threadpool.enqueue(work);

    return cm;
}

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
    map[@intFromEnum(.death)]         = .{.path=dir_audio ++ "kill.ogg",      .volume=0.7};
    map[@intFromEnum(.slide)]         = .{.path=dir_audio ++ "slide.ogg",     .volume=0.7};
    map[@intFromEnum(.sniper)]        = .{.path=dir_audio ++ "sniper.ogg",    .volume=0.7};
    map[@intFromEnum(.weapon_switch)] = .{.path=dir_audio ++ "switch.ogg",    .volume=0.2};
    map[@intFromEnum(.step)]          = .{.path=dir_audio ++ "step.ogg",      .volume=0.7};
    map[@intFromEnum(.pip)]           = .{.path=dir_audio ++ "pip.ogg",       .volume=0.7};
    map[@intFromEnum(.explosion)]     = .{.path=dir_audio ++ "explosion.ogg", .volume=0.7};
    map[@intFromEnum(.doink)]         = .{.path=dir_audio ++ "doink.ogg",     .volume=0.7};
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
    const num_samples: usize = @as(c_uint, @intCast(vorbis_info.channels))*c.stb_vorbis_stream_length_in_samples(vorbis);
    info.samples = try mem.persistent.alloc(f32, num_samples);
    const samples_per_channel = c.stb_vorbis_get_samples_float_interleaved(vorbis, vorbis_info.channels, &info.samples[0], @intCast(num_samples));
    std.debug.assert(samples_per_channel*2 == num_samples);
}
