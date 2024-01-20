const std = @import("std");

const common = @import("common");
const meta = common.draw_meta;
const draw_api = common.draw_api;
const profile = common.profile;
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
const sdtx = sokol.debugtext;

const res = @import("res");

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
    pass_action: sg.PassAction = .{},
    pass: sg.Pass = .{},
    pip: sg.Pipeline = .{},
    bind: sg.Bindings = .{},
    color: sg.Image = undefined,
    depth: sg.Image = undefined,
};

const Offscreen2d = struct {
    clear_pass_action: sg.PassAction = .{},
    load_pass_action: sg.PassAction = .{},
    pass: sg.Pass = .{},
    pip: sg.Pipeline = .{},
    bind: sg.Bindings = .{},
    color: sg.Image = undefined,
};

const OffscreenCubemap = struct {
    pass_action: sg.PassAction = .{},
    pass: sg.Pass = .{},
    pip: sg.Pipeline = .{},
    bind: sg.Bindings = .{},
};

const Display = struct {
    pass_action: sg.PassAction = .{},
    pip: sg.Pipeline = .{},
    bind: sg.Bindings = .{},
};

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
var pass_action_2d = sg.PassAction{};

const Uniforms = struct {
    mvp: m4,
    color: v4,
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
    -1.0,  1.0, 0.0, 0.0, // top left
     1.0,  1.0, 1.0, 0.0, // top right
     1.0, -1.0, 1.0, 1.0, // bottom right
    -1.0, -1.0, 0.0, 1.0, // bottom left
};
const textured_rectangle_indices = [_]u16{ 0, 1, 2, 0, 2, 3 };

const cube_vertices = [_]f32{
    0.5, -0.5, 0.5, // 0 front top left
    0.5, 0.5, 0.5, // 1 front top right
    0.5, 0.5, -0.5, // 2 front bottom right
    0.5, -0.5, -0.5, // 3 front bottom left
    -0.5, -0.5, 0.5, // 4 back top left
    -0.5, 0.5, 0.5, // 5 back top right
    -0.5, 0.5, -0.5, // 6 back bottom right
    -0.5, -0.5, -0.5, // 7 back bottom left
};
const cube_indices = [_]u16{
    0, 1, 2, 0, 2, 3, // front face
    5, 4, 7, 5, 7, 6, // back face
    1, 5, 6, 1, 6, 2, // right face
    4, 0, 3, 4, 3, 7, // left face
    4, 5, 1, 4, 1, 0, // top face
    3, 2, 6, 3, 6, 7, // bottom face
};

