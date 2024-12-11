const std = @import("std");
const common = @import("common");
const res = common.res;
const goosepack = common.goosepack;
const math = common.math;

const c = @cImport({
    @cInclude("./stb_image.c");
    @cDefine("STB_VORBIS_HEADER_ONLY", "");
    @cInclude("./stb_vorbis.c");
    @cInclude("./stb_rect_pack.h");
    @cInclude("./stb_truetype.h");
    @cInclude("./cgltf.h");
});

const sokol = @import("sokol");
const sg = sokol.gfx;

const native_endian = std.builtin.target.cpu.arch.endian();

var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_state.allocator();
var arena_state = std.heap.ArenaAllocator.init(gpa);
var arena = arena_state.allocator();

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var stdout_buffered_writer = std.io.bufferedWriter(stdout_file);
    const stdout = stdout_buffered_writer.writer();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    if (args.len < 3) {
        printUsage();
        return;
    }

    const gp_str = args[1];

    goosepack.setAllocators(arena, arena);
    var p = goosepack.init();

    const pack_in_memory: ?[]u8 = diskReadFileToMemory(gp_str) catch null;
    if (pack_in_memory != null) {
        try goosepack.load(&p, pack_in_memory.?);
    }

    {
        if (args.len < 3) {
            printUsage();
            return;
        }
        const action_str = args[2];
        const action = std.meta.stringToEnum(Action, action_str) orelse {
            std.log.err("Invalid action \"{s}\"\n", .{action_str});
            printUsage();
            return;
        };

        switch (action) {
            .list => {
                switch (args.len) {
                    3 => {
                        try stdout.print("gosepack version: {}\n", .{p.header.format_version});
                        try stdout.print("file iteration: {}\n", .{p.header.file_iteration});
                        try stdout.print("size: {} MiB\n\n", .{pack_in_memory.?.len / 1024 / 1024});

                        try stdout.print("{s:4} {s:32} {s:16} {s:16} {s:16}\n", .{ "id", "name", "type", "offset", "size" });
                        for (p.entries.?.items, 0..) |e, i| {
                            try stdout.print("{:3}: {s:32} {s:16} {:16} {:16}\n", .{ i, e.name, @tagName(e.type), e.offset, e.size });
                        }
                    },
                    4 => {
                        const id = try std.fmt.parseInt(usize, args[3], 10);
                        if (id >= p.entries.?.items.len) {
                            printUsage();
                            return;
                        }
                        // TODO(anjo): this double switch on entry
                        const entry = p.entries.?.items[id];
                        const resource = goosepack.getResource(&p, id);
                        switch (entry.type) {
                            .text => {
                                try stdout.writeAll(resource.text.bytes);
                            },
                            .shader => {
                                try stdout.print("== vertex shader ==\n", .{});
                                try stdout.writeAll(resource.shader.vs_bytes);
                                try stdout.print("== fragment shader ==\n", .{});
                                try stdout.writeAll(resource.shader.fs_bytes);
                                try stdout.print("f {}\n", .{resource.shader.fs_bytes[resource.shader.fs_bytes.len - 1]});
                                try stdout.print("v {}\n", .{resource.shader.vs_bytes[resource.shader.vs_bytes.len - 1]});
                            },
                            .texture => {
                                try stdout.print("size: {}x{}\n", .{ resource.image.width, resource.image.height });
                                try stdout.print("channels: {}\n", .{resource.image.channels});
                            },
                            .cubemap => {
                                try stdout.print("size: {}x{}\n", .{ resource.cubemap.width, resource.cubemap.height });
                                try stdout.print("channels: {}\n", .{resource.cubemap.channels});
                            },
                            .audio => {
                                try stdout.print("num samples: {}\n", .{resource.audio.samples.len});
                            },
                            .model => {
                                try stdout.print("binary data: {}\n", .{resource.model.binary_data.len});
                                for (resource.model.meshes, 0..) |m, i| {
                                    try stdout.print("mesh {}\n", .{i});
                                    for (m.primitives, 0..) |prim, j| {
                                        try stdout.print("  primitive {} - {}\n", .{ j, prim.buffer_types });
                                    }
                                }
                            },
                            .model_node => {
                                //const model = goosepack.lookup(&p, resource.model_node.model_name).model;
                                math.m4.print(resource.model_node.transform);
                            },
                            else => unreachable,
                        }
                    },
                    else => {
                        printUsage();
                        return;
                    },
                }
            },
            .add => {
                if (args.len < 4) {
                    printUsage();
                    return;
                }
                const resource_str = args[3];

                const res_type = std.meta.stringToEnum(goosepack.ResourceType, resource_str) orelse {
                    std.log.err("Invalid action \"{s}\"\n", .{resource_str});
                    printUsage();
                    return;
                };

                if (args.len < 5) {
                    std.log.err("Expected texture path", .{});
                    return;
                }
                const path = args[4];

                if (res_type == .directory) {
                    var map = std.StringHashMap(struct {
                        type: goosepack.ResourceType,
                        name: []const u8,
                        srcs: []goosepack.EntrySrc,
                    }).init(arena);
                    var worklist = std.ArrayList([]const u8).init(arena);
                    try worklist.append(path);

                    while (worklist.popOrNull()) |workitem| {
                        const dir = try std.fs.cwd().openDir(workitem, .{ .iterate = true });
                        var it = dir.iterate();
                        while (try it.next()) |e| {
                            const item_path = try std.fs.path.join(arena, &[_][]const u8{ workitem, e.name });
                            switch (e.kind) {
                                .file => {
                                    const basename = std.fs.path.stem(e.name);
                                    const extension = std.fs.path.extension(e.name);
                                    const name = try std.fs.path.join(arena, &[_][]const u8{ workitem, basename });

                                    if (std.mem.eql(u8, extension, ".vert") or
                                        std.mem.eql(u8, extension, ".frag"))
                                    {
                                        // Shaders
                                        if (!map.contains(name)) {
                                            const srcs = try gpa.alloc(goosepack.EntrySrc, 2);
                                            const exts = [2][]const u8{
                                                ".vert",
                                                ".frag",
                                            };
                                            for (srcs, 0..) |*s, i| {
                                                s.* = .{
                                                    .path = try std.mem.concat(gpa, u8, &[_][]const u8{
                                                        name,
                                                        exts[i],
                                                    }),
                                                };
                                            }

                                            try map.put(name, .{
                                                .type = .shader,
                                                .name = name,
                                                .srcs = srcs,
                                            });
                                        }
                                    } else if (std.mem.eql(u8, extension, ".png")) {
                                        if (std.mem.eql(u8, basename, "px") or
                                            std.mem.eql(u8, basename, "nx") or
                                            std.mem.eql(u8, basename, "py") or
                                            std.mem.eql(u8, basename, "ny") or
                                            std.mem.eql(u8, basename, "pz") or
                                            std.mem.eql(u8, basename, "nz"))
                                        {
                                            // Cubemap
                                            if (!map.contains(workitem)) {
                                                const srcs = try gpa.alloc(goosepack.EntrySrc, 6);
                                                const filenames = [6][]const u8{
                                                    "px.png",
                                                    "nx.png",
                                                    "py.png",
                                                    "ny.png",
                                                    "pz.png",
                                                    "nz.png",
                                                };
                                                for (srcs, 0..) |*s, i| {
                                                    s.* = .{
                                                        .path = try std.fs.path.join(arena, &[_][]const u8{
                                                            workitem,
                                                            filenames[i],
                                                        }),
                                                    };
                                                }

                                                try map.put(workitem, .{
                                                    .type = .cubemap,
                                                    .name = workitem,
                                                    .srcs = srcs,
                                                });
                                            }
                                        } else {
                                            // Texture
                                            const srcs = try gpa.alloc(goosepack.EntrySrc, 1);
                                            srcs[0] = .{
                                                .path = item_path,
                                            };
                                            try map.put(item_path, .{
                                                .type = .texture,
                                                .name = name,
                                                .srcs = srcs,
                                            });
                                        }
                                    } else if (std.mem.eql(u8, extension, ".ttf")) {
                                        const srcs = try gpa.alloc(goosepack.EntrySrc, 1);
                                        srcs[0] = .{
                                            .path = item_path,
                                        };
                                        try map.put(item_path, .{
                                            .type = .font,
                                            .name = name,
                                            .srcs = srcs,
                                        });
                                    } else if (std.mem.eql(u8, extension, ".ogg")) {
                                        // Audio
                                        const srcs = try gpa.alloc(goosepack.EntrySrc, 1);
                                        srcs[0] = .{
                                            .path = item_path,
                                        };
                                        try map.put(item_path, .{
                                            .type = .audio,
                                            .name = name,
                                            .srcs = srcs,
                                        });
                                    } else if (std.mem.eql(u8, extension, ".glb")) {
                                        // Model
                                        const srcs = try gpa.alloc(goosepack.EntrySrc, 1);
                                        srcs[0] = .{
                                            .path = item_path,
                                        };
                                        try map.put(item_path, .{
                                            .type = .model,
                                            .name = name,
                                            .srcs = srcs,
                                        });
                                    }
                                },
                                .directory => {
                                    try worklist.append(item_path);
                                },
                                else => unreachable,
                            }
                        }
                    }

                    var it = map.iterator();
                    while (it.next()) |e| {
                        try stdout.print("adding {s:32}: {s:16}\n", .{ e.key_ptr.*, @tagName(e.value_ptr.type) });
                        try diskLoadResource(&p, e.value_ptr.srcs, e.value_ptr.name, e.value_ptr.type);
                    }
                } else {
                    const ext = std.fs.path.extension(path);
                    const name = path[0 .. path.len - ext.len];
                    std.log.info("name {s}", .{name});
                    if (goosepack.lookupEntry(&p, name)) |ei| {
                        const entry = p.entries.?.items[ei.index];
                        std.log.info("always found \n{s}\n", .{entry.name});
                        if (goosepack.hasEntryBeenModified(entry)) {
                            std.log.info("modified", .{});
                            goosepack.deleteEntry(&p, entry);
                            const srcs = try gpa.alloc(goosepack.EntrySrc, 1);
                            srcs[0] = .{
                                .path = path,
                            };
                            try diskLoadResource(&p, srcs, name, res_type);
                        } else {
                            std.log.info("not modified", .{});
                        }
                    } else {
                        const srcs = try gpa.alloc(goosepack.EntrySrc, 1);
                        srcs[0] = .{
                            .path = path,
                        };
                        try diskLoadResource(&p, srcs, name, res_type);
                    }
                }
            },
            .del => {
                if (args.len < 4) {
                    printUsage();
                    return;
                }
                const id = try std.fmt.parseInt(usize, args[3], 10);
                if (id >= p.entries.?.items.len) {
                    std.log.err("{} not a valid entry id", .{id});
                    try stdout.print("{s:4} {s:32} {s:16} {s:16} {s:16}\n", .{ "id", "name", "type", "offset", "size" });
                    for (p.entries.?.items, 0..) |e, i| {
                        try stdout.print("{:3}: {s:32} {s:16} {:16} {:16}\n", .{ i, e.name, @tagName(e.type), e.offset, e.size });
                    }
                    try stdout_buffered_writer.flush();
                    return;
                }

                const entry = p.entries.?.items[id];
                goosepack.deleteEntry(&p, entry);
            },
            .update => {
                if (pack_in_memory == null) {
                    std.log.err("{s} does not exist\n", .{gp_str});
                    return;
                }

                var i: usize = 0;
                while (i < p.entries.?.items.len) {
                    const e = p.entries.?.items[i];
                    if (goosepack.hasEntryBeenModified(e)) {
                        try stdout.print("{s} modified\n", .{e.name});
                        goosepack.deleteEntry(&p, e);
                        try diskLoadResource(&p, e.srcs, e.name, e.type);
                    } else {
                        i += 1;
                    }
                }
            },
        }
    }

    try goosepack.saveToFile(&p, gp_str);

    arena_state.deinit();

    try stdout_buffered_writer.flush();
}

