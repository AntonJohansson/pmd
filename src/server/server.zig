const std = @import("std");

const net = @import("net");
const packet = net.packet;
const packet_meta = net.packet_meta;

const common = @import("common");
const Memory = common.Memory;
const Player = common.Player;
const EntityId = common.EntityId;
const Input = common.Input;
const InputType = common.InputType;
const bb = common.bb;
const threadpool = common.threadpool;
const stat = common.stat;
const code_module = common.code_module;
const command = common.command;

const config = common.config;
const Vars = config.Vars;
const vars = &config.vars;

const math = common.math;
const v3 = math.v3;

const logging = common.logging;
var log: logging.Log = .{
    .mirror_to_stdio = true,
};

const PeerData = struct {
    ids: std.BoundedArray(EntityId, 4) = .{},

    pub fn clear(self: *@This()) void {
        self.ids.len = 0;
    }
};

var peers: [net.max_peer_count]PeerData = undefined;

const NewConnectionData = struct {
    input_buffer: bb.ByteBuffer(1024) = .{},
    address: std.net.Address,
};

pub fn main() !void {
    var memory: Memory = .{};

    // Setup the allocators we'll be using
    // 1. GeneralPurposeAllocator for persitent data that will exist accross frames
    //    and has to be freed manually.
    // 2. ArenaAllocator for temporary data that during a frame
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    memory.mem.frame = arena_allocator.allocator();
    memory.mem.persistent = general_purpose_allocator.allocator();

    net.mem = memory.mem;

    var module = try code_module.CodeModule(struct {
        update: *fn (vars: *const Vars, memory: *Memory, player: *Player, input: *const Input, dt: f32) void,
        authorizedPlayerUpdate: *fn (vars: *const Vars, memory: *Memory, player: *Player, input: *const Input, dt: f32) void,
        authorizedUpdate: *fn (vars: *const Vars, memory: *Memory, dt: f32) void,
        draw: *fn (memory: *Memory) void,
    }).init(memory.mem.persistent, "zig-out/lib", "game");

    // TODO(anjo): Pass module name through compile time constants and don't rely on trying to
    // guess the name
    module.open(memory.mem.persistent) catch {
        log.err("Failed to open module: {s}", .{module.name});
        return;
    };
    defer module.close();

    const host = net.bind(9053) orelse return;
    defer std.os.closeSocket(host.fd);

    var new_connections: std.BoundedArray(NewConnectionData, 4) = .{};

    const fps = 165;
    const desired_frame_time = std.time.ns_per_s / fps;
    const dt: f32 = 1.0 / @as(f32, @floatFromInt(fps));

    var tick: u64 = 0;
    //const dt: f32 = 1.0/@intToFloat(f32, fps);
    var running = true;

    const crand = std.crypto.random;
    var prng = std.rand.DefaultPrng.init(crand.int(u64));
    const rand = prng.random();

    //var print_perf = false;

    var timer = try std.time.Timer.start();
    var actual_timer = try std.time.Timer.start();
    var frame_start_time: u64 = 0;
    var frame_end_time: u64 = 0;

    while (running) {
        frame_start_time = timer.read();

        //log.info("---- Starting tick {}", .{tick});

        {
            {
                if (try module.reloadIfChanged(memory.mem.persistent)) {
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
                                command.dodododododododo( message.data[0..message.len]);

                                net.pushMessageToAllOtherPeers(e.peer_index, message.*);
                            },
                            .PlayerJoinRequest => {
                                const message: *align(1) packet.PlayerJoinRequest = @ptrCast(e.data);
                                _ = message;

                                const player = try memory.players.addOne();

                                var peer = &peers[e.peer_index];
                                const id = try peer.ids.addOne();
                                id.* = common.newEntityId();
                                player.id = id.*;

                                log.info("A new player joined the game: {}", .{id.*});

                                // Joined response for player trying to connect
                                net.pushMessage(e.peer_index, packet.PlayerJoinResponse{
                                    .id = id.*,
                                });

                                // Add to respawn queue
                                memory.respawns.appendAssumeCapacity(.{
                                    .id = id.*,
                                    .time_left = 1.0,
                                });

                                // Send peer joined packet to all other clients
                                net.pushMessageToAllOtherPeers(e.peer_index, packet.PeerJoined{
                                    .player = player.*,
                                });

                                // Send peer joined to packed to new connection, informing of all other clients
                                for (memory.players.slice()) |p| {
                                    if (p.id == id.*)
                                        continue;
                                    net.pushMessage(e.peer_index, packet.PeerJoined{
                                        .player = p,
                                    });
                                }
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
                                        module.function_table.update(vars, &memory, player, &input, dt);
                                        module.function_table.authorizedPlayerUpdate(vars, &memory, player, &input, dt);
                                        net.pushMessage(e.peer_index, packet.PlayerUpdateAuth{
                                            .tick = message.tick,
                                            .player = player.*,
                                        });
                                    }
                                }
                            },
                            .EntityUpdate => {
                                const message: *align(1) packet.EntityUpdate = @ptrCast(e.data);
                                if (common.findEntityById(memory.entities.slice(), message.entity.id)) |entity| {
                                    entity.* = message.entity;
                                } else {
                                    memory.entities.appendAssumeCapacity(message.entity);
                                }
                                net.pushMessageToAllOtherPeers(e.peer_index, message.*);
                            },
                            else => {
                                std.log.err("Unrecognized packet type: {}", .{e.kind});
                                break;
                            },
                        }
                    }
                }
            }

            module.function_table.authorizedUpdate(vars, &memory, dt);

            for (memory.entities.slice()) |*e| {
                if (!e.flags.updated_server)
                    continue;
                e.flags.updated_server = false;
                net.pushMessageToAllPeers(packet.EntityUpdate {
                    .entity = e.*,
                });
            }

            for (memory.new_spawns.constSlice()) |p| {
                net.pushMessageToAllPeers(packet.SpawnPlayer{
                    .player = p.*,
                });
            }
            memory.new_spawns.resize(0) catch unreachable;

            if (memory.new_damage.len > 0) {
                var p = packet.NewDamage {};
                @memcpy(p.new_damage[0..memory.new_damage.len], memory.new_damage.constSlice());
                p.num_damage = memory.new_damage.len;
                memory.new_damage.resize(0) catch unreachable;
                net.pushMessageToAllPeers(p);
            }

            if (memory.new_sounds.len > 0) {
                var p = packet.NewSounds {};
                @memcpy(p.new_sounds[0..memory.new_sounds.len], memory.new_sounds.constSlice());
                p.num_sounds = memory.new_sounds.len;
                memory.new_sounds.resize(0) catch unreachable;
                net.pushMessageToAllPeers(p);
            }

            if (memory.new_hitscans.len > 0) {
                for (memory.new_hitscans.constSlice()) |h| {
                    memory.hitscans.appendAssumeCapacity(h);
                }

                var p = packet.NewHitscans {};
                @memcpy(p.new_hitscans[0..memory.new_hitscans.len], memory.new_hitscans.constSlice());
                p.num_hitscans = memory.new_hitscans.len;
                memory.new_hitscans.resize(0) catch unreachable;
                net.pushMessageToAllPeers(p);
            }

            if (memory.new_nades.len > 0) {
                for (memory.new_nades.constSlice()) |n| {
                    memory.nades.appendAssumeCapacity(n);
                }

                var p = packet.NewNades {};
                @memcpy(p.new_nades[0..memory.new_nades.len], memory.new_nades.constSlice());
                p.num_nades = memory.new_nades.len;
                memory.new_nades.resize(0) catch unreachable;
                net.pushMessageToAllPeers(p);
            }

            if (memory.new_explosions.len > 0) {
                for (memory.new_explosions.constSlice()) |e| {
                    memory.explosions.appendAssumeCapacity(e);
                }

                var p = packet.NewExplosions {};
                @memcpy(p.new_explosions[0..memory.new_explosions.len], memory.new_explosions.constSlice());
                p.num_explosions = memory.new_explosions.len;
                memory.explosions.resize(0) catch unreachable;
                net.pushMessageToAllPeers(p);
            }

            if (memory.new_kills.len > 0) {
                for (memory.new_kills.constSlice()) |k| {
                    net.pushMessageToAllPeers(packet.Kill{
                        .from = k.from,
                        .to = k.to,
                    });
                }
                memory.new_kills.resize(0) catch unreachable;
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
                //const s = perf_stats.get(.SendNetData).startTime();
                //defer s.endTime();

                _ = rand;
                _ = new_connections;

                net.processServer(&host);
            }

            //
            // End of frame
            //

            tick += 1;

            frame_end_time = timer.read();
            const frame_time = frame_end_time - frame_start_time;

            // Here we shoehorn in some sleeping to not consume all the cpu resources
            {
                const start_sleep = timer.read();
                var time_left = @as(i64, @intCast(desired_frame_time)) - @as(i64, @intCast(frame_time));
                if (time_left > std.time.us_per_s) {
                    // if we have at least 1us left, sleep
                    std.time.sleep(@intCast(time_left));
                }

                // spin for the remaining time
                while (timer.read() - start_sleep < time_left) {}
            }

            _ = arena_allocator.reset(.retain_capacity);

        }

        if (actual_timer.read() >= 2*std.time.ns_per_s) {
            actual_timer.reset();

            //if (print_perf) {
            //    for (&perf_stats.stat_data, 0..) |*s,i| {
            //        const result = s.mean_std();
            //        std.log.info("{s:20} {:10} {:10}", .{@tagName(@as(perf_stats.enum_type, @enumFromInt(i))), result.avg, result.std});
            //    }
            //    std.log.info("----------", .{});
            //    for (&time_stats.stat_data, 0..) |*s,i| {
            //        const result = s.mean_std();
            //        std.log.info("{s:20} {:10} {:10}", .{@tagName(@as(time_stats.enum_type, @enumFromInt(i))), result.avg, result.std});
            //    }
            //    std.log.info("----------", .{});
            //    for (&net.net_stats.stat_data, 0..) |*s,i| {
            //        const result = s.mean_std();
            //        std.log.info("{s:20} {:10} {:10}", .{@tagName(@as(net.net_stats.enum_type, @enumFromInt(i))), result.avg, result.std});
            //    }
            //    std.log.info("----------", .{});
            //}
        }
    }
}
