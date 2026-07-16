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

const native_endian = std.builtin.target.cpu.arch.endian();

pub var arena_frame: *common.Arena = undefined;
pub var arena_persistent: *common.ArenaFreelist = undefined;

pub fn load_resource(pack: *goosepack.Pack, srcs: []goosepack.EntrySrc, name: []const u8, res_type: goosepack.ResourceType) !goosepack.Entry {
    switch (res_type) {
        .text => {
            var text = res.Text{};
            try load_text(&text, srcs);
            return try goosepack.resource_append(pack, srcs, name, res_type, goosepack.Resource{
                .text = text,
            }, null, null);
        },
        .shader => {
            var shader = res.Shader{};
            try load_shader(&shader, srcs);
            return try goosepack.resource_append(pack, srcs, name, res_type, goosepack.Resource{
                .shader = shader,
            }, null, null);
        },
        .texture => {
            var image = res.Image{};
            try load_texture(&image, srcs);
            return try goosepack.resource_append(pack, srcs, name, res_type, goosepack.Resource{
                .image = image,
            }, null, null);
        },
        .cubemap => {
            var cubemap = res.Cubemap{};
            try load_cubemap(&cubemap, srcs);
            return try goosepack.resource_append(pack, srcs, name, res_type, goosepack.Resource{
                .cubemap = cubemap,
            }, null, null);
        },
        .audio => {
            var audio = res.Audio{};
            try load_audio(&audio, srcs);
            return try goosepack.resource_append(pack, srcs, name, res_type, goosepack.Resource{
                .audio = audio,
            }, null, null);
        },
        .model => {
            // TODO: breaks pattern:( maybe more simplification is possible
            var model = res.Model{};
            return try load_model(pack, &model, srcs, name);
        },
        .font => {
            var font = res.Font{};

            try load_font(&font, srcs);
            return try goosepack.resource_append(pack, srcs, name, res_type, goosepack.Resource{
                .font = font,
            }, null, null);
        },
        else => unreachable,
    }
}

pub fn collect_and_update_entries(pack: *goosepack.Pack) ![]goosepack.Entry {
    var used: usize = 0;
    var entries = arena_frame.alloc(goosepack.Entry, pack.entries.len);

    var i: usize = 0;
    while (i < pack.entries.len) {
        const e = pack.entries[i];
        if (e.parent == null and goosepack.has_entry_been_modified(e)) {
            try goosepack.entry_delete_child_tree(pack, i);
            entries[used] = e;
            used += 1;
        } else {
            i += 1;
        }
    }

    for (entries[0..used]) |*e| {
        e.* = try load_resource(pack, e.srcs, e.name, e.type);
    }

    try generate_pack_ids(pack);

    return entries[0..used];
}

// @TODO(anjo): Move to save?
pub fn generate_pack_ids(pack: *goosepack.Pack) !void {
    const fd = try std.fs.cwd().createFile("src/common/generated/res-ids.zig", .{});
    defer fd.close();
    var buffer: [1024]u8 = undefined;
    var w = fd.writer(&buffer);
    const wi = &w.interface;
    for (pack.entries, 0..) |e,j| {
        try wi.print("const {s} = {};\n", .{e.name, j});
        //if (e.type == .model_node) {
        //    for (pack.resources[j].model_node.tree.nodes, 0..) |n,k| {
        //    }
        //}
    }
}

fn read_file_with_size(file: std.fs.File, buf: []u8) void {
    var read_buffer: [1024]u8 = undefined;
    var file_reader = file.reader(&read_buffer);
    const reader = &file_reader.interface;
    reader.readSliceAll(buf) catch unreachable;
}

pub fn read_file_to_persistent_memory(path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    const size = (try file.stat()).size;

    const buf = arena_persistent.alloc(u8, size);
    read_file_with_size(file, buf);
    return buf;
}

pub fn read_file_to_persistent_memory_zero_terminate(path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    const size = (try file.stat()).size + 1;

    const buf = arena_persistent.alloc(u8, size);
    buf[size - 1] = 0;
    read_file_with_size(file, buf[0 .. size - 1]);
    return buf;
}