fn printUsage() void {
    std.log.err("Usage: pack [file] [resource] [option]...", .{});
}

const Action = enum(u8) {
    list,
    add,
    del,
    update,
};

//
// Disk
//

fn diskLoadResource(pack: *goosepack.Pack, srcs: []goosepack.EntrySrc, name: []const u8, res_type: goosepack.ResourceType) !void {
    switch (res_type) {
        .text => {
            var text = res.Text{};

            try diskLoadText(&text, srcs);
            try goosepack.addResource(pack, srcs, name, res_type, goosepack.Resource{
                .text = text,
            }, null, null);
        },
        .shader => {
            var shader = res.Shader{};

            try diskLoadShader(&shader, srcs);
            try goosepack.addResource(pack, srcs, name, res_type, goosepack.Resource{
                .shader = shader,
            }, null, null);
        },
        .texture => {
            var image = res.Image{};

            try diskLoadTexture(&image, srcs);
            try goosepack.addResource(pack, srcs, name, res_type, goosepack.Resource{
                .image = image,
            }, null, null);
        },
        .cubemap => {
            var cubemap = res.Cubemap{};

            try diskLoadCubemap(&cubemap, srcs);
            try goosepack.addResource(pack, srcs, name, res_type, goosepack.Resource{
                .cubemap = cubemap,
            }, null, null);
        },
        .audio => {
            var audio = res.Audio{};

            try diskLoadAudio(&audio, srcs);
            try goosepack.addResource(pack, srcs, name, res_type, goosepack.Resource{
                .audio = audio,
            }, null, null);
        },
        .model => {
            try diskLoadModel(pack, srcs, name);
        },
        .font => {
            var font = res.Font{};

            try diskLoadFont(&font, srcs);
            try goosepack.addResource(pack, srcs, name, res_type, goosepack.Resource{
                .font = font,
            }, null, null);
        },
        else => unreachable,
    }
}

