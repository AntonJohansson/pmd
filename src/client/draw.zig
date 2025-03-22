const std = @import("std");

const common = @import("common");
const meta = common.draw_meta;
const draw_api = common.draw_api;
const primitive = common.primitive;
const Color = primitive.Color;
const config = common.config;

const math = common.math;
const v2 = math.v2;
const v3 = math.v3;
const v4 = math.v4;
const m4 = math.m4;
const m3 = math.m3;

const sokol = @import("sokol");
const sg = sokol.gfx;
const slog = sokol.log;

const res = common.res;
const goosepack = common.goosepack;

var log: common.log.GroupLog(.draw) = undefined;

pub const Pipeline = enum {
    depth,
};

//const extra = @import("primitive_extra.zig");
//pub const BindingId = extra.BindingId;
//pub const PrimitiveType = extra.PrimitiveType;

//var bindings: std.BoundedArray(sg.Bindings, 16) = .{};
//pub fn addVertexBinding(vertices: []const f32) BindingId {
//    const binding = bindings.addOne() catch unreachable;
//    binding.* = sg.Bindings{};
//    binding.vertex_buffers[0] = sg.makeBuffer(.{
//        .data = sg.asRange(vertices),
//    });
//    return bindings.len;
//}

var circle_bind = sg.Bindings{};
var rectangle_bind = sg.Bindings{};
var cube_bind = sg.Bindings{};

var pipelines: std.BoundedArray(sg.Pipeline, 16) = .{};
var binds: std.BoundedArray(BindInfo, 64) = .{};

const MeshBindings = struct {
    bind: sg.Bindings = undefined,
    pip: sg.Pipeline = undefined,
    image: sg.Image = undefined,
    sampler: sg.Sampler = undefined,
    buffer_types: u8 = 0,
    has_image: bool = false,
};

const BindInfo = struct {
    id: u64,
    prim_index: u32,
    mesh_index: u32,
    mesh_binds: MeshBindings,
};

fn buildBindForMesh(model: res.Model, material: res.Material, mesh_index: u32, prim_index: u32) MeshBindings {
    const mesh = model.meshes[mesh_index];
    const prim = mesh.primitives[prim_index];
    var bind: sg.Bindings = .{};
    if ((prim.buffer_types & res.bt_position) != 0) {
        bind.vertex_buffers[0] = sg.makeBuffer(.{
            .data = sg.asRange(prim.pos.?),
        });
    }
    if ((prim.buffer_types & res.bt_normals) != 0) {
        bind.vertex_buffers[1] = sg.makeBuffer(.{
            .data = sg.asRange(prim.normals.?),
        });
    }
    if (material.has_image and (prim.buffer_types & res.bt_texcoords) != 0) {
        bind.vertex_buffers[2] = sg.makeBuffer(.{
            .data = sg.asRange(prim.texcoords.?),
        });
    }
    if ((prim.buffer_types & res.bt_indices) != 0) {
        bind.index_buffer = sg.makeBuffer(.{
            .type = .INDEXBUFFER,
            .data = sg.asRange(prim.indices.?),
        });
    }

    var pip: sg.Pipeline = undefined;
    if (material.has_image and (prim.buffer_types & res.bt_texcoords) != 0) {
        pip = pipeline_texture;
    } else {
        pip = pipeline_3d;
    }

    var image: sg.Image = undefined;
    var smp: sg.Sampler = undefined;
    if ((prim.buffer_types & res.bt_texcoords) != 0) {
        if (material.has_image) {
            const format: sg.PixelFormat = switch (material.image.channels) {
                4 => .RGBA8,
                else => unreachable,
            };
            var desc = sg.ImageDesc{
                .width = @intCast(material.image.width),
                .height = @intCast(material.image.height),
                .pixel_format = format,
                .sample_count = 1,
            };
            std.log.info("{} {} {}", .{material.image.width, material.image.height, material.image.channels});
            desc.data.subimage[0][0] = sg.asRange(material.image.pixels);
            image = sg.makeImage(desc);

            smp = sg.makeSampler(.{
                .min_filter = .NEAREST,
                .mag_filter = .NEAREST,
                .wrap_u = .CLAMP_TO_BORDER,
                .wrap_v = .CLAMP_TO_BORDER,
            });
        }
    }

    return .{
        .bind = bind,
        .pip = pip,
        .image = image,
        .sampler = smp,
        .buffer_types = prim.buffer_types,
        .has_image = material.has_image,
    };
}

fn bindForMesh(model: res.Model, material: res.Material, mesh_index: u32, prim_index: u32) MeshBindings {
    for (binds.buffer) |info| {
        if (info.id == model.id and info.mesh_index == mesh_index and info.prim_index == prim_index)
            return info.mesh_binds;
    }
    const mesh_binds = buildBindForMesh(model, material, mesh_index, prim_index);
    binds.appendAssumeCapacity(.{ .id = model.id, .mesh_index = mesh_index, .prim_index = prim_index, .mesh_binds = mesh_binds});
    return mesh_binds;
}

// TODO: ?
//fn buildPipelineForModel(model: res.Model) *sg.Pipeline {
//    _ = model;
//    var attachments_desc = sg.AttachmentsDesc{};
//    attachments_desc.colors[0].image = offscreen_3d.color;
//    attachments_desc.depth_stencil.image = offscreen_3d.depth;
//    offscreen_3d.pass.attachments = sg.makeAttachments(attachments_desc);
//    //offscreen_3d.pass.swapchain.width =
//    //offscreen_3d.pass.swapchain.height =
//
//    var desc = sg.PipelineDesc{
//        .index_type = .UINT16,
//        .shader = shd_3d,
//        .primitive_type = .TRIANGLE,
//        .cull_mode = .FRONT,
//        .sample_count = 1,
//        .depth = .{
//            .pixel_format = .DEPTH,
//            .compare = .LESS_EQUAL,
//            .write_enabled = true,
//        },
//    };
//    desc.colors[0] = .{
//        .blend = .{
//            .enabled = true,
//            .src_factor_rgb = .SRC_ALPHA,
//            .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
//        },
//        .pixel_format = .RGBA8,
//    };
//    desc.layout.attrs[0].format = .FLOAT3;
//
//    const pip = pipelines.addOneAssumeCapacity();
//    pip.* = sg.makePipeline(desc);
//    return pip;
//}

const UniformsVertex3d = struct {
    mvp: m4,
    model: m4,
};

const UniformsFragment3d = struct {
    color: v4,
    light_pos: v3 = .{},
    light_color: v3 = .{},
    camera_pos: v3 = .{},
};

const UniformsVertex2d = struct {
    mvp: m4,
};

const UniformsFragment2d = struct {
    color: v4,
};


const UniformsVertexVoxelChunk = struct {
    vp: m4 = undefined,
    chunk_pos: v3 = .{},
    rotations: [6]m4 = undefined,
    voxel_size: f32 = voxel_width,
};

const UniformsFragmentVoxelChunk = struct {
    color: v4 = .{},
    light_pos: v3 = .{},
    light_color: v3 = .{},
    camera_pos: v3 = .{},
};

const UniformsVertexAtlas = struct {
    vs_off: v2,
    vs_scale: v2,
};

const UniformsFragmentAtlas = struct {
    off: v2,
    scale: v2,
    fg: v4,
    bg: v4,
};

