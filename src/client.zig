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
const InputName = common.InputName;

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

const glfw = @import("mach-glfw");
const Key = glfw.Key;
const MouseButton = glfw.MouseButton;

// TODO: rename "TriggerType"?
const TriggerType = enum {
    rising_edge,
    falling_edge,
    rising_or_falling_edge,
    state,
    toggle,
};

const MouseScrollDir = enum {
    scroll_up,
    scroll_down,
};

const MouseScroll = struct {
    dir: MouseScrollDir,
};

const InputType = union(enum) {
    unmapped: bool,
    key: Key,
    mouse_button: MouseButton,
    mouse_scroll: MouseScroll,
};

const InputState = struct {
    trigger: TriggerType = .state,
    input_type: InputType = .{.unmapped = true},
    last_action: glfw.Action = .release,
};

const InputMap = struct {
    const len = @typeInfo(InputName).Enum.fields.len;
    map: [len]InputState = [_]InputState{.{}} ** len,

    const Self = @This();

    fn map_key(self: *Self, input_name: InputName, trigger: TriggerType, key: Key) void {
        self.map[@intFromEnum(input_name)] = InputState {
            .trigger = trigger,
            .input_type = .{.key = key},
        };
    }

    fn map_mouse_button(self: *Self, input_name: InputName, input_type: TriggerType, mouse_button: MouseButton) void {
        self.map[@intFromEnum(input_name)] = InputState {
            .trigger = input_type,
            .input_type = .{.mouse_button = mouse_button},
        };
    }

    fn map_mouse_scroll(self: *Self, input_name: InputName, dir: MouseScrollDir) void {
        self.map[@intFromEnum(input_name)] = InputState {
            .trigger = .state,
            .input_type = .{.mouse_scroll = .{.dir = dir}},
        };
    }
};