pub fn read_file_to_frame_memory(path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    const size = (try file.stat()).size;

    const buf = arena_frame.alloc(u8, size);
    read_file_with_size(file, buf);
    return buf;
}

pub fn read_file_to_frame_memory_zero_terminate(path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    const size = (try file.stat()).size + 1;

    const buf = arena_frame.alloc(u8, size);
    buf[size - 1] = 0;
    read_file_with_size(file, buf[0 .. size - 1]);
    return buf;
}

fn load_text(text: *res.Text, srcs: []goosepack.EntrySrc) !void {
    text.bytes = try read_file_to_persistent_memory(srcs[0].path);
}

fn load_shader(shader: *res.Shader, srcs: []goosepack.EntrySrc) !void {
    shader.vs_bytes = try read_file_to_persistent_memory_zero_terminate(srcs[0].path);
    shader.fs_bytes = try read_file_to_persistent_memory_zero_terminate(srcs[1].path);
}

fn load_png_from_memory(buf: []const u8) ?res.Image {
    var width: c_int = undefined;
    var height: c_int = undefined;
    var channels: c_int = undefined;
    const desired_channels = 4;

    const pixels = c.stbi_load_from_memory(buf.ptr, @intCast(buf.len), &width, &height, &channels, desired_channels) orelse return null;
    defer c.stbi_image_free(pixels);

    var image: res.Image = undefined;

    const bytes: usize = @intCast(width * height * desired_channels);
    image.pixels = arena_persistent.alloc(u8, bytes);
    @memcpy(image.pixels, pixels[0..bytes]);

    image.width = @intCast(width);
    image.height = @intCast(height);
    image.channels = @intCast(desired_channels);

    return image;
}

fn load_texture(image: *res.Image, srcs: []goosepack.EntrySrc) !void {
    const buf = try read_file_to_frame_memory(srcs[0].path);
    image.* = load_png_from_memory(buf) orelse {
        std.log.err("Failed to decode image {s}", .{srcs[0].path});
        return;
    };
}