fn uniform_type(T: anytype) sg.UniformType {
    return switch (T) {
        f32 => .FLOAT,
        v2 => .FLOAT2,
        v3 => .FLOAT3,
        v4 => .FLOAT4,
        m4 => .MAT4,
        else => unreachable,
    };
}

fn specify_uniforms(desc: *sg.ShaderUniformBlock, uniform: anytype, stage: sg.ShaderStage) void {
    desc.size = @sizeOf(uniform);
    desc.stage = stage;
    const ti = @typeInfo(uniform);
    inline for (ti.Struct.fields, 0..) |field, i| {
        comptime var base_type = field.type;
        var array_count: u32 = 0;
        const field_ti = @typeInfo(base_type);
        if (field_ti == .Array) {
            base_type = field_ti.Array.child;
            array_count = field_ti.Array.len;
        }
        desc.glsl_uniforms[i] = .{
            .glsl_name = field.name,
            .type = uniform_type(base_type),
            .array_count = @intCast(array_count),
        };
    }
}

const circle_vertices = blk: {
    const inner_radius = 9;
    const outer_radius = 10.0;
    const len = 16;

    // Use an extra point len+1 to make
    // sure the ends of the circle "connect"
    var vertices: [6 * (len + 1)]f32 = undefined;

    for (0..(len + 1)) |i| {
        const angle = (2.0 * std.math.pi * @as(f32, @floatFromInt(i % len))) / @as(f32, @floatFromInt(len));
        vertices[6 * i + 0] = outer_radius * @cos(angle);
        vertices[6 * i + 1] = outer_radius * @sin(angle);
        vertices[6 * i + 2] = 0;
        vertices[6 * i + 3] = inner_radius * @cos(angle);
        vertices[6 * i + 4] = inner_radius * @sin(angle);
        vertices[6 * i + 5] = 0;
    }

    break :blk vertices;
};

const rectangle_vertices = [_]f32{ -0.5, 0.5, 0.5, 0.5, 0.5, -0.5, -0.5, -0.5 };
const rectangle_indices = [_]u16{ 0, 1, 2, 0, 2, 3 };

const textured_rectangle_vertices = [_]f32{
    -1.0, 1.0, 0.0, 0.0, // top left
    1.0, 1.0, 1.0, 0.0, // top right
    1.0, -1.0, 1.0, 1.0, // bottom right
    -1.0, -1.0, 0.0, 1.0, // bottom left
};
const textured_rectangle_indices = [_]u16{ 0, 1, 2, 0, 2, 3 };

// TODO: https://developer.nvidia.com/gpugems/gpugems/part-vi-beyond-triangles/chapter-39-volume-rendering-techniques

const voxel_width = 32.0;
const half_voxel_width = 0.5*voxel_width;
const voxel_face_vertices = [_]f32{
    half_voxel_width, -half_voxel_width, half_voxel_width, //   0   x front top left
    half_voxel_width, half_voxel_width, half_voxel_width, //    3   x front top right
    -half_voxel_width, -half_voxel_width, half_voxel_width, //  12 -x back top left
    -half_voxel_width, half_voxel_width, half_voxel_width, //   15 -x back top right
};

const voxel_face_normals = [_]f32{
    0,  0,  1,
    0,  0,  1,
    0,  0,  1,
    0,  0,  1,
};

const voxel_face_texcoords = [_]f32{
    0,0,
    1,0,
    0,1,
    1,1,
};

const voxel_face_indices = [_]u16{
    0, 1, 3,
    0, 3, 2,
};

const cube_vertices = [_]f32{
    0.5, -0.5, 0.5, //   0   x front top left
    0.5, -0.5, 0.5, //   1  -y front top left
    0.5, -0.5, 0.5, //   2   z front top left
    0.5, 0.5, 0.5, //    3   x front top right
    0.5, 0.5, 0.5, //    4   y front top right
    0.5, 0.5, 0.5, //    5   z front top right
    0.5, 0.5, -0.5, //   6   x front bottom right
    0.5, 0.5, -0.5, //   7   y front bottom right
    0.5, 0.5, -0.5, //   8  -z front bottom right
    0.5, -0.5, -0.5, //  9   x front bottom left
    0.5, -0.5, -0.5, //  10 -y front bottom left
    0.5, -0.5, -0.5, //  11 -z front bottom left
    -0.5, -0.5, 0.5, //  12 -x back top left
    -0.5, -0.5, 0.5, //  13 -y back top left
    -0.5, -0.5, 0.5, //  14  z back top left
    -0.5, 0.5, 0.5, //   15 -x back top right
    -0.5, 0.5, 0.5, //   16  y back top right
    -0.5, 0.5, 0.5, //   17  z back top right
    -0.5, 0.5, -0.5, //  18 -x back bottom right
    -0.5, 0.5, -0.5, //  19  y back bottom right
    -0.5, 0.5, -0.5, //  20 -z back bottom right
    -0.5, -0.5, -0.5, // 21 -x back bottom left
    -0.5, -0.5, -0.5, // 22 -y back bottom left
    -0.5, -0.5, -0.5, // 23 -z back bottom left
};
const cube_normals = [_]f32{
    1,  0,  0,
    0,  -1, 0,
    0,  0,  1,

    1,  0,  0,
    0,  1,  0,
    0,  0,  1,

    1,  0,  0,
    0,  1,  0,
    0,  0,  -1,

    1,  0,  0,
    0,  -1, 0,
    0,  0,  -1,

    -1, 0,  0,
    0,  -1, 0,
    0,  0,  1,

    -1, 0,  0,
    0,  1,  0,
    0,  0,  1,

    -1, 0,  0,
    0,  1,  0,
    0,  0,  -1,

    -1, 0,  0,
    0,  -1, 0,
    0,  0,  -1,
};

const cube_indices = [_]u16{
    0, 6, 3, 0, 9, 6, // front face
    15, 21, 12, 15, 18, 21, // back face
    4, 19, 16, 4, 7, 19, // right face
    13, 10, 1, 13, 22, 10, // left face
    14, 5, 17, 14, 2, 5, // top face
    11, 20, 8, 11, 23, 20, // bottom face
};

var cube_model: res.Model = undefined;
var pip_cube_model = sg.Pipeline{};
var bind_cube_model = sg.Bindings{};
var pack: *goosepack.Pack = undefined;
var mem: common.MemoryAllocators = undefined;
var font: res.Font = undefined;
var uniforms_voxel: UniformsVertexVoxelChunk = .{};

var bindings_initialized = false;
var sampler_linear_clamped: sg.Sampler = undefined;
var sampler_nearest_clamped: sg.Sampler = undefined;
var binding_textured_rectangle: sg.Bindings = undefined;
var binding_cubemap: sg.Bindings = undefined;

fn deinit_bindings() void {
    sg.destroySampler(sampler_linear_clamped);
    sg.destroySampler(sampler_nearest_clamped);
    sg.destroyBuffer(binding_textured_rectangle.vertex_buffers[0]);
    sg.destroyBuffer(binding_textured_rectangle.index_buffer);
    sg.destroyBuffer(binding_cubemap.vertex_buffers[0]);
    sg.destroyBuffer(binding_cubemap.index_buffer);
}

