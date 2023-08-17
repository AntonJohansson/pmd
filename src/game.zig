const std = @import("std");
const cos = std.math.cos;
const sin = std.math.sin;
const max = std.math.max;
const min = std.math.min;

const common = @import("common.zig");
const Memory = common.Memory;
const Player = common.Player;
const Input = common.Input;

const Graph = common.Graph;
const graphAppend = common.graphAppend;

const config = @import("config.zig");
const Vars = config.Vars;

const primitive = @import("primitive.zig");
const Color = primitive.Color;

const math = @import("math.zig");
const v3 = math.v3;
const v2 = math.v2;
const m4 = math.m4;
const m4view = math.m4view;
const m4projection = math.m4projection;
const v2add = math.v2add;
const v2sub = math.v2sub;
const v2normalize = math.v2normalize;
const v2scale = math.v2scale;
const v3scale = math.v3scale;
const v3add = math.v3add;
const v3cross = math.v3cross;
const v3neg = math.v3neg;
const v3normalize = math.v3normalize;
const v3len = math.v3len;
const v3len2 = math.v3len2;
const v3dot = math.v3dot;

const draw_api = @import("draw.zig");
const pushCircle = draw_api.pushCircle;
const pushCube = draw_api.pushCube;
const pushRectangle = draw_api.pushRectangle;
const pushLine = draw_api.pushLine;
const pushText = draw_api.pushText;
const begin3d = draw_api.begin3d;
const end3d = draw_api.end3d;
const begin2d = draw_api.begin2d;
const end2d = draw_api.end2d;

export fn update(vars: *const Vars, memory: *Memory, player: *Player, input: *const Input) void {
    const dt = 1.0/60.0;

    if (input.cursor_delta.x != 0 or input.cursor_delta.y != 0) {
        player.yaw   -= input.cursor_delta.x;
        player.pitch += input.cursor_delta.y;
        player.pitch = std.math.clamp(player.pitch, -std.math.pi/2.0+0.01, std.math.pi/2.0-0.1);
        player.dir = v3 {
            .x = cos(player.yaw)*cos(player.pitch),
            .y = sin(player.yaw)*cos(player.pitch),
            .z = -sin(player.pitch),
        };
    }

    const onground = player.pos.z == 0;

    if (onground) {
        // Apply friction
        const speed = v3len(player.vel);
        if (speed > 0) {
            const control = if (speed < vars.stopspeed) vars.stopspeed else speed;
            var newspeed = speed - dt*control*vars.friction;
            if (newspeed < 0)
                newspeed = 0;
            newspeed /= speed;
            player.vel = v3scale(newspeed, player.vel);
        }
    }

    var dx: f32 = -1.0*@as(f32, @floatFromInt(@intFromBool(input.isset(.MoveForward)))) + 1.0*@as(f32, @floatFromInt(@intFromBool(input.isset(.MoveBack))));
    var dy: f32 = -1.0*@as(f32, @floatFromInt(@intFromBool(input.isset(.MoveLeft))))    + 1.0*@as(f32, @floatFromInt(@intFromBool(input.isset(.MoveRight))));
    var dz: f32 =  0.0;
    if (player.editor) {
        dz = 1.0*@as(f32, @floatFromInt(@intFromBool(input.isset(.MoveUp)))) - 1.0*@as(f32, @floatFromInt(@intFromBool(input.isset(.MoveDown))));
    }

    const len2 = dx*dx + dy*dy + dz*dz;

    if (len2 > 0.0) {
        const len = std.math.sqrt(len2);
        dx /= len;
        dy /= len;
        dz /= len;

        const up      = v3 {.x = 0, .y = 0, .z = 1};
        const forward = v3 {.x = cos(player.yaw), .y = sin(player.yaw), .z = 0};
        const right   = v3cross(forward, up);

        var wishvel = v3add(v3add(v3scale(-vars.forwardspeed*dx, forward), v3scale(vars.sidespeed*dy, right)), v3scale(vars.upspeed*dz, up));
        const wishdir = v3normalize(wishvel);
        var wishspeed = v3len(wishvel);
        if (wishspeed > vars.maxspeed) {
            wishvel = v3scale(vars.maxspeed/wishspeed, wishvel);
            wishspeed = vars.maxspeed;
        }

        const speed_in_wishdir = v3dot(player.vel, wishdir);
        const addspeed = wishspeed - speed_in_wishdir;

	if (addspeed > 0) {
            var accelspeed = vars.acceleration*dt*wishspeed;
            if (accelspeed > addspeed)
                accelspeed = addspeed;

            player.vel = v3add(player.vel, v3scale(accelspeed, wishdir));
        }
    }

    if (input.isset(.Jump) and player.pos.z == 0) {
        //player.acc = v3add(player.acc, v3 {.x = 0, .y = 0, .z = vars.jump});
    }

    player.pos = v3add(player.pos, v3scale(dt, player.vel));

    // collision z dir
    if (player.pos.z < 0) {
        player.pos.z = 0;
        player.vel.z = 0;
    }

    // copy player pos to camera pos
    if (!vars.mode2d) {
        memory.pos = v3add(player.pos, v3 {.x = 0, .y = 0, .z = 22});
        memory.dir = player.dir;
    } else {
        if (input.isset(.Interact)) {
            memory.target.x -= input.cursor_delta.x / memory.zoom;
            memory.target.y -= input.cursor_delta.y / memory.zoom;
        }
        if (input.scroll != 0) {
            memory.zoom += input.scroll;
            if (memory.zoom < 0.1)
                memory.zoom = 0.1;
        }
    }

    if (input.isset(.ResetCamera)) {
        memory.target.x = 0.5;
        memory.target.y = 0.5;
        memory.zoom = 1.0;
    }
    //
    // Rz(a)Ry(b)Rx(c)
    //
    //      cos(a)cos(b)    cos(a)sin(b)sin(c) - sin(a)cos(c)     cos(a)sin(b)cos(c) + sin(a)sin(c)
    //   =  sin(a)cos(b)    sin(a)sin(b)sin(c) + cos(a)cos(c)     sin(a)sin(b)cos(c) - cos(a)sin(c)
    //         -sin(b)                 cos(b)sin(c)                        cos(b)cos(c)
    //
    // Rz(a)Ry(b) = Rz(a)Ry(b)Rz(0)
    //
    //      cos(a)cos(b)     -sin(a)     cos(a)sin(b)
    //   =  sin(a)cos(b)      cos(a)     sin(a)sin(b)
    //         -sin(b)          0           cos(b)
    //
    // Rz(a)Ry(b)[x y z]'
    //
    //      cos(a)cos(b)x - sin(a)y + cos(a)sin(b)z
    //   =  sin(a)cos(b)x + cos(a)y + sin(a)sin(b)z
    //                -sin(b)x + cos(b)z
    //
}