fn diskLoadText(text: *res.Text, srcs: []goosepack.EntrySrc) !void {
    const buf = try diskReadFileToMemory(srcs[0].path);
    text.bytes = buf;
}

fn diskLoadShader(shader: *res.Shader, srcs: []goosepack.EntrySrc) !void {
    shader.vs_bytes = try diskReadFileToMemoryZeroTerminate(srcs[0].path);
    shader.fs_bytes = try diskReadFileToMemoryZeroTerminate(srcs[1].path);
}

fn diskLoadTexture(image: *res.Image, srcs: []goosepack.EntrySrc) !void {
    const buf = try diskReadFileToMemory(srcs[0].path);
    defer gpa.free(buf);

    var width: c_int = undefined;
    var height: c_int = undefined;
    var channels: c_int = undefined;
    const desired_channels = 4;

    const pixels = c.stbi_load_from_memory(buf.ptr, @intCast(buf.len), &width, &height, &channels, desired_channels) orelse {
        std.log.err("Failed to decode image {s}", .{srcs[0].path});
        return;
    };
    defer c.stbi_image_free(pixels);

    const bytes: usize = @intCast(width * height * channels);
    image.pixels = try arena.alloc(u8, bytes);
    @memcpy(image.pixels, pixels[0..bytes]);

    image.width = @intCast(width);
    image.height = @intCast(height);
    image.channels = @intCast(channels);
}