fn rebuild_bindings() void {
    if (bindings_initialized) {
        deinit_bindings();
    } else {
        bindings_initialized = true;
    }

    sampler_linear_clamped = sg.makeSampler(.{
        .min_filter = .LINEAR,
        .mag_filter = .LINEAR,
        .wrap_u = .CLAMP_TO_BORDER,
        .wrap_v = .CLAMP_TO_BORDER,
    });

    sampler_nearest_clamped = sg.makeSampler(.{
        .min_filter = .NEAREST,
        .mag_filter = .NEAREST,
        .wrap_u = .CLAMP_TO_BORDER,
        .wrap_v = .CLAMP_TO_BORDER,
    });

    // textured rectangle
    binding_textured_rectangle.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&textured_rectangle_vertices),
    });
    binding_textured_rectangle.index_buffer = sg.makeBuffer(.{
        .type = .INDEXBUFFER,
        .data = sg.asRange(&textured_rectangle_indices),
    });
    binding_textured_rectangle.samplers[0] = sampler_linear_clamped;

    // cubemap
    binding_cubemap.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&cube_vertices),
    });
    binding_cubemap.index_buffer = sg.makeBuffer(.{
        .type = .INDEXBUFFER,
        .data = sg.asRange(&cube_indices),
    });
    binding_cubemap.samplers[0] = sampler_linear_clamped;
}

// Shaders
var shaders_initialized = false;
var shd_2d: sg.Shader = undefined;
var shd_pp: sg.Shader = undefined;
var shd_text: sg.Shader = undefined;
var shd_display: sg.Shader = undefined;
var shd_cm: sg.Shader = undefined;
var shd_3d: sg.Shader = undefined;
var shd_voxelchunk: sg.Shader = undefined;
var shd_texture: sg.Shader = undefined;

fn make_shader_and_write_if_valid(shd: *sg.Shader, desc: sg.ShaderDesc) void {
    const tmp = sg.makeShader(desc);
    const state = sg.queryShaderState(tmp);
    const valid = state != .FAILED and state != .INVALID;
    if (valid) {
        if (shaders_initialized) {
            sg.destroyShader(shd.*);
        }
        shd.* = tmp;
    }
}

fn deinit_shaders() void {
    sg.destroyShader(shd_2d);
    sg.destroyShader(shd_pp);
    sg.destroyShader(shd_text);
    sg.destroyShader(shd_display);
    sg.destroyShader(shd_cm);
    sg.destroyShader(shd_3d);
    sg.destroyShader(shd_voxelchunk);
    sg.destroyShader(shd_texture);
}

fn rebuild_shaders() void {
    if (shaders_initialized) {
        // We instead deinit if makeShader succeeds
        //deinit_shaders();
    } else {
        shaders_initialized = true;
    }

    // 2d shader
    {
        var shd_desc = sg.ShaderDesc{};
        const res_shader = goosepack.resource_lookup(pack, "res/2d-p").?.shader;
        shd_desc.vertex_func.source = @ptrCast(res_shader.vs_bytes);
        shd_desc.fragment_func.source = @ptrCast(res_shader.fs_bytes);
        specify_uniforms(&shd_desc.uniform_blocks[0], UniformsVertex2d, .VERTEX);
        specify_uniforms(&shd_desc.uniform_blocks[1], UniformsFragment2d, .FRAGMENT);
        make_shader_and_write_if_valid(&shd_2d, shd_desc);
    }

    // 3d shader
    {
        var shd_desc = sg.ShaderDesc{};
        const res_shader = goosepack.resource_lookup(pack, "res/3d-pn").?.shader;
        shd_desc.vertex_func.source = @ptrCast(res_shader.vs_bytes);
        shd_desc.fragment_func.source = @ptrCast(res_shader.fs_bytes);
        specify_uniforms(&shd_desc.uniform_blocks[0], UniformsVertex3d, .VERTEX);
        specify_uniforms(&shd_desc.uniform_blocks[1], UniformsFragment3d, .FRAGMENT);
        make_shader_and_write_if_valid(&shd_3d, shd_desc);
    }

    // texture shader
    {
        var shd_desc = sg.ShaderDesc{};
        const res_shader = goosepack.resource_lookup(pack, "res/3d-pnt").?.shader;
        shd_desc.vertex_func.source = @ptrCast(res_shader.vs_bytes);
        shd_desc.fragment_func.source = @ptrCast(res_shader.fs_bytes);
        specify_uniforms(&shd_desc.uniform_blocks[0], UniformsVertex3d, .VERTEX);
        specify_uniforms(&shd_desc.uniform_blocks[1], UniformsFragment3d, .FRAGMENT);
        shd_desc.images[0] = .{ .stage = .FRAGMENT };
        shd_desc.samplers[0] = .{ .stage = .FRAGMENT };
        shd_desc.image_sampler_pairs[0] = .{
            .stage = .FRAGMENT,
            .image_slot = 0,
            .sampler_slot = 0,
            .glsl_name = "tex",
        };
        make_shader_and_write_if_valid(&shd_texture, shd_desc);
    }

    // Voxel chunk shader
    {
        var shd_desc = sg.ShaderDesc{};
        const res_shader = goosepack.resource_lookup(pack, "res/voxelchunk").?.shader;
        shd_desc.vertex_func.source = @ptrCast(res_shader.vs_bytes);
        shd_desc.fragment_func.source = @ptrCast(res_shader.fs_bytes);
        //shd_desc.fs.images[0] = .{ .used = true }
        //shd_desc.fs.samplers[0] = .{ .used = true };
        //shd_desc.fs.image_sampler_pairs[0] = .{
        //    .used = true,
        //    .image_slot = 0,
        //    .sampler_slot = 0,
        //    .glsl_name = "tex",
        //};
        specify_uniforms(&shd_desc.uniform_blocks[0], UniformsVertexVoxelChunk, .VERTEX);
        specify_uniforms(&shd_desc.uniform_blocks[1], UniformsFragmentVoxelChunk, .FRAGMENT);
        make_shader_and_write_if_valid(&shd_voxelchunk, shd_desc);
    }

    // Postprocess shader
    {
        var shd_desc = sg.ShaderDesc{};
        const res_shader = goosepack.resource_lookup(pack, "res/cc").?.shader;
        shd_desc.vertex_func.source = @ptrCast(res_shader.vs_bytes);
        shd_desc.fragment_func.source = @ptrCast(res_shader.fs_bytes);
        shd_desc.images[0] = .{ .stage = .FRAGMENT };
        shd_desc.samplers[0] = .{ .stage = .FRAGMENT };
        shd_desc.image_sampler_pairs[0] = .{
            .stage = .FRAGMENT,
            .image_slot = 0,
            .sampler_slot = 0,
            .glsl_name = "tex",
        };
        make_shader_and_write_if_valid(&shd_pp, shd_desc);
    }

    {
        var shd_desc = sg.ShaderDesc{};
        const res_shader = goosepack.resource_lookup(pack, "res/text").?.shader;
        shd_desc.vertex_func.source = @ptrCast(res_shader.vs_bytes);
        shd_desc.fragment_func.source = @ptrCast(res_shader.fs_bytes);
        specify_uniforms(&shd_desc.uniform_blocks[0], UniformsVertexAtlas, .VERTEX);
        specify_uniforms(&shd_desc.uniform_blocks[1], UniformsFragmentAtlas, .FRAGMENT);
        shd_desc.images[0] = .{ .stage = .FRAGMENT };
        shd_desc.samplers[0] = .{ .stage = .FRAGMENT };
        shd_desc.image_sampler_pairs[0] = .{
            .stage = .FRAGMENT,
            .image_slot = 0,
            .sampler_slot = 0,
            .glsl_name = "tex",
        };
        make_shader_and_write_if_valid(&shd_text, shd_desc);
    }

    // TODO(anjo): We can get rid of this shader after moving 2d to separate buffer
    // Display shader
    {
        var shd_desc = sg.ShaderDesc{};
        shd_desc.vertex_func.source =
            \\ #version 330
            \\ layout(location=0) in vec2 position;
            \\ layout(location=1) in vec2 texcoords;
            \\ out vec2 v_texcoords;
            \\ void main() {
            \\   v_texcoords = texcoords;
            \\   gl_Position = vec4(position, 0, 1);
            \\ }
        ;
        shd_desc.fragment_func.source =
            \\ #version 330
            \\ in vec2 v_texcoords;
            \\ out vec4 frag_color;
            \\ uniform sampler2D tex;
            \\ void main() {
            \\   frag_color = texture(tex, vec2(v_texcoords.x, 1.0-v_texcoords.y));
            \\ }
        ;

        shd_desc.images[0] = .{ .stage = .FRAGMENT };
        shd_desc.samplers[0] = .{ .stage = .FRAGMENT };
        shd_desc.image_sampler_pairs[0] = .{
            .stage = .FRAGMENT,
            .image_slot = 0,
            .sampler_slot = 0,
            .glsl_name = "tex",
        };
        make_shader_and_write_if_valid(&shd_display, shd_desc);
    }

    // Cubemap shader
    {
        var shd_desc = sg.ShaderDesc{};
        const res_shader = goosepack.resource_lookup(pack, "res/cubemap").?.shader;
        shd_desc.vertex_func.source = @ptrCast(res_shader.vs_bytes);
        shd_desc.fragment_func.source = @ptrCast(res_shader.fs_bytes);
        specify_uniforms(&shd_desc.uniform_blocks[0], UniformsVertex2d, .VERTEX);
        specify_uniforms(&shd_desc.uniform_blocks[1], UniformsFragment2d, .FRAGMENT);
        shd_desc.images[0] = .{ .stage = .FRAGMENT, .image_type = .CUBE };
        shd_desc.samplers[0] = .{ .stage = .FRAGMENT };
        shd_desc.image_sampler_pairs[0] = .{
            .stage = .FRAGMENT,
            .image_slot = 0,
            .sampler_slot = 0,
            .glsl_name = "cube",
        };
        make_shader_and_write_if_valid(&shd_cm, shd_desc);
    }
}

