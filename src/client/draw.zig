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

const sokol = @import("sokol");
const sg = sokol.gfx;
const slog = sokol.log;

const res = common.res;
const goosepack = common.goosepack;

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

const Offscreen3d = struct {
    pass: sg.Pass = .{},
    pip: sg.Pipeline = .{},
    bind: sg.Bindings = .{},
    color: sg.Image = undefined,
    depth: sg.Image = undefined,
};

const Offscreen2d = struct {
    pass: sg.Pass = .{},
    pip: sg.Pipeline = .{},
    bind: sg.Bindings = .{},
    color: sg.Image = undefined,
};

const OffscreenCubemap = struct {
    pass: sg.Pass = .{},
    pip: sg.Pipeline = .{},
    bind: sg.Bindings = .{},
};

const Display = struct {
    pass: sg.Pass = .{},
    pip: sg.Pipeline = .{},
    bind: sg.Bindings = .{},
};

const Postprocess = struct {
    pass: sg.Pass = .{},
    pip: sg.Pipeline = .{},
    bind: sg.Bindings = .{},
};

const TextPipeline = struct {
    pass: sg.Pass = .{},
    pip: sg.Pipeline = .{},
    bind: sg.Bindings = .{},
    atlas: sg.Image = undefined,
    chars: []res.FontChar = undefined,
};

var text_pipeline: TextPipeline = .{};
var postprocess: Postprocess = .{};
var display: Display = .{};
var offscreen_3d: Offscreen3d = .{};
var offscreen_2d: Offscreen2d = .{};
var offscreen_cubemap: OffscreenCubemap = .{};

var pip_mesh = sg.Pipeline{};
var pip_mesh_line = sg.Pipeline{};
var pip_triangle_strip = sg.Pipeline{};

var circle_bind = sg.Bindings{};
var rectangle_bind = sg.Bindings{};
var cube_bind = sg.Bindings{};

var pipelines: std.BoundedArray(sg.Pipeline, 16) = .{};
var shd_3d: sg.Shader = undefined;

const BindInfo = struct {
    base: *const u8,
    prim_index: u32,
    mesh_index: u32,
    bind: sg.Bindings,
};

var binds: std.BoundedArray(BindInfo, 64) = .{};

fn sliceFromBufferView(model: res.Model, view: res.BufferView) []const u8 {
    const base: [*]const u8 = @ptrCast(model.binary_data.ptr);
    return (base + view.offset)[0..view.size];
}

fn buildBindForMesh(model: res.Model, mesh_index: u32, prim_index: u32) sg.Bindings {
    const mesh = model.meshes[mesh_index];
    const prim = mesh.primitives[prim_index];
    var bind: sg.Bindings = .{};
    if ((prim.buffer_types & res.bt_position) != 0) {
        const buf = sliceFromBufferView(model, prim.pos);
        bind.vertex_buffers[0] = sg.makeBuffer(.{
            .data = sg.asRange(buf),
        });
    }
    if ((prim.buffer_types & res.bt_normals) != 0) {
        const buf = sliceFromBufferView(model, prim.normals);
        bind.vertex_buffers[1] = sg.makeBuffer(.{
            .data = sg.asRange(buf),
        });
    }
    if ((prim.buffer_types & res.bt_indices) != 0) {
        const buf = sliceFromBufferView(model, prim.indices);
        bind.index_buffer = sg.makeBuffer(.{
            .type = .INDEXBUFFER,
            .data = sg.asRange(buf),
        });
    }
    return bind;
}

fn bindForMesh(model: res.Model, mesh_index: u32, prim_index: u32) sg.Bindings {
    for (binds.buffer) |info| {
        if (info.base == @as(*const u8, @ptrCast(model.binary_data.ptr)) and info.mesh_index == mesh_index and info.prim_index == prim_index)
            return info.bind;
    }
    const bind = buildBindForMesh(model, mesh_index, prim_index);
    binds.appendAssumeCapacity(.{ .base = @ptrCast(model.binary_data.ptr), .mesh_index = mesh_index, .prim_index = prim_index, .bind = bind });
    return bind;
}

// TODO: ?
fn buildPipelineForModel(model: res.Model) *sg.Pipeline {
    _ = model;
    var attachments_desc = sg.AttachmentsDesc{};
    attachments_desc.colors[0].image = offscreen_3d.color;
    attachments_desc.depth_stencil.image = offscreen_3d.depth;
    offscreen_3d.pass.attachments = sg.makeAttachments(attachments_desc);
    //offscreen_3d.pass.swapchain.width =
    //offscreen_3d.pass.swapchain.height =

    var desc = sg.PipelineDesc{
        .index_type = .UINT16,
        .shader = shd_3d,
        .primitive_type = .TRIANGLE,
        .cull_mode = .FRONT,
        .sample_count = 1,
        .depth = .{
            .pixel_format = .DEPTH,
            .compare = .LESS_EQUAL,
            .write_enabled = true,
        },
    };
    desc.colors[0] = .{
        .blend = .{
            .enabled = true,
            .src_factor_rgb = .SRC_ALPHA,
            .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
        },
        .pixel_format = .RGBA8,
    };
    desc.layout.attrs[0].format = .FLOAT3;

    const pip = pipelines.addOneAssumeCapacity();
    pip.* = sg.makePipeline(desc);
    return pip;
}