fn diskLoadCubemap(cm: *res.Cubemap, srcs: []goosepack.EntrySrc) !void {
    // Load first face and set cubemap format
    {
        const path = srcs[0].path;
        const buf = try diskReadFileToMemory(path);
        defer gpa.free(buf);

        var width: c_int = undefined;
        var height: c_int = undefined;
        var channels: c_int = undefined;
        const desired_channels = 4;

        const pixels = c.stbi_load_from_memory(buf.ptr, @intCast(buf.len), &width, &height, &channels, desired_channels) orelse {
            std.log.err("Failed to decode image {s}", .{path});
            return;
        };
        defer c.stbi_image_free(pixels);

        const bytes: u32 = @intCast(width * height * channels);
        cm.bytes = try arena.alloc(u8, 6 * bytes);
        cm.width = @intCast(width);
        cm.height = @intCast(height);
        cm.channels = @intCast(channels);
        @memcpy(cm.faceSlice(0), pixels[0..bytes]);
    }

    for (1..6) |i| {
        {
            const path = srcs[i].path;
            const buf = try diskReadFileToMemory(path);
            defer gpa.free(buf);

            var width: c_int = undefined;
            var height: c_int = undefined;
            var channels: c_int = undefined;
            const desired_channels = 4;

            const pixels = c.stbi_load_from_memory(buf.ptr, @intCast(buf.len), &width, &height, &channels, desired_channels) orelse {
                std.log.err("Failed to decode image {s}", .{path});
                return;
            };
            defer c.stbi_image_free(pixels);

            std.debug.assert(width == cm.width and height == cm.height and channels == cm.channels);
            const slice = cm.faceSlice(i);
            @memcpy(slice, pixels[0..slice.len]);
        }
    }
}

