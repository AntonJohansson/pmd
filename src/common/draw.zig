const std = @import("std");
const bb = @import("bytebuffer.zig");

const meta = @import("draw_meta.zig");

const config = @import("config.zig");

const primitive = @import("primitive.zig");
const Color = primitive.Color;

const math = @import("math.zig");
const v2 = math.v2;
const v3 = math.v3;
const v4 = math.v4;
const m4 = math.m4;

const sokol = @import("sokol");
const sg = sokol.gfx;
const slog = sokol.log;
const sdtx = sokol.debugtext;

pub const Buffer = bb.ByteBuffer(32*8192);

pub const Pipeline = enum {
    no_depth,
    depth,
};

pub const Header = struct {
    kind: meta.PrimitiveKind,
    color: Color,
    pipeline: Pipeline = .depth,
};

pub fn pushText(b: *Buffer, text: primitive.Text, color: Color) void {
    b.push(Header{
        .kind = meta.mapPrimitiveToKind(@TypeOf(text)),
        .color = color,
    });
    b.push(text);
}

pub fn begin3d(b: *Buffer, camera: primitive.Camera3d) void {
    b.push(Header{
        .kind = meta.mapPrimitiveToKind(@TypeOf(camera)),
        .color = undefined,
    });
    b.push(camera);
}

pub fn end3d(b: *Buffer) void {
    b.push(Header{
        .kind = .End3d,
        .color = undefined,
    });
}

pub fn begin2d(b: *Buffer, camera: primitive.Camera2d) void {
    b.push(Header{
        .kind = meta.mapPrimitiveToKind(@TypeOf(camera)),
        .color = undefined,
    });
    b.push(camera);
}

pub fn end2d(b: *Buffer) void {
    b.push(Header{
        .kind = .End2d,
        .color = undefined,
    });
}

pub fn pushLine(b: *Buffer, line: primitive.Line, color: Color) void {
    b.push(Header{
        .kind = meta.mapPrimitiveToKind(@TypeOf(line)),
        .color = color,
    });
    b.push(line);
}

pub fn pushRectangle(b: *Buffer, r: primitive.Rectangle, c: Color) void {
    b.push(Header{
        .kind = meta.mapPrimitiveToKind(@TypeOf(r)),
        .color = c,
    });
    b.push(r);
}

pub fn pushCube(b: *Buffer, cube: primitive.Cube, color: Color) void {
    b.push(Header{
        .kind = meta.mapPrimitiveToKind(@TypeOf(cube)),
        .color = color,
    });
    b.push(cube);
}

pub fn pushCube2(b: *Buffer, cube: primitive.Cube2, color: Color) void {
    b.push(Header{
        .kind = meta.mapPrimitiveToKind(@TypeOf(cube)),
        .color = color,
    });
    b.push(cube);
}

pub fn pushPlane(b: *Buffer, plane: primitive.Plane, color: Color) void {
    b.push(Header{
        .kind = meta.mapPrimitiveToKind(@TypeOf(plane)),
        .color = color,
    });
    b.push(plane);
}

pub fn pushVector(b: *Buffer, v: primitive.Vector, color: Color) void {
    b.push(Header{
        .kind = meta.mapPrimitiveToKind(@TypeOf(v)),
        .color = color,
    });
    b.push(v);
}

pub fn push(b: *Buffer, p: anytype, color: Color) void {
    b.push(Header{
        .kind = meta.mapPrimitiveToKind(@TypeOf(p)),
        .color = color,
    });
    b.push(p);
}

pub fn pushNoDepth(b: *Buffer, p: anytype, color: Color) void {
    b.push(Header{
        .kind = meta.mapPrimitiveToKind(@TypeOf(p)),
        .color = color,
        .pipeline = .no_depth,
    });
    b.push(p);
}

const extra = @import("primitive_extra.zig");
pub const BindingId = extra.BindingId;
pub const PrimitiveType = extra.PrimitiveType;

//var bindings: std.BoundedArray(sg.Bindings, 16) = .{};
//pub fn addVertexBinding(vertices: []const f32) BindingId {
//    const binding = bindings.addOne() catch unreachable;
//    binding.* = sg.Bindings{};
//    binding.vertex_buffers[0] = sg.makeBuffer(.{
//        .data = sg.asRange(vertices),
//    });
//    return bindings.len;
//}

//fn castToRaylibVector2(v: v2) raylib.Vector2 {
//    return @as(*const raylib.Vector2, @ptrCast(&v)).*;
//}