var images_initialized = false;
var image_3d_framebuffer: sg.Image = undefined;
var image_3d_depthbuffer: sg.Image = undefined;
var image_2d_framebuffer: sg.Image = undefined;

fn deinit_images() void {
    sg.destroyImage(image_3d_framebuffer);
    sg.destroyImage(image_3d_depthbuffer);
    sg.destroyImage(image_2d_framebuffer);
}

fn rebuild_images(width: u32, height: u32) void {
    if (images_initialized) {
        deinit_images();
    } else {
        images_initialized = true;
    }

    image_3d_framebuffer = sg.makeImage(.{
        .render_target = true,
        .width = @intCast(width),
        .height = @intCast(height),
        .pixel_format = .RGBA8,
        .sample_count = 1,
    });

    image_3d_depthbuffer = sg.makeImage(.{
        .render_target = true,
        .width = @intCast(width),
        .height = @intCast(height),
        .pixel_format = .DEPTH,
        .sample_count = 1,
    });

    image_2d_framebuffer = sg.makeImage(.{
        .render_target = true,
        .width = @intCast(width),
        .height = @intCast(height),
        .pixel_format = .RGBA8,
        .sample_count = 1,
    });
}

var passes_initialized = false;
var pass_load: sg.Pass = .{};
var pass_load_color_depth: sg.Pass = .{};
var pass_load_clear: sg.Pass = .{};
var pass_load_swapchain: sg.Pass = .{};

fn deinit_passes() void {
    sg.destroyAttachments(pass_load_color_depth.attachments);
    sg.destroyAttachments(pass_load_clear.attachments);
}

fn rebuild_passes(width: u32, height: u32) void {
    if (passes_initialized) {
        deinit_passes();
    } else {
        passes_initialized = true;
    }

    pass_load.action.colors[0] = .{
        .load_action = .LOAD,
    };

    {
        pass_load_color_depth.action.colors[0] = .{
            .load_action = .LOAD,
        };
        var attachments_desc = sg.AttachmentsDesc{};
        attachments_desc.colors[0].image = image_3d_framebuffer;
        attachments_desc.depth_stencil.image = image_3d_depthbuffer;
        pass_load_color_depth.attachments = sg.makeAttachments(attachments_desc);
    }

    {
        pass_load_clear.action.colors[0] = .{
            .load_action = .LOAD,
            .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
        };
        var attachments_desc = sg.AttachmentsDesc{};
        attachments_desc.colors[0].image = image_2d_framebuffer;
        pass_load_clear.attachments = sg.makeAttachments(attachments_desc);
    }

    {
        pass_load_swapchain.action.colors[0] = .{
            .load_action = .LOAD,
        };
        pass_load_swapchain.swapchain.width = @intCast(width);
        pass_load_swapchain.swapchain.height = @intCast(height);
    }

}

var pipelines_initialized = false;
var image_font_atlas: sg.Image = undefined;
var image_cubemap: sg.Image = undefined;
var pipeline_text: sg.Pipeline = undefined;
var pipeline_3d: sg.Pipeline = undefined;
var pipeline_2d: sg.Pipeline = undefined;
var pipeline_texture: sg.Pipeline = undefined;
var pipeline_cubemap: sg.Pipeline = undefined;
var pipeline_postprocess: sg.Pipeline = undefined;
var pipeline_overlay_2d: sg.Pipeline = undefined;
var pipeline_voxel: sg.Pipeline = undefined;
var font_chars: []res.FontChar = undefined;

fn deinit_pipelines() void {
    sg.destroyImage(image_font_atlas);
    sg.destroyImage(image_cubemap);
    sg.destroyPipeline(pipeline_text);
    sg.destroyPipeline(pipeline_3d);
    sg.destroyPipeline(pipeline_2d);
    sg.destroyPipeline(pipeline_texture);
    sg.destroyPipeline(pipeline_cubemap);
    sg.destroyPipeline(pipeline_postprocess);
    sg.destroyPipeline(pipeline_overlay_2d);
    sg.destroyPipeline(pipeline_voxel);

    //pipelines = .{};
    for (binds.slice()) |b| {
        if ((b.mesh_binds.buffer_types & res.bt_position) != 0) {
            sg.destroyBuffer(b.mesh_binds.bind.vertex_buffers[0]);
        }
        if ((b.mesh_binds.buffer_types & res.bt_normals) != 0) {
            sg.destroyBuffer(b.mesh_binds.bind.vertex_buffers[1]);
        }
        if (b.mesh_binds.has_image and (b.mesh_binds.buffer_types & res.bt_texcoords) != 0) {
            sg.destroyBuffer(b.mesh_binds.bind.vertex_buffers[2]);
        }
        if ((b.mesh_binds.buffer_types & res.bt_indices) != 0) {
            sg.destroyBuffer(b.mesh_binds.bind.index_buffer);
        }
        if (b.mesh_binds.has_image) {
            sg.destroyImage(b.mesh_binds.image);
        }
    }
    binds = .{};
}