pub fn diskLoadAudio(audio: *res.Audio, srcs: []goosepack.EntrySrc) !void {
    const buf = try diskReadFileToMemory(srcs[0].path);
    defer gpa.free(buf);

    var err: c_int = undefined;
    const vorbis = c.stb_vorbis_open_memory(buf.ptr, @intCast(buf.len), &err, null) orelse {
        std.log.err("Failed to decode file: {s}", .{srcs[0].path});
        return;
    };
    std.debug.assert(err == 0);

    const vorbis_info = c.stb_vorbis_get_info(vorbis);
    const num_samples: usize = @as(c_uint, @intCast(vorbis_info.channels)) * c.stb_vorbis_stream_length_in_samples(vorbis);
    audio.samples = try arena.alloc(f32, num_samples);
    const samples_per_channel = c.stb_vorbis_get_samples_float_interleaved(vorbis, vorbis_info.channels, &audio.samples[0], @intCast(num_samples));
    std.debug.assert(samples_per_channel * 2 == num_samples);
}

pub fn diskLoadFont(font: *res.Font, srcs: []goosepack.EntrySrc) !void {
    const buf = try diskReadFileToMemory(srcs[0].path);
    defer gpa.free(buf);

    const num_chars = 96;
    font.size = 30;
    font.width = 512;
    font.height = 512;
    const size = @as(u32, @intCast(font.width)) * @as(u32, @intCast(font.height));
    font.pixels = try gpa.alloc(u8, size);
    font.chars = try gpa.alloc(res.FontChar, num_chars);

    const pd = try gpa.alloc(c.stbtt_packedchar, num_chars);
    defer gpa.free(pd);

    var spc: c.stbtt_pack_context = .{};
    std.debug.assert(c.stbtt_PackBegin(&spc, font.pixels.ptr, font.width, font.height, 0, 1, null) != 0);
    std.debug.assert(c.stbtt_PackFontRange(&spc, buf.ptr, 0, c.STBTT_POINT_SIZE(@as(f32, @floatFromInt(font.size))), 32, num_chars, pd.ptr) != 0);
    c.stbtt_PackEnd(&spc);

    for (pd, 0..) |p, i| {
        font.chars[i] = .{
            .x0 = p.x0,
            .y0 = p.y0,
            .x1 = p.x1,
            .y1 = p.y1,
            .xoff = p.xoff,
            .yoff = p.yoff,
            .xadvance = p.xadvance,
            .xoff2 = p.xoff2,
            .yoff2 = p.yoff2,
        };
    }
}