const Uniforms3d = struct {
    mvp: m4,
    model: m4,
    color: v4,
    light_pos: v3 = .{},
    light_color: v3 = .{},
    camera_pos: v3 = .{},
};

const Uniforms2d = struct {
    mvp: m4,
    color: v4,
};

const AtlasUniform = struct {
    off: v2,
    scale: v2,
    vs_off: v2,
    vs_scale: v2,
    fg: v4,
    bg: v4,
};

const TextUniform = struct {
    off: v2,
    scale: v2,
};

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

pub fn init(_mem: common.MemoryAllocators, _pack: *goosepack.Pack) void {
    mem = _mem;

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

    // 2d shader
    var shd_2d: sg.Shader = undefined;
    {
        var shd_desc = sg.ShaderDesc{};
        shd_desc.vs.source =
            \\ #version 330
            \\ layout(location=0) in vec2 position;
            \\ uniform mat4 mvp;
            \\ uniform mat4 model;
            \\ void main() {
            \\   gl_Position = mvp*vec4(position, 0, 1);
            \\ }
        ;
        shd_desc.fs.source =
            \\ #version 330
            \\ uniform vec4 color;
            \\ out vec4 frag_color;
            \\ void main() {
            \\   frag_color = color;
            \\ }
        ;
        shd_desc.vs.uniform_blocks[0].size = @sizeOf(Uniforms2d);
        shd_desc.vs.uniform_blocks[0].uniforms[0] = .{
            .name = "mvp",
            .type = .MAT4,
        };
        shd_desc.vs.uniform_blocks[0].uniforms[1] = .{
            .name = "color",
            .type = .FLOAT4,
        };
        shd_2d = sg.makeShader(shd_desc);
    }

    // 3d shader
    {
        var shd_desc = sg.ShaderDesc{};
        const res_shader = goosepack.lookup(pack, "res/default").?.shader;
        const vs = res_shader.vs_bytes;
        const fs = res_shader.fs_bytes;
        shd_desc.vs.source = @ptrCast(vs);
        shd_desc.fs.source = @ptrCast(fs);
        shd_desc.vs.uniform_blocks[0].size = @sizeOf(Uniforms3d);
        shd_desc.vs.uniform_blocks[0].uniforms[0] = .{
            .name = "mvp",
            .type = .MAT4,
        };
        shd_desc.vs.uniform_blocks[0].uniforms[1] = .{
            .name = "model",
            .type = .MAT4,
        };
        shd_desc.vs.uniform_blocks[0].uniforms[2] = .{
            .name = "color",
            .type = .FLOAT4,
        };
        shd_desc.vs.uniform_blocks[0].uniforms[3] = .{
            .name = "light_pos",
            .type = .FLOAT3,
        };
        shd_desc.vs.uniform_blocks[0].uniforms[4] = .{
            .name = "light_color",
            .type = .FLOAT3,
        };
        shd_desc.vs.uniform_blocks[0].uniforms[5] = .{
            .name = "camera_pos",
            .type = .FLOAT3,
        };
        std.log.info("f {}\n", .{fs[fs.len - 1]});
        std.log.info("v {}\n", .{vs[vs.len - 1]});
        shd_3d = sg.makeShader(shd_desc);
        std.log.info("arstarsta\n", .{});
    }

    // Postprocess shader
    var shd_pp: sg.Shader = undefined;
    {
        var shd_desc = sg.ShaderDesc{};

        const res_shader = goosepack.lookup(pack, "res/cc").?.shader;
        const vs = res_shader.vs_bytes;
        const fs = res_shader.fs_bytes;
        shd_desc.vs.source = @ptrCast(vs);
        shd_desc.fs.source = @ptrCast(fs);

        shd_desc.fs.images[0] = .{ .used = true };
        shd_desc.fs.samplers[0] = .{ .used = true };
        shd_desc.fs.image_sampler_pairs[0] = .{
            .used = true,
            .image_slot = 0,
            .sampler_slot = 0,
            .glsl_name = "tex",
        };
        shd_pp = sg.makeShader(shd_desc);
    }

    var shd_text: sg.Shader = undefined;
    {
        var shd_desc = sg.ShaderDesc{};
        shd_desc.vs.source =
            \\ #version 330
            \\ layout(location=0) in vec2 position;
            \\ layout(location=1) in vec2 texcoords;
            \\ out vec2 v_texcoords;
            \\ uniform vec2 vs_off;
            \\ uniform vec2 vs_scale;
            \\ void main() {
            \\   v_texcoords = texcoords;
            \\   gl_Position = vec4(vs_scale*0.5*(position+vec2(1,1)) + vs_off, 0, 1);
            \\ }
        ;
        shd_desc.fs.source =
            \\ #version 330
            \\ in vec2 v_texcoords;
            \\ out vec4 frag_color;
            \\ uniform sampler2D tex;
            \\ uniform vec2 off;
            \\ uniform vec2 scale;
            \\ uniform vec4 fg;
            \\ uniform vec4 bg;
            \\ void main() {
            \\   float c = texture(tex, scale*v_texcoords + off).r;
            \\   frag_color = vec4(0,0,0,0) + fg*c;
            \\ }
        ;

        shd_desc.fs.uniform_blocks[0].size = @sizeOf(AtlasUniform);
        shd_desc.fs.uniform_blocks[0].uniforms[0] = .{
            .name = "off",
            .type = .FLOAT2,
        };
        shd_desc.fs.uniform_blocks[0].uniforms[1] = .{
            .name = "scale",
            .type = .FLOAT2,
        };
        shd_desc.fs.uniform_blocks[0].uniforms[2] = .{
            .name = "vs_off",
            .type = .FLOAT2,
        };
        shd_desc.fs.uniform_blocks[0].uniforms[3] = .{
            .name = "vs_scale",
            .type = .FLOAT2,
        };
        shd_desc.fs.uniform_blocks[0].uniforms[4] = .{
            .name = "fg",
            .type = .FLOAT4,
        };
        shd_desc.fs.uniform_blocks[0].uniforms[5] = .{
            .name = "bg",
            .type = .FLOAT4,
        };

        shd_desc.fs.images[0] = .{ .used = true };
        shd_desc.fs.samplers[0] = .{ .used = true };
        shd_desc.fs.image_sampler_pairs[0] = .{
            .used = true,
            .image_slot = 0,
            .sampler_slot = 0,
            .glsl_name = "tex",
        };
        shd_text = sg.makeShader(shd_desc);
    }

    // Display shader
    var shd_display: sg.Shader = undefined;
    {
        var shd_desc = sg.ShaderDesc{};
        shd_desc.vs.source =
            \\ #version 330
            \\ layout(location=0) in vec2 position;
            \\ layout(location=1) in vec2 texcoords;
            \\ out vec2 v_texcoords;
            \\ void main() {
            \\   v_texcoords = texcoords;
            \\   gl_Position = vec4(position, 0, 1);
            \\ }
        ;
        shd_desc.fs.source =
            \\ #version 330
            \\ in vec2 v_texcoords;
            \\ out vec4 frag_color;
            \\ uniform sampler2D tex;
            \\ void main() {
            \\   frag_color = texture(tex, vec2(v_texcoords.x, 1.0-v_texcoords.y));
            \\ }
        ;

        shd_desc.fs.images[0] = .{ .used = true };
        shd_desc.fs.samplers[0] = .{ .used = true };
        shd_desc.fs.image_sampler_pairs[0] = .{
            .used = true,
            .image_slot = 0,
            .sampler_slot = 0,
            .glsl_name = "tex",
        };
        shd_display = sg.makeShader(shd_desc);
    }

    // Cubemap shader
    var shd_cm: sg.Shader = undefined;
    {
        var shd_desc = sg.ShaderDesc{};
        shd_desc.vs.source =
            \\ #version 330
            \\ layout(location=0) in vec3 position;
            \\ out vec3 v_texcoords;
            \\ uniform mat4 mvp;
            \\ uniform mat4 model;
            \\ void main() {
            \\   v_texcoords = normalize(position);
            \\   gl_Position = mvp*vec4(position, 1);
            \\ }
        ;
        shd_desc.fs.source =
            \\ #version 330
            \\ in vec3 v_texcoords;
            \\ out vec4 frag_color;
            \\ uniform samplerCube cube;
            \\ uniform vec4 color;
            \\ void main() {
            \\   frag_color = color*texture(cube, v_texcoords);
            \\ }
        ;
        shd_desc.vs.uniform_blocks[0].size = @sizeOf(Uniforms2d);
        shd_desc.vs.uniform_blocks[0].uniforms[0] = .{
            .name = "mvp",
            .type = .MAT4,
        };
        shd_desc.vs.uniform_blocks[0].uniforms[1] = .{
            .name = "color",
            .type = .FLOAT4,
        };
        shd_desc.fs.images[0] = .{ .used = true, .image_type = .CUBE };
        shd_desc.fs.samplers[0] = .{ .used = true };
        shd_desc.fs.image_sampler_pairs[0] = .{
            .used = true,
            .image_slot = 0,
            .sampler_slot = 0,
            .glsl_name = "cube",
        };
        shd_cm = sg.makeShader(shd_desc);
    }

    //
    // Pipelines
    //

    // Offscreen 3d
    {
        offscreen_3d.pass.action.colors[0] = .{
            .load_action = .LOAD,
        };

        offscreen_3d.color = sg.makeImage(.{
            .render_target = true,
            .width = 800,
            .height = 600,
            .pixel_format = .RGBA8,
            .sample_count = 1,
        });

        offscreen_3d.depth = sg.makeImage(.{
            .render_target = true,
            .width = 800,
            .height = 600,
            .pixel_format = .DEPTH,
            .sample_count = 1,
        });

        var attachments_desc = sg.AttachmentsDesc{};
        attachments_desc.colors[0].image = offscreen_3d.color;
        attachments_desc.depth_stencil.image = offscreen_3d.depth;
        offscreen_3d.pass.attachments = sg.makeAttachments(attachments_desc);

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
        offscreen_3d.pip = sg.makePipeline(pip_desc);
    }

    // Offscreen 2d
    {
        offscreen_2d.pass.action.colors[0] = .{
            .load_action = .LOAD,
            .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
        };

        offscreen_2d.color = sg.makeImage(.{
            .render_target = true,
            .width = 800,
            .height = 600,
            .pixel_format = .RGBA8,
            .sample_count = 1,
        });

        var attachments_desc = sg.AttachmentsDesc{};
        attachments_desc.colors[0].image = offscreen_2d.color;
        offscreen_2d.pass.attachments = sg.makeAttachments(attachments_desc);

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
        offscreen_2d.pip = sg.makePipeline(pip_desc);
    }

    // Text shader
    {
        text_pipeline.pass.action.colors[0] = .{
            .load_action = .LOAD,
        };

        font = goosepack.lookup(pack, "res/fonts/MononokiNerdFontMono-Regular").?.font;
        var data = sg.ImageData{};
        data.subimage[0][0] = .{ .ptr = font.pixels.ptr, .size = font.pixels.len };
        text_pipeline.atlas = sg.makeImage(.{
            .width = font.width,
            .height = font.height,
            .data = data,
            .pixel_format = .R8,
            .sample_count = 1,
        });
        text_pipeline.chars = font.chars;

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
        text_pipeline.pip = sg.makePipeline(pip_desc);

        const smp = sg.makeSampler(.{
            .min_filter = .LINEAR,
            .mag_filter = .LINEAR,
            .wrap_u = .REPEAT,
            .wrap_v = .REPEAT,
        });

        text_pipeline.bind.vertex_buffers[0] = sg.makeBuffer(.{
            .data = sg.asRange(&textured_rectangle_vertices),
        });
        text_pipeline.bind.index_buffer = sg.makeBuffer(.{
            .type = .INDEXBUFFER,
            .data = sg.asRange(&textured_rectangle_indices),
        });
        text_pipeline.bind.fs.samplers[0] = smp;
    }

    // Cubemap
    {
        offscreen_cubemap.pass.action.colors[0] = .{
            .load_action = .LOAD,
        };

        var attachments_desc = sg.AttachmentsDesc{};
        attachments_desc.colors[0].image = offscreen_3d.color;
        attachments_desc.depth_stencil.image = offscreen_3d.depth;
        offscreen_cubemap.pass.attachments = sg.makeAttachments(attachments_desc);

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
        offscreen_cubemap.pip = sg.makePipeline(pip_desc);

        offscreen_cubemap.bind.vertex_buffers[0] = sg.makeBuffer(.{
            .data = sg.asRange(&cube_vertices),
        });
        offscreen_cubemap.bind.index_buffer = sg.makeBuffer(.{
            .type = .INDEXBUFFER,
            .data = sg.asRange(&cube_indices),
        });

        const cubemap = goosepack.lookup(pack, "res/cm").?.cubemap;

        var img_desc = sg.ImageDesc{
            .type = .CUBE,
            .width = @intCast(cubemap.width),
            .height = @intCast(cubemap.height),
            .pixel_format = .RGBA8,
        };
        for (0..@intFromEnum(sg.CubeFace.NUM)) |i| {
            img_desc.data.subimage[i][0] = sg.asRange(cubemap.faceSlice(@intCast(i)));
        }
        offscreen_cubemap.bind.fs.images[0] = sg.allocImage();
        sg.initImage(offscreen_cubemap.bind.fs.images[0], img_desc);

        const smp = sg.makeSampler(.{
            .min_filter = .LINEAR,
            .mag_filter = .LINEAR,
        });
        offscreen_cubemap.bind.fs.samplers[0] = smp;
    }

    // Postprocess
    {
        postprocess.pass.action.colors[0] = .{
            .load_action = .LOAD,
        };
        postprocess.pass.swapchain.width = 800;
        postprocess.pass.swapchain.height = 600;

        //var attachments_desc = sg.AttachmentsDesc{};
        //attachments_desc.colors[0].image = offscreen_3d.color;
        ////attachments_desc.depth_stencil.image = offscreen_3d.depth;
        //postprocess.pass.attachments = sg.makeAttachments(attachments_desc);

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
        postprocess.pip = sg.makePipeline(pip_desc);

        const smp = sg.makeSampler(.{
            .min_filter = .LINEAR,
            .mag_filter = .LINEAR,
            .wrap_u = .REPEAT,
            .wrap_v = .REPEAT,
        });

        postprocess.bind.vertex_buffers[0] = sg.makeBuffer(.{
            .data = sg.asRange(&textured_rectangle_vertices),
        });
        postprocess.bind.index_buffer = sg.makeBuffer(.{
            .type = .INDEXBUFFER,
            .data = sg.asRange(&textured_rectangle_indices),
        });
        postprocess.bind.fs.samplers[0] = smp;
    }

    // Display
    {
        display.pass.action.colors[0] = .{
            .load_action = .LOAD,
        };
        display.pass.swapchain.width = 800;
        display.pass.swapchain.height = 600;

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
        display.pip = sg.makePipeline(pip_desc);

        const smp = sg.makeSampler(.{
            .min_filter = .LINEAR,
            .mag_filter = .LINEAR,
            .wrap_u = .REPEAT,
            .wrap_v = .REPEAT,
        });

        display.bind.vertex_buffers[0] = sg.makeBuffer(.{
            .data = sg.asRange(&textured_rectangle_vertices),
        });
        display.bind.index_buffer = sg.makeBuffer(.{
            .type = .INDEXBUFFER,
            .data = sg.asRange(&textured_rectangle_indices),
        });
        display.bind.fs.samplers[0] = smp;
    }

    // 3d mesh shader
    {
        var pip_desc = sg.PipelineDesc{
            .shader = shd_3d,
            .cull_mode = .BACK,
            .depth = .{
                .compare = .LESS_EQUAL,
                .write_enabled = true,
            },
        };
        pip_desc.layout.attrs[0].format = .FLOAT3;
        pip_mesh = sg.makePipeline(pip_desc);
    }
    // pip mesh line
    {
        var pip_desc = sg.PipelineDesc{
            .shader = shd_3d,
            .primitive_type = .LINE_STRIP,
            .depth = .{
                .compare = .LESS_EQUAL,
                .write_enabled = true,
            },
        };
        pip_desc.layout.attrs[0].format = .FLOAT3;
        pip_mesh_line = sg.makePipeline(pip_desc);
    }
    // triangle strip
    {
        var pip_desc = sg.PipelineDesc{
            .shader = shd_3d,
            .primitive_type = .TRIANGLE_STRIP,
            .depth = .{
                .compare = .LESS_EQUAL,
                .write_enabled = true,
            },
        };
        pip_desc.layout.attrs[0].format = .FLOAT3;
        pip_triangle_strip = sg.makePipeline(pip_desc);
    }
}

