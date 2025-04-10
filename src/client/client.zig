const std = @import("std");

const build_options = @import("build_options");

const common = @import("common");
const bb = common.bb;
const stat = common.stat;
const code_module = common.code_module;
const command = common.command;
const camera = common.camera;
const config = common.config;
const Vars = config.Vars;
const Memory = common.Memory;
const Player = common.Player;
const EntityId = common.EntityId;
const Input = common.Input;
const InputName = common.InputName;
const BoundedArray = common.BoundedArray;
const goosepack = common.goosepack;
const draw_api = common.draw_api;
const draw = @import("draw.zig");
const disk = if (build_options.options.debug) @import("pack-disk") else struct {};

const cl = @import("command_meta.zig");

const math = common.math;
const v2 = math.v2;
const v3 = math.v3;
const f32equal = math.f32equal;
const m4 = math.m4;

const net = @import("net");
const res = common.res;

const headers = net.headers;
const packet = net.packet;
const packet_meta = net.packet_meta;

const sokol = @import("sokol");
const sa = sokol.audio;
const slog = sokol.log;

const c = @cImport({
    @cInclude("glfw3.h");
});

var log: common.log.GroupLog(.general) = undefined;

//
// State
//

pub fn update_game_state(lp: *LocalPlayer, input: *const Input) void {
    switch (active_state(lp)) {
        .gameplay => {
            if (input.isset(.to_editor)) {
                push_state(lp, .editor);
            } else if (input.isset(.to_pause)) {
                push_state(lp, .pause);
            } else if (input.isset(.to_console)) {
                push_state(lp, .console);
            }
        },
        .editor => {
            if (input.isset(.to_editor)) {
                _ = pop_state(lp);
            } else if (input.isset(.to_pause)) {
                push_state(lp, .pause);
            } else if (input.isset(.to_console)) {
                push_state(lp, .console);
            }
        },
        .pause => {
            if (input.isset(.to_pause)) {
                _ = pop_state(lp);
            } else if (input.isset(.to_console)) {
                push_state(lp, .console);
            }
        },
        .console => {
            if (input.isset(.to_console)) {
                _ = pop_state(lp);
            }
        },
    }
}

pub fn active_state(lp: *LocalPlayer) common.State {
    return lp.state_stack[lp.active_state];
}

pub fn push_state(lp: *LocalPlayer, s: common.State) void {
    std.debug.assert(lp.active_state + 1 < lp.state_stack.len);
    lp.active_state += 1;
    lp.state_stack[lp.active_state] = s;
}

pub fn pop_state(lp: *LocalPlayer) common.State {
    std.debug.assert(lp.active_state > 0);
    lp.active_state -= 1;
    return lp.state_stack[lp.active_state + 1];
}

//
// Input
//

//
// Here we set up structs to represent mapping inputs such as "key 'A' pressed"
// to some sort of input-independent action such as "move left".
//
// Ideally this code should require as little logic as possible and just be an
// array access or similar.
//
// TODO:
//  - Some way to remap keys.  This is a bit complicated as the code responsible
//    for interacting with the user game.zig doesn't have access to raw inputs.
//
//    Some way of specifying from game.zig that the "move left" input should be
//    remapped to the next valid input, could work.
//
//  - Support mapping multiple keys to the same action, e.g. both "space" and
//    "mouse scroll" could map to "jump".
//

const str_input_map_keyboard = "input_keyboard";
const str_input_map_gamepad = "input_gamepad";

const InputMapsType = enum {
    mouse_keyboard,
    gamepad,
};

fn setup_mouse_keyboard_input(im: *res.InputMaps) void {
    const gameplay = im.get(.gameplay);
    gameplay.map_key(.MoveForward, .state, .w);
    gameplay.map_key(.MoveLeft, .state, .a);
    gameplay.map_key(.MoveBack, .state, .s);
    gameplay.map_key(.MoveRight, .state, .d);
    gameplay.map_mouse_scroll(.Jump, .scroll_down);
    gameplay.map_key(.Crouch, .state, .left_control);
    gameplay.map_key(.Sprint, .state, .left_shift);
    gameplay.map_key(.ResetCamera, .rising_edge, .r);
    gameplay.map_key(.Save, .rising_edge, .o);
    gameplay.map_key(.Load, .rising_edge, .p);
    gameplay.map_mouse_button(.Interact, .rising_edge, .b1);
    gameplay.map_mouse_button(.AltInteract, .state, .b2);

    gameplay.map_mouse_button(.bolt_back, .rising_edge, .b4);
    gameplay.map_mouse_button(.bolt_forward, .rising_edge, .b5);

    gameplay.map_key(.SwitchWeapon, .rising_edge, .q);
    gameplay.map_key(.DebugFramePauseDataCollection, .rising_edge, .b);
    gameplay.map_key(.DebugFrameBack, .rising_edge, .c);
    gameplay.map_key(.DebugFrameForward, .rising_edge, .v);
    gameplay.map_key(.DebugShowData, .toggle, .x);
    gameplay.map_key(.to_pause, .rising_edge, .escape);
    gameplay.map_key(.to_console, .rising_edge, .grave_accent);
    gameplay.map_key(.to_editor, .rising_edge, .f2);

    const editor = im.get(.editor);
    editor.map_key(.MoveForward, .state, .w);
    editor.map_key(.MoveLeft, .state, .a);
    editor.map_key(.MoveBack, .state, .s);
    editor.map_key(.MoveRight, .state, .d);
    editor.map_key(.MoveUp, .state, .space);
    editor.map_key(.MoveDown, .state, .left_control);
    editor.map_key(.Sprint, .state, .left_shift);
    editor.map_key(.ResetCamera, .rising_edge, .r);
    editor.map_key(.Save, .rising_edge, .o);
    editor.map_key(.Load, .rising_edge, .p);
    editor.map_key(.TogglePlacementMode, .rising_edge, .q);
    editor.map_key(.add_chunk, .rising_edge, .f);
    editor.map_key(.remove_chunk, .rising_edge, .p);
    editor.map_mouse_button(.PlaceBlock, .rising_edge, .b1);
    editor.map_mouse_button(.SelectRegion, .rising_edge, .b2);
    editor.map_key(.SelectBlock1, .rising_edge, .num_1);
    editor.map_key(.SelectBlock2, .rising_edge, .num_2);
    editor.map_key(.SelectBlock3, .rising_edge, .num_3);
    editor.map_key(.SelectBlock4, .rising_edge, .num_4);
    editor.map_key(.SelectBlock5, .rising_edge, .num_5);
    editor.map_key(.to_console, .rising_edge, .grave_accent);
    editor.map_key(.to_pause, .rising_edge, .escape);
    editor.map_key(.to_editor, .rising_edge, .f2);

    const pause = im.get(.pause);
    pause.map_key(.MoveForward, .state, .w);
    pause.map_key(.MoveLeft, .state, .a);
    pause.map_key(.MoveBack, .state, .s);
    pause.map_key(.MoveRight, .state, .d);
    pause.map_key(.MoveUp, .state, .space);
    pause.map_key(.MoveDown, .state, .left_control);
    pause.map_key(.Sprint, .state, .left_shift);
    pause.map_key(.ResetCamera, .rising_edge, .r);
    pause.map_key(.Save, .rising_edge, .o);
    pause.map_key(.Load, .rising_edge, .p);
    pause.map_mouse_button(.Interact, .rising_edge, .b1);
    pause.map_mouse_button(.AltInteract, .rising_edge, .b2);
    pause.map_key(.to_console, .rising_edge, .grave_accent);
    pause.map_key(.to_pause, .rising_edge, .escape);

    const console = im.get(.console);
    console.map_key(.Enter, .rising_edge, .enter);
    console.map_key(.to_console, .rising_edge, .grave_accent);
}