//var cc_shader: raylib.Shader = undefined;
//var font: raylib.Font = undefined;
pub fn init(mem: common.MemoryAllocators) void {
    _ = mem;
    sg.setup(.{
        .logger = .{ .func = slog.func },
    });

    // Setup debug text
    var sdtx_desc = sdtx.Desc{
        .context = .{
            .color_format = .RGBA8,
            .depth_format = .NONE,
        },
        .logger = .{ .func = slog.func },
    };
    sdtx_desc.fonts[0] = sdtx.fontKc853();
    sdtx.setup(sdtx_desc);

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
        shd_desc.vs.uniform_blocks[0].size = @sizeOf(Uniforms);
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
    var shd_3d: sg.Shader = undefined;
    {
        var shd_desc = sg.ShaderDesc{};
        shd_desc.vs.source =
            \\ #version 330
            \\ layout(location=0) in vec3 position;
            \\ uniform mat4 mvp;
            \\ void main() {
            \\   gl_Position = mvp * vec4(position, 1);
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
        shd_desc.vs.uniform_blocks[0].size = @sizeOf(Uniforms);
        shd_desc.vs.uniform_blocks[0].uniforms[0] = .{
            .name = "mvp",
            .type = .MAT4,
        };
        shd_desc.vs.uniform_blocks[0].uniforms[1] = .{
            .name = "color",
            .type = .FLOAT4,
        };
        shd_3d = sg.makeShader(shd_desc);
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
        shd_desc.vs.uniform_blocks[0].size = @sizeOf(Uniforms);
        shd_desc.vs.uniform_blocks[0].uniforms[0] = .{
            .name = "mvp",
            .type = .MAT4,
        };
        shd_desc.vs.uniform_blocks[0].uniforms[1] = .{
            .name = "color",
            .type = .FLOAT4,
        };
        shd_desc.fs.images[0] = .{
            .used = true,
            .image_type = .CUBE
        };
        shd_desc.fs.samplers[0] = .{
            .used = true
        };
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
        offscreen_3d.pass_action.colors[0] = .{
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

        var pass_desc = sg.PassDesc{};
        pass_desc.color_attachments[0].image = offscreen_3d.color;
        pass_desc.depth_stencil_attachment.image = offscreen_3d.depth;
        offscreen_3d.pass = sg.makePass(pass_desc);

        var pip_desc = sg.PipelineDesc{
            .index_type = .UINT16,
            .shader = shd_3d,
            .cull_mode = .BACK,
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
        offscreen_3d.pip = sg.makePipeline(pip_desc);
    }

    // Offscreen 2d
    {
        offscreen_2d.load_pass_action.colors[0] = .{
            .load_action = .LOAD,
        };

        offscreen_2d.clear_pass_action.colors[0] = .{
            .load_action = .CLEAR,
            .clear_value = .{.r=0,.g=0,.b=0,.a=0},
        };

        offscreen_2d.color = sg.makeImage(.{
            .render_target = true,
            .width = 800,
            .height = 600,
            .pixel_format = .RGBA8,
            .sample_count = 1,
        });

        var pass_desc = sg.PassDesc{};
        pass_desc.color_attachments[0].image = offscreen_2d.color;
        offscreen_2d.pass = sg.makePass(pass_desc);

        var pip_desc = sg.PipelineDesc{
            .index_type = .UINT16,
            .shader = shd_2d,
            .sample_count = 1,
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

    // Cubemap
    {
        offscreen_cubemap.pass_action.colors[0] = .{
            .load_action = .LOAD,
        };

        var pass_desc = sg.PassDesc{};
        pass_desc.color_attachments[0].image = offscreen_3d.color;
        pass_desc.depth_stencil_attachment.image = offscreen_3d.depth;
        offscreen_cubemap.pass = sg.makePass(pass_desc);

        var pip_desc = sg.PipelineDesc{
            .index_type = .UINT16,
            .shader = shd_cm,
            .cull_mode = .FRONT,
            .sample_count = 1,
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

        profile.start("cubemap");
        const cubemap = res.loadCubemap(2048, 2048, [6][]const u8{
            "./res/px.png",
            "./res/nx.png",
            "./res/py.png",
            "./res/ny.png",
            "./res/pz.png",
            "./res/nz.png",
        }) catch unreachable;
        profile.end();

        profile.sort();
        profile.dump();

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

    // Display
    {
        display.pass_action.colors[0] = .{
            .load_action = .LOAD,
        };

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

    sg.beginPass(offscreen_2d.pass, offscreen_2d.clear_pass_action);
    sg.endPass();

    while (b.bytes.hasData()) {
        const header = b.pop(draw_api.Header);

        switch (header.kind) {
            .Camera3d => {
                const camera = b.pop(primitive.Camera3d);
                vp = m4.mul(camera.proj, camera.view);

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
                    sg.beginPass(offscreen_cubemap.pass, offscreen_cubemap.pass_action);
                    sg.applyViewport(view_width * @as(i32, @intCast(col_index)), view_height * @as(i32, @intCast(row_index)), view_width, view_height, true);
                    sg.applyPipeline(offscreen_cubemap.pip);
                    sg.applyBindings(offscreen_cubemap.bind);
                    const scale = 80000.0;
                    const uniforms = Uniforms{
                        .mvp = m4.transpose(m4.mul(vp, m4.modelWithRotations(.{},.{.x=scale,.y=scale,.z=scale},.{.x=std.math.pi/2.0,.y=0.0,.z=0}))),
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

                sg.beginPass(offscreen_3d.pass, offscreen_3d.pass_action);
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

                sg.beginPass(offscreen_2d.pass, offscreen_2d.load_pass_action);

                // index = j*height + i
                const row_index = @divFloor(index_2d, views_per_row);
                const col_index = index_2d - views_per_row * row_index;
                if (need_view_stretch and row_index == views_per_col - 1) {
                    const num_last_row_views = views_per_row - num_missing_views;
                    view_width = @intFromFloat(@as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(num_last_row_views)));
                }
                sg.applyViewport(view_width * @as(i32, @intCast(col_index)), view_height * @as(i32, @intCast(row_index)), view_width, view_height, true);
                index_2d += 1;

                sg.applyPipeline(offscreen_2d.pip);
            },
            .End2d => {
                sdtx.draw();
                sg.endPass();
            },
            .Text => {
                const text = b.pop(primitive.Text);

                const fontsize = 8.0;
                const scale = @as(f32, @floatFromInt(height)) * text.size / fontsize;
                const scaled_fontsize = fontsize * scale;
                const x: f32 = @as(f32, @floatFromInt(width)) * text.pos.x / scaled_fontsize;
                const y: f32 = @as(f32, @floatFromInt(height)) * (1.0 - (text.pos.y + text.size)) / scaled_fontsize;

                {
                    //const offset = v2{ .x = r.size.x / 2, .y = r.size.y / 2 };
                    const size = .{
                        .x = scaled_fontsize*@as(f32, @floatFromInt(text.len))/@as(f32, @floatFromInt(width)),
                        .y = scaled_fontsize / @as(f32, @floatFromInt(height)),
                    };
                    const model = m4.model2d(v2.add(text.pos, .{.x=size.x/2.0,.y=size.y/2.0}), size);
                    const uniforms = Uniforms{
                        .mvp = m4.transpose(m4.mul(vp, model)),
                        .color = v4{
                            .x = @as(f32, @floatFromInt(96)) / 255.0,
                            .y = @as(f32, @floatFromInt(0)) / 255.0,
                            .z = @as(f32, @floatFromInt(0)) / 255.0,
                            .w = @as(f32, @floatFromInt(96)) / 255.0,
                        },
                    };

                    sg.applyBindings(rectangle_bind);
                    sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
                    sg.draw(0, rectangle_indices.len, 1);
                }

                sdtx.canvas(@as(f32, @floatFromInt(width)) / scale, @as(f32, @floatFromInt(height)) / scale);
                sdtx.origin(0.0, 0.0);
                sdtx.font(0);
                sdtx.pos(x, y);
                sdtx.color4b(header.color.r, header.color.b, header.color.g, header.color.a);
                sdtx.puts(&text.str);

                //
                // below is for working with unicode where we have to do more work
                // to figure out the width of text.
                //
                //const spacing = text.size / @as(f32, @floatFromInt(font.baseSize));
                //raylib.DrawTextEx(font, &text.str,
                //    castToRaylibVector2(text.pos),
                //    text.size,
                //    spacing,
                //    castToRaylibColor(header.color));

                //if (text.cursor_index) |cursor_index| {
                //    var offset_x: f32 = 0;

                //    const scale_factor = text.size/@as(f32, @floatFromInt(font.baseSize));

                //    for (text.str[0..cursor_index]) |codepoint| {
                //        const glyph_index: usize = @intCast(raylib.GetGlyphIndex(font, codepoint));
                //        if (font.glyphs[glyph_index].advanceX != 0) {
                //            offset_x += @as(f32, @floatFromInt(font.glyphs[glyph_index].advanceX));
                //        } else {
                //            offset_x += (font.recs[glyph_index].width + @as(f32, @floatFromInt(font.glyphs[glyph_index].offsetX)));
                //        }
                //    }
                //    offset_x *= scale_factor;
                //    const total_spacing = if (cursor_index > 1) cursor_index - 1 else 0;
                //    offset_x += @as(f32, @floatFromInt(total_spacing)) * spacing;

                //    raylib.DrawRectangle(@intFromFloat(text.pos.x + offset_x), @intFromFloat(text.pos.y), @intFromFloat(text.size/10), @intFromFloat(text.size), raylib.RED);
                //}
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
            .Mesh => {
                const m = b.pop(primitive.Mesh);
                _ = m;

                //var bind = sg.Bindings{};
                //bind.vertex_buffers[0] = sg.makeBuffer(.{
                //    .data = sg.asRange(m.verts),
                //});

                //const model = m4.model(.{ .x = 0, .y = 0, .z = 0 }, .{ .x = 1, .y = 1, .z = 1 });
                //var uniforms = Uniforms{
                //    .mvp = m4.transpose(m4.mul(vp, model)),
                //    .color = v4{ .x = 255.0, .y = 255.0, .z = 255.0, .w = 255.0 },
                //};

                //// TODO(anjo): We're always going to miss the last edge, we have to list
                //// the first vertex at the end to get around this...
                ////
                //// we can probably use a geometry shader
                ////  https://learnopengl.com/Advanced-OpenGL/Geometry-Shader
                ////sg.applyPipeline(pip_mesh_line);
                ////sg.applyBindings(bind);
                ////sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
                ////sg.draw(0, @intCast(m.verts.len), 1);

                //uniforms.color.x = @as(f32, @floatFromInt(header.color.r)) / 255.0;
                //uniforms.color.y = @as(f32, @floatFromInt(header.color.g)) / 255.0;
                //uniforms.color.z = @as(f32, @floatFromInt(header.color.b)) / 255.0;
                //uniforms.color.w = @as(f32, @floatFromInt(header.color.a)) / 255.0;

                //sg.applyPipeline(pip_mesh);
                //sg.applyBindings(bind);
                //sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
                //sg.draw(0, @intCast(m.verts.len), 1);

                //sg.destroyBuffer(bind.vertex_buffers[0]);
            },
            .Rectangle => {
                const r = b.pop(primitive.Rectangle);
                const offset = v2{ .x = r.size.x / 2, .y = r.size.y / 2 };
                const model = m4.model2d(v2.add(r.pos, offset), r.size);
                const uniforms = Uniforms{
                    .mvp = m4.transpose(m4.mul(vp, model)),
                    .color = v4{
                        .x = @as(f32, @floatFromInt(header.color.r)) / 255.0,
                        .y = @as(f32, @floatFromInt(header.color.g)) / 255.0,
                        .z = @as(f32, @floatFromInt(header.color.b)) / 255.0,
                        .w = @as(f32, @floatFromInt(header.color.a)) / 255.0,
                    },
                };

                sg.applyBindings(rectangle_bind);
                sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
                sg.draw(0, rectangle_indices.len, 1);
            },
            .Cube => {
                const cube = b.pop(primitive.Cube);

                {
                    sg.applyPipeline(offscreen_3d.pip);
                    sg.applyBindings(cube_bind);
                    const uniforms = Uniforms{
                        .mvp = m4.transpose(m4.mul(vp, cube.model)),
                        .color = v4{
                            .x = @as(f32, @floatFromInt(header.color.r)) / 255.0,
                            .y = @as(f32, @floatFromInt(header.color.g)) / 255.0,
                            .z = @as(f32, @floatFromInt(header.color.b)) / 255.0,
                            .w = @as(f32, @floatFromInt(header.color.a)) / 255.0,
                        },
                    };
                    sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
                    sg.draw(0, cube_indices.len, 1);
                }
            },
            .Plane => {
                const p = b.pop(primitive.Plane);
                {
                    sg.applyPipeline(offscreen_3d.pip);
                    sg.applyBindings(cube_bind);
                    const uniforms = Uniforms{
                        .mvp = m4.transpose(m4.mul(vp, p.model)),
                        .color = v4{
                            .x = @as(f32, @floatFromInt(header.color.r)) / 255.0,
                            .y = @as(f32, @floatFromInt(header.color.g)) / 255.0,
                            .z = @as(f32, @floatFromInt(header.color.b)) / 255.0,
                            .w = @as(f32, @floatFromInt(header.color.a)) / 255.0,
                        },
                    };

                    sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
                    sg.draw(0, cube_indices.len, 1);
                }
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
        }
    }

    {
        display.bind.fs.images[0] = offscreen_3d.color;
        sg.beginDefaultPass(display.pass_action, @intCast(width), @intCast(height));
        sg.applyPipeline(display.pip);
        sg.applyBindings(display.bind);
        sg.draw(0, textured_rectangle_indices.len, 1);
        sg.endPass();
    }

    {
        display.bind.fs.images[0] = offscreen_2d.color;
        sg.beginDefaultPass(display.pass_action, @intCast(width), @intCast(height));
        sg.applyPipeline(display.pip);
        sg.applyBindings(display.bind);
        sg.draw(0, textured_rectangle_indices.len, 1);
        sg.endPass();
    }

    sg.commit();

    b.bytes.clear();
}
