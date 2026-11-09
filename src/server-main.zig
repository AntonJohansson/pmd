const std = @import("std");

const core = @import("core.zig");
const gs = @import("common");
const net = @import("net");
const draw = @import("client/draw.zig");
const cl = @import("client/command_meta.zig");

const math = gs.math;
const v2 = math.v2;
const v3 = math.v3;
const m4 = math.m4;

const sokol = @import("sokol");
const sa = sokol.audio;
const slog = sokol.log;

const c = @cImport({
    @cInclude("glfw3.h");
});

pub fn main(init: std.process.Init) !void {
    const args = init.minimal.args.vector;
    const io = init.io;
    core.init(args, io, thread_loop, "conf-server.zon");
}

const PeerData = struct {
    ids: gs.BoundedArray(gs.EntityId, 4) = .{},

    pub fn clear(self: *@This()) void {
        self.ids.used = 0;
    }
};

var peers: [net.max_peer_count]PeerData = undefined;

const NewConnectionData = struct {
    input_buffer: gs.bb.ByteBuffer(1024) = .{},
    address: std.Io.net.IpAddress,
};

var host: net.Host = .{};

//
// main-loop
//

fn thread_loop(module: *const core.Module, io: std.Io) void {
    var log = gs.thread.log_memory.group_log(.general);
    log.info("Starting thread {}", .{gs.thread.id});

    if (gs.thread.is_main()) {
        gs.memory.animation_states = gs.ArrayCircular(gs.AnimationList){
            .data = gs.thread.arena_persistent.alloc(gs.AnimationList, 64),
        };

        host = net.bind(9053) catch return;
    }

    defer {
        if (gs.thread.is_main()) {
            defer _ = std.os.linux.close(host.fd);
        }
    }

    const new_connections: gs.BoundedArray(NewConnectionData, 4) = .{};
    var prng = std.Random.DefaultPrng.init(0);
    const rand = prng.random();

    core.thread_await_main(gs.thread);

    if (!module.function_table.init(gs.system, gs.thread, gs.memory)) {
        log.err("Failed to initialize module: {s}", .{module.name});
        return;
    }
    defer module.function_table.deinit(gs.thread, gs.memory);

    while (gs.thread.should_run.load(.acquire)) {
        core.frame_begin(gs.thread, io);

        if (gs.thread.is_main()) {
            gs.memory.map_mods.used = 0;
        }

        if (gs.thread.is_main()) {
            //
            // Read network
            //
            var events: []net.Event = undefined;
            {
                const block_rescv = gs.thread.profile.begin("net receive", 0);
                events = net.receiveMessagesServer(host.fd);
                gs.thread.profile.end(block_rescv);

                //
                // Process network data
                //
                for (events) |event| {
                    switch (event) {
                        .peer_connected => |e| {
                            log.info("Peer {} connected", .{e.peer_index});
                            peers[e.peer_index].clear();
                            net.pushMessage(e.peer_index, net.packet.Joined{
                                .tick = gs.memory.tick,
                            });
                        },
                        .peer_disconnected => |e| {
                            log.info("Peer {} disconneted", .{e.peer_index});
                            for (peers[e.peer_index].ids.slice()) |id| {
                                const index = gs.findIndexById(gs.memory.players.slice(), id);
                                if (index != null)
                                    _ = gs.memory.players.swap_remove(index.?);
                                // TODO: reliable
                                net.pushMessageToAllPeers(net.packet.PeerDisconnected{
                                    .id = id,
                                });
                            }
                            peers[e.peer_index].clear();
                        },
                        .message_received => |e| {
                            switch (e.kind) {
                                .Pong => {},
                                .Command => {
                                    const message: *align(1) net.packet.Command = @ptrCast(e.data);
                                    std.log.info("Running command: {s}", .{message.data[0..message.len]});
                                    gs.command.dodododododododo(message.data[0..message.len]);

                                    net.pushMessageToAllOtherPeers(e.peer_index, message.*);
                                },
                                .PlayerJoinRequest => {
                                    const message: *align(1) net.packet.PlayerJoinRequest = @ptrCast(e.data);
                                    _ = message;

                                    const player = gs.Player{
                                        .id = gs.newEntityId(),
                                        .pos = .{ .x = 0, .y = 0 },
                                    };

                                    var peer = &peers[e.peer_index];
                                    peer.ids.append(player.id);
                                    gs.memory.players.append(player);

                                    log.info("A new player joined the game: {}", .{player.id});

                                    // Joined response for player trying to connect
                                    net.pushMessage(e.peer_index, net.packet.PlayerJoinResponse{
                                        .id = player.id,
                                    });

                                    // Add to respawn queue
                                    gs.memory.respawns.append(.{
                                        .id = player.id,
                                        .time_left = 1.0,
                                    });

                                    // Send peer joined packet to all other clients
                                    net.pushMessageToAllOtherPeers(e.peer_index, net.packet.PeerJoined{
                                        .player = player,
                                    });

                                    // Send peer joined to packed to new connection, informing of all other clients
                                    for (gs.memory.players.slice()) |p| {
                                        if (p.id == player.id) {
                                            continue;
                                        }
                                        net.pushMessage(e.peer_index, net.packet.PeerJoined{
                                            .player = p,
                                        });
                                    }
                                },
                                .PlayerUpdate => {
                                    const message: *align(1) net.packet.PlayerUpdate = @ptrCast(e.data);
                                    var peer = &peers[e.peer_index];
                                    var found_id = false;
                                    for (peer.ids.slice()) |id| {
                                        if (id == message.id) {
                                            found_id = true;
                                            break;
                                        }
                                    }
                                    if (found_id) {
                                        if (gs.findPlayerById(gs.memory.players.slice(), message.id)) |player| {
                                            const input: gs.Input = message.input;

                                            // Copy player state
                                            player.in_editor = (message.in_editor == 1);

                                            module.function_table.update(gs.thread, &gs.config.vars, gs.memory, player, &input, gs.system.dt);
                                            module.function_table.authorizedPlayerUpdate(gs.thread, &gs.config.vars, gs.memory, player, &input, gs.system.dt);

                                            net.pushMessage(e.peer_index, net.packet.PlayerUpdateAuth{
                                                .tick = message.tick,
                                                .player = player.*,
                                            });

                                            if (gs.memory.map_mods.used > 0) {
                                                std.log.info("sending map mods\n", .{});
                                                var p = net.packet.NewMapMods{};
                                                std.debug.assert(gs.memory.map_mods.used <= p.mods.len);
                                                @memcpy(p.mods[0..gs.memory.map_mods.used], gs.memory.map_mods.slice());
                                                p.num_mods = @intCast(gs.memory.map_mods.used);
                                                net.pushMessageToAllOtherPeers(e.peer_index, p);
                                            }
                                        }
                                    }
                                },
                                .EntityUpdate => {
                                    const message: *align(1) net.packet.EntityUpdate = @ptrCast(e.data);
                                    if (gs.findEntityById(gs.memory.entities.slice(), message.entity.id)) |entity| {
                                        entity.* = message.entity;
                                    } else {
                                        gs.memory.entities.append(message.entity);
                                    }
                                    net.pushMessageToAllOtherPeers(e.peer_index, message.*);
                                },
                                else => {
                                    std.log.err("Unrecognized packet type: {}", .{e.kind});
                                    break;
                                },
                            }
                        },
                    }
                }
            }

            module.function_table.authorizedUpdate(gs.thread, &gs.config.vars, gs.memory, gs.system.dt);
            module.function_table.server_update(&gs.config.vars, gs.memory, gs.system.dt);

            for (gs.memory.entities.slice()) |*e| {
                if (!e.flags.updated_server)
                    continue;
                e.flags.updated_server = false;
                net.pushMessageToAllPeers(net.packet.EntityUpdate{
                    .entity = e.*,
                });
            }

            for (gs.memory.new_spawns.slice()) |p| {
                net.pushMessageToAllPeers(net.packet.SpawnPlayer{
                    .player = p.*,
                });
            }
            gs.memory.new_spawns.clear();

            if (gs.memory.new_damage.used > 0) {
                var p = net.packet.NewDamage{};
                @memcpy(p.new_damage[0..gs.memory.new_damage.used], gs.memory.new_damage.slice());
                p.num_damage = @intCast(gs.memory.new_damage.used);
                gs.memory.new_damage.clear();
                net.pushMessageToAllPeers(p);
            }

            if (gs.memory.new_sounds.used > 0) {
                var p = net.packet.NewSounds{};
                @memcpy(p.new_sounds[0..gs.memory.new_sounds.used], gs.memory.new_sounds.slice());
                p.num_sounds = @intCast(gs.memory.new_sounds.used);
                gs.memory.new_sounds.clear();
                net.pushMessageToAllPeers(p);
            }

            if (gs.memory.new_hitscans.used > 0) {
                for (gs.memory.new_hitscans.slice()) |h| {
                    gs.memory.hitscans.append(h);
                }

                var p = net.packet.NewHitscans{};
                @memcpy(p.new_hitscans[0..gs.memory.new_hitscans.used], gs.memory.new_hitscans.slice());
                p.num_hitscans = @intCast(gs.memory.new_hitscans.used);
                gs.memory.new_hitscans.clear();
                net.pushMessageToAllPeers(p);
            }

            if (gs.memory.new_nades.used > 0) {
                for (gs.memory.new_nades.slice()) |n| {
                    gs.memory.nades.append(n);
                }

                var p = net.packet.NewNades{};
                @memcpy(p.new_nades[0..gs.memory.new_nades.used], gs.memory.new_nades.slice());
                p.num_nades = @intCast(gs.memory.new_nades.used);
                gs.memory.new_nades.clear();
                net.pushMessageToAllPeers(p);
            }

            if (gs.memory.new_explosions.used > 0) {
                for (gs.memory.new_explosions.slice()) |e| {
                    gs.memory.explosions.append(e);
                }

                var p = net.packet.NewExplosions{};
                @memcpy(p.new_explosions[0..gs.memory.new_explosions.used], gs.memory.new_explosions.slice());
                p.num_explosions = @intCast(gs.memory.new_explosions.used);
                gs.memory.explosions.clear();
                net.pushMessageToAllPeers(p);
            }

            if (gs.memory.new_kills.used > 0) {
                for (gs.memory.new_kills.slice()) |k| {
                    net.pushMessageToAllPeers(net.packet.Kill{
                        .from = k.from,
                        .to = k.to,
                    });
                }
                gs.memory.new_kills.clear();
            }
        }

        if (gs.thread.is_main()) {
            //
            // Queue player updates
            //
            net.pushMessageToAllPeers(net.packet.ServerPlayerUpdate{
                .players = gs.memory.players.data,
                .num_players = gs.memory.players.used,
            });

            //
            // Send network data
            //
            {
                //const s = perf_stats.get(.SendNetData).startTime();
                //defer s.endTime();

                _ = rand;
                _ = new_connections;

                net.processServer(&host, gs.memory.time);
            }
        }

        core.frame_end(gs.thread, gs.memory, io);
    }

    log.info("Exiting thread {}", .{gs.thread.id});
}