fn load_cubemap(cm: *res.Cubemap, srcs: []goosepack.EntrySrc) !void {
    // Load first face and set cubemap format
    {
        const path = srcs[0].path;
        const buf = try read_file_to_frame_memory(path);

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
        cm.bytes = arena_persistent.alloc(u8, 6 * bytes);
        cm.width = @intCast(width);
        cm.height = @intCast(height);
        cm.channels = @intCast(channels);
        @memcpy(cm.faceSlice(0), pixels[0..bytes]);
    }

    for (1..6) |i| {
        {
            const path = srcs[i].path;
            const buf = try read_file_to_frame_memory(path);

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

fn load_audio(audio: *res.Audio, srcs: []goosepack.EntrySrc) !void {
    const buf = try read_file_to_frame_memory(srcs[0].path);

    var err: c_int = undefined;
    const vorbis = c.stb_vorbis_open_memory(buf.ptr, @intCast(buf.len), &err, null) orelse {
        std.log.err("Failed to decode file: {s}", .{srcs[0].path});
        return;
    };
    std.debug.assert(err == 0);

    const vorbis_info = c.stb_vorbis_get_info(vorbis);
    const num_samples: usize = @as(c_uint, @intCast(vorbis_info.channels)) * c.stb_vorbis_stream_length_in_samples(vorbis);
    audio.samples = arena_persistent.alloc(f32, num_samples);
    const samples_per_channel = c.stb_vorbis_get_samples_float_interleaved(vorbis, vorbis_info.channels, &audio.samples[0], @intCast(num_samples));
    std.debug.assert(samples_per_channel * 2 == num_samples);
}

fn load_font(font: *res.Font, srcs: []goosepack.EntrySrc) !void {
    const buf = try read_file_to_frame_memory(srcs[0].path);

    const num_chars = 96;
    font.size = 30;
    font.width = 512;
    font.height = 512;
    const size = @as(u32, @intCast(font.width)) * @as(u32, @intCast(font.height));
    font.pixels = arena_persistent.alloc(u8, size);
    font.chars = arena_persistent.alloc(res.FontChar, num_chars);

    const pd = arena_frame.alloc(c.stbtt_packedchar, num_chars);

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

fn path_persistent_join(l: []const u8, r: []const u8) []u8 {
    const buf = arena_persistent.alloc(u8, l.len + r.len + 1);
    @memcpy(buf[0..l.len], l);
    @memcpy(buf[l.len + 1 ..], r);
    buf[l.len] = std.fs.path.sep;
    return buf;
}

fn path_persistent_join_3(l: []const u8, m: []const u8, r: []const u8) []u8 {
    const buf = arena_persistent.alloc(u8, l.len + m.len + r.len + 2);

    @memcpy(buf[0..l.len], l);
    buf[l.len] = std.fs.path.sep;

    @memcpy(buf[l.len + 1 .. l.len + m.len + 1], m);
    buf[l.len + m.len + 1] = std.fs.path.sep;

    @memcpy(buf[l.len + m.len + 2 ..], r);
    return buf;
}

fn load_model(pack: *goosepack.Pack, model: *res.Model, srcs: []goosepack.EntrySrc, name: []const u8) anyerror!error{ InvalidGLTF, TextureDecodeFailure }!goosepack.Entry {
    const buf = try read_file_to_frame_memory(srcs[0].path);

    var options: c.cgltf_options = .{};
    var maybe_data: ?*c.cgltf_data = null;
    const result = c.cgltf_parse(&options, @ptrCast(buf.ptr), buf.len, &maybe_data);
    defer c.cgltf_free(maybe_data);

    if (result != c.cgltf_result_success) {
        std.log.err("Failed to parse gltf[{}]: {s}", .{ result, srcs[0].path });
        return error.InvalidGLTF;
    }

    const data = maybe_data.?;

    const binary_base: [*]u8 = @ptrCast(@constCast(data.bin.?));
    const binary_data: []u8 = @as([*]u8, @ptrCast(binary_base))[0..data.bin_size];
    model.binary_data = arena_persistent.alloc(u8, binary_data.len);
    @memcpy(model.binary_data, binary_data);

    model.id = @intFromPtr(binary_base);

    // images

    // materials

    // meshes
    model.materials = arena_persistent.alloc(res.Material, data.materials_count);
    @memset(model.materials.?, .{});
    for (0..data.materials_count) |i| {
        const mat = &data.materials[i];
        if (mat.has_pbr_metallic_roughness == 1) {
            const pbr = &mat.pbr_metallic_roughness;

            var model_mat = res.Material{
                .base_color = .{
                    .x = pbr.base_color_factor[0],
                    .y = pbr.base_color_factor[1],
                    .z = pbr.base_color_factor[2],
                    .w = pbr.base_color_factor[3],
                },
            };

            if (pbr.base_color_texture.texture != null) {
                const image = pbr.base_color_texture.texture.*.image;

                const view = image.*.buffer_view;
                model_mat.image = load_png_from_memory(model.binary_data[view.*.offset..(view.*.offset + view.*.size)]) orelse {
                    std.log.err("Failed to decode model subimage {s}", .{image.*.name});
                    return error.TextureDecodeFailure;
                };
            }

            model.materials.?[i] = model_mat;
        }
    }

    model.meshes = arena_persistent.alloc(res.Mesh, data.meshes_count);
    model.nodes = arena_persistent.alloc(u32, data.nodes_count);

    for (0..data.meshes_count) |i| {
        const mesh = &data.meshes[i];
        model.meshes[i].primitives = arena_persistent.alloc(res.MeshPrimitive, mesh.primitives_count);

        for (0..mesh.primitives_count) |j| {
            const prim = &mesh.primitives[j];

            // default initialize primitive
            model.meshes[i].primitives[j] = .{};

            if (prim.material != null) {
                model.meshes[i].primitives[j].material_index = @as(res.MaterialIndex, @intCast(@intFromPtr(prim.material) - @intFromPtr(data.materials))) / @sizeOf(@typeInfo(@TypeOf(data.materials)).pointer.child);
            }

            var buffer_types: u8 = 0;
            if (prim.indices) |acc| {
                const view = acc.*.buffer_view;
                // TODO: add support for [*], I assume these count as slices
                model.meshes[i].primitives[j].indices = model.binary_data[view.*.offset..(view.*.offset + view.*.size)];
                buffer_types |= res.bt_indices;
            }

            for (0..prim.attributes_count) |k| {
                const attr = &prim.attributes[k];
                const acc = attr.data;
                const slot = gltf_attr_type_to_vs_input_slot(attr.type);
                const view = acc.*.buffer_view;

                const view_slice = model.binary_data[view.*.offset..(view.*.offset + view.*.size)];
                switch (slot) {
                    .position => {
                        model.meshes[i].primitives[j].pos = view_slice;
                        buffer_types |= res.bt_position;
                    },
                    .normal => {
                        model.meshes[i].primitives[j].normals = view_slice;
                        buffer_types |= res.bt_normals;
                    },
                    .texcoord => {
                        model.meshes[i].primitives[j].texcoords = view_slice;
                        buffer_types |= res.bt_texcoords;
                    },
                    else => unreachable,
                }
            }

            model.meshes[i].primitives[j].buffer_types = buffer_types;
        }
    }

    const root_entry_index = pack.entries.len;
    //const root_resource_index = pack.resources.?.items.len;
    //var num_root_children: usize = 0;
    //var root_children: []i32 = try persistent.alloc(i32, data.nodes_count);

    const root_entry = try goosepack.resource_append(pack, srcs, name, .model, goosepack.Resource{
        .model = model.*,
    }, null, null);

    //const first_node_index: i32 = @intCast(pack.entries.?.items.len);
    for (0..data.nodes_count) |i| {
        const node = &data.nodes[i];
        if (node.parent == null) {
            // compute number of children
            var num_nodes: usize = 0;
            {
                var stack = common.IntrusiveList(struct {
                    //info: goosepack.EntryInfo,
                    node: @TypeOf(node),
                    parent_transform: math.m4 = undefined,
                    parent_index: u8 = 0,
                }){
                    .arena = arena_frame,
                };
                stack.append(.{
                    .node = node,
                });

                while (stack.pop()) |item| {
                    num_nodes += 1;
                    for (0..item.node.children_count) |j| {
                        const child = &item.node.children[j][0];
                        stack.append(.{
                            .node = child,
                        });
                    }
                }
            }

            var index: usize = 0;
            var nodes = arena_persistent.alloc(common.TransformTreeNode, num_nodes);
            var node_ids = arena_persistent.alloc(res.Id, num_nodes);

            // fill out children transform
            {
                var stack = common.IntrusiveList(struct {
                    node: @TypeOf(node),
                    parent_transform: math.m4 = undefined,
                    parent_index: u8 = 0,
                }){
                    .arena = arena_frame,
                };
                stack.append(.{
                    .node = node,
                    .parent_transform = math.m4_identity,
                });
                while (stack.pop()) |item| {
                    var transform = math.m4_identity;
                    if (item.node.parent != null) {
                        if (item.node.has_matrix == 1) {
                            transform.m00 = item.node.matrix[0];
                            transform.m01 = item.node.matrix[1];
                            transform.m02 = item.node.matrix[2];
                            transform.m03 = item.node.matrix[3];

                            transform.m10 = item.node.matrix[4];
                            transform.m11 = item.node.matrix[5];
                            transform.m12 = item.node.matrix[6];
                            transform.m13 = item.node.matrix[7];

                            transform.m20 = item.node.matrix[8];
                            transform.m21 = item.node.matrix[9];
                            transform.m22 = item.node.matrix[10];
                            transform.m23 = item.node.matrix[11];

                            transform.m30 = item.node.matrix[12];
                            transform.m31 = item.node.matrix[13];
                            transform.m32 = item.node.matrix[14];
                            transform.m33 = item.node.matrix[15];
                        } else {
                            const t: math.v3 = if (item.node.has_translation == 1) .{ .x = item.node.translation[0], .y = item.node.translation[1], .z = item.node.translation[2] } else math.v3.zeros();
                            const s: math.v3 = if (item.node.has_scale == 1) .{ .x = item.node.scale[0], .y = item.node.scale[1], .z = item.node.scale[2] } else math.v3.ones();
                            const r: math.Quat = if (item.node.has_rotation == 1) .{ .v = .{ .x = item.node.rotation[0], .y = item.node.rotation[1], .z = item.node.rotation[2] }, .s = item.node.rotation[3] } else .{};
                            transform = math.m4.from_transform(.{ .position = t, .rotation = r, .scale = s });
                        }
                    }

                    var mesh_index: ?common.res.MeshIndex = null;
                    if (item.node.mesh != null) {
                        mesh_index = @intCast((@intFromPtr(item.node.mesh) - @intFromPtr(data.meshes)) / @sizeOf(c.cgltf_mesh));
                    }

                    nodes[index] = .{
                        .transform = transform,
                        .root_transform = math.m4.mul(item.parent_transform, transform),
                        .mesh_index = mesh_index,
                        .parent = item.parent_index,
                        .flags = .{
                            .dirty = 1,
                        },
                    };
                    node_ids[index] = res.runtime_pack_id(path_persistent_join(name, std.mem.span(item.node.name)));
                    index += 1;

                    for (0..item.node.children_count) |j| {
                        const child = &item.node.children[j][0];
                        stack.append(.{
                            .node = child,
                            .parent_transform = transform,
                            .parent_index = @intCast(nodes.len - 1),
                        });
                    }
                }
            }

            const new_name = path_persistent_join(name, std.mem.span(node.name));

            const tree = common.TransformTree{
                .nodes = nodes,
                .node_ids = node_ids,
                .id = common.res.runtime_pack_id(name),
                .flags = .{
                    .dirty = 1,
                },
            };

            // Hacky but whatever
            //pack.resources.?.items[root_resource_index].model.nodes[i] = @intCast(pack.resources.?.items.len);
            const node_index: i32 = @intCast(pack.entries.len);
            //var parent: ?i32 = null;
            //if (node.parent != null) {
            //    const a: u32 = @intCast(@intFromPtr(node.parent.?));
            //    const b: u32 = @intCast(@intFromPtr(data.nodes));
            //    const parent_index: i32 = @intCast((a - b) / @sizeOf(c.cgltf_node));
            //    parent = first_node_index + parent_index - node_index;
            //} else {
            //    parent = @as(i32, @intCast(root_entry_index)) - node_index;
            //}
            const model_node = res.ModelNode{
                .root_entry_relative_index = @as(i32, @intCast(root_entry_index)) - node_index,
                .tree = tree,
            };
            _ = try goosepack.resource_append(pack, srcs, new_name, .model_node, .{
                .model_node = model_node,
            }, null, null);
        }
        //const transform = math.m4_identity;
    }

    // nodes
    //const first_node_index: i32 = @intCast(pack.entries.?.items.len);
    //for (0..data.nodes_count) |i| {
    //    const node = &data.nodes[i];

    //    var mesh_index: ?u32 = null;
    //    if (node.mesh != null) {
    //        mesh_index = @intCast((@intFromPtr(node.mesh) - @intFromPtr(data.meshes)) / @sizeOf(c.cgltf_mesh));
    //    }

    //    var model_node = res.ModelNode{
    //        .mesh_index = mesh_index,
    //        .transform = math.m4_identity,
    //    };

    //    const node_index: i32 = @intCast(pack.entries.?.items.len);

    //    if (node.parent == null) {
    //        //const z_to_y_up = math.m4.fromQuat(math.Quat.fromAxisAngle(.{ .x = 1, .y = 0, .z = 0 }, -std.math.pi / 2.0));
    //        //model_node.transform = math.m4.mul(model_node.transform, z_to_y_up);
    //        root_children[num_root_children] = node_index - @as(i32, @intCast(root_entry_index));
    //        num_root_children += 1;
    //    } else {
    //        if (node.has_matrix == 1) {
    //            model_node.transform.m00 = node.matrix[0];
    //            model_node.transform.m01 = node.matrix[1];
    //            model_node.transform.m02 = node.matrix[2];
    //            model_node.transform.m03 = node.matrix[3];

    //            model_node.transform.m10 = node.matrix[4];
    //            model_node.transform.m11 = node.matrix[5];
    //            model_node.transform.m12 = node.matrix[6];
    //            model_node.transform.m13 = node.matrix[7];

    //            model_node.transform.m20 = node.matrix[8];
    //            model_node.transform.m21 = node.matrix[9];
    //            model_node.transform.m22 = node.matrix[10];
    //            model_node.transform.m23 = node.matrix[11];

    //            model_node.transform.m30 = node.matrix[12];
    //            model_node.transform.m31 = node.matrix[13];
    //            model_node.transform.m32 = node.matrix[14];
    //            model_node.transform.m33 = node.matrix[15];
    //        } else {
    //            const t: math.v3 = if (node.has_translation == 1) .{ .x = node.translation[0], .y = node.translation[1], .z = node.translation[2] } else math.v3.zeros();
    //            const s: math.v3 = if (node.has_scale == 1) .{ .x = node.scale[0], .y = node.scale[1], .z = node.scale[2] } else math.v3.ones();
    //            const r: math.Quat = if (node.has_rotation == 1) .{ .v = .{ .x = node.rotation[0], .y = node.rotation[1], .z = node.rotation[2] }, .s = node.rotation[3] } else .{};
    //            model_node.transform = math.m4.from(t, r, s);
    //        }
    //    }

    //    var parent: ?i32 = null;
    //    if (node.parent != null) {
    //        const a: u32 = @intCast(@intFromPtr(node.parent.?));
    //        const b: u32 = @intCast(@intFromPtr(data.nodes));
    //        const parent_index: i32 = @intCast((a - b) / @sizeOf(c.cgltf_node));
    //        parent = first_node_index + parent_index - node_index;
    //    } else {
    //        parent = @as(i32, @intCast(root_entry_index)) - node_index;
    //    }

    //    var children: ?[]i32 = null;
    //    if (node.children_count > 0) {
    //        children = try persistent.alloc(i32, node.children_count);
    //    }
    //    const new_name = try std.fs.path.join(persistent, &[_][]const u8{ name, std.mem.span(node.name) });
    //    for (0..node.children_count) |j| {
    //        const child = &node.children[j][0];
    //        const a: u32 = @intCast(@intFromPtr(child));
    //        const b: u32 = @intCast(@intFromPtr(data.nodes));
    //        const child_index: i32 = @intCast((a - b) / @sizeOf(c.cgltf_node));
    //        children.?[j] = first_node_index + child_index - node_index;
    //    }

    //    // Hacky but whatever
    //    pack.resources.?.items[root_resource_index].model.nodes[i] = @intCast(pack.resources.?.items.len);

    //    model_node.root_entry_relative_index = @as(i32, @intCast(root_entry_index)) - node_index;
    //    _ = try goosepack.resource_append(pack, srcs, new_name, .model_node, .{
    //        .model_node = model_node,
    //    }, parent, children);
    //}

    // Animation
    if (data.animations_count > 0) {
        std.log.info("has animations {}\n", .{data.animations_count});
        for (data.animations[0..data.animations_count]) |a| {
            std.log.info("{s}", .{a.name});
            std.log.info("{}", .{a.channels_count});
            std.log.info("{}", .{a.samplers_count});

            var animation: res.Animation = undefined;

            var common_name: ?[*c]u8 = null;
            for (a.channels[0..a.channels_count]) |channel| {
                std.debug.assert(channel.extensions_count == 0);
                const smp = channel.sampler;
                std.log.info("{*}", .{channel.target_node});
                std.log.info("{}", .{channel.target_path});

                const time_accessor = smp.*.input;
                std.debug.assert(time_accessor.*.type == c.cgltf_type_scalar);
                std.debug.assert(time_accessor.*.component_type == c.cgltf_component_type_r_32f);
                const view = time_accessor.*.buffer_view;
                const time_ptr: [*]align(1) f32 = @ptrCast(model.binary_data.ptr + view.*.offset);
                const time = arena_persistent.alloc(f32, time_accessor.*.count);
                @memcpy(time, time_ptr[0..time_accessor.*.count]);

                switch (channel.target_path) {
                    c.cgltf_animation_path_type_translation => {
                        const accessor = smp.*.output;
                        std.debug.assert(accessor.*.type == c.cgltf_type_vec3);
                        std.debug.assert(accessor.*.component_type == c.cgltf_component_type_r_32f);
                        const ptr: [*]align(1) f32 = @ptrCast(model.binary_data.ptr + accessor.*.buffer_view.*.offset);
                        animation.translation = .{
                            .time = time,
                            .data = upcast_slice_alloc(math.v3, ptr[0 .. accessor.*.count * 3]),
                        };
                    },
                    c.cgltf_animation_path_type_scale => {
                        const accessor = smp.*.output;
                        std.debug.assert(accessor.*.type == c.cgltf_type_vec3);
                        std.debug.assert(accessor.*.component_type == c.cgltf_component_type_r_32f);
                        const ptr: [*]align(1) f32 = @ptrCast(model.binary_data.ptr + accessor.*.buffer_view.*.offset);
                        animation.scale = .{
                            .time = time,
                            .data = upcast_slice_alloc(math.v3, ptr[0 .. accessor.*.count * 3]),
                        };
                    },
                    c.cgltf_animation_path_type_rotation => {
                        const accessor = smp.*.output;
                        std.debug.assert(accessor.*.type == c.cgltf_type_vec4);
                        std.debug.assert(accessor.*.component_type == c.cgltf_component_type_r_32f);
                        const ptr: [*]align(1) f32 = @ptrCast(model.binary_data.ptr + accessor.*.buffer_view.*.offset);
                        animation.rotation = .{
                            .time = time,
                            .data = upcast_slice_alloc(math.Quat, ptr[0 .. accessor.*.count * 4]),
                        };
                    },
                    else => unreachable,
                }

                std.log.info("-------------", .{});
                //const view_slice = model.binary_data[view.*.offset..(view.*.offset + view.*.size)];
                //const time_slice: []f32 = @ptrCast(view_slice);
                //_ = time_slice;

                std.log.info("s {}", .{smp.*.input.*.count});
                std.log.info("e {}", .{smp.*.output.*.count});
                std.log.info("s {}", .{smp.*.input.*.type});
                std.log.info("e {}", .{smp.*.output.*.type});

                if (common_name != null) {
                    std.debug.assert(channel.target_node.*.name == common_name.?);
                } else {
                    common_name = channel.target_node.*.name;
                }
            }

            animation.target = path_persistent_join(name, std.mem.span(common_name.?));
            const animation_name = path_persistent_join_3(name, "animation", std.mem.span(a.name));

            _ = try goosepack.resource_append(pack, srcs, animation_name, .animation, .{
                .animation = animation,
            }, null, null);
        }
    }

    // Hacky but whatever
    //pack.entries.?.items[root_resource_index].children = root_children[0..num_root_children];

    return root_entry;
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

//
// sokol
//

const sokol = @import("sokol");
const sg = sokol.gfx;

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

//
// Utilility
//

fn upcast_slice_alloc(comptime T: type, src: anytype) []T {
    const src_ti = @typeInfo(@TypeOf(src));
    std.debug.assert(src_ti == .pointer);
    std.debug.assert(src_ti.pointer.size == .slice);
    const size: usize = src.len * @sizeOf(src_ti.pointer.child) / @sizeOf(T);
    const dst = arena_persistent.alloc(T, size);
    const ptr: [*]align(1) T = @ptrCast(src.ptr);
    @memcpy(dst, ptr[0..size]);
    return dst;
}