pub fn deinit() void {
    sg.shutdown();
}

pub fn process(b: *draw_api.CommandBuffer, width: u32, height: u32, num_views: u32) void {
    var vp: m4 = .{};

    if (num_views == 0)
        return;

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

    offscreen_2d.pass.action.colors[0].load_action = .CLEAR;
    sg.beginPass(offscreen_2d.pass);
    sg.endPass();

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
                    sg.beginPass(offscreen_cubemap.pass);
                    sg.applyViewport(view_width * @as(i32, @intCast(col_index)), view_height * @as(i32, @intCast(row_index)), view_width, view_height, true);
                    sg.applyPipeline(offscreen_cubemap.pip);
                    sg.applyBindings(offscreen_cubemap.bind);
                    const scale = 80000.0;
                    const model = m4.modelWithRotations(.{}, .{ .x = scale, .y = scale, .z = scale }, .{ .x = std.math.pi / 2.0, .y = 0.0, .z = 0 });
                    const uniforms = Uniforms2d{
                        .mvp = m4.transpose(m4.mul(vp, model)),
                        .color = v4{
                            .x = @as(f32, @floatFromInt(255)) / 255.0,
                            .y = @as(f32, @floatFromInt(255)) / 255.0,
                            .z = @as(f32, @floatFromInt(255)) / 255.0,
                            .w = @as(f32, @floatFromInt(255)) / 255.0,
                        },
                    };
                    sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
                    sg.draw(0, cube_indices.len, 1);
                    sg.endPass();
                }

                sg.beginPass(offscreen_3d.pass);
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

                offscreen_2d.pass.action.colors[0].load_action = .LOAD;
                sg.beginPass(offscreen_2d.pass);

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

                text_pipeline.bind.fs.images[0] = text_pipeline.atlas;
                sg.applyPipeline(text_pipeline.pip);
                sg.applyBindings(text_pipeline.bind);

                const scale: f32 = 2.0 * text.size / (@as(f32, @floatFromInt(font.size)) / @as(f32, @floatFromInt(height)));
                const atlas_w: f32 = @floatFromInt(font.width);
                const atlas_h: f32 = @floatFromInt(font.height);

                var xoff: f32 = 0.0;
                for (text.str[0..text.len]) |c| {
                    const off = c - 32;
                    const char = text_pipeline.chars[off];

                    const sx = @as(f32, @floatFromInt(char.x1 - char.x0)) / atlas_w;
                    const sy = @as(f32, @floatFromInt(char.y1 - char.y0)) / atlas_h;
                    const vsx = (char.xoff2 - char.xoff) / atlas_w;
                    const vsy = (char.yoff2 - char.yoff) / atlas_h;

                    const uniforms = AtlasUniform{
                        .off = .{ .x = @as(f32, @floatFromInt(char.x0)) / atlas_w, .y = @as(f32, @floatFromInt(char.y0)) / atlas_h },
                        .scale = .{ .x = sx, .y = sy },
                        .vs_off = .{ .x = x + xoff + scale * char.xoff / atlas_w, .y = y - scale * char.yoff / atlas_h - scale * vsy },
                        .vs_scale = .{ .x = scale * vsx, .y = scale * vsy },
                        .fg = text.fg,
                        .bg = text.bg,
                    };
                    sg.applyUniforms(.FS, 0, sg.asRange(&uniforms));

                    sg.draw(0, textured_rectangle_indices.len, 1);
                    xoff += scale * char.xadvance / atlas_w;
                }
            },
            .Line => {
                const line = b.pop(primitive.Line);
                _ = line;
                //raylib.DrawLineEx(
                //    castToRaylibVector2(line.start),
                //    castToRaylibVector2(line.end),
                //    line.thickness,
                //    castToRaylibColor(header.color)
                //);
            },
            // .Mesh => {
            //     const m = b.pop(primitive.Mesh);
            //     _ = m;
            //
            //     //var bind = sg.Bindings{};
            //     //bind.vertex_buffers[0] = sg.makeBuffer(.{
            //     //    .data = sg.asRange(m.verts),
            //     //});
            //
            //     //const model = m4.model(.{ .x = 0, .y = 0, .z = 0 }, .{ .x = 1, .y = 1, .z = 1 });
            //     //var uniforms = Uniforms{
            //     //    .mvp = m4.transpose(m4.mul(vp, model)),
            //     //    .color = v4{ .x = 255.0, .y = 255.0, .z = 255.0, .w = 255.0 },
            //     //};
            //
            //     //// TODO(anjo): We're always going to miss the last edge, we have to list
            //     //// the first vertex at the end to get around this...
            //     ////
            //     //// we can probably use a geometry shader
            //     ////  https://learnopengl.com/Advanced-OpenGL/Geometry-Shader
            //     ////sg.applyPipeline(pip_mesh_line);
            //     ////sg.applyBindings(bind);
            //     ////sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
            //     ////sg.draw(0, @intCast(m.verts.len), 1);
            //
            //     //uniforms.color.x = @as(f32, @floatFromInt(header.color.r)) / 255.0;
            //     //uniforms.color.y = @as(f32, @floatFromInt(header.color.g)) / 255.0;
            //     //uniforms.color.z = @as(f32, @floatFromInt(header.color.b)) / 255.0;
            //     //uniforms.color.w = @as(f32, @floatFromInt(header.color.a)) / 255.0;
            //
            //     //sg.applyPipeline(pip_mesh);
            //     //sg.applyBindings(bind);
            //     //sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
            //     //sg.draw(0, @intCast(m.verts.len), 1);
            //
            //     //sg.destroyBuffer(bind.vertex_buffers[0]);
            // },
            .Rectangle => {
                const r = b.pop(primitive.Rectangle);
                const offset = v2{ .x = r.size.x / 2, .y = r.size.y / 2 };
                const model = m4.model2d(v2.add(r.pos, offset), r.size);
                const uniforms = Uniforms2d{
                    .mvp = m4.transpose(m4.mul(vp, model)),
                    .color = v4{
                        .x = @as(f32, @floatFromInt(header.color.r)) / 255.0,
                        .y = @as(f32, @floatFromInt(header.color.g)) / 255.0,
                        .z = @as(f32, @floatFromInt(header.color.b)) / 255.0,
                        .w = @as(f32, @floatFromInt(header.color.a)) / 255.0,
                    },
                };

                sg.applyPipeline(offscreen_2d.pip);
                sg.applyBindings(rectangle_bind);
                sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
                sg.draw(0, rectangle_indices.len, 1);
            },
            .Mesh => {
                const cmd = b.pop(primitive.Mesh);

                const node_entry_info = goosepack.lookupEntry(pack, cmd.name);
                const node = goosepack.getResource(pack, node_entry_info.?.index).model_node;
                const res_model = goosepack.lookup(pack, node.model_name) orelse {
                    std.log.info("Failed to lookup {s}\n", .{node.model_name});
                    unreachable;
                };
                const model = res_model.model;

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
                                const bind = bindForMesh(model, mesh_index, @intCast(prim_index));
                                const mat = model.materials[p.material_index];
                                sg.applyPipeline(offscreen_3d.pip);
                                sg.applyBindings(bind);
                                const uniforms = Uniforms3d{
                                    .mvp = m4.transpose(m4.mul(vp, transform)),
                                    .model = m4.transpose(transform),
                                    .color = v4{
                                        .x = mat.base_color.x * @as(f32, @floatFromInt(header.color.r)) / 255.0,
                                        .y = mat.base_color.y * @as(f32, @floatFromInt(header.color.g)) / 255.0,
                                        .z = mat.base_color.z * @as(f32, @floatFromInt(header.color.b)) / 255.0,
                                        .w = mat.base_color.w * @as(f32, @floatFromInt(header.color.a)) / 255.0,
                                    },
                                    .light_pos = light_pos,
                                    .light_color = light_color,
                                    .camera_pos = camera_pos,
                                };
                                sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
                                sg.draw(0, @intCast(p.indices.size / 2), 1);
                            }
                        }

                        if (item.info.entry.children) |children| {
                            for (children) |c| {
                                const entry = pack.entries.?.items[c];
                                stack.appendAssumeCapacity(.{ .info = .{ .entry = entry, .index = c }, .parent_transform = transform });
                            }
                        }
                    }
                } else {
                    if (node.mesh_index) |mesh_index| {
                        const mesh = model.meshes[mesh_index];
                        for (mesh.primitives, 0..) |p, prim_index| {
                            const bind = bindForMesh(model, mesh_index, @intCast(prim_index));
                            const mat = model.materials[p.material_index];
                            sg.applyPipeline(offscreen_3d.pip);
                            sg.applyBindings(bind);
                            const transform = m4.mul(cmd.model, node.transform);
                            const uniforms = Uniforms3d{
                                .mvp = m4.transpose(m4.mul(vp, transform)),
                                .model = m4.transpose(transform),
                                .color = v4{
                                    .x = mat.base_color.x * @as(f32, @floatFromInt(header.color.r)) / 255.0,
                                    .y = mat.base_color.y * @as(f32, @floatFromInt(header.color.g)) / 255.0,
                                    .z = mat.base_color.z * @as(f32, @floatFromInt(header.color.b)) / 255.0,
                                    .w = mat.base_color.w * @as(f32, @floatFromInt(header.color.a)) / 255.0,
                                },
                                .light_pos = light_pos,
                                .light_color = light_color,
                                .camera_pos = camera_pos,
                            };
                            sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
                            sg.draw(0, @intCast(p.indices.size / 2), 1);
                        }
                    }
                }
            },
            .Cube => {
                const cube = b.pop(primitive.Cube);

                {
                    sg.applyPipeline(offscreen_3d.pip);
                    sg.applyBindings(cube_bind);
                    const uniforms = Uniforms3d{
                        .mvp = m4.transpose(m4.mul(vp, cube.model)),
                        .model = m4.transpose(cube.model),
                        .color = v4{
                            .x = @as(f32, @floatFromInt(header.color.r)) / 255.0,
                            .y = @as(f32, @floatFromInt(header.color.g)) / 255.0,
                            .z = @as(f32, @floatFromInt(header.color.b)) / 255.0,
                            .w = @as(f32, @floatFromInt(header.color.a)) / 255.0,
                        },
                        .light_pos = light_pos,
                        .light_color = light_color,
                        .camera_pos = camera_pos,
                    };
                    sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
                    sg.draw(0, cube_indices.len, 1);
                }

                // {
                //     sg.applyPipeline(offscreen_3d.pip);
                //     sg.applyBindings(bind_cube_model);
                //     const uniforms = Uniforms{
                //         //.mvp = m4.transpose(m4.mul(vp, m4.model(.{.x=0,.y=0,.z=10}, .{.x=10,.y=10,.z=10}))),
                //         //.mvp = m4.transpose(m4.mul(vp, cube.model)),
                //         .mvp = m4.transpose(m4.mul(vp, m4.mul(cube.model, m4.model(.{ .x = 0, .y = 0, .z = 0 }, .{ .x = 0.5, .y = 0.5, .z = 0.5 })))),
                //
                //         .color = v4{
                //             .x = @as(f32, @floatFromInt(header.color.r)) / 255.0,
                //             .y = @as(f32, @floatFromInt(header.color.g)) / 255.0,
                //             .z = @as(f32, @floatFromInt(header.color.b)) / 255.0,
                //             .w = @as(f32, @floatFromInt(header.color.a)) / 255.0,
                //         },
                //     };
                //     sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
                //     sg.draw(0, @intCast(cube_model.indices.?.len / 2), 1);
                // }
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
                    sg.applyPipeline(offscreen_3d.pip);
                    sg.applyBindings(cube_bind);
                    const uniforms = Uniforms3d{
                        .mvp = m4.transpose(m4.mul(vp, m4.mul(cube.model, m))),
                        .model = m4.transpose(cube.model),
                        .color = v4{
                            .x = @as(f32, @floatFromInt(header.color.r)) / 255.0,
                            .y = @as(f32, @floatFromInt(header.color.g)) / 255.0,
                            .z = @as(f32, @floatFromInt(header.color.b)) / 255.0,
                            .w = @as(f32, @floatFromInt(header.color.a)) / 255.0,
                        },
                        .light_pos = light_pos,
                        .light_color = light_color,
                        .camera_pos = camera_pos,
                    };
                    sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
                    sg.draw(0, cube_indices.len, 1);
                }
            },
            .Plane => {
                const p = b.pop(primitive.Plane);
                _ = p;
                //{
                //    sg.applyPipeline(offscreen_3d.pip);
                //    sg.applyBindings(cube_bind);
                //    const uniforms = Uniforms{
                //        .mvp = m4.transpose(m4.mul(vp, p.model)),
                //        .color = v4{
                //            .x = @as(f32, @floatFromInt(header.color.r)) / 255.0,
                //            .y = @as(f32, @floatFromInt(header.color.g)) / 255.0,
                //            .z = @as(f32, @floatFromInt(header.color.b)) / 255.0,
                //            .w = @as(f32, @floatFromInt(header.color.a)) / 255.0,
                //        },
                //    };

                //    sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
                //    sg.draw(0, cube_indices.len, 1);
                //}
            },
            .Vector => {
                const vector = b.pop(primitive.Vector);
                _ = vector;

                //const thickness = 0.5;
                //const model = m4.modelFromZDir(v3.add(vector.pos, v3.scale(0.5 * vector.scale, vector.dir)), .{
                //    .x = thickness,
                //    .y = thickness,
                //    .z = vector.scale,
                //}, vector.dir);
                //const uniforms = Uniforms{
                //    .mvp = m4.transpose(m4.mul(vp, model)),
                //    .color = v4{
                //        .x = @as(f32, @floatFromInt(header.color.r)) / 255.0,
                //        .y = @as(f32, @floatFromInt(header.color.g)) / 255.0,
                //        .z = @as(f32, @floatFromInt(header.color.b)) / 255.0,
                //        .w = @as(f32, @floatFromInt(header.color.a)) / 255.0,
                //    },
                //};

                //switch (header.pipeline) {
                //    .depth => sg.applyPipeline(pip_3d),
                //}
                //sg.applyBindings(cube_bind);
                //sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
                //sg.draw(0, cube_indices.len, 1);
            },
            .Circle => {
                const circle = b.pop(primitive.Circle);
                _ = circle;
                //const uniforms = Uniforms{
                //    .mvp = m4.transpose(m4.mul(vp, circle.model)),
                //    .color = v4{
                //        .x = @as(f32, @floatFromInt(header.color.r)) / 255.0,
                //        .y = @as(f32, @floatFromInt(header.color.g)) / 255.0,
                //        .z = @as(f32, @floatFromInt(header.color.b)) / 255.0,
                //        .w = @as(f32, @floatFromInt(header.color.a)) / 255.0,
                //    },
                //};
                //sg.applyPipeline(pip_triangle_strip);
                //sg.applyBindings(circle_bind);
                //sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
                //sg.draw(0, circle_vertices.len, 1);
                //sg.applyPipeline(pip_2d);
            },
            .Color => {},
            .VoxelChunk => {},
            .VoxelTransform => {},
        }
    }

    {
        postprocess.bind.fs.images[0] = offscreen_3d.color;
        sg.beginPass(postprocess.pass);
        sg.applyPipeline(postprocess.pip);
        sg.applyBindings(postprocess.bind);
        sg.draw(0, textured_rectangle_indices.len, 1);
        sg.endPass();
    }

    {
        display.bind.fs.images[0] = offscreen_2d.color;
        sg.beginPass(display.pass);
        sg.applyPipeline(display.pip);
        sg.applyBindings(display.bind);
        sg.draw(0, textured_rectangle_indices.len, 1);
        sg.endPass();
    }

    sg.commit();

    b.bytes.clear();
}