//fn castToRaylibVector3(v: v3) raylib.Vector3 {
//    return @as(*const raylib.Vector3, @ptrCast(&v)).*;
//}
//
//fn castToRaylibColor(c: Color) raylib.Color {
//    return @as(*const raylib.Color, @ptrCast(&c)).*;
//}

var pip_2d  = sg.Pipeline{};
var pip_3d  = sg.Pipeline{};
var pip_3d_no_depth  = sg.Pipeline{};
var pip_mesh  = sg.Pipeline{};
var pip_mesh_line  = sg.Pipeline{};
var pip_triangle_strip  = sg.Pipeline{};

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
    var vertices: [6*(len+1)]f32 = undefined;

    for (0..(len+1)) |i| {
        const angle = (2.0*std.math.pi*@as(f32, @floatFromInt(i % len)))/@as(f32, @floatFromInt(len));
        vertices[6*i+0] = outer_radius*@cos(angle);
        vertices[6*i+1] = outer_radius*@sin(angle);
        vertices[6*i+2] = 0;
        vertices[6*i+3] = inner_radius*@cos(angle);
        vertices[6*i+4] = inner_radius*@sin(angle);
        vertices[6*i+5] = 0;
    }

    break :blk vertices;
};

const rectangle_vertices = [_]f32 {
    -0.5,  0.5,
     0.5,  0.5,
     0.5, -0.5,
    -0.5, -0.5
};
const rectangle_indices = [_]u16 {
    0, 1, 2, 0, 2, 3
};

const cube_vertices = [_]f32 {
     0.5,  -0.5,  0.5, // 0 front top left
     0.5,   0.5,  0.5, // 1 front top right
     0.5,   0.5, -0.5, // 2 front bottom right
     0.5,  -0.5, -0.5, // 3 front bottom left
    -0.5,  -0.5,  0.5, // 4 back top left
    -0.5,   0.5,  0.5, // 5 back top right
    -0.5,   0.5, -0.5, // 6 back bottom right
    -0.5,  -0.5, -0.5, // 7 back bottom left
};
const cube_indices = [_]u16 {
    0,1,2, 0,2,3, // front face
    5,4,7, 5,7,6, // back face
    1,5,6, 1,6,2, // right face
    4,0,3, 4,3,7, // left face
    4,5,1, 4,1,0, // top face
    3,2,6, 3,6,7, // bottom face
};

//var cc_shader: raylib.Shader = undefined;
//var font: raylib.Font = undefined;
pub fn init() void {
    sg.setup(.{
        .logger = .{.func = slog.func},
    });

    // Setup debug text
    var sdtx_desc: sdtx.Desc = .{
        .logger = .{.func = slog.func},
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

    // Setup shaders
    // 2d shader
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
        const shd = sg.makeShader(shd_desc);
        var pip_desc = sg.PipelineDesc {
            .index_type = .UINT16,
            .shader = shd,
        };
        pip_desc.layout.attrs[0].format = .FLOAT2;
        pip_2d = sg.makePipeline(pip_desc);
        pass_action_2d.colors[0] = .{
            .load_action = .LOAD,
        };
    }
    // 3d shader
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
        const shd = sg.makeShader(shd_desc);
        var pip_desc = sg.PipelineDesc {
            .index_type = .UINT16,
            .shader = shd,
            .cull_mode = .BACK,
            .depth = .{
                .compare = .LESS_EQUAL,
                .write_enabled = true,
            },
        };
        pip_desc.layout.attrs[0].format = .FLOAT3;
        pip_desc.colors[0] = .{
            .blend = .{
                .enabled = true,
                .src_factor_rgb = .SRC_ALPHA,
                .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
            },
        };
        pip_3d = sg.makePipeline(pip_desc);
    }
    // 3d mesh shader
    {
        var shd_desc = sg.ShaderDesc{};
        shd_desc.vs.source =
                \\ #version 330
                \\ layout(location=0) in vec3 position;
                \\ uniform mat4 mvp;
                \\ out vec4 vertex_pos;
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
        const shd = sg.makeShader(shd_desc);
        var pip_desc = sg.PipelineDesc {
            .shader = shd,
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
        const shd = sg.makeShader(shd_desc);
        var pip_desc = sg.PipelineDesc {
            .shader = shd,
            .primitive_type = .LINE_STRIP,
            .depth = .{
                .compare = .LESS_EQUAL,
                .write_enabled = true,
            },
        };
        pip_desc.layout.attrs[0].format = .FLOAT3;
        pip_mesh_line = sg.makePipeline(pip_desc);
    }
    // 3d shader no depth
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
        const shd = sg.makeShader(shd_desc);
        var pip_desc = sg.PipelineDesc {
            .index_type = .UINT16,
            .shader = shd,
            .cull_mode = .BACK,
        };
        pip_desc.layout.attrs[0].format = .FLOAT3;
        pip_3d_no_depth = sg.makePipeline(pip_desc);
    }
    // triangle strip
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
        const shd = sg.makeShader(shd_desc);
        var pip_desc = sg.PipelineDesc {
            .shader = shd,
            .primitive_type = .TRIANGLE_STRIP,
            .depth = .{
                .compare = .LESS_EQUAL,
                .write_enabled = true,
            },
        };
        pip_desc.layout.attrs[0].format = .FLOAT3;
        pip_triangle_strip = sg.makePipeline(pip_desc);
    }
    //cc_shader = raylib.LoadShader("res/cc.vert", "res/cc.frag");
    //font = raylib.LoadFont("res/mononoki.ttf");

    //const width = raylib.GetScreenWidth();
    //const height = raylib.GetScreenHeight();
    //config.vars.rt = raylib.LoadRenderTexture(width, height);
}
pub fn deinit() void {
    sg.shutdown();
    //raylib.UnloadShader(cc_shader);
    //raylib.UnloadFont(font);
    //raylib.UnloadRenderTexture(config.vars.rt);
}