//
// State
//

pub fn update_game_state(window: ?*c.GLFWwindow, lp: *LocalPlayer, input: *const gs.Input) void {
    switch (active_state(lp)) {
        .gameplay => {
            if (input.isset(.to_editor)) {
                push_state(lp, .editor);
            } else if (input.isset(.to_pause)) {
                c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_HIDDEN);
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
                c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);
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

pub fn active_state(lp: *LocalPlayer) gs.State {
    return lp.state_stack[lp.active_state];
}

pub fn push_state(lp: *LocalPlayer, s: gs.State) void {
    std.debug.assert(lp.active_state + 1 < lp.state_stack.len);
    lp.active_state += 1;
    lp.state_stack[lp.active_state] = s;
}

pub fn pop_state(lp: *LocalPlayer) gs.State {
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

fn setup_mouse_keyboard_input(im: *gs.res.InputMaps) void {
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
    pause.map_mouse_button(.Interact, .tristate, .b1);
    pause.map_mouse_button(.AltInteract, .rising_edge, .b2);
    pause.map_key(.to_console, .rising_edge, .grave_accent);
    pause.map_key(.to_pause, .rising_edge, .escape);

    const console = im.get(.console);
    console.map_key(.Enter, .rising_edge, .enter);
    console.map_key(.to_console, .rising_edge, .grave_accent);
}

fn setup_gamepad_input(im: *gs.res.InputMaps) void {
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

fn setup_input_maps(pack: *gs.goosepack.Pack, im: *gs.res.InputMaps, t: InputMapsType) void {
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
    const num_inputs = @typeInfo(gs.InputName).@"enum".fields.len;
    const num_states = @typeInfo(gs.State).@"enum".fields.len;

    active_state: u8 = 0,
    state_stack: [num_states]gs.State = .{.gameplay} ** num_states,
    from_state: gs.State = .gameplay,

    input_device: ?InputDevice = null,
    input_device_id: ?usize = null,
    input_maps: ?gs.res.InputMaps = null,
    input: gs.Input = undefined,

    last_input_actions: [num_inputs]gs.res.Action = .{.release} ** num_inputs,

    // TODO: We only need to allocate this when on network
    input_buffer: gs.bb.CircularBuffer(gs.Input, 256) = .{},

    id: ?gs.EntityId = null,
};

fn findLocalPlayerById(lp: []LocalPlayer, id: gs.EntityId) ?*LocalPlayer {
    for (lp) |*l| {
        if (l.id != null and l.id.? == id)
            return l;
    }
    return null;
}

//
// GLFW interfacing
//

fn glfw_get_error() [*:0]u8 {
    var desc: [*:0]u8 = undefined;
    _ = c.glfwGetError(@ptrCast(&desc));
    return desc;
}

fn glfw_get_key(window: ?*c.GLFWwindow, key: gs.res.Key) gs.res.Action {
    return @enumFromInt(c.glfwGetKey(window, @intFromEnum(key)));
}

var key_repeat_timer: u64 = 0;
var last_key: gs.res.Key = undefined;
var last_char: u8 = 0;
var repeat = false;
var last_key_down = false;

var capture_text = false;
var wait_for_first_key_input = true;
fn charCallback(window: ?*c.GLFWwindow, codepoint: c_uint) callconv(.c) void {
    if (!capture_text and !wait_for_first_key_input) {
        return;
    }

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
    if (codepoint >= 0x80) {
        return;
    }

    last_char = @truncate(codepoint);
    repeat = false;
    const time: *align(1) u64 = @ptrCast(c.glfwGetWindowUserPointer(window));
    key_repeat_timer = time.*;
    if (!(last_char >= 32 and last_char <= 126) or last_char == '`')
        return;

    if (wait_for_first_key_input) {
        wait_for_first_key_input = false;
        return;
    }

    if (gs.memory.console_input.used < gs.memory.console_input.data.len - 1) {
        gs.memory.console_input.append(@as(u8, @truncate(@as(u32, @intCast(last_char)))));
        gs.memory.console_input.data[gs.memory.console_input.used] = 0;
        gs.memory.console_input_index += 1;
    }
}

var scroll_delta: f32 = 0.0;
fn scrollCallback(window: ?*c.GLFWwindow, dx: f64, dy: f64) callconv(.c) void {
    _ = window;
    _ = dx;
    scroll_delta = @floatCast(dy);
}

//
// ?
//
fn appendSliceAssumeForceDstAlignment(comptime alignment: usize, comptime T: type, bounded_array: anytype, src: []align(alignment) const T) void {
    const old_len = bounded_array.used;
    bounded_array.used = @intCast(bounded_array.used + src.len);
    @memcpy(@as([]align(alignment) T, @ptrCast(bounded_array.slice()[old_len..][0..src.len])), src);
}
