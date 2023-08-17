const std = @import("std");
const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("rlgl.h");
    @cInclude("raygui.h");
});

const Ant = struct {
    x: f32,
    y: f32,
    vel_x: f32,
    vel_y: f32,
};

const Vec2 = struct {
    x: f32,
    y: f32,
};

pub fn main() void {
    const width = 1920;
    const height = 1080;
    raylib.InitWindow(width, height, "floating");
    defer raylib.CloseWindow();
    raylib.SetTargetFPS(60);

    var prng = std.rand.DefaultPrng.init(0);
    const random = prng.random();

    const scent_width = width/2;
    const scent_height = height/2;

    const num_ants = 100000;
    var ants_pos: [num_ants]Vec2 = undefined;
    var ants_vel: [num_ants]Vec2 = undefined;
    for (ants_pos) |*p| {
        const angle = 2*std.math.pi*random.float(f32);
        const radius = 50.0*std.math.pi*random.float(f32);
        p.x = scent_width/2 + radius * std.math.cos(angle);
        p.y = scent_height/2 + radius * std.math.sin(angle);
    }
    for (ants_vel) |*v| {
        const angle = 2*std.math.pi*random.float(f32);
        const speed = 100.0;//1.0 + 10.0*std.math.pi*random.float(f32);
        v.x = speed*std.math.cos(angle);
        v.y = speed*std.math.sin(angle);
    }

    const scent_texture = raylib.LoadRenderTexture(scent_width, scent_height);
    defer raylib.UnloadRenderTexture(scent_texture);

    const wall_texture = raylib.LoadRenderTexture(scent_width, scent_height);
    defer raylib.UnloadRenderTexture(wall_texture);

    const shader = raylib.LoadShader(0, "src/scent.frag");
    defer raylib.UnloadShader(shader);

    const comp = raylib.LoadFileText("src/ants.comp");
    const ants_program = raylib.rlLoadComputeShaderProgram(raylib.rlCompileShader(comp, raylib.RL_COMPUTE_SHADER));
    raylib.UnloadFileText(comp);
    defer raylib.rlUnloadShaderProgram(ants_program);

    const scent = raylib.LoadFileText("src/scent.comp");
    const scent_program = raylib.rlLoadComputeShaderProgram(raylib.rlCompileShader(scent, raylib.RL_COMPUTE_SHADER));
    raylib.UnloadFileText(scent);
    defer raylib.rlUnloadShaderProgram(scent_program);

    const ssbo_pos = raylib.rlLoadShaderBuffer(@sizeOf(@TypeOf(ants_pos)), &ants_pos, raylib.RL_DYNAMIC_COPY);
    const ssbo_vel = raylib.rlLoadShaderBuffer(@sizeOf(@TypeOf(ants_vel)), &ants_vel, raylib.RL_DYNAMIC_COPY);
    raylib.rlUpdateShaderBuffer(ssbo_pos, &ants_pos, @sizeOf(@TypeOf(ants_pos)), 0);
    raylib.rlUpdateShaderBuffer(ssbo_vel, &ants_vel, @sizeOf(@TypeOf(ants_vel)), 0);
    std.debug.assert(ssbo_pos != 0);
    std.debug.assert(ssbo_vel != 0);
    defer raylib.rlUnloadShaderBuffer(ssbo_pos);
    defer raylib.rlUnloadShaderBuffer(ssbo_vel);

    raylib.SetTextureWrap(scent_texture.texture, raylib.TEXTURE_WRAP_CLAMP);

    var x: f32 = 400;
    var y: f32 = 400;

    // ant sense variables
    var dt: f32 = 1.0/60.0;
    var sense_angle: f32 = std.math.pi / 4.0;
    var turn_left_interval: f32 = std.math.pi / 2.0;
    var turn_right_interval: f32 = std.math.pi / 2.0;
    var move_randomly_interval: f32 = std.math.pi / 2.0;
    var vel: f32 = 100.0;

    // scent variables
    var d0: [4]f32 = .{0.0, 0.0, 0.0, 0.0};
    var d1: [4]f32 = .{0.12, 0.12, 0.12, 0.12};
    var d2: [4]f32 = .{0.12, 0.12, 0.12, 0.12};

    // ant uniforms
    const dt_uniform = raylib.rlGetLocationUniform(ants_program, "dt");
    const sense_angle_uniform = raylib.rlGetLocationUniform(ants_program, "sense_angle");
    const turn_left_interval_uniform = raylib.rlGetLocationUniform(ants_program, "turn_left_interval");
    const turn_right_interval_uniform = raylib.rlGetLocationUniform(ants_program, "turn_right_interval");
    const move_randomly_interval_uniform = raylib.rlGetLocationUniform(ants_program, "move_randomly_interval");
    const vel_uniform = raylib.rlGetLocationUniform(ants_program, "vel_value");

    // Set default ant variables
    raylib.rlEnableShader(ants_program);
    raylib.rlSetUniform(dt_uniform, &dt, raylib.RL_SHADER_UNIFORM_FLOAT, 1);
    raylib.rlSetUniform(sense_angle_uniform, &sense_angle, raylib.RL_SHADER_UNIFORM_FLOAT, 1);
    raylib.rlSetUniform(turn_left_interval_uniform, &turn_left_interval, raylib.RL_SHADER_UNIFORM_FLOAT, 1);
    raylib.rlSetUniform(turn_right_interval_uniform, &turn_right_interval, raylib.RL_SHADER_UNIFORM_FLOAT, 1);
    raylib.rlSetUniform(move_randomly_interval_uniform, &move_randomly_interval, raylib.RL_SHADER_UNIFORM_FLOAT, 1);
    raylib.rlSetUniform(vel_uniform, &vel, raylib.RL_SHADER_UNIFORM_FLOAT, 1);
    raylib.rlDisableShader();

    // scent uniforms
    const d0_uniform = raylib.rlGetLocationUniform(scent_program, "d0");
    const d1_uniform = raylib.rlGetLocationUniform(scent_program, "d1");
    const d2_uniform = raylib.rlGetLocationUniform(scent_program, "d2");

    // Set default scent variables
    raylib.rlEnableShader(scent_program);
    raylib.rlSetUniform(d0_uniform, &d0, raylib.RL_SHADER_UNIFORM_VEC4, 1);
    raylib.rlSetUniform(d1_uniform, &d1, raylib.RL_SHADER_UNIFORM_VEC4, 1);
    raylib.rlSetUniform(d2_uniform, &d2, raylib.RL_SHADER_UNIFORM_VEC4, 1);
    raylib.rlDisableShader();

    // UI vars
    var show_ui = false;
    var run_ants = true;
    var draw_walls = true;

    var camera = raylib.Camera2D{
        .offset = .{.x = width/2, .y = height/2},
        .target = .{.x = width/2, .y = height/2},
        .rotation = 0,
        .zoom = 1,
    };

    raylib.GuiSetStyle(raylib.DEFAULT, raylib.TEXT_SIZE, 24);

    while (!raylib.WindowShouldClose()) {
        // Handle ui input
        if (raylib.IsKeyPressed(raylib.KEY_SPACE))
            show_ui = !show_ui;

        if (raylib.IsKeyPressed(raylib.KEY_P))
            run_ants = !run_ants;

        if (raylib.IsKeyPressed(raylib.KEY_O))
            draw_walls = !draw_walls;

        if (raylib.IsMouseButtonDown(raylib.MOUSE_BUTTON_LEFT)) {
            const delta = raylib.GetMouseDelta();
            camera.target.x -= delta.x/camera.zoom;
            camera.target.y -= delta.y/camera.zoom;
        }

        const scroll = raylib.GetMouseWheelMove();
        if (scroll != 0.0) {
            camera.zoom += scroll;
            if (camera.zoom < 0.1)
                camera.zoom = 0.1;
        }

        // Handle player input
        var dirx: i32 = 0;
        var diry: i32 = 0;
        if (raylib.IsKeyDown(raylib.KEY_W))
            diry += -1;
        if (raylib.IsKeyDown(raylib.KEY_A))
            dirx += -1;
        if (raylib.IsKeyDown(raylib.KEY_S))
            diry += 1;
        if (raylib.IsKeyDown(raylib.KEY_D))
            dirx += 1;

        const len = std.math.sqrt(@intToFloat(f32, dirx)*@intToFloat(f32, dirx) + @intToFloat(f32, diry)*@intToFloat(f32, diry));
        if (len > 0) {
            const dx = @intToFloat(f32, dirx)/len;
            const dy = @intToFloat(f32, diry)/len;

            const player_vel: f32 = 3.0;
            x += dx*player_vel;
            y += dy*player_vel;
        }

        if (run_ants) {
            // Run ant shader
            raylib.rlEnableShader(ants_program);
            raylib.rlBindShaderBuffer(ssbo_pos, 1);
            raylib.rlBindShaderBuffer(ssbo_vel, 2);
            raylib.rlBindImageTexture(scent_texture.texture.id, 3, scent_texture.texture.format, false);
            raylib.rlBindImageTexture(wall_texture.texture.id, 4, wall_texture.texture.format, false);
            raylib.rlComputeShaderDispatch(num_ants, 1, 1);
            raylib.rlDisableShader();

            // Run scent shader
            raylib.rlEnableShader(scent_program);
            raylib.rlBindImageTexture(scent_texture.texture.id, 3, scent_texture.texture.format, false);
            raylib.rlBindImageTexture(wall_texture.texture.id, 4, wall_texture.texture.format, false);
            raylib.rlComputeShaderDispatch(@intCast(c_uint, scent_texture.texture.width),
                                           @intCast(c_uint, scent_texture.texture.height),
                                           1);
            raylib.rlDisableShader();
        }

        // Draw walls if RMB down
        if (raylib.IsMouseButtonDown(raylib.MOUSE_BUTTON_RIGHT)) {
            var p = raylib.GetScreenToWorld2D(.{.x = @intToFloat(f32, raylib.GetMouseX()), .y = @intToFloat(f32, raylib.GetMouseY())}, camera);
            p.x /= 2.0;
            p.y /= 2.0;
            p.y = scent_height - p.y;
            raylib.BeginTextureMode(wall_texture);
            //const scale = width/scent_width;
            raylib.DrawCircleV(p, 5.0, .{.r = 128, .g = 128, .b = 0, .a = 100});
            raylib.EndTextureMode();
        }

        //raylib.rlReadShaderBuffer(ssbo_pos, &ants_pos, @sizeOf(@TypeOf(ants_pos)), 0);

        raylib.BeginDrawing();
        raylib.ClearBackground(raylib.BLACK);

        raylib.BeginMode2D(camera);

        // Draw scent
        raylib.DrawTextureEx(scent_texture.texture, .{.x = 0, .y = 0}, 0, width/scent_width, raylib.WHITE);

        // Draw wall
        if (draw_walls) {
            raylib.DrawTextureEx(wall_texture.texture, .{.x = 0, .y = 0}, 0, width/scent_width, raylib.WHITE);
        }

        // Draw player
        raylib.DrawCircle(@floatToInt(i32, x),
                          @floatToInt(i32, y),
                          4.0,
                          raylib.BLUE);

        raylib.EndMode2D();

        // gui
        if (show_ui) {
            var bounds = raylib.Rectangle {.x = 40, .y = 50, .width = 100, .height = 30};
            guiUniformSlider(&bounds, ants_program, sense_angle_uniform, "(%) sense angle", &sense_angle, 0.0, 2*std.math.pi);
            guiUniformSlider(&bounds, ants_program, turn_left_interval_uniform, "(%) turn L interval", &turn_left_interval, 0.0, 2*std.math.pi);
            guiUniformSlider(&bounds, ants_program, turn_right_interval_uniform, "(%) turn R interval", &turn_right_interval, 0.0, 2*std.math.pi);
            guiUniformSlider(&bounds, ants_program, move_randomly_interval_uniform, "(%) move rand. interval", &move_randomly_interval, 0.0, 2*std.math.pi);
            guiUniformSlider(&bounds, ants_program, vel_uniform, "(./.) vel", &vel, 0.0, 1000.0);

            // scent ui
            bounds.y += 10;
            guiUniformSlider(&bounds, scent_program, d0_uniform, "d0", &d0, 0.0, 1.0/4.0);
            bounds.y += 10;
            guiUniformSlider(&bounds, scent_program, d1_uniform, "d1", &d1, 0.0, 1.0/4.0);
            bounds.y += 10;
            guiUniformSlider(&bounds, scent_program, d2_uniform, "d2", &d2, 0.0, 1.0/4.0);
            bounds.y += 10;

            // Diagram
            const diagram_x = bounds.x + bounds.width/2;
            const diagram_y = bounds.y + 100;
            raylib.DrawCircle(@floatToInt(c_int, diagram_x), @floatToInt(c_int, diagram_y), 10.0, raylib.BLUE);


            const sense_dist: f32 = 50.0;
            raylib.DrawLineEx(.{.x = diagram_x, .y = diagram_y},
                              .{.x = diagram_x, .y = diagram_y - sense_dist},
                              2.0,
                              raylib.BLUE);
            raylib.DrawLineEx(.{.x = diagram_x, .y = diagram_y},
                              .{.x = diagram_x + sense_dist*std.math.cos(std.math.pi/2.0 + sense_angle),
                                .y = diagram_y - sense_dist*std.math.sin(std.math.pi/2.0 + sense_angle)},
                              2.0,
                              raylib.BLUE);
            raylib.DrawLineEx(.{.x = diagram_x, .y = diagram_y},
                              .{.x = diagram_x + sense_dist*std.math.cos(std.math.pi/2.0 - sense_angle),
                                .y = diagram_y - sense_dist*std.math.sin(std.math.pi/2.0 - sense_angle)},
                              2.0,
                              raylib.BLUE);

            const sense_size: f32 = 20.0;
            raylib.DrawRectangleV(.{.x = diagram_x - sense_size/2,
                                    .y = diagram_y - sense_size/2 - sense_dist},
                                  .{.x = sense_size, .y = sense_size},
                                  raylib.GREEN);
            raylib.DrawRectangleV(.{.x = diagram_x - sense_size/2 + sense_dist*std.math.cos(std.math.pi/2.0 + sense_angle),
                                    .y = diagram_y - sense_size/2 - sense_dist*std.math.sin(std.math.pi/2.0 + sense_angle)},
                                  .{.x = sense_size, .y = sense_size},
                                  raylib.GREEN);
            raylib.DrawRectangleV(.{.x = diagram_x - sense_size/2 + sense_dist*std.math.cos(std.math.pi/2.0 - sense_angle),
                                    .y = diagram_y - sense_size/2 - sense_dist*std.math.sin(std.math.pi/2.0 - sense_angle)},
                                  .{.x = sense_size, .y = sense_size},
                                  raylib.GREEN);
        }

        raylib.DrawFPS(10,10);
        raylib.EndDrawing();
    }
}

