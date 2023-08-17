const std = @import("std");
const bb = @import("bytebuffer.zig");

const meta = @import("draw_meta.zig");

const config = @import("config.zig");

const primitive = @import("primitive.zig");
const Color = primitive.Color;

const math = @import("math.zig");
const v3 = math.v3;
const v2 = math.v2;
const v3add = math.v3add;

const raylib = @cImport({
    @cInclude("raylib.h");
});

pub const Buffer = bb.ByteBuffer(16*8192);

pub const Header = struct {
    kind: meta.PrimitiveKind,
    color: Color,
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

pub fn pushCircle(b: *Buffer, circle: primitive.Circle, color: Color) void {
    b.push(Header{
        .kind = meta.mapPrimitiveToKind(@TypeOf(circle)),
        .color = color,
    });
    b.push(circle);
}

pub fn pushCube(b: *Buffer, cube: primitive.Cube, color: Color) void {
    b.push(Header{
        .kind = meta.mapPrimitiveToKind(@TypeOf(cube)),
        .color = color,
    });
    b.push(cube);
}

fn castToRaylibVector2(v: v2) raylib.Vector2 {
    return @as(*const raylib.Vector2, @ptrCast(&v)).*;
}

fn castToRaylibVector3(v: v3) raylib.Vector3 {
    return @as(*const raylib.Vector3, @ptrCast(&v)).*;
}

fn castToRaylibColor(c: Color) raylib.Color {
    return @as(*const raylib.Color, @ptrCast(&c)).*;
}

var cc_shader: raylib.Shader = undefined;
var font: raylib.Font = undefined;
pub fn init() void {
    cc_shader = raylib.LoadShader("res/cc.vert", "res/cc.frag");
    font = raylib.LoadFont("res/mononoki.ttf");

    const width = raylib.GetScreenWidth();
    const height = raylib.GetScreenHeight();
    config.vars.rt = raylib.LoadRenderTexture(width, height);
}
pub fn deinit() void {
    raylib.UnloadShader(cc_shader);
    raylib.UnloadFont(font);
    raylib.UnloadRenderTexture(config.vars.rt);
}

pub fn process(b: *Buffer) void {

    const width = raylib.GetScreenWidth();
    const height = raylib.GetScreenHeight();

    if (raylib.IsWindowResized()) {
        raylib.UnloadRenderTexture(config.vars.rt);
        config.vars.rt = raylib.LoadRenderTexture(width, height);
    }

    raylib.BeginDrawing();
    raylib.ClearBackground(raylib.BLACK);

    while (b.hasData()) {
        const header = b.pop(Header);

        switch (header.kind) {
            .Camera3d => {
                const camera = b.pop(primitive.Camera3d);
                const raylib_camera = raylib.Camera3D {
                    .position = castToRaylibVector3(camera.pos),
                    .target = castToRaylibVector3(v3add(camera.pos, camera.dir)),
                    .up = raylib.Vector3 {.x = 0, .y = 0, .z = 1},
                    .fovy = 45.0,
                    .projection = raylib.CAMERA_PERSPECTIVE,
                };

                raylib.BeginTextureMode(config.vars.rt);
                raylib.ClearBackground(raylib.BLACK);
                raylib.BeginMode3D(raylib_camera);
            },
            .End3d => {
                raylib.EndMode3D();
                raylib.EndTextureMode();

                //if (config.vars.bloom) {
                //    raylib.BeginTextureMode(config.vars.bloom_downscale);
                //        raylib.DrawTextureEx(config.vars.rt.texture,
                //                             .{.x = 0.0, .y = 0.0},
                //                             0.0,
                //                             1.0/@as(f32, @floatFromInt(config.vars.bloom_scale),
                //                             raylib.WHITE);
                //    raylib.EndTextureMode();

                //    raylib.BeginTextureMode(config.vars.bloom_upscale);
                //        raylib.DrawTextureEx(config.vars.bloom_downscale.texture,
                //                             .{.x = 0.0, .y = 0.0},
                //                             0.0,
                //                             @as(f32, @floatFromInt(config.vars.bloom_scale),
                //                             raylib.WHITE);
                //    raylib.EndTextureMode();

                //    final_rt = config.vars.bloom_upscale;
                //}
            },
            .Camera2d => {
                const camera = b.pop(primitive.Camera2d);
                var final_rt: raylib.RenderTexture = config.vars.rt;
                raylib.BeginMode2D(raylib.Camera2D {
                    .offset = .{
                        .x = @as(f32, @floatFromInt(width))/2,
                        .y = @as(f32, @floatFromInt(height))/2
                    },
                    .target = .{
                        .x = @as(f32, @floatFromInt(width))*camera.target.x,
                        .y = @as(f32, @floatFromInt(height))*camera.target.y,
                    },
                    .rotation = 0,
                    .zoom = camera.zoom,
                });
                raylib.BeginShaderMode(cc_shader);
                    raylib.DrawTextureEx(final_rt.texture,
                        .{.x = 0.0, .y = 0.0}, 0.0, 1.0,
                        raylib.WHITE);
                raylib.EndShaderMode();
            },
            .End2d => {
                raylib.EndMode2D();
            },
            .Text => {
                const text = b.pop(primitive.Text);
                const spacing = text.size / @as(f32, @floatFromInt(font.baseSize));
                raylib.DrawTextEx(font, &text.str,
                    castToRaylibVector2(text.pos),
                    text.size,
                    spacing,
                    castToRaylibColor(header.color));

                if (text.cursor_index) |cursor_index| {
                    var offset_x: f32 = 0;

                    const scale_factor = text.size/@as(f32, @floatFromInt(font.baseSize));

                    for (text.str[0..cursor_index]) |codepoint| {
                        const glyph_index: usize = @intCast(raylib.GetGlyphIndex(font, codepoint));
                        if (font.glyphs[glyph_index].advanceX != 0) {
                            offset_x += @as(f32, @floatFromInt(font.glyphs[glyph_index].advanceX));
                        } else {
                            offset_x += (font.recs[glyph_index].width + @as(f32, @floatFromInt(font.glyphs[glyph_index].offsetX)));
                        }
                    }
                    offset_x *= scale_factor;
                    const total_spacing = if (cursor_index > 1) cursor_index - 1 else 0;
                    offset_x += @as(f32, @floatFromInt(total_spacing)) * spacing;

                    raylib.DrawRectangle(@intFromFloat(text.pos.x + offset_x), @intFromFloat(text.pos.y), @intFromFloat(text.size/10), @intFromFloat(text.size), raylib.RED);
                }
            },
            .Line => {
                const line = b.pop(primitive.Line);
                raylib.DrawLineEx(
                    castToRaylibVector2(line.start),
                    castToRaylibVector2(line.end),
                    line.thickness,
                    castToRaylibColor(header.color)
                );
            },
            .Circle => {
                const circle = b.pop(primitive.Circle);
                raylib.DrawCircle(
                    @intFromFloat(circle.pos.x),
                    @intFromFloat(circle.pos.y),
                    circle.radius,
                    castToRaylibColor(header.color)
                );
            },
            .Rectangle => {
                const r = b.pop(primitive.Rectangle);
                raylib.DrawRectangle(
                    @intFromFloat(r.pos.x),
                    @intFromFloat(r.pos.y),
                    @intFromFloat(r.size.x),
                    @intFromFloat(r.size.y),
                    castToRaylibColor(header.color)
                );
            },
            .Cube => {
                const c = b.pop(primitive.Cube);
                raylib.DrawCube(
                    .{
                        .x = c.pos.x + c.size.x/2.0,
                        .y = c.pos.y + c.size.y/2.0,
                        .z = c.pos.z + c.size.z/2.0,
                    },
                    c.size.x,
                    c.size.y,
                    c.size.z,
                    castToRaylibColor(header.color)
                );
            },
            .Color => {},
        }
    }

    raylib.EndDrawing();

    b.clear();
}
