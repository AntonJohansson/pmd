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
const ThreadState = common.ThreadState;
const Player = common.Player;
const EntityId = common.EntityId;
const Input = common.Input;
const InputName = common.InputName;
const BoundedArray = common.BoundedArray;
const goosepack = common.goosepack;
const draw_api = common.draw_api;
const draw = @import("draw.zig");
const disk = if (build_options.options.debug) @import("pack-disk") else struct {};

const Arena = common.Arena;
const Pool = common.Pool;

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

threadlocal var log: common.log.GroupLog(.general) = undefined;

var ii: usize = 0;

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

fn findLocalPlayerById(lp: []LocalPlayer, id: EntityId) ?*LocalPlayer {
    for (lp) |*l| {
        if (l.id != null and l.id.? == id)
            return l;
    }
    return null;
}

var memory: Memory = .{};
const Module = code_module.CodeModule(struct {
    init: *fn (ts: *ThreadState, memory: *Memory) callconv(.c) bool,
    deinit: *fn (ts: *ThreadState, memory: *Memory) callconv(.c) void,
    update: *fn (ts: *ThreadState, vars: *const Vars, memory: *Memory, player: *Player, input: *const Input, dt: f32) callconv(.c) void,
    authorizedPlayerUpdate: *fn (ts: *ThreadState, vars: *const Vars, memory: *Memory, player: *Player, input: *const Input, dt: f32) callconv(.c) void,
    authorizedUpdate: *fn (ts: *ThreadState, vars: *const Vars, memory: *Memory, dt: f32) callconv(.c) void,
    client_update: *fn (ts: *ThreadState, vars: *const Vars, memory: *Memory, dt: f32) callconv(.c) void,
    draw: *fn (ts: *ThreadState, vars: *const Vars, memory: *Memory, b: *draw_api.CommandBuffer, player_id: common.EntityId, input: *const Input) callconv(.c) void,
});
var module: Module = undefined;

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

    if (memory.console_input.used < memory.console_input.data.len - 1) {
        memory.console_input.append(@as(u8, @truncate(@as(u32, @intCast(last_char)))));
        memory.console_input.data[memory.console_input.used] = 0;
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

// C calling convention necessary since this function might
// be called across a library boundary.
const page_size = std.heap.page_size_min;
fn page_alloc(size: usize) []u8 {
    const aligned_size = page_size * @divTrunc(size+page_size, page_size);
    return std.heap.page_allocator.alignedAlloc(u8, null, aligned_size) catch unreachable;
}

const KiB = 1024;
const MiB = 1024 * KiB;
const GiB = 1024 * MiB;

//
// START SYSTEM INIT
//

const max_num_threads = 16;
var num_threads: usize = 0;
var threads: [max_num_threads - 1]std.Thread = undefined;
var main_thread_id: std.Thread.Id = undefined;

threadlocal var ts: common.ThreadState = undefined;

var startup_futex = std.atomic.Value(u32).init(0);

fn system_init() void {
    num_threads = 8;
    main_thread_id = std.Thread.getCurrentId();
    for (threads[0..(num_threads - 1)], 0..) |*t, i| {
        t.* = std.Thread.spawn(.{}, thread_main, .{ i + 1, num_threads }) catch {
            std.log.err("Failed spawning thread {}", .{i});
            std.process.exit(1);
        };
    }
}

fn system_deinit() void {
    for (threads[0..(num_threads - 1)]) |*t| {
        t.join();
    }
}

//
// END SYSTEM INIT
//


// Draw state
var command_buffer: draw_api.CommandBuffer = .{};

// Player state
var local_players: BoundedArray(LocalPlayer, 16) = .{};

pub fn main() void {
    system_init();
    thread_main(0, num_threads);
    system_deinit();
}

fn thread_main(thread_id: usize, thread_num_threads: usize) void {
    // Initialize thread state
    ts = .{
        .id = @intCast(thread_id),
        .num_threads = @intCast(thread_num_threads),
    };

    ts.arena_frame = Arena{ .memory = page_alloc(256 * MiB) };
    var arena_persisent_state = Arena{ .memory = page_alloc(256 * MiB) };
    ts.arena_persistent = common.ArenaFreelist{ .arena = &arena_persisent_state };
    var arena_log_persistent = Arena{ .memory = page_alloc(1 * KiB) };
    var arena_res = Arena{ .memory = page_alloc(1 * GiB) };
    const mirror_to_stdio = false;
    ts.log_memory = common.log.LogMemory.init(&ts.arena_frame, &arena_log_persistent, null, mirror_to_stdio) catch {
        return;
    };

    ts.profile.init();
    defer ts.profile.deinit();

    log = ts.log_memory.group_log(.general);

    const num_cpus = std.Thread.getCpuCount() catch 1;
    _ = num_cpus;
    var window: ?*c.GLFWwindow = null;
    var pack_in_memory: ?[]u8 = null;

    if (ts.is_main()) {
        memory.animation_states = common.ArrayCircular(common.AnimationState){
            .data = ts.arena_persistent.alloc(common.AnimationState, 64),
        };
        memory.windows.arena = &ts.arena_frame;

        memory.barrier.init(@intCast(num_threads));

        if (build_options.options.debug) {
            disk.arena_frame = &ts.arena_frame;
            disk.arena_persistent = &ts.arena_persistent;
        }

        net.arena_frame = &ts.arena_frame;
        net.arena_persistent = &ts.arena_persistent;
        net.init(&ts.log_memory);
        res.arena = &arena_res;

        goosepack.arena_frame = &ts.arena_frame;
        var arena_pack_state = Arena{ .memory = page_alloc(1 * GiB) };
        var arena_freelist_pack_state = common.ArenaFreelist{ .arena = &arena_pack_state };
        goosepack.arena_persistent = &arena_freelist_pack_state;

        //
        // Load pack
        //

        pack_in_memory = res.read_file_to_memory("res.gp") catch null;
        memory.pack = goosepack.Pack{};
        if (pack_in_memory) |bytes| {
            goosepack.load(&memory.pack, bytes) catch {
                log.err("Failed loading pack", .{});
            };
        }

        //
        // Force connect to server
        //

        cl.run("connect 127.0.0.1 9053");

        //
        // GLFW init
        //
        if (c.glfwInit() == 0) {
            log.err("Failed to initialize GLFW: {s}", .{glfw_get_error()});
            std.process.exit(1);
        }

        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
        c.glfwWindowHint(c.GLFW_OPENGL_FORWARD_COMPAT, c.GLFW_TRUE);
        c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);

        window = c.glfwCreateWindow(800, 600, "floating", null, null) orelse {
            log.err("Failed to open window: {s}", .{glfw_get_error()});
            std.process.exit(1);
        };

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
        draw.init(&ts.log_memory, &memory.pack);

        //
        // Audio
        //

        sa.setup(.{
            .logger = .{ .func = slog.func },
            .num_channels = 2,
        });

        //
        // Modules
        //
        const module_path = "/home/aj/git/pmd/zig-out/lib";
        const module_name = "game";
        module = Module.init(&ts.arena_persistent, module_path, module_name) catch {
            log.err("Failed to init module: {} at {}", .{ module_name, module_path });
            return;
        };

        module.open() catch |err| {
            log.err("Failed to open module {}", .{err});
            return;
        };
    }

    defer {
        if (ts.is_main()) {
            module.close();
            sa.shutdown();
            draw.deinit();
            c.glfwDestroyWindow(window);
            c.glfwTerminate();
        }
    }

    //
    // Make non-main threads wait here until all global system are initialized
    //

    if (ts.is_main()) {
        std.log.info("main starting others", .{});
        startup_futex.store(1, .release);
        std.Thread.Futex.wake(&startup_futex, @intCast(num_threads - 1));
    } else {
        while (startup_futex.load(.acquire) == 0) {
            std.Thread.Futex.wait(&startup_futex, 0);
        }
    }

    if (!module.function_table.init(&ts, &memory)) {
        log.err("Failed to initialize module: {s}", .{module.name});
        return;
    }
    defer module.function_table.deinit(&ts, &memory);

    //
    // Simulation state
    //

    const desired_frame_time = std.time.ns_per_s / common.target_fps;
    const dt: f32 = 1.0 / @as(f32, @floatFromInt(common.target_fps));
    var tick: u64 = 0;

    // Load all sounds into buffers
    var playing_sounds: BoundedArray(PlayingSound, 64) = .{};

    //
    // Input state
    //

    const max_num_gamepads = c.GLFW_JOYSTICK_LAST + 1;
    const keyboard_input_device_id = c.GLFW_JOYSTICK_LAST + 1;
    var occupied_input_devices = [_]InputDeviceState{.connected} ** (keyboard_input_device_id + 1);
    var debug_gamepad_off: usize = 0;

    timer = std.time.Timer.start() catch unreachable;
    key_repeat_timer = std.time.Timer.start() catch unreachable;

    var frame_start_time: u64 = 0;
    var frame_end_time: u64 = 0;

    // Scan for connected joysticks
    {
        //for (0..@intFromEnum(glfw.Joystick.Id.last)) |i| {
        //    const present = glfw.Joystick.present(.{.jid = @enumFromInt(i)});
        //}
    }

    var connected = false;

    @memset(&memory.console_input.data, 0);

    var old_mouse_pos: v2 = .{ .x = 0.0, .y = 0.0 };

    var running = true;
    while (running) {
        memory.barrier.wait();

        ts.profile.begin_frame();

        if (ts.is_main()) {
            frame_start_time = timer.read();
        }

        log.info("---- Starting tick {} (thread {})", .{ tick, ts.id });

        if (ts.is_main()) {
            memory.windows.head = null;
            memory.windows.tail = null;
            memory.map_mods.used = 0;
        }

        var width: c_int = undefined;
        var height: c_int = undefined;
        if (ts.is_main()) {
            scroll_delta = 0.0;
            c.glfwPollEvents();

            //const frame_stat = memory.time_stats.get(.Frametime).startTime();
            memory.time += desired_frame_time;

            if (c.glfwWindowShouldClose(window) == 1) {
                running = false;
            }

            {
                const reloaded = module.reload_if_changed() catch false;
                if (reloaded) {
                    //_ = module.function_table.fofo();
                }
            }

            c.glfwGetWindowSize(window, &width, &height);
            config.vars.aspect = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));
        }

        if (ts.is_main()) {
            //
            // Read network
            //
            var events: []net.Event = undefined;
            if (server_index) |si| {
                const block_rescv = ts.profile.begin("net receive", 0);
                events = net.receiveMessagesClient(&host, si);
                ts.profile.end(block_rescv);

                //
                // Process network data
                //
                const block_process = ts.profile.begin("net process", 0);
                for (events) |event| {
                    switch (event) {
                        .peer_connected => {
                            // Clear local players and players in game when joining a server
                            for (local_players.slice()) |*lp| {
                                lp.id = null;
                            }
                            memory.players.used = 0;
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
                                    memory.players.append(.{
                                        .id = message.id,
                                    });

                                    var local_player_id: ?usize = null;
                                    for (local_players.slice(), 0..) |*lp, i| {
                                        if (lp.id == null) {
                                            local_player_id = i;
                                            lp.id = message.id;
                                            break;
                                        }
                                    }

                                    std.debug.assert(local_player_id != null);
                                    log.info("Player joined", .{});
                                    log.info("  local player id: {}", .{local_player_id.?});
                                    log.info("  game player id: {}", .{message.id});
                                },
                                .PeerJoined => {
                                    const message: *align(1) packet.PeerJoined = @ptrCast(e.data);
                                    memory.players.append(message.player);
                                    log.info("Player connected {}", .{message.player.id});
                                },
                                .PeerDisconnected => {
                                    const message: *align(1) packet.PeerDisconnected = @ptrCast(e.data);
                                    const index = common.findIndexById(memory.players.slice(), message.id);
                                    if (index != null)
                                        _ = memory.players.swap_remove(index.?);
                                    log.info("Player {} disconnected", .{message.id});
                                },
                                .SpawnPlayer => {
                                    const message: *align(1) packet.SpawnPlayer = @ptrCast(e.data);
                                    const player = common.findPlayerById(&memory.players.data, message.player.id) orelse unreachable;
                                    player.* = message.player;
                                    log.info("Spawning", .{});
                                },
                                .PlayerUpdateAuth => {
                                    const message: *align(1) packet.PlayerUpdateAuth = @ptrCast(e.data);
                                    const local_player = findLocalPlayerById(local_players.slice(), message.player.id);
                                    if (local_player != null) {
                                        const player = common.findPlayerById(&memory.players.data, message.player.id);

                                        var auth_player = message.player;
                                        var offset = @as(i64, @intCast(message.tick)) - @as(i64, @intCast(tick)) + 2;
                                        var auth_memory = memory;
                                        while (offset <= 0) : (offset += 1) {
                                            const old_input = local_player.?.input_buffer.peekRelative(offset);
                                            module.function_table.update(&ts, &config.vars, &auth_memory, &auth_player, old_input, dt);
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
                                        if (common.findPlayerById(&memory.players.data, player.id)) |p| {
                                            p.* = player;
                                        } else {
                                            memory.players.append(player);
                                        }
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
                                            for (local_players.slice()) |lp| {
                                                if (lp.id == s.id_from) {
                                                    local = true;
                                                    break;
                                                }
                                            }
                                            if (local)
                                                continue;
                                        }
                                        memory.new_sounds.append(s);
                                    }
                                },
                                .NewHitscans => {
                                    const message: *align(1) packet.NewHitscans = @ptrCast(e.data);
                                    for (message.new_hitscans[0..message.num_hitscans]) |h| {
                                        var local = false;
                                        for (local_players.slice()) |lp| {
                                            if (lp.id == h.id_from) {
                                                local = true;
                                                break;
                                            }
                                        }
                                        if (local)
                                            continue;
                                        memory.new_hitscans.append(h);
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
                                        memory.map_mods.append(m);
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
                                        memory.entities.append(message.entity);
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
                ts.profile.end(block_process);
            }
        }

        if (ts.is_main()) {
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
                        const block = ts.profile.begin("new player", 0);
                        defer ts.profile.end(block);
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
                                            var lp = LocalPlayer{};
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
                                                memory.players.append(player);

                                                memory.respawns.append(.{
                                                    .id = lp.id.?,
                                                    .time_left = 0.0,
                                                });
                                            }

                                            local_players.append(lp);
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
                                                    var lp = LocalPlayer{};
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
                                                        memory.players.append(player);

                                                        memory.respawns.append(.{
                                                            .id = lp.id.?,
                                                            .time_left = 0.0,
                                                        });
                                                    }

                                                    local_players.append(lp);
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
                        const block = ts.profile.begin("gather input", 0);
                        defer ts.profile.end(block);

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

                            const player = common.findPlayerById(&memory.players.data, lp.id.?);

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
                                    const block_update = ts.profile.begin("update", 0);
                                    defer ts.profile.end(block_update);
                                    module.function_table.update(&ts, &config.vars, &memory, player.?, &lp.input, dt);
                                }
                                if (!connected) {
                                    module.function_table.authorizedPlayerUpdate(&ts, &config.vars, &memory, player.?, &lp.input, dt);
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
                                if (memory.console_input_index < memory.console_input.used and (glfw_get_key(window, .right) == .press or last_key == .right and repeat)) {
                                    memory.console_input_index += 1;
                                }
                                if (memory.console_input_index > 0 and (glfw_get_key(window, .backspace) == .press or last_key == .backspace and repeat)) {
                                    _ = memory.console_input.ordered_remove(memory.console_input_index - 1);
                                    memory.console_input.data[memory.console_input.used] = 0;
                                    memory.console_input_index -= 1;
                                }
                                if (memory.console_input.used < memory.console_input.data.len - 1 and (last_char >= 32 and last_char <= 126 and repeat)) {
                                    memory.console_input.append(@as(u8, @truncate(@as(u32, @intCast(last_char)))));
                                    memory.console_input.data[memory.console_input.used] = 0;
                                    memory.console_input_index += 1;
                                }

                                if (lp.input.isset(.Enter) and memory.console_input.used > 0) {
                                    command.dodododododododo(memory.console_input.slice());
                                    std.log.info("Running command: {s}", .{memory.console_input.slice()});

                                    memory.console_input_index = 0;
                                    memory.console_input.used = 0;
                                    memory.console_input.data[0] = 0;
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
                    for (memory.new_sounds.slice()) |s| {
                        _ = s;
                        //playing_sounds.appendAssumeCapacity(.{
                        //    .samples = sound_file_map[@intFromEnum(s.type)].samples,
                        //    .volume = sound_file_map[@intFromEnum(s.type)].volume,
                        //});
                    }
                    memory.new_sounds.clear();

                    for (memory.new_hitscans.slice()) |h| {
                        memory.hitscans.append(h);
                    }
                    memory.new_hitscans.clear();

                    for (memory.new_nades.slice()) |n| {
                        memory.nades.append(n);
                    }
                    memory.new_nades.clear();

                    for (memory.new_explosions.slice()) |e| {
                        memory.explosions.append(e);
                    }
                    memory.explosions.clear();

                    memory.new_damage.clear();

                    memory.new_spawns.clear();
                }
            }
        }

        if (ts.is_main()) {
            // TODO(anjo): Move to some "lobby" related thing
            if (!connected) {
                module.function_table.authorizedUpdate(&ts, &config.vars, &memory, dt);
            }

            module.function_table.client_update(&ts, &config.vars, &memory, dt);

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
        }

        if (ts.is_main()) {
            //
            // Send network data
            //
            if (server_index) |index| {
                net.process(&host, index);
            }
        }

        //
        // Render
        //
        //{

        memory.barrier.wait();

        {
            {
                const block = ts.profile.begin("draw collect", 0);
                defer ts.profile.end(block);
                for (local_players.slice()) |lp| {
                    if (lp.id == null) {
                        continue;
                    }
                    module.function_table.draw(&ts, &config.vars, &memory, &command_buffer, lp.id.?, &lp.input);
                }
            }
        }

        //ii = 0;
        //asm volatile ("mfence");
        //memory.barrier.wait();
        //asm volatile ("mfence");
        //if (ts.id == 0) {ii += 5;}
        //asm volatile ("mfence");
        //memory.barrier.wait();
        //asm volatile ("mfence");
        //if (ts.id == 1) {ii += 6;}
        //asm volatile ("mfence");
        //memory.barrier.wait();
        //asm volatile ("mfence");
        //if (ts.id == 2) {ii += 7;}
        //asm volatile ("mfence");
        //memory.barrier.wait();
        //std.log.info("ii({}): {}", .{ts.id, ii});
        //std.debug.assert(ii == 18);

        if (ts.is_main()) {
            {
                const block = ts.profile.begin("draw", 0);
                defer ts.profile.end(block);
                draw.process(&command_buffer, @intCast(width), @intCast(height), @intCast(local_players.used));
            }

            c.glfwSwapBuffers(window);
        }

        if (ts.is_main()) {
            //
            // Audio
            //
            {
                const num_needed_samples = 2 * @as(usize, @intCast(sa.expect()));

                var samples = ts.arena_frame.alloc(f32, num_needed_samples);
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
                while (index < playing_sounds.used) {
                    const s = playing_sounds.slice()[index];
                    if (s.index == s.samples.len) {
                        _ = playing_sounds.swap_remove(index);
                    } else {
                        index += 1;
                    }
                }

                if (num_samples > 0)
                    _ = sa.push(&samples[0], @intCast(num_samples));
            }
        }

        memory.barrier.wait();

        if (ts.is_main()) {
            //
            // End of frame
            //

            // In debug mode, check for updates to the pack
            if (build_options.options.debug) {
                if (tick % config.vars.pack_update_check_interval_ns == 0) {
                    const block = ts.profile.begin("pack update", 0);
                    ts.profile.end(block);

                    const entries = disk.collect_and_update_entries(&memory.pack) catch unreachable;
                    for (entries) |e| {
                        std.log.info("- {s}", .{e.name});
                    }
                    if (entries.len > 0) {

                        // builder will be .deinit() from thread which writes to the pack file
                        var builder = goosepack.save_to_memory(&memory.pack);
                        const buffer = ts.arena_frame.alloc(u8, builder.get_size());
                        builder.dump_to_buffer(buffer);
                        memory.pack = .{};
                        goosepack.load(&memory.pack, buffer) catch |err| {
                            log.err("Failed to reload pack {}", .{err});
                        };
                        pack_in_memory = buffer;
                        // Swawn thread which writes to disk
                        // TODO(anjo): when threading
                        //try memory.threadpool.spawn(write_pack_to_file.run, .{ &builder, "res.gp" });

                        // Force recompilation of shaders and etc.
                        draw.resources_update(entries);
                    }
                }
            }
        }

        // Debug profiling and data collection
        {
            ts.profile.end_frame();
            if (!memory.debug_data_collection_paused) {
                // TODO(anjo): ??
                const next = ts.debug_frame_data.peekRelative(1);
                if (next.used) {
                    const s: []common.Profile = @ptrCast(next.profile);
                    ts.arena_persistent.free(s);
                }

                ts.debug_frame_data.push(.{
                    .profile = ts.profile.duplicate(&ts.arena_persistent) catch unreachable,
                    .used = true,
                });
            }
        }

        if (ts.is_main()) {
            tick += 1;

            frame_end_time = timer.read();
            const frame_time = frame_end_time - frame_start_time;

            // Here we shoehorn in some sleeping to not consume all the cpu resources
            {
                const start_sleep = timer.read();
                const time_left = @as(i64, @intCast(desired_frame_time)) - @as(i64, @intCast(frame_time));
                if (time_left > std.time.us_per_s) {
                    // if we have at least 1us left, sleep
                    std.Thread.sleep(@intCast(time_left));
                }

                // spin for the remaining time
                while (timer.read() - start_sleep < time_left) {}
            }
        }

        // clear allocator
        ts.arena_frame.top = 0;
    }

    std.posix.close(host.fd);
}

fn appendSliceAssumeForceDstAlignment(comptime alignment: usize, comptime T: type, bounded_array: anytype, src: []align(alignment) const T) void {
    const old_len = bounded_array.used;
    bounded_array.used = @intCast(bounded_array.used + src.len);
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
            fn run(builder: *common.serialize.StringBuilder, file: []const u8) void {
                builder.dumpToFile(file) catch {};
                builder.deinit();
            }
        }
    else
        struct {};