fn mapUniformType(comptime t: type) c_int {
    return switch (t) {
        f32 => raylib.RL_SHADER_UNIFORM_FLOAT,
        [4]f32 => raylib.RL_SHADER_UNIFORM_VEC4,
        else => unreachable,
    //RL_SHADER_UNIFORM_VEC2
    //RL_SHADER_UNIFORM_VEC3
    //RL_SHADER_UNIFORM_VEC4
    //RL_SHADER_UNIFORM_INT
    //RL_SHADER_UNIFORM_IVEC2
    //RL_SHADER_UNIFORM_IVEC3
    //RL_SHADER_UNIFORM_IVEC4
    };
}

fn guiUniformSliderSingle(bounds: *raylib.Rectangle, text: [*c]const u8, value: anytype, min: f32, max: f32) bool {
    const new_value = raylib.GuiSliderBar(bounds.*, "", text, value.*, min, max);
    bounds.y += bounds.height;
    const changed = new_value != value.*;
    if (changed)
        value.* = new_value;
    return changed;
}

fn guiUniformSlider(bounds: *raylib.Rectangle, program: c_uint, uniform: c_int, text: [*c]const u8, value: anytype, min: f32, max: f32) void {
    switch (@TypeOf(value.*)) {
        f32 => {
            if (guiUniformSliderSingle(bounds, text, value, min, max)) {
                raylib.rlEnableShader(program);
                raylib.rlSetUniform(uniform, value, mapUniformType(@TypeOf(value.*)), 1);
                raylib.rlDisableShader();
            }
        },
        [4]f32 => {
            if (guiUniformSliderSingle(bounds, text, &value[0], min, max) or
                guiUniformSliderSingle(bounds, text, &value[1], min, max) or
                guiUniformSliderSingle(bounds, text, &value[2], min, max) or
                guiUniformSliderSingle(bounds, text, &value[3], min, max)) {
                raylib.rlEnableShader(program);
                raylib.rlSetUniform(uniform, value, mapUniformType(@TypeOf(value.*)), 1);
                raylib.rlDisableShader();
            }
        },
        else => unreachable,
    }
}