pub fn process(b: *Buffer, width: u32, height: u32, num_views: u32) void {
    var vp: m4 = .{};

    if (num_views == 0)
        return;

    const views_per_row: u32 = @intFromFloat(@ceil(std.math.sqrt(@as(f32, @floatFromInt(num_views)))));
    const views_per_col: u32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(num_views))/@as(f32, @floatFromInt(views_per_row))));
    const view_width:  i32 = @intFromFloat(@as(f32, @floatFromInt(width))  / @as(f32, @floatFromInt(views_per_row)));
    const view_height: i32 = @intFromFloat(@as(f32, @floatFromInt(height)) / @as(f32, @floatFromInt(views_per_col)));
    var index_3d: u32 = 0;
    var index_2d: u32 = 0;

    while (b.hasData()) {
        const header = b.pop(Header);

        switch (header.kind) {
            .Camera3d => {
                const camera = b.pop(primitive.Camera3d);
                vp = m4.mul(camera.proj, camera.view);

                var pass_action_3d = sg.PassAction{};
                if (index_3d == 0) {
                    pass_action_3d.colors[0] = .{
                        .load_action = .CLEAR,
                        .clear_value = .{.r = 0, .g = 0, .b = 0, .a = 1},
                    };
                } else {
                    pass_action_3d.colors[0] = .{
                        .load_action = .LOAD,
                    };
                }
                sg.beginDefaultPass(pass_action_3d, @intCast(width), @intCast(height));

                // index = j*height + i
                const j = @divFloor(index_3d, views_per_row);
                const i = index_3d - views_per_row*j;
                std.log.info("{}: {}x{}, {}, {}", .{index_3d, views_per_row, views_per_col, i,j});
                sg.applyViewport(view_width*@as(i32, @intCast(i)),
                                 view_height*@as(i32, @intCast(j)),
                                 view_width, view_height, true);
                index_3d += 1;
            },
            .End3d => {
                //raylib.EndMode3D();
                //raylib.EndTextureMode();
                sg.endPass();
            },
            .Camera2d => {
                const camera = b.pop(primitive.Camera2d);

                const view_to_world = m4.model2d(camera.target, .{.x = 0.5/camera.zoom, .y = 0.5/camera.zoom});
                const world_to_view = m4.inverse(view_to_world);

                vp = world_to_view;

                //var final_rt: raylib.RenderTexture = config.vars.rt;
                //raylib.BeginMode2D(raylib.Camera2D {
                //    .offset = .{
                //        .x = @as(f32, @floatFromInt(width))/2,
                //        .y = @as(f32, @floatFromInt(height))/2
                //    },
                //    .target = .{
                //        .x = @as(f32, @floatFromInt(width))*camera.target.x,
                //        .y = @as(f32, @floatFromInt(height))*camera.target.y,
                //    },
                //    .rotation = 0,
                //    .zoom = camera.zoom,
                //});
                //raylib.BeginShaderMode(cc_shader);
                //    raylib.DrawTextureEx(final_rt.texture,
                //        .{.x = 0.0, .y = 0.0}, 0.0, 1.0,
                //        raylib.WHITE);
                //raylib.EndShaderMode();
                sg.beginDefaultPass(pass_action_2d, @intCast(width), @intCast(height));
                sg.applyPipeline(pip_2d);

                // index = j*height + i
                const j = @divFloor(index_2d, views_per_row);
                const i = index_2d - views_per_row*j;
                std.log.info("{}: {}x{}, {}, {}", .{index_2d, views_per_row, views_per_col, i,j});
                sg.applyViewport(view_width*@as(i32, @intCast(i)),
                                 view_height*@as(i32, @intCast(j)),
                                 view_width, view_height, true);
                index_2d += 1;
            },
            .End2d => {
                sdtx.draw();
                sg.endPass();
            },
            .Text => {
                const text = b.pop(primitive.Text);

                const fontsize = 8.0;
                const scale = @as(f32, @floatFromInt(height))*text.size/fontsize;
                const scaled_fontsize = fontsize * scale;
                sdtx.canvas(@as(f32, @floatFromInt(width))/scale, @as(f32, @floatFromInt(height))/scale);
                sdtx.origin(0.0, 0.0);
                sdtx.font(0);
                sdtx.pos(@as(f32, @floatFromInt(width))*text.pos.x/scaled_fontsize, @as(f32, @floatFromInt(height))*(1.0-(text.pos.y + text.size))/scaled_fontsize);
                sdtx.color3b(header.color.r, header.color.b, header.color.g);
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

                var bind = sg.Bindings{};
                bind.vertex_buffers[0] = sg.makeBuffer(.{
                    .data = sg.asRange(m.verts),
                });

                const model = m4.model(.{.x=0,.y=0,.z=0},.{.x=1,.y=1,.z=1});
                var uniforms = Uniforms {
                    .mvp = m4.transpose(m4.mul(vp, model)),
                    .color = v4 {
                        .x = 255.0,
                        .y = 255.0,
                        .z = 255.0,
                        .w = 255.0
                    },
                };

                // TODO(anjo): We're always going to miss the last edge, we have to list
                // the first vertex at the end to get around this...
                //
                // we can probably use a geometry shader
                //  https://learnopengl.com/Advanced-OpenGL/Geometry-Shader
                //sg.applyPipeline(pip_mesh_line);
                //sg.applyBindings(bind);
                //sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
                //sg.draw(0, @intCast(m.verts.len), 1);

                uniforms.color.x = @as(f32, @floatFromInt(header.color.r))/255.0;
                uniforms.color.y = @as(f32, @floatFromInt(header.color.g))/255.0;
                uniforms.color.z = @as(f32, @floatFromInt(header.color.b))/255.0;
                uniforms.color.w = @as(f32, @floatFromInt(header.color.a))/255.0;

                sg.applyPipeline(pip_mesh);
                sg.applyBindings(bind);
                sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
                sg.draw(0, @intCast(m.verts.len), 1);

                sg.destroyBuffer(bind.vertex_buffers[0]);
            },
            .Rectangle => {
                const r = b.pop(primitive.Rectangle);
                const offset = v2 {.x = r.size.x/2, .y = r.size.y/2};
                const model = m4.model2d(v2.add(r.pos, offset), r.size);
                const uniforms = Uniforms {
                    .mvp = m4.transpose(m4.mul(vp, model)),
                    .color = v4 {
                        .x = @as(f32, @floatFromInt(header.color.r))/255.0,
                        .y = @as(f32, @floatFromInt(header.color.g))/255.0,
                        .z = @as(f32, @floatFromInt(header.color.b))/255.0,
                        .w = @as(f32, @floatFromInt(header.color.a))/255.0,
                    },
                };

                sg.applyBindings(rectangle_bind);
                sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
                sg.draw(0, rectangle_indices.len, 1);
            },
            .Cube => {
                const c = b.pop(primitive.Cube);

                const model = m4.model(
                    .{
                        .x = c.pos.x+c.size.x/2,
                        .y = c.pos.y+c.size.y/2,
                        .z = c.pos.z+c.size.z/2,
                    },
                    .{
                        .x = c.size.x,
                        .y = c.size.y,
                        .z = c.size.z,
                    });
                const uniforms = Uniforms {
                    .mvp = m4.transpose(m4.mul(vp, model)),
                    .color = v4 {
                        .x = @as(f32, @floatFromInt(header.color.r))/255.0,
                        .y = @as(f32, @floatFromInt(header.color.g))/255.0,
                        .z = @as(f32, @floatFromInt(header.color.b))/255.0,
                        .w = @as(f32, @floatFromInt(header.color.a))/255.0,
                    },
                };

                switch (header.pipeline) {
                    .depth    => sg.applyPipeline(pip_3d),
                    .no_depth => sg.applyPipeline(pip_3d_no_depth),
                }
                sg.applyBindings(cube_bind);
                sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
                sg.draw(0, cube_indices.len, 1);
            },
            .Cube2 => {
                const c = b.pop(primitive.Cube2);
                const uniforms = Uniforms {
                    .mvp = m4.transpose(m4.mul(vp, c.model)),
                    .color = v4 {
                        .x = @as(f32, @floatFromInt(header.color.r))/255.0,
                        .y = @as(f32, @floatFromInt(header.color.g))/255.0,
                        .z = @as(f32, @floatFromInt(header.color.b))/255.0,
                        .w = @as(f32, @floatFromInt(header.color.a))/255.0,
                    },
                };

                switch (header.pipeline) {
                    .depth    => sg.applyPipeline(pip_3d),
                    .no_depth => sg.applyPipeline(pip_3d_no_depth),
                }
                sg.applyBindings(cube_bind);
                sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
                sg.draw(0, cube_indices.len, 1);
            },
            .Plane => {
                const p = b.pop(primitive.Plane);
                const uniforms = Uniforms {
                    .mvp = m4.transpose(m4.mul(vp, p.model)),
                    .color = v4 {
                        .x = @as(f32, @floatFromInt(header.color.r))/255.0,
                        .y = @as(f32, @floatFromInt(header.color.g))/255.0,
                        .z = @as(f32, @floatFromInt(header.color.b))/255.0,
                        .w = @as(f32, @floatFromInt(header.color.a))/255.0,
                    },
                };

                switch (header.pipeline) {
                    .depth    => sg.applyPipeline(pip_3d),
                    .no_depth => sg.applyPipeline(pip_3d_no_depth),
                }
                sg.applyBindings(cube_bind);
                sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
                sg.draw(0, cube_indices.len, 1);
            },
            .Vector => {
                const vector = b.pop(primitive.Vector);

                const thickness = 0.5;
                const model = m4.modelFromZDir(
                    v3.add(vector.pos, v3.scale(0.5*vector.scale, vector.dir)),
                    .{
                        .x = thickness,
                        .y = thickness,
                        .z = vector.scale,
                    },
                    vector.dir);
                const uniforms = Uniforms {
                    .mvp = m4.transpose(m4.mul(vp, model)),
                    .color = v4 {
                        .x = @as(f32, @floatFromInt(header.color.r))/255.0,
                        .y = @as(f32, @floatFromInt(header.color.g))/255.0,
                        .z = @as(f32, @floatFromInt(header.color.b))/255.0,
                        .w = @as(f32, @floatFromInt(header.color.a))/255.0,
                    },
                };

                switch (header.pipeline) {
                    .depth    => sg.applyPipeline(pip_3d),
                    .no_depth => sg.applyPipeline(pip_3d_no_depth),
                }
                sg.applyBindings(cube_bind);
                sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
                sg.draw(0, cube_indices.len, 1);
            },
            .Circle => {
                const circle = b.pop(primitive.Circle);
                const uniforms = Uniforms {
                    .mvp = m4.transpose(m4.mul(vp, circle.model)),
                    .color = v4 {
                        .x = @as(f32, @floatFromInt(header.color.r))/255.0,
                        .y = @as(f32, @floatFromInt(header.color.g))/255.0,
                        .z = @as(f32, @floatFromInt(header.color.b))/255.0,
                        .w = @as(f32, @floatFromInt(header.color.a))/255.0,
                    },
                };
                sg.applyPipeline(pip_triangle_strip);
                sg.applyBindings(circle_bind);
                sg.applyUniforms(.VS, 0, sg.asRange(&uniforms));
                sg.draw(0, circle_vertices.len, 1);
                sg.applyPipeline(pip_2d);
            },
            .Color => {},
        }
    }

    sg.commit();

    //for (bindings_to_remove.slice()) |bbb| {
    //    sg.destroyBuffer(bbb.vertex_buffers[0]);
    //}

    b.clear();
}