fn rebuild_pipelines() void {
    if (pipelines_initialized) {
        deinit_pipelines();
    } else {
        pipelines_initialized = true;
    }

    // Text pipeline
    {
        font = goosepack.resource_lookup(pack, "res/fonts/MononokiNerdFontMono-Regular").?.font;
        var data = sg.ImageData{};
        data.subimage[0][0] = .{ .ptr = font.pixels.ptr, .size = font.pixels.len };
        image_font_atlas = sg.makeImage(.{
            .width = font.width,
            .height = font.height,
            .data = data,
            .pixel_format = .R8,
            .sample_count = 1,
        });
        font_chars = font.chars;

        var pip_desc = sg.PipelineDesc{
            .index_type = .UINT16,
            .shader = shd_text,
            .color_count = 1,
            .sample_count = 1,
            .depth = .{
                .pixel_format = .NONE,
            },
        };
        pip_desc.colors[0] = .{
            .blend = .{
                .enabled = true,
                .src_factor_rgb = .SRC_ALPHA,
                .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
                .src_factor_alpha = .SRC_ALPHA,
                .dst_factor_alpha = .DST_ALPHA,
                .op_alpha = .ADD,
                .op_rgb = .ADD,
            },
        };
        pip_desc.layout.attrs[0].format = .FLOAT2;
        pip_desc.layout.attrs[1].format = .FLOAT2;
        pipeline_text = sg.makePipeline(pip_desc);
    }

    // Offscreen 3d
    {
        var pip_desc = sg.PipelineDesc{
            .index_type = .UINT16,
            .shader = shd_3d,
            .cull_mode = .FRONT,
            .sample_count = 1,
            .depth = .{
                .pixel_format = .DEPTH,
                .compare = .LESS_EQUAL,
                .write_enabled = true,
            },
            .label = "offscreen 3d",
        };
        pip_desc.colors[0] = .{
            .blend = .{
                .enabled = true,
                .src_factor_rgb = .SRC_ALPHA,
                .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
            },
            .pixel_format = .RGBA8,
        };
        pip_desc.layout.attrs[0].format = .FLOAT3;
        pip_desc.layout.attrs[1].format = .FLOAT3;
        pip_desc.layout.attrs[1].buffer_index = 1;
        pipeline_3d = sg.makePipeline(pip_desc);
    }

    // Offscreen 2d
    {
        var pip_desc = sg.PipelineDesc{
            .index_type = .UINT16,
            .shader = shd_2d,
            .sample_count = 1,
            .color_count = 1,
            .depth = .{
                .pixel_format = .NONE,
            },
            .label = "offscreen 2d",
        };
        pip_desc.colors[0] = .{
            .blend = .{
                .enabled = true,
                .src_factor_rgb = .SRC_ALPHA,
                .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
            },
            .pixel_format = .RGBA8,
        };
        pip_desc.layout.attrs[0].format = .FLOAT2;
        pipeline_2d = sg.makePipeline(pip_desc);
    }

    // Texture pipeline
    {
        var pip_desc = sg.PipelineDesc{
            .index_type = .UINT16,
            .shader = shd_texture,
            .cull_mode = .FRONT,
            .sample_count = 1,
            .depth = .{
                .pixel_format = .DEPTH,
                .compare = .LESS_EQUAL,
                .write_enabled = true,
            },
            .label = "pipeline texture",
        };
        pip_desc.colors[0] = .{
            .blend = .{
                .enabled = true,
                .src_factor_rgb = .SRC_ALPHA,
                .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
            },
            .pixel_format = .RGBA8,
        };
        pip_desc.layout.attrs[0].format = .FLOAT3;
        pip_desc.layout.attrs[1].format = .FLOAT3;
        pip_desc.layout.attrs[1].buffer_index = 1;
        pip_desc.layout.attrs[2].format = .FLOAT2;
        pip_desc.layout.attrs[2].buffer_index = 2;
        pipeline_texture = sg.makePipeline(pip_desc);
    }

    // Voxelchunk pipeline
    {
        var pip_desc = sg.PipelineDesc{
            .index_type = .UINT16,
            .shader = shd_voxelchunk,
            .cull_mode = .FRONT,
            .sample_count = 1,
            .depth = .{
                .pixel_format = .DEPTH,
                .compare = .LESS_EQUAL,
                .write_enabled = true,
            },
            .label = "voxel pipeline",
        };
        pip_desc.colors[0] = .{
            .blend = .{
                .enabled = true,
                .src_factor_rgb = .SRC_ALPHA,
                .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
            },
            .pixel_format = .RGBA8,
        };
        pip_desc.layout.attrs[0].format = .FLOAT3;
        pip_desc.layout.attrs[0].buffer_index = 0;
        pip_desc.layout.attrs[1].format = .FLOAT3;
        pip_desc.layout.attrs[1].buffer_index = 1;
        pip_desc.layout.attrs[2].format = .UBYTE4;
        pip_desc.layout.attrs[2].buffer_index = 2;
        pip_desc.layout.buffers[2].step_func = .PER_INSTANCE;
        pipeline_voxel = sg.makePipeline(pip_desc);
    }

    // Cubemap
    {
        var pip_desc = sg.PipelineDesc{
            .index_type = .UINT16,
            .shader = shd_cm,
            .cull_mode = .BACK,
            .sample_count = 1,
            .color_count = 1,
            .depth = .{
                .pixel_format = .DEPTH,
                .compare = .LESS_EQUAL,
                .write_enabled = true,
            },
            .label = "offscreen cubemap",
        };
        pip_desc.colors[0] = .{
            .blend = .{
                .enabled = true,
                .src_factor_rgb = .SRC_ALPHA,
                .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
            },
            .pixel_format = .RGBA8,
        };
        pip_desc.layout.attrs[0].format = .FLOAT3;
        pipeline_cubemap = sg.makePipeline(pip_desc);

        const cubemap = goosepack.resource_lookup(pack, "res/cm").?.cubemap;
        var img_desc = sg.ImageDesc{
            .type = .CUBE,
            .width = @intCast(cubemap.width),
            .height = @intCast(cubemap.height),
            .pixel_format = .RGBA8,
        };
        for (0..@intFromEnum(sg.CubeFace.NUM)) |i| {
            img_desc.data.subimage[i][0] = sg.asRange(cubemap.faceSlice(@intCast(i)));
        }
        image_cubemap = sg.allocImage();
        sg.initImage(image_cubemap, img_desc);
    }

    // Postprocess
    {
        var pip_desc = sg.PipelineDesc{
            .index_type = .UINT16,
            .shader = shd_pp,
            .cull_mode = .BACK,
            .depth = .{
                .compare = .LESS_EQUAL,
                .write_enabled = true,
            },
        };
        pip_desc.colors[0] = .{
            .blend = .{
                .enabled = true,
                .src_factor_rgb = .SRC_ALPHA,
                .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
            },
        };
        pip_desc.layout.attrs[0].format = .FLOAT2;
        pip_desc.layout.attrs[1].format = .FLOAT2;
        pipeline_postprocess = sg.makePipeline(pip_desc);
    }

    // Display
    {
        var pip_desc = sg.PipelineDesc{
            .index_type = .UINT16,
            .shader = shd_display,
            .cull_mode = .BACK,
            .depth = .{
                .compare = .LESS_EQUAL,
                .write_enabled = true,
            },
        };
        pip_desc.colors[0] = .{
            .blend = .{
                .enabled = true,
                .src_factor_rgb = .SRC_ALPHA,
                .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
            },
        };
        pip_desc.layout.attrs[0].format = .FLOAT2;
        pip_desc.layout.attrs[1].format = .FLOAT2;
        pipeline_overlay_2d = sg.makePipeline(pip_desc);
    }
}