pub fn diskLoadModel(pack: *goosepack.Pack, srcs: []goosepack.EntrySrc, name: []const u8) !void {
    const buf = try diskReadFileToMemory(srcs[0].path);
    //defer gpa.free(buf);

    var options: c.cgltf_options = .{};
    std.log.info("options: {}", .{options});
    var maybe_data: ?*c.cgltf_data = null;
    const result = c.cgltf_parse(&options, @ptrCast(buf.ptr), buf.len, &maybe_data);
    defer c.cgltf_free(maybe_data);

    if (result != c.cgltf_result_success) {
        std.log.err("Failed to parse gltf[{}]: {s}", .{ result, srcs[0].path });
        return;
    }

    const data = maybe_data.?;

    std.log.info("data:", .{});
    std.log.info("  meshes:       {}", .{data.meshes_count});
    std.log.info("  materials:    {}", .{data.materials_count});
    std.log.info("  accessors:    {}", .{data.accessors_count});
    std.log.info("  buffer_views: {}", .{data.buffer_views_count});
    std.log.info("  buffers:      {}", .{data.buffers_count});
    std.log.info("  images:       {}", .{data.images_count});
    std.log.info("  textures:     {}", .{data.textures_count});
    std.log.info("  samplers:     {}", .{data.samplers_count});
    std.log.info("  skins:        {}", .{data.skins_count});
    std.log.info("  nodes:        {}", .{data.nodes_count});
    std.log.info("  animations:   {}", .{data.animations_count});
    std.log.info("  variants:     {}", .{data.variants_count});
    std.log.info("  bin size:     {}", .{data.bin_size});

    for (0..data.materials_count) |i| {
        const material = &data.materials[i];
        std.log.info("material {}", .{i});
        std.log.info("  has_pbr_metallic_roughness {}", .{material.has_pbr_metallic_roughness});
        std.log.info("  has_pbr_specular_glossiness {}", .{material.has_pbr_specular_glossiness});
        std.log.info("  has_clearcoat {}", .{material.has_clearcoat});
        std.log.info("  has_transmission {}", .{material.has_transmission});
        std.log.info("  has_volume {}", .{material.has_volume});
        std.log.info("  has_ior {}", .{material.has_ior});
        std.log.info("  has_specular {}", .{material.has_specular});
        std.log.info("  has_sheen {}", .{material.has_sheen});
        std.log.info("  has_emissive_strength {}", .{material.has_emissive_strength});
        std.log.info("  has_iridescence {}", .{material.has_iridescence});
        std.log.info("  has_anisotropy {}", .{material.has_anisotropy});
        std.log.info("  has_dispersion {}", .{material.has_dispersion});
    }

    var model = res.Model{};

    // copy binary data
    std.log.info("  copying binary data", .{});
    {
        const base: [*]u8 = @constCast(@ptrCast(data.bin.?));
        const slice: []u8 = @as([*]u8, @ptrCast(base))[0..data.bin_size];
        model.binary_data = slice;
    }

    // buffer views
    std.log.info("Adding {} buffer views", .{data.buffer_views_count});
    for (0..data.buffer_views_count) |i| {
        const view = &data.buffer_views[i];
        //std.log.info("{}", .{view});
        //std.log.info("{}", .{view.buffer.*});
        std.log.info("view offset {} [{}]", .{ view.offset, view.size });
        //switch (view.type) {
        //    c.cgltf_buffer_view_type_indices => {
        //        std.log.info("{}: index buffer", .{i});
        //        std.debug.assert(view.buffer.*.uri == null);
        //        const base: [*]align(1) u8 = @alignCast(buf.ptr + view.offset);
        //        var dd: []u8 = @as([*]u8, @ptrCast(base))[0..view.size];
        //        _ = dd;
        //        //for (dd) |d| {
        //        //    std.log.info("{}", .{d});
        //        //}
        //    },
        //    c.cgltf_buffer_view_type_vertices => {
        //        std.debug.assert(view.buffer.*.uri == null);
        //        const base: [*]align(4) u8 = @alignCast(buf.ptr + 4*view.offset);
        //        _ = base;
        //        //var dd: []f32 = @as([*]f32, @ptrCast(base))[0..view.size/4];
        //        std.log.info("{}: vertex buffer", .{i});
        //        //for (dd) |d| {
        //        //    std.log.info("{}", .{d});
        //        //}
        //    },
        //    else => unreachable,
        //}
    }

    // buffers
    //std.log.info("  Adding {} buffers", .{data.buffers_count});
    //for (0..data.buffers_count) |i| {
    //    const buffer = &data.buffers[i];
    ////    if (buffer.uri) |uri| {
    ////        std.log.info("buffer uri {s}", .{uri});
    ////    }
    //    std.log.info("buffer {}", .{buffer});
    //}

    // images

    // materials

    // meshes
    std.log.info("  {} meshes", .{data.meshes_count});
    model.materials = try arena.alloc(res.Material, data.materials_count);
    for (0..data.materials_count) |i| {
        const mat = &data.materials[i];
        model.materials[i] = .{
            .base_color = .{
                .x = mat.pbr_metallic_roughness.base_color_factor[0],
                .y = mat.pbr_metallic_roughness.base_color_factor[1],
                .z = mat.pbr_metallic_roughness.base_color_factor[2],
                .w = mat.pbr_metallic_roughness.base_color_factor[3],
            },
        };
    }
    model.meshes = try arena.alloc(res.Mesh, data.meshes_count);
    model.nodes = try arena.alloc(u32, data.nodes_count);
    for (0..data.meshes_count) |i| {
        const mesh = &data.meshes[i];
        model.meshes[i].primitives = try arena.alloc(res.MeshPrimitive, mesh.primitives_count);

        std.log.info("    {} primitives", .{mesh.primitives_count});
        for (0..mesh.primitives_count) |j| {
            const prim = &mesh.primitives[j];
            model.meshes[i].primitives[j].material_index = @as(res.MaterialIndex, @intCast(@intFromPtr(prim.material) - @intFromPtr(data.materials))) / @sizeOf(@typeInfo(@TypeOf(data.materials)).Pointer.child);

            var buffer_types: u8 = 0;

            const prim_type = gltf_to_prim_type(prim.type);
            std.log.info("      prim type {}", .{prim_type});
            if (prim.indices) |acc| {
                const index_type = gltf_to_index_type(prim);
                std.log.info("      index type {}", .{index_type});

                const view = acc.*.buffer_view;
                std.log.info("        view offset {}", .{view.*.offset});
                std.log.info("        view count {}", .{view.*.size});
                std.log.info("        view stride {}", .{view.*.stride});
                // TODO: add support for [*], I assume these count as slices
                model.meshes[i].primitives[j].indices = .{ .offset = @intCast(view.*.offset), .size = @intCast(view.*.size) };
                buffer_types |= res.bt_indices;
            }

            std.log.info("      {} attributes", .{prim.attributes_count});
            for (0..prim.attributes_count) |k| {
                const attr = &prim.attributes[k];
                const acc = attr.data;
                const vs_format = gltf_to_vertex_format(acc);
                const slot = gltf_attr_type_to_vs_input_slot(attr.type);
                std.log.info("        vs format {}", .{vs_format});
                std.log.info("        slot {}", .{slot});
                std.log.info("        offset {}", .{acc.*.offset});
                std.log.info("        count {}", .{acc.*.count});
                std.log.info("        stride {}", .{acc.*.stride});

                const view = acc.*.buffer_view;
                std.log.info("        view offset {}", .{view.*.offset});
                std.log.info("        view count {}", .{view.*.size});
                std.log.info("        view stride {}", .{view.*.stride});

                switch (slot) {
                    .position => {
                        model.meshes[i].primitives[j].pos = .{ .offset = @intCast(view.*.offset), .size = @intCast(view.*.size) };
                        buffer_types |= res.bt_position;
                    },
                    .normal => {
                        model.meshes[i].primitives[j].normals = .{ .offset = @intCast(view.*.offset), .size = @intCast(view.*.size) };
                        buffer_types |= res.bt_normals;
                    },
                    .texcoord => {
                        model.meshes[i].primitives[j].texcoords = .{ .offset = @intCast(view.*.offset), .size = @intCast(view.*.size) };
                        buffer_types |= res.bt_texcoords;
                    },
                    else => unreachable,
                }
            }

            model.meshes[i].primitives[j].buffer_types = buffer_types;
        }
    }

    const z_to_y_up = math.m4.fromQuat(math.Quat.fromAxisAngle(.{ .x = 1, .y = 0, .z = 0 }, -std.math.pi / 2.0));
    // nodes
    const first_node_index: u32 = @intCast(pack.entries.?.items.len);
    for (0..data.nodes_count) |i| {
        const node = &data.nodes[i];
        std.log.info("node {} - {s}", .{ i, node.name });
        std.log.info("  {}", .{node.has_translation});
        std.log.info("  {}", .{node.has_scale});
        std.log.info("  {}", .{node.has_rotation});
        std.log.info("  {}", .{node.has_matrix});

        var mesh_index: ?u32 = null;
        if (node.mesh != null) {
            mesh_index = @intCast((@intFromPtr(node.mesh) - @intFromPtr(data.meshes)) / @sizeOf(c.cgltf_mesh));
        }

        var model_node = res.ModelNode{
            .model_name = name,
            .mesh_index = mesh_index,
            .transform = math.identity,
        };
        if (node.parent == null) {
            model_node.transform = math.m4.mul(model_node.transform, z_to_y_up);
            //model_node.transform = z_to_y_up;
        } else {
            if (node.has_matrix == 1) {
                model_node.transform.m00 = node.matrix[0];
                model_node.transform.m01 = node.matrix[1];
                model_node.transform.m02 = node.matrix[2];
                model_node.transform.m03 = node.matrix[3];

                model_node.transform.m10 = node.matrix[4];
                model_node.transform.m11 = node.matrix[5];
                model_node.transform.m12 = node.matrix[6];
                model_node.transform.m13 = node.matrix[7];

                model_node.transform.m20 = node.matrix[8];
                model_node.transform.m21 = node.matrix[9];
                model_node.transform.m22 = node.matrix[10];
                model_node.transform.m23 = node.matrix[11];

                model_node.transform.m30 = node.matrix[12];
                model_node.transform.m31 = node.matrix[13];
                model_node.transform.m32 = node.matrix[14];
                model_node.transform.m33 = node.matrix[15];
            } else {
                const t: math.v3 = if (node.has_translation == 1) .{ .x = node.translation[0], .y = node.translation[1], .z = node.translation[2] } else math.v3.zeros();
                const s: math.v3 = if (node.has_scale == 1) .{ .x = node.scale[0], .y = node.scale[1], .z = node.scale[2] } else math.v3.ones();
                const r: math.Quat = if (node.has_rotation == 1) .{ .v = .{ .x = node.rotation[0], .y = node.rotation[1], .z = node.rotation[2] }, .s = node.rotation[3] } else .{};
                model_node.transform = math.m4.from(t, r, s);
            }
        }

        var parent: ?u32 = null;
        var parent_index: ?u32 = null;
        if (node.parent != null) {
            const a: u32 = @intCast(@intFromPtr(node.parent.?));
            const b: u32 = @intCast(@intFromPtr(data.nodes));
            parent_index = (a - b) / @sizeOf(c.cgltf_node);
            parent = first_node_index + parent_index.?;
        }

        var children: ?[]u32 = null;
        if (node.children_count > 0) {
            children = try arena.alloc(u32, node.children_count);
        }
        const new_name = try std.fs.path.join(arena, &[_][]const u8{ name, std.mem.span(node.name) });
        for (0..node.children_count) |j| {
            const child = &node.children[j][0];
            const a: u32 = @intCast(@intFromPtr(child));
            const b: u32 = @intCast(@intFromPtr(data.nodes));
            const child_index = (a - b) / @sizeOf(c.cgltf_node);
            children.?[j] = first_node_index + child_index;
            std.log.info("    {} - {}", .{ j, child_index });
        }

        model.nodes[i] = @intCast(pack.resources.?.items.len);
        try goosepack.addResource(pack, srcs, new_name, .model_node, .{
            .model_node = model_node,
        }, parent, children);
    }

    try goosepack.addResource(pack, srcs, name, .model, goosepack.Resource{
        .model = model,
    }, null, null);
}

