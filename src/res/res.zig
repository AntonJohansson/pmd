const std = @import("std");

const common = @import("common");
const profile = common.profile;

const c = @cImport({
    @cInclude("./stb_image.c");
});

pub var mem: common.MemoryAllocators = .{};

pub const Image = struct {
    pixels: []u8 = undefined,
    width: u32 = 0,
    height: u32 = 0,
    channels: u32 = 0,
};

const Cubemap = struct {
    bytes: []u8 = undefined,
    width: u32 = 0,
    height: u32 = 0,
    channels: u32 = 0,

    pub fn faceSlice(cm: *const Cubemap, face: usize) []u8 {
        const bytes = cm.width*cm.height*cm.channels;
        return cm.bytes[face*bytes..(face+1)*bytes];
    }
};

pub fn readFileToMemory(path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    const size = (try file.stat()).size;
    const buf = try file.readToEndAlloc(mem.frame, size);
    return buf;
}

pub fn loadImage(image: *Image, path: []const u8) !void {
    const buf = try readFileToMemory(path);

    var width: c_int = undefined;
    var height: c_int = undefined;
    var channels: c_int = undefined;
    const desired_channels = 4;

    const pixels = c.stbi_load_from_memory(buf.ptr, @intCast(buf.len), &width, &height, &channels, desired_channels);
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
