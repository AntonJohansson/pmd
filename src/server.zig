const std = @import("std");
const packet = @import("packet.zig");
const bb = @import("bytebuffer.zig");
const net = @import("net.zig");
const threadpool = @import("threadpool.zig");
const stat = @import("stat.zig");
const packet_meta = @import("packet_meta.zig");
const code_module = @import("code_module.zig");

const config = @import("config.zig");
const Vars = config.Vars;
const vars = &config.vars;

const command = @import("command.zig");

const math = @import("math.zig");
const v3 = math.v3;

const common = @import("common.zig");
const Memory = common.Memory;
const Player = common.Player;
const PlayerId = common.PlayerId;
const Input = common.Input;
const InputType = common.InputType;


const logging = @import("logging.zig");
var log: logging.Log = .{
    .mirror_to_stdio = true,
};

const PeerData = struct {
    ids: std.BoundedArray(PlayerId, 4) = .{},

    pub fn clear(self: *@This()) void {
        self.ids.len = 0;
    }
};

var peers: [net.max_peer_count]PeerData = undefined;

var perf_stats : stat.AllStatData(enum(usize) {
    Timeout,
    ReadNetData,
    ProcessNetData,
    SendNetData,
}) = .{};

var time_stats : stat.AllStatData(enum(usize) {
    Frametime,
}) = .{};

const NewConnectionData = struct {
    input_buffer: bb.ByteBuffer(1024) = .{},
    address: std.net.Address,
};

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();

    net.temp_allocator = gpa;

    var module = try code_module.CodeModule(struct {
        update: *fn (vars: *const Vars, memory: *Memory, player: *Player, input: *const Input) void,
        draw: *fn (memory: *Memory) void,
    }).init(gpa, "zig-out/lib", "libgame");

    try module.open(gpa);
    defer module.close();

    const host = net.bind(gpa, 9053) orelse return;
    defer std.os.closeSocket(host.fd);

    var new_connections: std.BoundedArray(NewConnectionData, 4) = .{};

    const fps = 165;
    const desired_frame_time = std.time.ns_per_s / fps;

    var tick: u64 = 0;
    //const dt: f32 = 1.0/@intToFloat(f32, fps);
    var running = true;

    const crand = std.crypto.random;
    var prng = std.rand.DefaultPrng.init(crand.int(u64));
    const rand = prng.random();

    var print_perf = false;

    var timer = try std.time.Timer.start();
    var actual_timer = try std.time.Timer.start();
    var frame_start_time: u64 = 0;
    var accumulator: u64 = 0;

    var memory: Memory = .{};

    while (running) {
        const frame_end_time = timer.read();
        const frame_time = frame_end_time - frame_start_time;
        frame_start_time = frame_end_time;
        accumulator += frame_time;

        while (accumulator >= desired_frame_time) {
            if (accumulator >= desired_frame_time) {
                accumulator -= desired_frame_time;
            } else {
                accumulator = 0;
            }

            const frame_stat = time_stats.get(.Frametime).startTime();

            {
                if (try module.reloadIfChanged(gpa)) {
                    //_ = module.function_table.fofo();
                }
            }

            //
            // Read network
            //
            var events: []net.Event = undefined;
            {
                events = net.receiveMessagesServer(host.fd);
            }

            //
            // Process network data
            //
            for (events) |event| {
                switch (event) {
                    .peer_connected => |e| {
                        log.info("Peer {} connected", .{e.peer_index});
                        peers[e.peer_index].clear();
                        net.pushMessage(e.peer_index, packet.Joined {
                            .tick = tick,
                        });
                    },
                    .peer_disconnected => |e| {
                        log.info("Peer {} disconneted", .{e.peer_index});
                        for (peers[e.peer_index].ids.slice()) |id| {
                            const index = common.findIndexById(memory.players.slice(), id);
                            if (index != null)
                                _ = memory.players.swapRemove(index.?);
                            // TODO: reliable
                            net.pushMessageToAllPeers(packet.PeerDisconnected {
                                .id = id,
                            });
                        }
                        peers[e.peer_index].clear();
                    },
                    .message_received => |e| {
                        switch (e.kind) {
                            .Pong => {
                            },
                            .Command => {
                                const message: *align(1) packet.Command = @ptrCast(e.data);
                                std.log.info("Running command: {s}", .{message.data[0..message.len]});
                                command.dodododododododo(null, message.data[0..message.len]);

                                net.pushMessageToAllOtherPeers(e.peer_index, message.*);
                            },
                            .PlayerJoinRequest => {
                                const message: *align(1) packet.PlayerJoinRequest = @ptrCast(e.data);
                                _ = message;

                                const player = try memory.players.addOne();

                                var peer = &peers[e.peer_index];
                                const id = try peer.ids.addOne();
                                id.* = common.newPlayerId();
                                player.id = id.*;
                                player.pos = v3 {.x = 0, .y = 0, .z = 0};
                                player.vel = v3 {.x = 0, .y = 0, .z = 0};
                                player.dir = v3 {.x = 1, .y = 0, .z = 0};
                                player.yaw = 0;
                                player.pitch = 0;

                                log.info("A new player joined the game: {}", .{id.*});

                                net.pushMessage(e.peer_index, packet.PlayerJoinResponse{
                                    .player = player.*,
                                });

                                net.pushMessageToAllOtherPeers(e.peer_index, packet.PeerJoined{
                                    .player = player.*,
                                });
                            },
                            .PlayerUpdate => {
                                const message: *align(1) packet.PlayerUpdate = @ptrCast(e.data);
                                var peer = &peers[e.peer_index];
                                var found_id = false;
                                for (peer.ids.slice()) |id| {
                                    if (id == message.id) {
                                        found_id = true;
                                        break;
                                    }
                                }
                                if (found_id) {
                                    if (common.findPlayerById(memory.players.slice(), message.id)) |player| {
                                        const input: Input = message.input;
                                        module.function_table.update(vars, &memory, player, &input);
                                        net.pushMessage(e.peer_index, packet.PlayerUpdateAuth{
                                            .tick = message.tick,
                                            .player = player.*,
                                        });
                                    }
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
            // Queue player updates
            //
            net.pushMessageToAllPeers(packet.ServerPlayerUpdate{
                .players = memory.players.buffer,
                .num_players = memory.players.len,
            });

            //
            // Send network data
            //
            {
                const s = perf_stats.get(.SendNetData).startTime();
                defer s.endTime();

                _ = rand;
                _ = new_connections;

                net.processServer(&host);
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

        if (actual_timer.read() >= 2*std.time.ns_per_s) {
            actual_timer.reset();

            if (print_perf) {
                for (&perf_stats.stat_data, 0..) |*s,i| {
                    const result = s.mean_std();
                    std.log.info("{s:20} {:10} {:10}", .{@tagName(@as(perf_stats.enum_type, @enumFromInt(i))), result.avg, result.std});
                }
                std.log.info("----------", .{});
                for (&time_stats.stat_data, 0..) |*s,i| {
                    const result = s.mean_std();
                    std.log.info("{s:20} {:10} {:10}", .{@tagName(@as(time_stats.enum_type, @enumFromInt(i))), result.avg, result.std});
                }
                std.log.info("----------", .{});
                for (&net.net_stats.stat_data, 0..) |*s,i| {
                    const result = s.mean_std();
                    std.log.info("{s:20} {:10} {:10}", .{@tagName(@as(net.net_stats.enum_type, @enumFromInt(i))), result.avg, result.std});
                }
                std.log.info("----------", .{});
            }
        }
    }
}