const LocalPlayer = struct {
    input_map: InputMap,
    input: Input = undefined,

    // TODO: We only need to allocate this when on network
    input_buffer: bb.CircularBuffer(Input, 256) = .{},

    id: ?PlayerId = null,
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

var memory: Memory = .{};

var timer: std.time.Timer = undefined;
var key_repeat_timer: std.time.Timer = undefined;
var last_key: Key = .unknown;
var last_char: u8 = 0;
var repeat = false;

var capture_text = false;
fn charCallback(window: glfw.Window, codepoint: u21) void {
    _ = window;
    if (!capture_text)
        return;

    // codepoint -> utf8 string
    //size_t count = 0;
    //if (codepoint < 0x80)
    //    s[count++] = (char) codepoint;
    //else if (codepoint < 0x800)
    //{
    //    s[count++] = (codepoint >> 6) | 0xc0;
    //    s[count++] = (codepoint & 0x3f) | 0x80;
    //}
    //else if (codepoint < 0x10000)
    //{
    //    s[count++] = (codepoint >> 12) | 0xe0;
    //    s[count++] = ((codepoint >> 6) & 0x3f) | 0x80;
    //    s[count++] = (codepoint & 0x3f) | 0x80;
    //}
    //else if (codepoint < 0x110000)
    //{
    //    s[count++] = (codepoint >> 18) | 0xf0;
    //    s[count++] = ((codepoint >> 12) & 0x3f) | 0x80;
    //    s[count++] = ((codepoint >> 6) & 0x3f) | 0x80;
    //    s[count++] = (codepoint & 0x3f) | 0x80;
    //}

    // We don't care about multibyte codepoints, our font rendering
    // doesn't support it atm, so...
    if (codepoint >= 0x80)
        return;

    last_char = @truncate(codepoint);
    repeat = false;
    key_repeat_timer.reset();
    if (!(last_char >= 32 and last_char <= 126) or last_char == '`')
        return;

    if (memory.console_input.len < memory.console_input.buffer.len-1) {
        memory.console_input.append(@as(u8, @truncate(@as(u32, @intCast(last_char))))) catch {};
        memory.console_input.buffer[memory.console_input.len] = 0;
        memory.console_input_index += 1;
    }
}

var scroll_delta: f32 = 0.0;
fn scrollCallback(window: glfw.Window, dx: f64, dy: f64) void {
    _ = window;
    _ = dx;
    scroll_delta = @floatCast(dy);
}

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();

    net.temp_allocator = gpa;

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

    const fps = 165;
    const desired_frame_time = std.time.ns_per_s / fps;

    var tick: u64 = 0;
    //const dt: f32 = 1.0/@intToFloat(f32, fps);

    //
    // Network state
    //
    net.pushMessage(server_index, packet.ConnectionRequest{
        .client_salt = crand.int(u64)
    });

    //
    // GLFW init
    //
    if (!glfw.init(.{})) {
        std.log.err("Failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
        std.process.exit(1);
    }
    defer glfw.terminate();

    const hints = glfw.Window.Hints {
        .context_version_major = 3,
        .context_version_minor = 3,
        .opengl_forward_compat = true,
        .opengl_profile = .opengl_core_profile,
    };

    const window = glfw.Window.create(1920, 1080, "floating", null, null, hints) orelse {
        std.log.err("Failed to open window: {?s}", .{glfw.getErrorString()});
        std.process.exit(1);
    };
    defer window.destroy();
    glfw.makeContextCurrent(window);
    glfw.swapInterval(1);
    window.setInputMode(.cursor, .disabled);
    window.setCharCallback(charCallback);
    window.setScrollCallback(scrollCallback);

    // initialize renderer
    draw.init();
    defer draw.deinit();

    //
    // Modules
    //
    var module = try code_module.CodeModule(struct {
        update: *fn (vars: *const Vars, memory: *Memory, player: *Player, input: *const Input) void,
        draw: *fn (vars: *const Vars, memory: *Memory, b: *draw.Buffer, player_id: common.PlayerId, input: *const Input) void,
    }).init(gpa, "zig-out/lib", "game");

    try module.open(gpa);
    defer module.close();

    //
    // Input state
    //

    var input_map0 = InputMap{};
    input_map0.map_key(.MoveForward,   .state,       .w);
    input_map0.map_key(.MoveLeft,      .state,       .a);
    input_map0.map_key(.MoveBack,      .state,       .s);
    input_map0.map_key(.MoveRight,     .state,       .d);
    //input_map0.map_key(.Jump,          .rising_edge, .space);
    input_map0.map_mouse_scroll(.Jump, .scroll_down);
    input_map0.map_key(.Crouch,        .state,       .left_control);
    input_map0.map_key(.Sprint,        .state,       .left_shift);
    input_map0.map_key(.ResetCamera,   .rising_edge, .r);
    input_map0.map_key(.Console,       .toggle,      .grave_accent);
    input_map0.map_key(.Enter,         .rising_edge, .enter);
    input_map0.map_key(.EnableCursor,  .toggle,      .escape);
    input_map0.map_key(.Editor,        .toggle,      .x);
    input_map0.map_key(.Save,          .rising_edge, .o);
    input_map0.map_key(.Load,          .rising_edge, .p);
    input_map0.map_mouse_button(.MoveUp,      .state,       .five);
    input_map0.map_mouse_button(.MoveDown,    .state,       .four);
    input_map0.map_mouse_button(.Interact,    .state,       .left);
    input_map0.map_mouse_button(.AltInteract, .rising_edge, .right);

    var input_map1 = InputMap{};

    memory.vel_graph.data = try gpa.alloc(f32, 2*fps);

    var draw_buffer: draw.Buffer = .{};

    var local_players = [_]LocalPlayer{
        .{.input_map = input_map0},
        .{.input_map = input_map1},
    };

    // add a player so we can play locally
    // TODO: don't perform attempts to read/write net
    // if we're not connected.
    {
        const player = try memory.players.addOne();
        const id = common.newPlayerId();
        local_players[0].id = id;
        player.id = id;
        player.pos = v3 {.x = 0, .y = 0, .z = 0};
        player.vel = v3 {.x = 0, .y = 0, .z = 0};
        player.dir = v3 {.x = 1, .y = 0, .z = 0};
        player.yaw = 0;
        player.pitch = 0;
    }

    timer = try std.time.Timer.start();
    key_repeat_timer = try std.time.Timer.start();

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

    var old_mouse_pos: v2 = .{.x = 0.0, .y = 0.0};

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

            scroll_delta = 0.0;
            glfw.pollEvents();

            const frame_stat = memory.time_stats.get(.Frametime).startTime();

            if (window.shouldClose())
                running = false;

            {
                const s = perf_stats.get(.ModuleReloadCheck).startTime();
                defer s.endTime();
                if (try module.reloadIfChanged(gpa)) {
                    //_ = module.function_table.fofo();
                }
            }

            const size = window.getSize();
            const width = size.width;
            const height = size.height;
            config.vars.aspect = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));

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
                        // Clear local players and players in game when joining a server
                        for (&local_players) |*l|
                            l.id = null;
                        memory.players.len = 0;
                    },
                    .peer_disconnected => {
                    },
                    .message_received => |e| {
                        switch (e.kind) {
                            .Command => {
                                const message: *align(1) packet.Command = @ptrCast(e.data);

                                log.info("Running command: {s}", .{message.data[0..message.len]});
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

                                log.info("joined, we have id {}", .{player.id});
                            },
                            .PeerJoined => {
                                const message: *align(1) packet.PeerJoined = @ptrCast(e.data);
                                const player = try memory.players.addOne();
                                player.* = message.player;
                                log.info("Player connected {}", .{player.id});
                            },
                            .PeerDisconnected => {
                                const message: *align(1) packet.PeerDisconnected = @ptrCast(e.data);
                                const index = common.findIndexById(memory.players.slice(), message.id);
                                if (index != null)
                                    _ = memory.players.swapRemove(index.?);
                                log.info("Player {} disconnected", .{message.id});
                            },
                            .PlayerUpdateAuth => {
                                const message: *align(1) packet.PlayerUpdateAuth = @ptrCast(e.data);
                                const local_player = findLocalPlayerById(&local_players, message.player.id);
                                if (local_player != null) {
                                    const player = common.findPlayerById(&memory.players.buffer, message.player.id);

                                    //log.info("  checking auth", .{});
                                    var auth_player = message.player;
                                    var offset = @as(i64, @intCast(message.tick)) - @as(i64, @intCast(tick)) + 2;
                                    var auth_memory = memory;
                                    while (offset <= 0) : (offset += 1) {
                                        const old_input = local_player.?.input_buffer.peekRelative(offset);
                                        module.function_table.update(&config.vars, &auth_memory, &auth_player, &old_input);
                                    }

                                    if (!v3eql(auth_player.pos, player.?.pos)) {
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
                                for (message.players[0..message.num_players]) |player| {
                                    if (findLocalPlayerById(&local_players, player.id) != null)
                                        continue;
                                    const current_player = common.findPlayerById(&memory.players.buffer, player.id) orelse try memory.players.addOne();
                                    current_player.* = player;
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

                //
                // TODO(anjo): Here we need some type of mapping between input devices e.g. mouse+keyboard/controller
                // to local players.
                //
                // For the time being we just assume that mouse+keyboard maps to the first local player.
                //

                {
                    const lp = &local_players[0];
                    if (lp.id != null) {
                        //lp.input.clear();
                        for (&lp.input_map.map, 0..) |*state,i| {

                            const action: glfw.Action = switch (state.input_type) {
                                InputType.key => |key| window.getKey(key),
                                InputType.mouse_button => |mb| window.getMouseButton(mb),
                                InputType.mouse_scroll => |ms| switch (ms.dir) {
                                    .scroll_down => if (scroll_delta < 0.0) .press else .release,
                                    .scroll_up   => if (scroll_delta > 0.0) .press else .release,
                                },
                                else => continue,
                            };

                            const input_name: InputName = @enumFromInt(i);
                            switch (state.trigger) {
                                .state => {
                                    const active = action == .press;
                                    lp.input.setto(input_name, active);
                                },
                                .rising_edge => {
                                    const active = state.last_action == .release and action == .press;
                                    lp.input.setto(input_name, active);
                                },
                                .falling_edge => {
                                    const active = state.last_action == .press and action == .release;
                                    lp.input.setto(input_name, active);
                                },
                                .rising_or_falling_edge => {
                                    const active = state.last_action != action;
                                    lp.input.setto(input_name, active);
                                },
                                .toggle => {
                                    const active = state.last_action == .release and action == .press;
                                    lp.input.setto(input_name, active != lp.input.isset(input_name));
                                },
                            }
                            state.last_action = action;
                        }
                        // TODO(anjo): We have to dealy with mouse buttons separately here which is annoying
                        if (window.getMouseButton(.left) == .press) {
                            lp.input.set(.Interact);
                        }
                        // TODO(anjo): We have to dealy with mouse buttons separately here which is annoying
                        lp.input.scroll = scroll_delta;

                        var delta: v2 = .{};
                        {
                            const pos = window.getCursorPos();
                            delta.x = @as(f32, @floatCast(pos.xpos)) - old_mouse_pos.x;
                            delta.y = @as(f32, @floatCast(pos.ypos)) - old_mouse_pos.y;
                            old_mouse_pos.x = @floatCast(pos.xpos);
                            old_mouse_pos.y = @floatCast(pos.ypos);
                        }

                        lp.input.cursor_delta = .{.x = delta.x/@as(f32, @floatFromInt(width)), .y = delta.y/@as(f32, @floatFromInt(height))};

                        if (!lp.input.isset(.Console)) {
                            // push input state

                            lp.input_buffer.push(lp.input);

                            net.pushMessage(server_index, packet.PlayerUpdate{
                                .tick = tick,
                                .id = lp.id.?,
                                .input = lp.input,
                            });

                            const player = common.findPlayerById(&memory.players.buffer, lp.id.?);

                            // run predictive move
                            if (player != null)
                                module.function_table.update(&config.vars, &memory, player.?, &lp.input);
                        }
                    }
                }

                memory.show_cursor = local_players[0].input.isset(.EnableCursor);
                capture_text = local_players[0].input.isset(.Console);
                if (local_players[0].input.isset(.Console)) {
                    //if (window.getKey(last_key) == .down and (!repeat and key_repeat_timer.read() >= 500*std.time.us_per_s or
                    //        repeat and key_repeat_timer.read() >= 50*std.time.us_per_s)) {
                    //    key_repeat_timer.reset();
                    //    repeat = true;
                    //}
                    if (memory.console_input_index > 0 and (window.getKey(.left) == .press or last_key == .left and repeat)) {
                        memory.console_input_index -= 1;
                    }
                    if (memory.console_input_index < memory.console_input.len and (window.getKey(.right) == .press or last_key == .right and repeat)) {
                        memory.console_input_index += 1;
                    }
                    if (memory.console_input_index > 0 and (window.getKey(.backspace) == .press or last_key == .backspace and repeat)) {
                        _ = memory.console_input.orderedRemove(memory.console_input_index-1);
                        memory.console_input.buffer[memory.console_input.len] = 0;
                        memory.console_input_index -= 1;
                    }
                    if (memory.console_input.len < memory.console_input.buffer.len-1 and (last_char >= 32 and last_char <= 126 and repeat)) {
                        memory.console_input.append(@as(u8, @truncate(@as(u32, @intCast(last_char))))) catch {};
                        memory.console_input.buffer[memory.console_input.len] = 0;
                        memory.console_input_index += 1;
                    }

                    if (local_players[0].input.isset(.Enter)) {
                        command.dodododododododo(server_index, memory.console_input.slice());
                        std.log.info("Running command: {s}", .{memory.console_input.slice()});

                        memory.console_input_index = 0;
                        memory.console_input.len = 0;
                        memory.console_input.buffer[0] = 0;
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

                for (local_players) |lp| {
                    if (lp.id == null)
                        continue;
                    module.function_table.draw(&config.vars, &memory, &draw_buffer, lp.id.?, &lp.input);
                }
                draw.process(&draw_buffer, width, height);

                window.swapBuffers();
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