fn setup_gamepad_input(im: *res.InputMaps) void {
    const gameplay = im.get(.gameplay);
    gameplay.map_gamepad_axis_abs(.MoveForward, .state, .{ .axis = .left_y, .dir = .smaller_than_zero });
    gameplay.map_gamepad_axis_abs(.MoveBack, .state, .{ .axis = .left_y, .dir = .larger_than_zero });
    gameplay.map_gamepad_axis_abs(.MoveRight, .state, .{ .axis = .left_x, .dir = .larger_than_zero });
    gameplay.map_gamepad_axis_abs(.MoveLeft, .state, .{ .axis = .left_x, .dir = .smaller_than_zero });
    gameplay.map_gamepad_button(.Jump, .rising_edge, .right_bumper);
    gameplay.map_gamepad_button(.Crouch, .state, .left_bumper);
    //gameplay.map_key(.Sprint,                    .state,       .left_shift);
    //gameplay.map_gamepad_button(.Editor, .rising_edge, .start);
    gameplay.map_gamepad_axis_abs(.Interact, .rising_edge, .{ .axis = .right_trigger, .dir = .larger_than_zero });
    gameplay.map_gamepad_button(.AltInteract, .state, .right_bumper);
    gameplay.map_gamepad_button(.SwitchWeapon, .rising_edge, .y);
    gameplay.map_gamepad_button(.DebugIncGamepadOffset, .rising_edge, .dpad_up);
    gameplay.map_gamepad_button(.DebugDecGamepadOffset, .rising_edge, .dpad_down);

    const editor = im.get(.editor);
    editor.map_gamepad_axis_abs(.MoveForward, .state, .{ .axis = .left_y, .dir = .smaller_than_zero });
    editor.map_gamepad_axis_abs(.MoveBack, .state, .{ .axis = .left_y, .dir = .larger_than_zero });
    editor.map_gamepad_axis_abs(.MoveRight, .state, .{ .axis = .left_x, .dir = .larger_than_zero });
    editor.map_gamepad_axis_abs(.MoveLeft, .state, .{ .axis = .left_x, .dir = .smaller_than_zero });
    editor.map_gamepad_button(.MoveUp, .state, .a);
    editor.map_gamepad_button(.MoveDown, .state, .b);
    //editor.map_gamepad_button(.Editor, .toggle, .start);
    editor.map_gamepad_button(.Interact, .rising_edge, .x);
    editor.map_gamepad_button(.AltInteract, .state, .right_bumper);
}

fn setup_input_maps(pack: *goosepack.Pack, im: *res.InputMaps, t: InputMapsType) void {
    _ = pack;
    switch (t) {
        .mouse_keyboard => setup_mouse_keyboard_input(im),
        .gamepad => setup_gamepad_input(im),
    }
}

//
// LocalPlayer represents a player on the local game. This is to support
// splitscreen/couch co-op.
//

const InputDeviceState = enum {
    connected,
    disconnected,
    occupied,
};

const InputDevice = union(enum) {
    mouse_keyboard: struct {},
    gamepad: struct {
        id: u4,
    },
};

const LocalPlayer = struct {
    const num_inputs = @typeInfo(common.InputName).@"enum".fields.len;
    const num_states = @typeInfo(common.State).@"enum".fields.len;

    active_state: u8 = 0,
    state_stack: [num_states]common.State = .{.gameplay} ** num_states,
    from_state: common.State = .gameplay,

    input_device: ?InputDevice = null,
    input_device_id: ?usize = null,
    input_maps: ?res.InputMaps = null,
    input: Input = undefined,

    last_input_actions: [num_inputs]res.Action = .{.release} ** num_inputs,

    // TODO: We only need to allocate this when on network
    input_buffer: bb.CircularBuffer(Input, 256) = .{},

    id: ?EntityId = null,
};

fn findLocalPlayerById(local_players: []LocalPlayer, id: EntityId) ?*LocalPlayer {
    for (local_players) |*l| {
        if (l.id != null and l.id.? == id)
            return l;
    }
    return null;
}

var memory: Memory = .{};

//
// glfw globals and callbacks for collecting inputs
//

var timer: std.time.Timer = undefined;
var key_repeat_timer: std.time.Timer = undefined;
var last_key: res.Key = undefined;
var last_char: u8 = 0;
var repeat = false;
var last_key_down = false;