pub fn init(log_memory: *common.log.LogMemory, _mem: common.MemoryAllocators, _pack: *goosepack.Pack) void {
    mem = _mem;

    log = log_memory.group_log(.draw);

    uniforms_voxel.rotations[@intFromEnum(primitive.VoxelTransform.FaceDir.up)] = math.m4_identity;
    uniforms_voxel.rotations[@intFromEnum(primitive.VoxelTransform.FaceDir.down)] = m4.transpose(m4.modelRotX(std.math.pi));
    uniforms_voxel.rotations[@intFromEnum(primitive.VoxelTransform.FaceDir.back)] = m4.transpose(m4.modelRotY(-std.math.pi/2.0));
    uniforms_voxel.rotations[@intFromEnum(primitive.VoxelTransform.FaceDir.front)] = m4.transpose(m4.modelRotY(std.math.pi/2.0));
    uniforms_voxel.rotations[@intFromEnum(primitive.VoxelTransform.FaceDir.left)] = m4.transpose(m4.modelRotX(std.math.pi/2.0));
    uniforms_voxel.rotations[@intFromEnum(primitive.VoxelTransform.FaceDir.right)] = m4.transpose(m4.modelRotX(-std.math.pi/2.0));

    sg.setup(.{
        .logger = .{ .func = slog.func },
    });

    pack = _pack;

    // Setup bindings
    circle_bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&circle_vertices),
    });

    rectangle_bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&rectangle_vertices),
    });
    rectangle_bind.index_buffer = sg.makeBuffer(.{
        .type = .INDEXBUFFER,
        .data = sg.asRange(&rectangle_indices),
    });

    cube_bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&cube_vertices),
    });
    cube_bind.vertex_buffers[1] = sg.makeBuffer(.{
        .data = sg.asRange(&cube_normals),
    });
    cube_bind.index_buffer = sg.makeBuffer(.{
        .type = .INDEXBUFFER,
        .data = sg.asRange(&cube_indices),
    });

    //
    // Pipelines
    //

    rebuild_bindings();
    rebuild_shaders();
    rebuild_pipelines();
    rebuild_images(800, 600);
    rebuild_passes(800, 600);
}

pub fn deinit() void {
    sg.shutdown();
}

pub fn resources_update(entries: []goosepack.Entry) void {
    _ = entries;
    rebuild_shaders();
    rebuild_pipelines();
}

var old_width: u32 = 800;
var old_height: u32 = 600;