fn f(h: f32, s: f32, v: f32, n: f32) f32 {
    const k = @mod(n + h/60.0, 6.0);
    return v - v*s*@max(0.0, @min(@min(k, 4 - k), 1));
}

fn hsvToRgb(h: f32, s: f32, v: f32) Color {
    return .{
        .r = @intFromFloat(255.0*f(h,s,v, 5.0)),
        .g = @intFromFloat(255.0*f(h,s,v, 3.0)),
        .b = @intFromFloat(255.0*f(h,s,v, 1.0)),
        .a = 255,
    };
}

export fn draw(vars: *const Vars, memory: *Memory, b: *draw_api.Buffer) void {

    begin3d(b, primitive.Camera3d {
        .pos = memory.pos,
        .dir = memory.dir,
    });

    // Draw map(?)
    const grid_size = 32;
    const tile_size = 32.0;
    const tile_max_height = 4.0;
    const tile_base_height = 2.0;
    var prng = std.rand.DefaultPrng.init(0);
    const rand = prng.random();
    {
        var i: usize = 0;
        while (i < grid_size) : (i += 1) {
            var j: usize = 0;
            while (j < grid_size) : (j += 1) {
                pushCube(b, .{
                    .pos = .{
                        .x = tile_size*@as(f32, @floatFromInt(i)) - tile_size*@as(f32, @floatFromInt(grid_size))/2,
                        .y = tile_size*@as(f32, @floatFromInt(j)) - tile_size*@as(f32, @floatFromInt(grid_size))/2,
                        .z = 0.0,
                    },
                    .size = .{
                        .x = tile_size,
                        .y = tile_size,
                        .z = tile_base_height + tile_max_height*rand.float(f32),
                    },
                },
                hsvToRgb(
                    80.0 + 10.0*(2.0*rand.float(f32)-1.0),
                    0.8 +  0.2*(2.0*rand.float(f32)-1.0),
                    0.5 +  0.2*(2.0*rand.float(f32)-1.0)
                ),
                );
            }
        }
    }

    // Draw players
    const player_cube_size = 0.5;
    for (memory.players.slice()) |player| {
        pushCube(b, .{
            .pos = .{
                .x = player.pos.x - player_cube_size/2.0,
                .y = player.pos.y - player_cube_size/2.0,
                .z = player.pos.z + tile_base_height + tile_max_height,
            },
            .size = .{
                .x = player_cube_size,
                .y = player_cube_size,
                .z = 1.0,
            },
        },
        hsvToRgb(180, 0.75, 0.75),
        );
    }

    end3d(b);

    begin2d(b, primitive.Camera2d {
        .target = memory.target,
        .zoom = memory.zoom,
    });
        if (vars.speedometer) {
            graphAppend(&memory.vel_graph, v3len(memory.players.buffer[0].vel));
            drawGraph(b, &memory.vel_graph,
                .{.x = 10, .y = 80 + 200},
                .{.x = 200, .y = 100},
                .{.x = 10, .y = 10},
                15, 0.75, 0.5);
        }

        const width = 800.0;
        const height = 600.0;
        const textheight = height/30;
        const fontsize = textheight;

        if (memory.show_console) {
        //    if (!mouse_enabled) {
        //        mouse_enabled = true;
        //        raylib.EnableCursor();
        //    }
            pushRectangle(b, .{
                .pos = .{
                    .x = 0,
                    .y = 0,
                },
                .size = .{
                    .x = width,
                    .y = height/3
                }
            }, hsvToRgb(200, 0.5, 0.25));
            pushRectangle(b, .{
                .pos = .{
                    .x = 0,
                    .y = height/3-textheight,
                },
                .size = .{
                    .x = width,
                    .y = textheight,
                }
            }, hsvToRgb(200, 0.5, 0.1));

            {
                var text = primitive.Text{
                    .pos = .{
                        .x = 0,
                        .y = height/3-textheight,
                    },
                    .str = undefined,
                    .len = memory.console_input.len,
                    .size = fontsize,
                    .cursor_index = memory.console_input_index,
                };
                @memset(&text.str, 0);
                std.mem.copy(u8, &text.str, memory.console_input.slice());
                pushText(b, text, hsvToRgb(200, 0.75, 0.75));
            }
        }
    end2d(b);
}