var capture_text = false;
var wait_for_first_key_input = true;
fn charCallback(window: ?*c.GLFWwindow, codepoint: c_uint) callconv(.c) void {
    _ = window;
    if (!capture_text and !wait_for_first_key_input)
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

    if (wait_for_first_key_input) {
        wait_for_first_key_input = false;
        return;
    }

    if (memory.console_input.used < memory.console_input.buffer.len - 1) {
        memory.console_input.append(@as(u8, @truncate(@as(u32, @intCast(last_char))))) catch {};
        memory.console_input.buffer[memory.console_input.used] = 0;
        memory.console_input_index += 1;
    }
}

var scroll_delta: f32 = 0.0;
fn scrollCallback(window: ?*c.GLFWwindow, dx: f64, dy: f64) callconv(.c) void {
    _ = window;
    _ = dx;
    scroll_delta = @floatCast(dy);
}

const PlayingSound = struct {
    samples: []f32 = undefined,
    index: usize = 0,
    volume: f32 = 1.0,
};

var host: net.Host = .{};
var server_index: ?net.PeerIndex = null;
pub fn connect(ip: []const u8, port: u16) void {
    const crand = std.crypto.random;
    server_index = net.connect(&host, ip, port) orelse blk: {
        log.err("Failed to connect to server {s}:{}", .{ ip, port });
        break :blk null;
    };
    net.pushMessage(server_index.?, packet.ConnectionRequest{ .client_salt = crand.int(u64) });
}