fn gltf_to_vertex_format(acc: *c.cgltf_accessor) sg.VertexFormat {
    switch (acc.component_type) {
        c.cgltf_component_type_r_8 => {
            if (acc.type == c.cgltf_type_vec4) {
                return if (acc.normalized != 0) .BYTE4N else .BYTE4;
            }
        },
        c.cgltf_component_type_r_8u => {
            if (acc.type == c.cgltf_type_vec4) {
                return if (acc.normalized != 0) .UBYTE4N else .UBYTE4;
            }
        },
        c.cgltf_component_type_r_16 => {
            switch (acc.type) {
                c.cgltf_type_vec2 => return if (acc.normalized != 0) .SHORT2N else .SHORT2,
                c.cgltf_type_vec4 => return if (acc.normalized != 0) .SHORT4N else .SHORT4,
                else => unreachable,
            }
        },
        c.cgltf_component_type_r_32f => {
            switch (acc.type) {
                c.cgltf_type_scalar => return .FLOAT,
                c.cgltf_type_vec2 => return .FLOAT2,
                c.cgltf_type_vec3 => return .FLOAT3,
                c.cgltf_type_vec4 => return .FLOAT4,
                else => unreachable,
            }
        },
        else => {},
    }
    return .INVALID;
}

fn gltf_attr_type_to_vs_input_slot(attr_type: c.cgltf_attribute_type) res.VertexAttribute {
    switch (attr_type) {
        c.cgltf_attribute_type_position => return .position,
        c.cgltf_attribute_type_normal => return .normal,
        c.cgltf_attribute_type_texcoord => return .texcoord,
        else => unreachable,
    }
}