fn drawCenteredLine(b: *draw_api.Buffer, start: v2, end: v2, thickness: f32, color: Color) void {
    const dir = v2normalize(v2sub(end, start));
    const ortho = v2 { .x = -dir.y, .y = dir.x };

    const new_start = v2add(start, v2scale(thickness/2.0, ortho));
    const new_end = v2add(end, v2scale(thickness/2.0, ortho));

    pushLine(b, .{
        .start = new_start,
        .end = new_end,
        .thickness = thickness,
    }, color);
}

fn drawGraph(b: *draw_api.Buffer, g: *Graph, pos: v2, size: v2, margin: v2, h: f32, s: f32, v: f32) void {
    var bg = hsvToRgb(50.0, 0.75, 0.05);
    bg.a = @intFromFloat(0.75 * 255.0);
    pushRectangle(b, .{
        .pos = pos,
        .size = size,
    }, bg);

    // Find max/min
    for (g.data) |y| {
        if (y < g.min) {
            g.min = y;
        } else if (y > g.max) {
            g.max = y;
        }
    }

    const scale_x = (size.x - 2*margin.x) / @as(f32, @floatFromInt(g.data.len-1));
    const scale_y = (size.y - 2*margin.y) / (g.max - g.min);

    var last_x: f32 = 0;
    var last_y: f32 = 0;
    for (g.data, 0..) |data_y,i| {
        const x = pos.x + margin.x + scale_x * @as(f32, @floatFromInt(i));
        const y = pos.y - margin.y + size.y - (scale_y*data_y - scale_y*g.min);

        const last_index = (g.top + g.data.len - 1) % g.data.len;
        const dist = (g.data.len + last_index - i) % g.data.len;

        const color = hsvToRgb(h,s,v - 0.4*@as(f32, @floatFromInt(dist))/@as(f32, @floatFromInt(g.data.len)));
        if (i > 0) {
            drawCenteredLine(b,
                v2 {.x = last_x, .y = last_y},
                v2 {.x = x, .y = y},
                2.0, color);
        }

        pushCircle(b, .{
            .pos = .{.x = x, .y = y},
            .radius = 4.0,
        }, color);

        last_x = x;
        last_y = y;
    }

    pushLine(b, .{
        .start =.{
            .x = pos.x + margin.x + scale_x * @as(f32, @floatFromInt(g.top)),
            .y = pos.y,
        },
        .end = .{
             .x = pos.x + margin.y + scale_x * @as(f32, @floatFromInt(g.top)),
             .y = pos.y + size.y,
        },
        .thickness = 1.0,
    }, Color{.r = 128, .g = 128, .b = 128, .a = 255});
}