pub fn process(b: *draw_api.CommandBuffer, width: u32, height: u32, num_views: u32) void {
    var vp: m4 = .{};

    defer b.bytes.clear();

    if (num_views == 0) {
        return;
    }

    if (old_width != width or old_height != height) {
        rebuild_images(width, height);
        rebuild_passes(width, height);
        old_width = width;
        old_height = height;
    }

    const views_per_col: u32 = @intFromFloat(@ceil(std.math.sqrt(@as(f32, @floatFromInt(num_views)))));
    const views_per_row: u32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(num_views)) / @as(f32, @floatFromInt(views_per_col))));
    var view_width: i32 = @intFromFloat(@as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(views_per_row)));
    const view_height: i32 = @intFromFloat(@as(f32, @floatFromInt(height)) / @as(f32, @floatFromInt(views_per_col)));
    var index_3d: u32 = 0;
    var index_2d: u32 = 0;
    const num_missing_views = views_per_col * views_per_row - num_views;
    const need_view_stretch = num_missing_views > 0;

    var camera_pos: v3 = .{};
    const light_pos: v3 = .{ .x = 0, .y = 0, .z = 80 };
    const light_color: v3 = .{ .x = 1, .y = 1, .z = 1 };

    pass_load_clear.action.colors[0].load_action = .CLEAR;
    sg.beginPass(pass_load_clear);
    sg.endPass();

    var temp_vertex_buffers = std.ArrayList(sg.Buffer).init(mem.frame);

    while (b.bytes.hasData()) {
        const header = b.pop(draw_api.Header);

        switch (header.kind) {
            .Camera3d => {
                const camera = b.pop(primitive.Camera3d);
                vp = m4.mul(camera.proj, camera.view);
                camera_pos = camera.pos;

                // index = j*height + i
                const row_index = @divFloor(index_3d, views_per_row);
                const col_index = index_3d - views_per_row * row_index;
                if (need_view_stretch and row_index == views_per_col - 1) {
                    const num_last_row_views = views_per_row - num_missing_views;
                    view_width = @intFromFloat(@as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(num_last_row_views)));
                }
                index_3d += 1;

                // Draw cubemap
                {
                    sg.beginPass(pass_load_color_depth);
                    sg.applyViewport(view_width * @as(i32, @intCast(col_index)), view_height * @as(i32, @intCast(row_index)), view_width, view_height, true);
                    sg.applyPipeline(pipeline_cubemap);
                    binding_cubemap.images[0] = image_cubemap;
                    sg.applyBindings(binding_cubemap);
                    const scale = 80000.0;
                    const model = m4.modelWithRotations(.{}, .{ .x = scale, .y = scale, .z = scale }, .{ .x = std.math.pi / 2.0, .y = 0.0, .z = 0 });
                    sg.applyUniforms(0, sg.asRange(&UniformsVertex2d{
                        .mvp = m4.transpose(m4.mul(vp, model)),
                    }));
                    sg.applyUniforms(1, sg.asRange(&UniformsFragment2d{
                        .color = v4{
                            .x = @as(f32, @floatFromInt(255)) / 255.0,
                            .y = @as(f32, @floatFromInt(255)) / 255.0,
                            .z = @as(f32, @floatFromInt(255)) / 255.0,
                            .w = @as(f32, @floatFromInt(255)) / 255.0,
                        },
                    }));
                    sg.draw(0, cube_indices.len, 1);
                    sg.endPass();
                }

                sg.beginPass(pass_load_color_depth);
                sg.applyViewport(view_width * @as(i32, @intCast(col_index)), view_height * @as(i32, @intCast(row_index)), view_width, view_height, true);
            },
            .End3d => {
                sg.endPass();
            },
            .Camera2d => {
                const camera = b.pop(primitive.Camera2d);

                const view_to_world = m4.model2d(camera.target, .{ .x = 0.5 / camera.zoom, .y = 0.5 / camera.zoom });
                const world_to_view = m4.inverse(view_to_world);

                vp = world_to_view;

                pass_load_clear.action.colors[0].load_action = .LOAD;
                sg.beginPass(pass_load_clear);

                // index = j*height + i
                const row_index = @divFloor(index_2d, views_per_row);
                const col_index = index_2d - views_per_row * row_index;
                if (need_view_stretch and row_index == views_per_col - 1) {
                    const num_last_row_views = views_per_row - num_missing_views;
                    view_width = @intFromFloat(@as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(num_last_row_views)));
                }
                sg.applyViewport(view_width * @as(i32, @intCast(col_index)), view_height * @as(i32, @intCast(row_index)), view_width, view_height, true);
                index_2d += 1;
            },
            .End2d => {
                sg.endPass();
            },
            .Text => {
                const text = b.pop(primitive.Text);

                const x: f32 = 2.0 * text.pos.x - 1.0;
                const y: f32 = 2.0 * text.pos.y - 1.0;

                binding_textured_rectangle.images[0] = image_font_atlas;
                sg.applyPipeline(pipeline_text);
                sg.applyBindings(binding_textured_rectangle);

                //const scale: f32 = 2.0 * text.size / (@as(f32, @floatFromInt(font.size)) / @as(f32, @floatFromInt(height)));
                //const scale: f32 = 1.0;//(1.0/60.0) / (1.0/2.0);//2.0 * text.size / (@as(f32, @floatFromInt(font.size)) / @as(f32, @floatFromInt(height)));
                const atlas_w: f32 = @floatFromInt(font.width);
                const atlas_h: f32 = @floatFromInt(font.height);

                var xoff: f32 = 0.0;
                for (text.str[0..text.len]) |c| {
                    const off = c - 32;
                    const char = font_chars[off];

                    const sx = @as(f32, @floatFromInt(char.x1 - char.x0)) / atlas_w;
                    const sy = @as(f32, @floatFromInt(char.y1 - char.y0)) / atlas_h;
                    const vsx = (char.xoff2 - char.xoff) / atlas_w;
                    const vsy = (char.yoff2 - char.yoff) / atlas_h;
                    //const scale: f32 = 2.0 * text.size / (sy / atlas_h);
                    const scale: f32 = 2.0 * text.size / (@as(f32, @floatFromInt(font.size)) / atlas_h);

                    sg.applyUniforms(0, sg.asRange(&UniformsVertexAtlas{
                        .vs_off = .{
                            .x = x + xoff + scale * char.xoff / atlas_w,
                            .y = y - scale * char.yoff / atlas_h - scale * vsy
                        },
                        .vs_scale = .{ .x = scale * vsx, .y = scale * vsy },
                    }));
                    sg.applyUniforms(1, sg.asRange(&UniformsFragmentAtlas{
                        .off = .{
                            .x = @as(f32, @floatFromInt(char.x0)) / atlas_w,
                            .y = @as(f32, @floatFromInt(char.y0)) / atlas_h
                        },
                        .scale = .{
                            .x = sx,
                            .y = sy
                        },
                        .fg = text.fg,
                        .bg = text.bg,
                    }));

                    sg.draw(0, textured_rectangle_indices.len, 1);
                    xoff += scale * char.xadvance / atlas_w;
                }
            },
            .Rectangle => {
                const r = b.pop(primitive.Rectangle);
                const offset = v2{ .x = r.size.x / 2, .y = r.size.y / 2 };
                const model = m4.model2d(v2.add(r.pos, offset), r.size);

                sg.applyPipeline(pipeline_2d);
                sg.applyBindings(rectangle_bind);
                sg.applyUniforms(0, sg.asRange(&UniformsVertex2d{
                    .mvp = m4.transpose(m4.mul(vp, model)),
                }));
                sg.applyUniforms(1, sg.asRange(&UniformsFragment2d{
                    .color = v4{
                        .x = @as(f32, @floatFromInt(header.color.r)) / 255.0,
                        .y = @as(f32, @floatFromInt(header.color.g)) / 255.0,
                        .z = @as(f32, @floatFromInt(header.color.b)) / 255.0,
                        .w = @as(f32, @floatFromInt(header.color.a)) / 255.0,
                    },
                }));
                sg.draw(0, rectangle_indices.len, 1);
            },
            .Mesh => {
                const cmd = b.pop(primitive.Mesh);

                const node_entry_info = goosepack.entry_lookup(pack, cmd.name);
                const node = goosepack.getResource(pack, node_entry_info.?.index).model_node;
                const model = goosepack.getResource(pack, @intCast(@as(i32, @intCast(node_entry_info.?.index)) + node.root_entry_relative_index)).model;

                if (cmd.draw_children and node_entry_info.?.entry.children != null) {
                    var stack = std.ArrayList(struct {
                        info: goosepack.EntryInfo,
                        parent_transform: m4,
                    }).initCapacity(mem.frame, 128) catch unreachable;
                    stack.appendAssumeCapacity(.{ .info = node_entry_info.?, .parent_transform = cmd.model });
                    while (stack.popOrNull()) |item| {
                        const mesh_node = goosepack.getResource(pack, item.info.index).model_node;

                        const transform = m4.mul(item.parent_transform, mesh_node.transform);
                        if (mesh_node.mesh_index) |mesh_index| {
                            const mesh = model.meshes[mesh_index];
                            for (mesh.primitives, 0..) |p, prim_index| {
                                const material = model.materials[p.material_index];
                                var mesh_binds = bindForMesh(model, material, mesh_index, @intCast(prim_index));
                                if (material.has_image) {
                                    mesh_binds.bind.images[0] = mesh_binds.image;
                                    mesh_binds.bind.samplers[0] = mesh_binds.sampler;
                                }
                                sg.applyPipeline(mesh_binds.pip);
                                sg.applyBindings(mesh_binds.bind);
                                sg.applyUniforms(0, sg.asRange(&UniformsVertex3d{
                                    .mvp = m4.transpose(m4.mul(vp, transform)),
                                    .model = m4.transpose(transform),
                                }));
                                sg.applyUniforms(1, sg.asRange(&UniformsFragment3d{
                                    .color = v4{
                                        .x = material.base_color.x * @as(f32, @floatFromInt(header.color.r)) / 255.0,
                                        .y = material.base_color.y * @as(f32, @floatFromInt(header.color.g)) / 255.0,
                                        .z = material.base_color.z * @as(f32, @floatFromInt(header.color.b)) / 255.0,
                                        .w = material.base_color.w * @as(f32, @floatFromInt(header.color.a)) / 255.0,
                                    },
                                    .light_pos = light_pos,
                                    .light_color = light_color,
                                    .camera_pos = camera_pos,
                                }));
                                sg.draw(0, @intCast(p.indices.?.len / 2), 1);
                            }
                        }

                        if (item.info.entry.children) |children| {
                            for (children) |c| {
                                const index: u32 = @intCast(@as(i32, @intCast(item.info.index)) + c);
                                const entry = pack.entries.?.items[index];
                                stack.appendAssumeCapacity(.{ .info = .{ .entry = entry, .index = index }, .parent_transform = transform });
                            }
                        }
                    }
                } else {
                    if (node.mesh_index) |mesh_index| {
                        const mesh = model.meshes[mesh_index];
                        for (mesh.primitives, 0..) |p, prim_index| {
                            const material = model.materials[p.material_index];
                            var mesh_binds = bindForMesh(model, material, mesh_index, @intCast(prim_index));
                            if (material.has_image) {
                                mesh_binds.bind.images[0] = mesh_binds.image;
                                mesh_binds.bind.samplers[0] = mesh_binds.sampler;
                            }
                            sg.applyPipeline(mesh_binds.pip);
                            sg.applyBindings(mesh_binds.bind);
                            const transform = m4.mul(cmd.model, node.transform);
                            sg.applyUniforms(0, sg.asRange(&UniformsVertex3d{
                                .mvp = m4.transpose(m4.mul(vp, transform)),
                                .model = m4.transpose(transform),
                            }));
                            sg.applyUniforms(1, sg.asRange(&UniformsFragment3d{
                                .color = v4{
                                    .x = material.base_color.x * @as(f32, @floatFromInt(header.color.r)) / 255.0,
                                    .y = material.base_color.y * @as(f32, @floatFromInt(header.color.g)) / 255.0,
                                    .z = material.base_color.z * @as(f32, @floatFromInt(header.color.b)) / 255.0,
                                    .w = material.base_color.w * @as(f32, @floatFromInt(header.color.a)) / 255.0,
                                },
                                .light_pos = light_pos,
                                .light_color = light_color,
                                .camera_pos = camera_pos,
                            }));
                            sg.draw(0, @intCast(p.indices.?.len / 2), 1);
                        }
                    }
                }
            },
            .Cube => {
                const cube = b.pop(primitive.Cube);

                {
                    sg.applyPipeline(pipeline_3d);
                    sg.applyBindings(cube_bind);
                    sg.applyUniforms(0, sg.asRange(&UniformsVertex3d{
                        .mvp = m4.transpose(m4.mul(vp, cube.model)),
                        .model = m4.transpose(cube.model),
                    }));
                    sg.applyUniforms(1, sg.asRange(&UniformsFragment3d{
                        .color = v4{
                            .x = @as(f32, @floatFromInt(header.color.r)) / 255.0,
                            .y = @as(f32, @floatFromInt(header.color.g)) / 255.0,
                            .z = @as(f32, @floatFromInt(header.color.b)) / 255.0,
                            .w = @as(f32, @floatFromInt(header.color.a)) / 255.0,
                        },
                        .light_pos = light_pos,
                        .light_color = light_color,
                        .camera_pos = camera_pos,
                    }));
                    sg.draw(0, cube_indices.len, 1);
                }
            },
            .CubeOutline => {
                const cube = b.pop(primitive.CubeOutline);

                const pos = [4]v3{
                    .{ .x = 0.5, .y = 0.5, .z = 0 },
                    .{ .x = 0.5, .y = -0.5, .z = 0 },
                    .{ .x = -0.5, .y = 0.5, .z = 0 },
                    .{ .x = -0.5, .y = -0.5, .z = 0 },
                };
                const scale = v3{ .x = cube.thickness, .y = cube.thickness, .z = 1 };
                const inds = [3][3]u8{
                    .{ 0, 1, 2 },
                    .{ 0, 2, 1 },
                    .{ 2, 0, 1 },
                };
                for (0..12) |i| {
                    const group = @divTrunc(i, 4);
                    const index = i % 4;
                    const ss = v3{
                        .x = @as([3]f32, @bitCast(scale))[inds[group][0]],
                        .y = @as([3]f32, @bitCast(scale))[inds[group][1]],
                        .z = @as([3]f32, @bitCast(scale))[inds[group][2]],
                    };
                    const pp = v3{
                        .x = @as([3]f32, @bitCast(pos[index]))[inds[group][0]],
                        .y = @as([3]f32, @bitCast(pos[index]))[inds[group][1]],
                        .z = @as([3]f32, @bitCast(pos[index]))[inds[group][2]],
                    };
                    const m = math.m4.model(pp, ss);
                    sg.applyPipeline(pipeline_3d);
                    sg.applyBindings(cube_bind);
                    sg.applyUniforms(0, sg.asRange(&UniformsVertex3d{
                        .mvp = m4.transpose(m4.mul(vp, m4.mul(cube.model, m))),
                        .model = m4.transpose(cube.model),
                    }));
                    sg.applyUniforms(1, sg.asRange(&UniformsFragment3d{
                        .color = v4{
                            .x = @as(f32, @floatFromInt(header.color.r)) / 255.0,
                            .y = @as(f32, @floatFromInt(header.color.g)) / 255.0,
                            .z = @as(f32, @floatFromInt(header.color.b)) / 255.0,
                            .w = @as(f32, @floatFromInt(header.color.a)) / 255.0,
                        },
                        .light_pos = light_pos,
                        .light_color = light_color,
                        .camera_pos = camera_pos,
                    }));
                    sg.draw(0, cube_indices.len, 1);
                }
            },
            .VoxelChunk => {
                const chunk = b.pop(primitive.VoxelChunk);

                const data_ptr: [*]u8 = @ptrCast(chunk.voxels.ptr);
                const data_slice = data_ptr[0..4*chunk.voxels.len];
                //std.debug.assert(4*@sizeOf(f32)*data_slice.len == @sizeOf(primitive.VoxelTransform)*chunk.voxels.len);
                temp_vertex_buffers.append(sg.makeBuffer(.{
                    .data = sg.asRange(&voxel_face_vertices),
                })) catch unreachable;
                temp_vertex_buffers.append(sg.makeBuffer(.{
                    .data = sg.asRange(&voxel_face_normals),
                })) catch unreachable;
                temp_vertex_buffers.append(sg.makeBuffer(.{
                    .data = sg.asRange(data_slice),
                })) catch unreachable;
                temp_vertex_buffers.append(sg.makeBuffer(.{
                    .type = .INDEXBUFFER,
                    .data = sg.asRange(&voxel_face_indices),
                })) catch unreachable;
                var bind = sg.Bindings{};
                bind.vertex_buffers[0] = temp_vertex_buffers.items[0];
                bind.vertex_buffers[1] = temp_vertex_buffers.items[1];
                bind.vertex_buffers[2] = temp_vertex_buffers.items[2];
                bind.index_buffer = temp_vertex_buffers.items[3];

                sg.applyPipeline(pipeline_voxel);
                sg.applyBindings(bind);
                uniforms_voxel.vp = m4.transpose(vp);
                sg.applyUniforms(0, sg.asRange(&uniforms_voxel));
                sg.applyUniforms(1, sg.asRange(&UniformsFragmentVoxelChunk{
                    .color = v4{
                        .x = @as(f32, @floatFromInt(header.color.r)) / 255.0,
                        .y = @as(f32, @floatFromInt(header.color.g)) / 255.0,
                        .z = @as(f32, @floatFromInt(header.color.b)) / 255.0,
                        .w = @as(f32, @floatFromInt(header.color.a)) / 255.0,
                    },
                    .light_pos = light_pos,
                    .light_color = light_color,
                    .camera_pos = camera_pos,
                }));
                sg.draw(0, cube_indices.len, @intCast(chunk.voxels.len));
            },
            .VoxelTransform => {},
            else => {},
        }
    }

    {
        binding_textured_rectangle.images[0] = image_3d_framebuffer;
        sg.beginPass(pass_load_swapchain);
        sg.applyPipeline(pipeline_postprocess);
        sg.applyBindings(binding_textured_rectangle);
        sg.draw(0, textured_rectangle_indices.len, 1);
        sg.endPass();
    }

    // TODO(anjo): Move 2d to separate buffer and process here, get rid of this
    // shader
    {
        binding_textured_rectangle.images[0] = image_2d_framebuffer;
        sg.beginPass(pass_load_swapchain);
        sg.applyPipeline(pipeline_overlay_2d);
        sg.applyBindings(binding_textured_rectangle);
        sg.draw(0, textured_rectangle_indices.len, 1);
        sg.endPass();
    }

    sg.commit();

    for (temp_vertex_buffers.items) |buf| {
        sg.destroyBuffer(buf);
    }
}
