const std = @import("std") ;
const bb = @import("bytebuffer.zig");
const packet = @import("packet.zig");
const packet_meta = @import("packet_meta.zig");
const headers = @import("headers.zig");
const net = @import("net.zig");
const statistics = @import("stat.zig");
const command = @import("command.zig");
const code_module = @import("code_module.zig");

const config = @import("config.zig");
const Vars = config.Vars;

const common = @import("common.zig");
const Memory = common.Memory;
const Player = common.Player;
const PlayerId = common.PlayerId;
const Input = common.Input;
const InputType = common.InputType;

const camera = @import("camera.zig");

const math = @import("math.zig");
const v2 = math.v2;
const v3 = math.v3;
const v3add = math.v3add;
const v3eql = math.v3eql;
const v3scale = math.v3scale;
const v3normalize = math.v3normalize;
const f32equal = math.f32equal;
const v3len2 = math.v3len2;
const v3len = math.v3len;
const m4 = math.m4;
const m4model = math.m4model;
const m4view = math.m4view;
const m4view_from_camera = math.m4view_from_camera;
const m4projection = math.m4projection;
const m4mul = math.m4mul;
const m4transpose = math.m4transpose;

const draw = @import("draw.zig");

const logging = @import("logging.zig");
var log: logging.Log = .{
    .mirror_to_stdio = true,
};

const raylib = @cImport({
    @cInclude("raylib.h");
});

const rlgl = @cImport({
    @cInclude("rlgl.h");
});

const InputMap = struct {
    const len = @typeInfo(InputType).Enum.fields.len;
    map: [len]c_int = [_]c_int{raylib.KEY_NULL} ** len,

    const Self = @This();
    fn set(self: *Self, input_type: InputType, key: c_int) void {
        self.map[@intFromEnum(input_type)] = key;
    }
};

const LocalPlayer = struct {
    input_map: InputMap,
    input: Input = undefined,
    input_buffer: bb.CircularBuffer(Input, 256) = .{},
    id: ?PlayerId = null,
    debug_auth_player: ?Player = null,
    debug_auth_player_correct: ?Player = null,
};

fn findLocalPlayerById(local_players: []LocalPlayer, id: PlayerId) ?*LocalPlayer {
    for (local_players) |*l| {
        if (l.id != null and l.id.? == id)
            return l;
    }
    return null;
}

var perf_stats : statistics.AllStatData(enum(usize) {
    ReadNetData,
    ProcessNetData,
    SendNetData,
    Update,
    Render,
    ModuleReloadCheck,
}) = .{};