fn gltf_to_prim_type(prim_type: c.cgltf_primitive_type) sg.PrimitiveType {
    switch (prim_type) {
        c.cgltf_primitive_type_points => return .POINTS,
        c.cgltf_primitive_type_lines => return .LINES,
        c.cgltf_primitive_type_line_strip => return .LINE_STRIP,
        c.cgltf_primitive_type_triangles => return .TRIANGLES,
        c.cgltf_primitive_type_triangle_strip => return .TRIANGLE_STRIP,
        else => unreachable,
    }
}

fn gltf_to_index_type(prim: *allowzero c.cgltf_primitive) sg.IndexType {
    if (prim.indices != null) {
        if (prim.indices.*.component_type == c.cgltf_component_type_r_16u) {
            return .UINT16;
        } else {
            return .UINT32;
        }
    }

    unreachable;
}

fn diskReadFileToMemory(path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    const size = (try file.stat()).size;
    const buf = try file.readToEndAllocOptions(gpa, size, null, @alignOf(u64), null);
    return buf;
}

fn diskReadFileToMemoryZeroTerminate(path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    const size = (try file.stat()).size + 1;

    var array_list = try std.ArrayListAligned(u8, 1).initCapacity(gpa, size);
    defer array_list.deinit();
    try file.reader().readAllArrayListAligned(1, &array_list, size);
    try array_list.append(0);
    const buf = try array_list.toOwnedSlice();
    return buf;
}

//
// GLTF specifics
//