pub fn main() !void {
    // Setup the allocators we'll be using
    // 1. GeneralPurposeAllocator for persitent data that will exist accross frames
    //    and has to be freed manually.
    // 2. ArenaAllocator for temporary data that during a frame
    var general_purpose_allocator: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const page_size = std.heap.page_size_min;
    var fixed_allocator = std.heap.FixedBufferAllocator.init(try std.heap.page_allocator.alignedAlloc(u8, null, 128000 * page_size));
    defer std.heap.page_allocator.free(fixed_allocator.buffer);
    //var fixed_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    memory.mem.frame = fixed_allocator.threadSafeAllocator();
    memory.mem.persistent = general_purpose_allocator.allocator();

    memory.windows_persistent = std.ArrayList(common.WindowPersistentState){};
    memory.animation_states = std.ArrayList(common.AnimationState){};
    memory.log_memory = try common.log.LogMemory.init(memory.mem.persistent, memory.mem.frame, null, false);
    log = memory.log_memory.group_log(.general);

    if (build_options.options.debug) {
        disk.frame = memory.mem.frame;
        disk.persistent = memory.mem.persistent;
    }

    memory.profile.init(memory.mem.persistent);
    defer memory.profile.deinit();

    const num_cpus = std.Thread.getCpuCount() catch 1;
    try memory.threadpool.init(.{
        .allocator = memory.mem.persistent,
        .n_jobs = @intCast(num_cpus - 1),
    });
    defer memory.threadpool.deinit();

    net.mem = memory.mem;
    res.mem = memory.mem;
    net.init(&memory.log_memory);

    //
    // Load pack
    //

    goosepack.setAllocators(memory.mem.frame, memory.mem.persistent);

    var pack_in_memory: ?[]u8 = undefined;
    defer {
        if (pack_in_memory) |bytes| memory.mem.persistent.free(bytes);
    }

    {
        pack_in_memory = res.readFileToMemory(memory.mem.persistent, "res.gp") catch null;
        memory.pack = goosepack.init();
        if (pack_in_memory) |bytes| {
            try goosepack.load(&memory.pack, bytes);
        }
    }

    //
    // Connect to server
    //
    //connect("127.0.0.1", 9053);
    cl.run("connect 127.0.0.1 9053");

    //
    // Simulation state
    //

    const desired_frame_time = std.time.ns_per_s / common.target_fps;
    const dt: f32 = 1.0 / @as(f32, @floatFromInt(common.target_fps));

    var tick: u64 = 0;

    //
    // GLFW init
    //
    if (c.glfwInit() == 0) {
        log.err("Failed to initialize GLFW: {s}", .{glfw_get_error()});
        std.process.exit(1);
    }
    defer c.glfwTerminate();

    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
    c.glfwWindowHint(c.GLFW_OPENGL_FORWARD_COMPAT, c.GLFW_TRUE);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);

    const window = c.glfwCreateWindow(800, 600, "floating", null, null) orelse {
        log.err("Failed to open window: {s}", .{glfw_get_error()});
        std.process.exit(1);
    };
    defer c.glfwDestroyWindow(window);

    c.glfwMakeContextCurrent(window);
    c.glfwSwapInterval(0);
    c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);
    c.glfwSetInputMode(window, c.GLFW_RAW_MOUSE_MOTION, c.GLFW_TRUE);
    _ = c.glfwSetCharCallback(window, charCallback);
    _ = c.glfwSetScrollCallback(window, scrollCallback);

    // Update gamepad database
    {
        const controller_db = @embedFile("gamecontrollerdb.txt");
        _ = c.glfwUpdateGamepadMappings(controller_db);
    }

    // initialize renderer
    draw.init(&memory.log_memory, memory.mem, &memory.pack);
    defer draw.deinit();

    //
    // Audio
    //

    sa.setup(.{
        .logger = .{ .func = slog.func },
        .num_channels = 2,
    });
    defer sa.shutdown();

    // Load all sounds into buffers
    var playing_sounds: BoundedArray(PlayingSound, 64) = .{};

    //
    // Modules
    //
    var module = try code_module.CodeModule(struct {
        init: *fn (memory: *Memory) callconv(.c) bool,
        deinit: *fn (memory: *Memory) callconv(.c) void,
        update: *fn (vars: *const Vars, memory: *Memory, player: *Player, input: *const Input, dt: f32) callconv(.c) void,
        authorizedPlayerUpdate: *fn (vars: *const Vars, memory: *Memory, player: *Player, input: *const Input, dt: f32) callconv(.c) void,
        authorizedUpdate: *fn (vars: *const Vars, memory: *Memory, dt: f32) callconv(.c) void,
        client_update: *fn (vars: *const Vars, memory: *Memory, dt: f32) callconv(.c) void,
        draw: *fn (vars: *const Vars, memory: *Memory, b: *draw_api.CommandBuffer, player_id: common.EntityId, input: *const Input) callconv(.c) void,
    }).init(memory.mem.persistent, "zig-out/lib", "game");

    try module.open(memory.mem.persistent);
    defer module.close();

    if (!module.function_table.init(&memory)) {
        log.err("Failed to initialize module: {s}", .{module.name});
        return;
    }
    defer module.function_table.deinit(&memory);

    //
    // Input state
    //

    const max_num_gamepads = c.GLFW_JOYSTICK_LAST + 1;
    const keyboard_input_device_id = c.GLFW_JOYSTICK_LAST + 1;
    var occupied_input_devices = [_]InputDeviceState{.connected} ** (keyboard_input_device_id + 1);
    var debug_gamepad_off: usize = 0;

    var command_buffer: draw_api.CommandBuffer = .{};

    var local_players: BoundedArray(LocalPlayer, 16) = .{};

    timer = try std.time.Timer.start();
    key_repeat_timer = try std.time.Timer.start();

    var frame_start_time: u64 = 0;
    var frame_end_time: u64 = 0;

    // Scan for connected joysticks
    {
        //for (0..@intFromEnum(glfw.Joystick.Id.last)) |i| {
        //    const present = glfw.Joystick.present(.{.jid = @enumFromInt(i)});
        //}
    }

    var connected = false;

    @memset(&memory.console_input.buffer, 0);

    var old_mouse_pos: v2 = .{ .x = 0.0, .y = 0.0 };

    var running = true;
    while (running) {
        memory.profile.begin_frame();

        frame_start_time = timer.read();

        log.info("---- Starting tick {}", .{tick});

        memory.windows = std.ArrayList(common.WindowState).init(memory.mem.frame);
        memory.map_mods = std.ArrayList(common.MapModify).init(memory.mem.frame);

        {
            scroll_delta = 0.0;
            c.glfwPollEvents();

            //const frame_stat = memory.time_stats.get(.Frametime).startTime();
            memory.time += desired_frame_time;

            if (c.glfwWindowShouldClose(window) == 1) {
                running = false;
            }

            {
                if (try module.reloadIfChanged(memory.mem.persistent)) {
                    //_ = module.function_table.fofo();
                }
            }

            var width: c_int = undefined;
            var height: c_int = undefined;
            c.glfwGetWindowSize(window, &width, &height);
            config.vars.aspect = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));

            //
            // Read network
            //
            var events: []net.Event = undefined;
            if (server_index) |si| {
                const block_rescv = memory.profile.begin("net receive", 0);
                events = net.receiveMessagesClient(&host, si);
                memory.profile.end(block_rescv);

                //
                // Process network data
                //
                const block_process = memory.profile.begin("net process", 0);
                for (events) |event| {
                    switch (event) {
                        .peer_connected => {
                            // Clear local players and players in game when joining a server
                            for (local_players.slice()) |*lp| {
                                lp.id = null;
                            }
                            memory.players.len = 0;
                            log.info("connected", .{});
                            connected = true;
                        },
                        .peer_disconnected => {
                            log.info("connected", .{});
                        },
                        .message_received => |e| {
                            switch (e.kind) {
                                .Command => {
                                    const message: *align(1) packet.Command = @ptrCast(e.data);

                                    // Hardcode set command as we need to treat the value passed separately.
                                    //if (setall and peer_index != null) {
                                    //    var command_packet = packet.Command{
                                    //        .data = undefined,
                                    //        .len = commandline.len,
                                    //    };
                                    //    std.mem.copy(u8, &command_packet.data, commandline);
                                    //    net.pushMessage(peer_index.?, command_packet);
                                    //}

                                    log.info("Running command: {s}", .{message.data[0..message.len]});
                                    command.dodododododododo(message.data[0..message.len]);
                                },
                                .ConnectionTimeout => {
                                    const message: *align(1) packet.ConnectionTimeout = @ptrCast(e.data);
                                    _ = message;
                                    if (connected) {
                                        connected = false;
                                        running = false;
                                        log.info("connection timeout", .{});
                                    }
                                },
                                .Joined => {
                                    const message: *align(1) packet.Joined = @ptrCast(e.data);
                                    tick = message.tick;
                                    log.info("Joined message", .{});
                                },
                                .PlayerJoinResponse => {
                                    const message: *align(1) packet.PlayerJoinResponse = @ptrCast(e.data);
                                    const player = try memory.players.addOne();
                                    player.id = message.id;

                                    var local_player_id: ?usize = null;
                                    for (local_players.slice(), 0..) |*lp, i| {
                                        if (lp.id == null) {
                                            local_player_id = i;
                                            lp.id = player.id;
                                            break;
                                        }
                                    }

                                    std.debug.assert(local_player_id != null);
                                    log.info("Player joined", .{});
                                    log.info("  local player id: {}", .{local_player_id.?});
                                    log.info("  game player id: {}", .{player.id});
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
                                .SpawnPlayer => {
                                    const message: *align(1) packet.SpawnPlayer = @ptrCast(e.data);
                                    const player = common.findPlayerById(&memory.players.buffer, message.player.id) orelse unreachable;
                                    player.* = message.player;
                                    log.info("Spawning", .{});
                                },
                                .PlayerUpdateAuth => {
                                    const message: *align(1) packet.PlayerUpdateAuth = @ptrCast(e.data);
                                    const local_player = findLocalPlayerById(local_players.slice(), message.player.id);
                                    if (local_player != null) {
                                        const player = common.findPlayerById(&memory.players.buffer, message.player.id);

                                        var auth_player = message.player;
                                        var offset = @as(i64, @intCast(message.tick)) - @as(i64, @intCast(tick)) + 2;
                                        var auth_memory = memory;
                                        while (offset <= 0) : (offset += 1) {
                                            const old_input = local_player.?.input_buffer.peekRelative(offset);
                                            module.function_table.update(&config.vars, &auth_memory, &auth_player, old_input, dt);
                                        }

                                        if (!v3.eql(auth_player.pos, player.?.pos)) {
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
                                        if (findLocalPlayerById(local_players.slice(), player.id) != null)
                                            continue;
                                        const current_player = common.findPlayerById(&memory.players.buffer, player.id) orelse try memory.players.addOne();
                                        current_player.* = player;
                                    }
                                },
                                .NewSounds => {
                                    const message: *align(1) packet.NewSounds = @ptrCast(e.data);
                                    for (message.new_sounds[0..message.num_sounds]) |s| {
                                        // TODO(anjo): we're hardcoding to skip death sounds here...
                                        //
                                        // check if the sound was triggered by us, and in that
                                        // case ignore it as we've already added it when we
                                        // updated locally
                                        if (s.type != .death) {
                                            var local = false;
                                            for (local_players.constSlice()) |lp| {
                                                if (lp.id == s.id_from) {
                                                    local = true;
                                                    break;
                                                }
                                            }
                                            if (local)
                                                continue;
                                        }
                                        memory.new_sounds.appendAssumeCapacity(s);
                                    }
                                },
                                .NewHitscans => {
                                    const message: *align(1) packet.NewHitscans = @ptrCast(e.data);
                                    for (message.new_hitscans[0..message.num_hitscans]) |h| {
                                        var local = false;
                                        for (local_players.constSlice()) |lp| {
                                            if (lp.id == h.id_from) {
                                                local = true;
                                                break;
                                            }
                                        }
                                        if (local)
                                            continue;
                                        memory.new_hitscans.appendAssumeCapacity(h);
                                    }
                                },
                                .NewExplosions => {
                                    const message: *align(1) packet.NewExplosions = @ptrCast(e.data);
                                    appendSliceAssumeForceDstAlignment(1, common.Explosion, &memory.new_explosions, message.new_explosions[0..message.num_explosions]);
                                },
                                .NewNades => {
                                    const message: *align(1) packet.NewNades = @ptrCast(e.data);
                                    appendSliceAssumeForceDstAlignment(1, common.Nade, &memory.new_nades, message.new_nades[0..message.num_nades]);
                                },
                                .NewDamage => {
                                    const message: *align(1) packet.NewDamage = @ptrCast(e.data);
                                    appendSliceAssumeForceDstAlignment(1, common.Damage, &memory.new_damage, message.new_damage[0..message.num_damage]);
                                },
                                .NewMapMods => {
                                    std.log.info("received map mods from server", .{});
                                    const message: *align(1) packet.NewMapMods = @ptrCast(e.data);
                                    for (message.mods[0..message.num_mods]) |m| {
                                        memory.map_mods.append(m) catch unreachable;
                                    }
                                },
                                .Kill => {
                                    const message: *align(1) packet.Kill = @ptrCast(e.data);
                                    var entry = memory.killfeed.push();
                                    entry.from = message.from;
                                    entry.to = message.to;
                                    entry.time_left = 2.0;
                                },
                                .EntityUpdate => {
                                    const message: *align(1) packet.EntityUpdate = @ptrCast(e.data);
                                    if (common.findEntityById(memory.entities.slice(), message.entity.id)) |entity| {
                                        entity.* = message.entity;
                                    } else {
                                        memory.entities.appendAssumeCapacity(message.entity);
                                    }
                                },
                                else => {
                                    log.err("Unrecognized packet type: {}", .{e.kind});
                                    break;
                                },
                            }
                        },
                    }
                }
                memory.profile.end(block_process);
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
                    {
                        const block = memory.profile.begin("new player", 0);
                        defer memory.profile.end(block);
                        for (occupied_input_devices, 0..) |d, i| {
                            if (d == .connected) {
                                // @unlikely

                                if (i == keyboard_input_device_id) {
                                    // Check if mouse/keyboard input happened
                                    const key_pressed = last_char > 0;
                                    var xpos: f64 = undefined;
                                    var ypos: f64 = undefined;
                                    c.glfwGetCursorPos(window, &xpos, &ypos);
                                    const mouse_moved = xpos > 0 or ypos > 0;
                                    if (key_pressed or mouse_moved) {
                                        occupied_input_devices[i] = .occupied;

                                        // add a player so we can play locally
                                        // TODO: don't perform attempts to read/write net
                                        // if we're not connected.
                                        {
                                            const lp = local_players.addOneAssumeCapacity();
                                            if (!connected) {
                                                lp.id = common.newEntityId();
                                            } else {
                                                lp.id = null;
                                            }
                                            lp.input_device_id = i;
                                            lp.input_maps = .{};
                                            setup_input_maps(&memory.pack, &lp.input_maps.?, .mouse_keyboard);

                                            if (server_index) |index| {
                                                net.pushMessage(index, packet.PlayerJoinRequest{});
                                            }
                                            log.info("Sending join request", .{});

                                            if (!connected) {
                                                const player = Player{
                                                    .id = lp.id.?,
                                                    .pos = v3{ .x = 0, .y = 0, .z = 10.0 },
                                                    .vel = v3{ .x = 0, .y = 0, .z = 0 },
                                                    .dir = v3{ .x = 1, .y = 0, .z = 0 },
                                                    .yaw = 0,
                                                    .pitch = 0,
                                                };
                                                memory.players.appendAssumeCapacity(player);

                                                memory.respawns.appendAssumeCapacity(.{
                                                    .id = lp.id.?,
                                                    .time_left = 0.0,
                                                });
                                            }
                                        }
                                    }
                                } else {
                                    // Check for gamepad input
                                    const index = (i + max_num_gamepads - debug_gamepad_off) % max_num_gamepads;
                                    var gamepad_press = false;
                                    if (occupied_input_devices[i] == .occupied) {
                                        continue;
                                    }
                                    const joystick: c_int = @intCast(index);
                                    const present = c.glfwJoystickPresent(joystick);
                                    if (present == 1) {
                                        var gamepad: c.GLFWgamepadstate = undefined;
                                        if (c.glfwGetGamepadState(joystick, &gamepad) == 0) {
                                            continue;
                                        }
                                        for (gamepad.buttons) |b| {
                                            const action: res.Action = @enumFromInt(b);
                                            if (action == .press) {
                                                gamepad_press = true;
                                                occupied_input_devices[i] = .occupied;
                                                log.info("Gamepad {}", .{i});

                                                // add a player so we can play locally
                                                // TODO: don't perform attempts to read/write net
                                                // if we're not connected.
                                                {
                                                    const lp = local_players.addOneAssumeCapacity();
                                                    if (!connected) {
                                                        lp.id = common.newEntityId();
                                                    } else {
                                                        lp.id = null;
                                                    }
                                                    lp.input_device_id = i;
                                                    lp.input_maps = .{};
                                                    setup_input_maps(&memory.pack, &lp.input_maps.?, .gamepad);

                                                    if (!connected) {
                                                        const player = Player{
                                                            .id = lp.id.?,
                                                            .pos = v3{ .x = 0, .y = 0, .z = 10.0 },
                                                            .vel = v3{ .x = 0, .y = 0, .z = 0 },
                                                            .dir = v3{ .x = 1, .y = 0, .z = 0 },
                                                            .yaw = 0,
                                                            .pitch = 0,
                                                        };
                                                        memory.players.appendAssumeCapacity(player);

                                                        memory.respawns.appendAssumeCapacity(.{
                                                            .id = lp.id.?,
                                                            .time_left = 0.0,
                                                        });
                                                    }
                                                }

                                                break;
                                            }
                                        }

                                        if (gamepad_press) {
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    {
                        const block = memory.profile.begin("gather input", 0);
                        defer memory.profile.end(block);

                        for (local_players.slice()) |*lp| {
                            if (lp.input_device_id == null or lp.id == null) {
                                continue;
                            }
                            //{
                            //    inline for (@typeInfo(Key).Enum.fields) |ef| {
                            //        if (ef.value == -1) {
                            //            continue;
                            //        }
                            //        const key: Key = @enumFromInt(ef.value);
                            //        std.log.info("{} - {s} - {}", .{ef.value, ef.name, window.getKey(key)});
                            //    }
                            //    inline for (@typeInfo(MouseButton).Enum.fields) |ef| {
                            //        const mb: MouseButton = @enumFromInt(ef.value);
                            //        std.log.info("{} - {s} - {}", .{ef.value, ef.name, window.getMouseButton(mb)});
                            //    }
                            //    inline for (@typeInfo(GamepadButton).Enum.fields) |ef| {
                            //        const gb: GamepadButton = @enumFromInt(ef.value);
                            //        const index: glfw.Joystick.Id = @enumFromInt((lp.input_device_id.? + max_num_gamepads - debug_gamepad_off) % max_num_gamepads);
                            //        const gamepad = glfw.Joystick.getGamepadState(.{ .jid = index }) orelse {
                            //            continue;
                            //        };
                            //        std.log.info("{} - {s} - {}", .{ef.value, ef.name, gamepad.getButton(gb)});
                            //    }
                            //    if (scroll_delta > 0) {
                            //    }
                            //    if (scroll_delta < 0) {
                            //    }
                            //}

                            // Collect inputs if we're not in the console
                            {
                                update_game_state(lp, &lp.input);
                                memory.active_state = active_state(lp);
                                const input_map = lp.input_maps.?.get(active_state(lp));

                                for (&input_map.map, 0..) |*state, i| {
                                    const input_name: InputName = @enumFromInt(i);
                                    //if (memory.state == .console and input_name != .Enter) {
                                    //    continue;
                                    //}

                                    const action: res.Action = switch (state.input_type) {
                                        res.InputType.key => |key| glfw_get_key(window, key),
                                        res.InputType.mouse_button => |mb| @enumFromInt(c.glfwGetMouseButton(window, @intFromEnum(mb))),
                                        res.InputType.mouse_scroll => |ms| switch (ms.dir) {
                                            .scroll_down => if (scroll_delta < 0.0) .press else .release,
                                            .scroll_up => if (scroll_delta > 0.0) .press else .release,
                                        },
                                        res.InputType.gamepad_button => |gb| blk: {
                                            const index = (lp.input_device_id.? + max_num_gamepads - debug_gamepad_off) % max_num_gamepads;
                                            var gamepad: c.GLFWgamepadstate = undefined;
                                            if (c.glfwGetGamepadState(@intCast(index), &gamepad) == 0) {
                                                continue;
                                            }
                                            var count: c_int = undefined;
                                            const buttons = c.glfwGetJoystickButtons(@intCast(index), &count);
                                            std.debug.assert(@intFromEnum(gb) < count);
                                            break :blk @enumFromInt(buttons[@intFromEnum(gb)]);
                                        },
                                        res.InputType.gamepad_axis_abs => |a| blk: {
                                            const deadzone = 0.1;
                                            const index = (lp.input_device_id.? + max_num_gamepads - debug_gamepad_off) % max_num_gamepads;
                                            var gamepad: c.GLFWgamepadstate = undefined;
                                            if (c.glfwGetGamepadState(@intCast(index), &gamepad) == 0) {
                                                continue;
                                            }
                                            var count: c_int = undefined;
                                            const axes = c.glfwGetJoystickAxes(@intCast(index), &count);
                                            std.debug.assert(@intFromEnum(a.axis) < count);
                                            break :blk switch (a.dir) {
                                                .larger_than_zero => if (axes[@intFromEnum(a.axis)] > deadzone) .press else .release,
                                                .smaller_than_zero => if (axes[@intFromEnum(a.axis)] < -deadzone) .press else .release,
                                            };
                                        },
                                        else => continue,
                                    };

                                    const last_action = lp.last_input_actions[i];
                                    switch (state.trigger) {
                                        .state => {
                                            const active = action == .press;
                                            lp.input.setto(input_name, active);
                                        },
                                        .rising_edge => {
                                            const active = last_action == .release and action == .press;
                                            lp.input.setto(input_name, active);
                                        },
                                        .falling_edge => {
                                            const active = last_action == .press and action == .release;
                                            lp.input.setto(input_name, active);
                                        },
                                        .rising_or_falling_edge => {
                                            const active = last_action != action;
                                            lp.input.setto(input_name, active);
                                        },
                                        .toggle => {
                                            const active = last_action == .release and action == .press;
                                            lp.input.setto(input_name, active != lp.input.isset(input_name));
                                        },
                                    }
                                    lp.last_input_actions[i] = action;
                                }
                            }

                            if (lp.input_device_id.? == keyboard_input_device_id) {
                                // Mouse/keyboard specific inputs

                                // TODO(anjo): We have to deal with mouse buttons separately here which is annoying
                                lp.input.scroll = scroll_delta;

                                var delta: v2 = .{};
                                {
                                    var xpos: f64 = undefined;
                                    var ypos: f64 = undefined;
                                    c.glfwGetCursorPos(window, &xpos, &ypos);
                                    delta.x = @as(f32, @floatCast(xpos)) - old_mouse_pos.x;
                                    delta.y = @as(f32, @floatCast(ypos)) - old_mouse_pos.y;
                                    old_mouse_pos.x = @floatCast(xpos);
                                    old_mouse_pos.y = @floatCast(ypos);
                                }

                                lp.input.cursor_delta = .{ .x = config.vars.sensitivity * delta.x, .y = config.vars.sensitivity * delta.y };
                            } else {
                                // Gamepad specific inputs
                                const deadzone = 0.1;
                                const index = (lp.input_device_id.? + max_num_gamepads - debug_gamepad_off) % max_num_gamepads;
                                var gamepad: c.GLFWgamepadstate = undefined;
                                if (c.glfwGetGamepadState(@intCast(index), &gamepad) == 0) {
                                    continue;
                                }
                                // TODO(anjo): @optimize
                                var count: c_int = undefined;
                                const axes = c.glfwGetJoystickAxes(@intCast(index), &count);
                                var dx = axes[@intFromEnum(res.GamepadAxis.right_x)];
                                var dy = axes[@intFromEnum(res.GamepadAxis.right_y)];
                                var abs_dx = @abs(dx);
                                var abs_dy = @abs(dy);
                                dx = if (abs_dx > deadzone) dx else 0.0;
                                dy = if (abs_dy > deadzone) dy else 0.0;
                                abs_dx = if (abs_dx > deadzone) abs_dx else 1.0;
                                abs_dy = if (abs_dy > deadzone) abs_dy else 1.0;
                                // TODO(anjo): Add acceleration
                                lp.input.cursor_delta.x = 20.0 * config.vars.sensitivity * dx / abs_dx;
                                // TODO(anjo): Move aspect ratio to camera
                                lp.input.cursor_delta.y = (9.0 / 16.0) * 20.0 * config.vars.sensitivity * dy / abs_dy;
                            }

                            // push input state
                            lp.input_buffer.push(lp.input);

                            const player = common.findPlayerById(&memory.players.buffer, lp.id.?);

                            if (connected) {
                                net.pushMessage(server_index.?, packet.PlayerUpdate{
                                    .tick = tick,
                                    .id = lp.id.?,
                                    .input = lp.input,
                                    .in_editor = @intFromBool(player.?.in_editor),
                                });
                            }

                            // Run predictive move
                            if (player != null) {
                                {
                                    const block_update = memory.profile.begin("update", 0);
                                    defer memory.profile.end(block_update);
                                    module.function_table.update(&config.vars, &memory, player.?, &lp.input, dt);
                                }
                                if (!connected) {
                                    module.function_table.authorizedPlayerUpdate(&config.vars, &memory, player.?, &lp.input, dt);
                                }
                            }

                            // Handle console input for 0:th local player input
                            capture_text = active_state(lp) == .console;
                            if (capture_text) {
                                // TODO(anjo): Move to charcallack
                                if (glfw_get_key(window, last_key) == .press) {
                                    last_key_down = true;
                                } else if (glfw_get_key(window, last_key) == .release) {
                                    last_key_down = false;
                                }
                                if (last_key_down and (!repeat and key_repeat_timer.read() >= 500 * std.time.us_per_s or
                                    repeat and key_repeat_timer.read() >= 50 * std.time.us_per_s))
                                {
                                    key_repeat_timer.reset();
                                    repeat = true;
                                }

                                if (memory.console_input_index > 0 and (glfw_get_key(window, .left) == .press or last_key == .left and repeat)) {
                                    memory.console_input_index -= 1;
                                }
                                if (memory.console_input_index < memory.console_input.len and (glfw_get_key(window, .right) == .press or last_key == .right and repeat)) {
                                    memory.console_input_index += 1;
                                }
                                if (memory.console_input_index > 0 and (glfw_get_key(window, .backspace) == .press or last_key == .backspace and repeat)) {
                                    _ = memory.console_input.orderedRemove(memory.console_input_index - 1);
                                    memory.console_input.buffer[memory.console_input.len] = 0;
                                    memory.console_input_index -= 1;
                                }
                                if (memory.console_input.len < memory.console_input.buffer.len - 1 and (last_char >= 32 and last_char <= 126 and repeat)) {
                                    memory.console_input.append(@as(u8, @truncate(@as(u32, @intCast(last_char))))) catch {};
                                    memory.console_input.buffer[memory.console_input.len] = 0;
                                    memory.console_input_index += 1;
                                }

                                if (lp.input.isset(.Enter) and memory.console_input.len > 0) {
                                    command.dodododododododo(memory.console_input.slice());
                                    std.log.info("Running command: {s}", .{memory.console_input.slice()});

                                    memory.console_input_index = 0;
                                    memory.console_input.len = 0;
                                    memory.console_input.buffer[0] = 0;
                                }
                            }

                            // @debug
                            if (lp.input.isset(.DebugIncGamepadOffset)) {
                                debug_gamepad_off += 1;
                                log.info("debug_gamepad_off: {}", .{debug_gamepad_off});
                            }
                            if (lp.input.isset(.DebugDecGamepadOffset)) {
                                if (debug_gamepad_off > 0)
                                    debug_gamepad_off -= 1;
                                log.info("debug_gamepad_off: {}", .{debug_gamepad_off});
                            }
                        }
                    }

                    // Move new_* to actual persistent buffers
                    for (memory.new_sounds.constSlice()) |s| {
                        _ = s;
                        //playing_sounds.appendAssumeCapacity(.{
                        //    .samples = sound_file_map[@intFromEnum(s.type)].samples,
                        //    .volume = sound_file_map[@intFromEnum(s.type)].volume,
                        //});
                    }
                    memory.new_sounds.resize(0) catch unreachable;

                    for (memory.new_hitscans.constSlice()) |h| {
                        memory.hitscans.appendAssumeCapacity(h);
                    }
                    memory.new_hitscans.resize(0) catch unreachable;

                    for (memory.new_nades.constSlice()) |n| {
                        memory.nades.appendAssumeCapacity(n);
                    }
                    memory.new_nades.resize(0) catch unreachable;

                    for (memory.new_explosions.constSlice()) |e| {
                        memory.explosions.appendAssumeCapacity(e);
                    }
                    memory.explosions.resize(0) catch unreachable;

                    memory.new_damage.resize(0) catch unreachable;

                    memory.new_spawns.resize(0) catch unreachable;
                }
            }

            // TODO(anjo): Move to some "lobby" related thing
            if (!connected) {
                module.function_table.authorizedUpdate(&config.vars, &memory, dt);
            }

            module.function_table.client_update(&config.vars, &memory, dt);

            // Send updated entities to server
            if (connected) {
                for (memory.entities.slice()) |*e| {
                    if (!e.flags.updated_client)
                        continue;
                    e.flags.updated_client = false;
                    net.pushMessageToAllPeers(packet.EntityUpdate{
                        .entity = e.*,
                    });
                }
            }

            //
            // Send network data
            //
            if (server_index) |index| {
                net.process(&host, index);
            }

            //
            // Render
            //
            {
                {
                    const block = memory.profile.begin("draw collect", 0);
                    defer memory.profile.end(block);
                    for (local_players.constSlice()) |lp| {
                        if (lp.id == null) {
                            continue;
                        }
                        module.function_table.draw(&config.vars, &memory, &command_buffer, lp.id.?, &lp.input);
                    }
                }

                {
                    const block = memory.profile.begin("draw", 0);
                    defer memory.profile.end(block);
                    draw.process(&command_buffer, @intCast(width), @intCast(height), @intCast(local_players.len));
                }

                c.glfwSwapBuffers(window);
            }

            //
            // Audio
            //
            {
                const num_needed_samples = 2 * @as(usize, @intCast(sa.expect()));

                var samples = try memory.mem.frame.alloc(f32, num_needed_samples);
                @memset(samples, 0);

                var num_samples: usize = 0;
                for (playing_sounds.slice()) |*s| {
                    const num_available_samples = @min(s.samples.len - s.index, num_needed_samples);

                    for (0..num_available_samples) |i| {
                        samples[i] += s.volume * s.samples[s.index + i];
                    }
                    s.index += num_available_samples;

                    if (num_available_samples > num_samples) {
                        num_samples = num_available_samples;
                    }
                }

                var index: usize = 0;
                while (index < playing_sounds.len) {
                    const s = playing_sounds.constSlice()[index];
                    if (s.index == s.samples.len) {
                        _ = playing_sounds.swapRemove(index);
                    } else {
                        index += 1;
                    }
                }

                if (num_samples > 0)
                    _ = sa.push(&samples[0], @intCast(num_samples));
            }

            //
            // End of frame
            //

            // In debug mode, check for updates to the pack
            if (build_options.options.debug) {
                if (tick % config.Vars.pack_update_check_interval_ns == 0) {
                    const block = memory.profile.begin("pack update", 0);
                    memory.profile.end(block);

                    const entries = disk.collect_and_update_entries(&memory.pack) catch unreachable;
                    for (entries) |e| {
                        std.log.info("- {s}", .{e.name});
                    }
                    if (entries.len > 0) {

                        // builder will be .deinit() from thread which writes to the pack file
                        var builder = try goosepack.saveToMemory(&memory.pack);
                        pack_in_memory = try builder.dumpToBuffer(memory.mem.persistent);
                        memory.pack = goosepack.init();
                        try goosepack.load(&memory.pack, pack_in_memory.?);
                        // Swawn thread which writes to disk
                        try memory.threadpool.spawn(write_pack_to_file.run, .{ &builder, "res.gp" });

                        // Force recompilation of shaders and etc.
                        draw.resources_update(entries);
                    }
                }
            }

            // Debug profiling data collection
            memory.profile.end_frame();
            if (!memory.debug_data_collection_paused) {
                const next = memory.debug_frame_data.peekRelative(1);
                if (next.used) {
                    next.profile.free_anchors();
                }

                memory.debug_frame_data.push(.{
                    .profile = memory.profile.duplicate() catch unreachable,
                    .used = true,
                });
            }

            tick += 1;

            frame_end_time = timer.read();
            const frame_time = frame_end_time - frame_start_time;

            // Here we shoehorn in some sleeping to not consume all the cpu resources
            {
                const start_sleep = timer.read();
                const time_left = @as(i64, @intCast(desired_frame_time)) - @as(i64, @intCast(frame_time));
                if (time_left > std.time.us_per_s) {
                    // if we have at least 1us left, sleep
                    std.time.sleep(@intCast(time_left));
                }

                // spin for the remaining time
                while (timer.read() - start_sleep < time_left) {}
            }

            fixed_allocator.reset();
        }
    }

    std.posix.close(host.fd);
}

fn appendSliceAssumeForceDstAlignment(comptime alignment: usize, comptime T: type, bounded_array: anytype, src: []align(alignment) const T) void {
    const old_len = bounded_array.len;
    bounded_array.len = @intCast(bounded_array.len + src.len);
    @memcpy(@as([]align(alignment) T, @ptrCast(bounded_array.slice()[old_len..][0..src.len])), src);
}

fn glfw_get_error() [*:0]u8 {
    var desc: [*:0]u8 = undefined;
    _ = c.glfwGetError(@ptrCast(&desc));
    return desc;
}

fn glfw_get_key(window: ?*c.GLFWwindow, key: res.Key) res.Action {
    return @enumFromInt(c.glfwGetKey(window, @intFromEnum(key)));
}

const write_pack_to_file =
    if (build_options.options.debug)
        struct {
            fn run(builder: *goosepack.StringBuilder, file: []const u8) void {
                builder.dumpToFile(file) catch {};
                builder.deinit();
            }
        }
    else
        struct {};