var time_stats: statistics.AllStatData(enum(usize) {
    Ping,
    Frametime,
}) = .{};

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();

    net.temp_allocator = gpa;

    var module = try code_module.CodeModule(struct {
        update: *fn (vars: *const Vars, memory: *Memory, player: *Player, input: *const Input) void,
        draw: *fn (vars: *const Vars, memory: *Memory, b: *draw.Buffer) void,
    }).init(gpa, "zig-out/lib", "libgame");

    try module.open(gpa,);
    defer module.close();

    //
    // Connect to server
    //
    var host: net.Host = .{};
    const server_index = net.connect(gpa, &host, "localhost", 9053) orelse return;
    defer std.os.close(host.fd);

    //
    // Simulation state
    //

    const crand = std.crypto.random;

    const fps = 60;
    const desired_frame_time = std.time.ns_per_s / fps;

    var tick: u64 = 0;
    //const dt: f32 = 1.0/@intToFloat(f32, fps);

    //
    // Network state
    //
    var batch = net.BatchBuilder{};
    batch.clear();
    net.pushMessage(server_index, packet.ConnectionRequest{
        .client_salt = crand.int(u64)
    });
    //
    // Raylib init
    //
    raylib.InitWindow(800, 600, "game");
    raylib.SetWindowState(raylib.FLAG_WINDOW_RESIZABLE);
    defer raylib.CloseWindow();

    raylib.DisableCursor();
    defer raylib.EnableCursor();

    draw.init();
    defer draw.deinit();

    //
    // Render state
    //

    const default_shader = raylib.LoadShader("res/default.vert", "res/default.frag");
    defer raylib.UnloadShader(default_shader);

    const grass_shader = raylib.LoadShader("res/grass.vert", "res/grass.frag");
    defer raylib.UnloadShader(grass_shader);
    grass_shader.locs[raylib.SHADER_LOC_MATRIX_MODEL] = raylib.GetShaderLocationAttrib(grass_shader, "matModel");

    //const mesh = raylib.GenMeshPoly(3, 0.1);
    var material = raylib.LoadMaterialDefault();
    material.shader = grass_shader;

    //
    // Input state
    //

    var input_map0 = InputMap{};
    input_map0.set(.MoveLeft,    raylib.KEY_A);
    input_map0.set(.MoveRight,   raylib.KEY_D);
    input_map0.set(.MoveForward, raylib.KEY_W);
    input_map0.set(.MoveBack,    raylib.KEY_S);
    input_map0.set(.MoveUp,      raylib.KEY_LEFT_SHIFT);
    input_map0.set(.MoveDown,    raylib.KEY_LEFT_CONTROL);
    input_map0.set(.Jump,        raylib.KEY_SPACE);
    input_map0.set(.ResetCamera, raylib.KEY_R);

    var input_map1 = InputMap{};
    input_map1.set(.MoveLeft,  raylib.KEY_J);
    input_map1.set(.MoveRight, raylib.KEY_L);
    input_map1.set(.MoveUp,    raylib.KEY_I);
    input_map1.set(.MoveDown,  raylib.KEY_K);

    var memory: Memory = .{
        .vel_graph = .{
            .data = try gpa.alloc(f32, 2*fps),
        },
    };

    var draw_buffer: draw.Buffer = .{};

    var local_players = [_]LocalPlayer{
        .{.input_map = input_map0},
        .{.input_map = input_map1},
    };

    var timer = try std.time.Timer.start();
    var key_repeat_timer = try std.time.Timer.start();
    var last_key: c_int = raylib.KEY_NULL;
    var last_char: c_int = raylib.KEY_NULL;
    var repeat = false;
    var frame_start_time: u64 = 0;
    var accumulator: u64 = 0;

    //config.vars.bloom_downscale = raylib.LoadRenderTexture(
    //    @divTrunc(width, @intCast(c_int, config.vars.bloom_scale)),
    //    @divTrunc(height,@intCast(c_int, config.vars.bloom_scale)));
    //defer raylib.UnloadRenderTexture(config.vars.bloom_downscale);
    //raylib.SetTextureWrap(config.vars.bloom_downscale.texture, raylib.TEXTURE_WRAP_CLAMP);

    //config.vars.bloom_upscale = raylib.LoadRenderTexture(width, height);
    //defer raylib.UnloadRenderTexture(config.vars.bloom_upscale);

    //
    // Generate grass
    //
    //var prng = std.rand.DefaultPrng.init(0);
    //const rand = prng.random();
    //const grid_size = 16;
    //const tile_size = 1.0;
    //const tile_max_height = 0.2;
    //const tile_base_height = 0.1;
    //const density = 32;
    //comptime var N = density*density*grid_size*grid_size;
    //var transforms = try gpa.alloc(raylib.Matrix, N);
    //defer gpa.free(transforms);
    //{
    //    const d = tile_size / @intToFloat(f32, density);
    //    var j: usize = 0;
    //    while (j < density*grid_size) : (j += 1) {
    //        var i: usize = 0;
    //        while (i < density*grid_size) : (i += 1) {
    //            const angle = 2.0*std.math.pi*rand.float(f32);
    //            const model = math.m4mul(math.m4model(
    //                    .{
    //                        .x = -@intToFloat(f32, grid_size)*tile_size/2.0 + @intToFloat(f32, i)*d + d/2 + (d/2)*(2.0*rand.float(f32)-1.0),
    //                        .y = -@intToFloat(f32, grid_size)*tile_size/2.0 + @intToFloat(f32, j)*d + d/2 + (d/2)*(2.0*rand.float(f32)-1.0),
    //                        .z = tile_base_height + tile_max_height,
    //                    },
    //                    .{
    //                        .x = 0.1,
    //                        .y = 0.1,
    //                        .z = 1.5 + rand.float(f32),
    //                    },
    //                    ), math.m4rotz(angle));

    //            const rmodel = raylib.Matrix {
    //                .m0 = model.m00, .m4 = model.m01, .m8  = model.m02, .m12 = model.m03,
    //                .m1 = model.m10, .m5 = model.m11, .m9  = model.m12, .m13 = model.m13,
    //                .m2 = model.m20, .m6 = model.m21, .m10 = model.m22, .m14 = model.m23,
    //                .m3 = model.m30, .m7 = model.m31, .m11 = model.m32, .m15 = model.m33,
    //            };

    //            const index = j*density*grid_size + i;
    //            transforms[index] = rmodel;
    //        }
    //    }
    //}

    var connected = false;

    @memset(&memory.console_input.buffer, 0);

    var running = true;
    while (running) {
        const frame_end_time = timer.read();
        const frame_time = frame_end_time - frame_start_time;
        frame_start_time = frame_end_time;
        accumulator += frame_time;



        while (accumulator >= desired_frame_time) {
            if (accumulator >= desired_frame_time) {
                accumulator -= desired_frame_time;
            }

            const frame_stat = time_stats.get(.Frametime).startTime();

            if (raylib.WindowShouldClose())
                running = false;

            {
                const s = perf_stats.get(.ModuleReloadCheck).startTime();
                defer s.endTime();
                if (try module.reloadIfChanged(gpa)) {
                    //_ = module.function_table.fofo();
                }
            }

            const width = raylib.GetScreenWidth();
            const height = raylib.GetScreenHeight();

            //
            // Read network
            //
            var events: []net.Event = undefined;
            {
                const s = perf_stats.get(.ReadNetData).startTime();
                defer s.endTime();

                events = net.receiveMessagesClient(&host, server_index);

                //net.net_stats.get(.NetIn).samples.push(total_bytes_read);
            }

            //
            // Process network data
            //
            for (events) |event| {
                switch (event) {
                    .peer_connected => {
                    },
                    .peer_disconnected => {
                    },
                    .message_received => |e| {
                        switch (e.kind) {
                            .Command => {
                                const message: *align(1) packet.Command = @ptrCast(e.data);
                                std.log.info("Running command: {s}", .{message.data[0..message.len]});
                                command.dodododododododo(null, message.data[0..message.len]);
                            },
                            .ConnectionTimeout => {
                                const message: *align(1) packet.ConnectionTimeout = @ptrCast(e.data);
                                _ = message;
                                if (connected) {
                                    connected = false;
                                    running = false;
                                    std.log.info("connection timeout", .{});
                                }
                            },
                            .Joined => {
                                const message: *align(1) packet.Joined = @ptrCast(e.data);
                                tick = message.tick;
                            },
                            .PlayerJoinResponse => {
                                const message: *align(1) packet.PlayerJoinResponse = @ptrCast(e.data);
                                const player = try memory.players.addOne();
                                player.* = message.player;

                                // We don't handle the case where there is no
                                // room for a local player, this should never
                                // happen as we ourselves request to join,
                                // so we should have space...
                                for (&local_players) |*l| {
                                    if (l.id == null) {
                                        l.id = player.id;
                                        break;
                                    }
                                }
                            },
                            .PeerJoined => {
                                const message: *align(1) packet.PeerJoined = @ptrCast(e.data);
                                const player = try memory.players.addOne();
                                player.* = message.player;
                                log.info("peer connected", .{});
                            },
                            .PlayerUpdateAuth => {
                                const message: *align(1) packet.PlayerUpdateAuth = @ptrCast(e.data);

                                const local_player = findLocalPlayerById(&local_players, message.player.id);
                                if (local_player != null) {
                                    const player = common.findPlayerById(&memory.players.buffer, message.player.id);

                                    local_player.?.debug_auth_player = message.player;

                                    //log.info("  checking auth", .{});
                                    var auth_player = message.player;
                                    var offset = @as(i64, @intCast(message.tick)) - @as(i64, @intCast(tick)) + 2;
                                    var auth_memory = memory;
                                    while (offset <= 0) : (offset += 1) {
                                        const old_input = local_player.?.input_buffer.peekRelative(offset);
                                        //log.info("    applying input for tick {}:", .{@intCast(i64, tick)+offset});
                                        //log.info("      {any}", .{old_input.active});
                                        module.function_table.update(&config.vars, &auth_memory, &auth_player, &old_input);
                                    }

                                    if (!v3eql(auth_player.pos, player.?.pos)) {
                                        local_player.?.debug_auth_player_correct = auth_player;

                                        log.info("  auth for tick {}:\n  {}\n  {}\n  {}", .{
                                            message.tick,
                                            message.player.pos,
                                            auth_player.pos,
                                            player.?.pos,
                                        });

                                        player.?.* = auth_player;
                                    }
                                }

                            },
                            .ServerPlayerUpdate => {
                                const message: *align(1) packet.ServerPlayerUpdate = @ptrCast(e.data);
                                for (message.players[0..message.num_players], 0..) |player,i| {
                                    if (findLocalPlayerById(&local_players, player.id) != null)
                                        continue;
                                    memory.players.len = @intCast(message.num_players);
                                    memory.players.buffer[i] = player;
                                }
                            },
                            else => {
                                std.log.err("Unrecognized packet type: {}", .{e.kind});
                                break;
                            },
                        }
                    }
                }
            }

            //
            // Handle client input
            //
            {
                const s = perf_stats.get(.Update).startTime();
                defer s.endTime();

                if (raylib.IsKeyPressed(raylib.KEY_GRAVE))
                    memory.show_console = !memory.show_console;

                if (memory.show_console) {
                    if (raylib.IsKeyDown(last_key) and (!repeat and key_repeat_timer.read() >= 500*std.time.us_per_s or
                                                         repeat and key_repeat_timer.read() >= 50*std.time.us_per_s)) {
                        key_repeat_timer.reset();
                        repeat = true;
                    }
                    if (memory.console_input_index > 0 and (raylib.IsKeyPressed(raylib.KEY_LEFT) or last_key == raylib.KEY_LEFT and repeat)) {
                        memory.console_input_index -= 1;
                    }
                    if (memory.console_input_index < memory.console_input.len and (raylib.IsKeyPressed(raylib.KEY_RIGHT) or last_key == raylib.KEY_RIGHT and repeat)) {
                        memory.console_input_index += 1;
                    }
                    if (memory.console_input_index > 0 and (raylib.IsKeyPressed(raylib.KEY_BACKSPACE) or last_key == raylib.KEY_BACKSPACE and repeat)) {
                        _ = memory.console_input.orderedRemove(memory.console_input_index-1);
                        memory.console_input.buffer[memory.console_input.len] = 0;
                        memory.console_input_index -= 1;
                    }
                    if (memory.console_input.len < memory.console_input.buffer.len-1 and (last_char >= 32 and last_char <= 126 and repeat)) {
                        memory.console_input.append(@as(u8, @truncate(@as(u32, @intCast(last_char))))) catch {};
                        memory.console_input.buffer[memory.console_input.len] = 0;
                        memory.console_input_index += 1;
                    }
                    while (true) {
                        const char = raylib.GetCharPressed();
                        const key = raylib.GetKeyPressed();
                        if (key == raylib.KEY_NULL)
                            break;
                        last_key = key;
                        last_char = char;
                        repeat = false;
                        key_repeat_timer.reset();
                        if (!(last_char >= 32 and last_char <= 126) or last_char == raylib.KEY_GRAVE)
                            continue;

                        if (memory.console_input.len < memory.console_input.buffer.len-1) {
                            memory.console_input.append(@as(u8, @truncate(@as(u32, @intCast(last_char))))) catch {};
                            memory.console_input.buffer[memory.console_input.len] = 0;
                            memory.console_input_index += 1;
                        }
                    }

                    if (raylib.IsKeyPressed(raylib.KEY_ENTER)) {
                        command.dodododododododo(server_index, memory.console_input.slice());
                        std.log.info("Running command: {s}", .{memory.console_input.slice()});

                        memory.console_input_index = 0;
                        memory.console_input.len = 0;
                        memory.console_input.buffer[0] = 0;
                    }
                } else {
                    if (raylib.IsKeyPressed(raylib.KEY_ENTER)) {
                        net.pushMessage(server_index, packet.PlayerJoinRequest{});
                        net.pushReliableMessage(server_index, packet.Pong{.num = 0});
                    }
                }

                //
                // TODO(anjo): Here we need some type of mapping between input devices e.g. mouse+keyboard/controller
                // to local players.
                //
                // For the time being we just assume that mouse+keyboard maps to the first local player.
                //

                {
                    const lp = &local_players[0];
                    if (lp.id != null) {
                        lp.input.clear();
                        if (!memory.show_console) {
                            for (lp.input_map.map, 0..) |key,i|
                                if (raylib.IsKeyDown(key))
                                    lp.input.set(@enumFromInt(i));
                            // TODO(anjo): We have to dealy with mouse buttons separately here which is annoying
                            if (raylib.IsMouseButtonDown(raylib.MOUSE_BUTTON_LEFT)) {
                                lp.input.set(.Interact);
                            }
                            // TODO(anjo): We have to dealy with mouse buttons separately here which is annoying
                            lp.input.scroll = raylib.GetMouseWheelMove();
                        }
                        const delta = raylib.GetMouseDelta();
                        lp.input.cursor_delta = .{.x = delta.x/@as(f32, @floatFromInt(width)), .y = delta.y/@as(f32, @floatFromInt(height))};
                        lp.input_buffer.push(lp.input);

                        net.pushMessage(server_index, packet.PlayerUpdate{
                            .tick = tick,
                            .id = lp.id.?,
                            .input = lp.input,
                        });

                        const player = common.findPlayerById(&memory.players.buffer, lp.id.?);
                        module.function_table.update(&config.vars, &memory, player.?, &lp.input);
                    }
                }
            }

            //
            // Send network data
            //
            {
                const s = perf_stats.get(.SendNetData).startTime();
                defer s.endTime();
                net.process(&host, server_index);
            }

            //
            // Render
            //
            {
                const s = perf_stats.get(.Render).startTime();
                defer s.endTime();

                module.function_table.draw(&config.vars, &memory, &draw_buffer);
                draw.process(&draw_buffer);
                        //rlgl.rlDisableBackfaceCulling();
                        //raylib.DrawMeshInstanced(mesh, material, transforms.ptr, N);
                        //rlgl.rlEnableBackfaceCulling();

                //var x_offset: f32 = 5.0;
                //var y_offset: f32 = 0;
                //var buf: [64]u8 = undefined;
                //if (config.vars.draw_fps) {
                //    for (time_stats.stat_data) |*stat,i| {
                //        const result = stat.mean_std();
                //        const str = std.fmt.bufPrint(buf[0..buf.len-1], "{s:20} {:10} {:10}", .{
                //            @tagName(@intToEnum(time_stats.enum_type, i)), result.avg, result.std
                //        }) catch unreachable;
                //        buf[str.len] = 0;
                //        raylib.DrawTextEx(font, @ptrCast([*c]const u8, str), raylib.Vector2{.x = x_offset, .y = y_offset}, fontsize, @intToFloat(f32, spacing), raylib.RAYWHITE);
                //        y_offset += 1.5 * fontsize;
                //    }
                //}
                //if (config.vars.draw_perf) {
                //    for (perf_stats.stat_data) |*stat,i| {
                //        const result = stat.mean_std();
                //        const str = std.fmt.bufPrint(buf[0..buf.len-1], "{s:20} {:10} {:10}", .{
                //            @tagName(@intToEnum(perf_stats.enum_type, i)), result.avg, result.std
                //        }) catch unreachable;
                //        buf[str.len] = 0;
                //        raylib.DrawTextEx(font, @ptrCast([*c]const u8, str), raylib.Vector2{.x = x_offset, .y = y_offset}, fontsize, @intToFloat(f32, spacing), raylib.RAYWHITE);
                //        y_offset += 1.5 * fontsize;
                //    }
                //}
                //if (config.vars.draw_net) {
                //    for (net.net_stats.stat_data) |*stat,i| {
                //        const result = stat.mean_std();
                //        const str = std.fmt.bufPrint(buf[0..buf.len-1], "{s:20} {:10} {:10}", .{
                //            @tagName(@intToEnum(net.net_stats.enum_type, i)), result.avg, result.std
                //        }) catch unreachable;
                //        buf[str.len] = 0;
                //        raylib.DrawTextEx(font, @ptrCast([*c]const u8, str), raylib.Vector2{.x = x_offset, .y = y_offset}, fontsize, @intToFloat(f32, spacing), raylib.RAYWHITE);
                //        y_offset += 1.5 * fontsize;
                //    }
                //}
            }

            tick += 1;

            frame_stat.endTime();
            // Here we shoehorn in some sleeping to not consume all the cpu resources
            {
                const real_dt = frame_stat.samples.peek();
                const time_left = @as(i64, @intCast(desired_frame_time)) - @as(i64, @intCast(real_dt));
                if (time_left > std.time.us_per_s) {
                    // if we have at least 1us left, sleep
                    std.time.sleep(@intCast(time_left));
                }
            }
        }
    }
}
