const std = @import("std");
const os = std.os;
const posix = std.posix;

pub const headers = @import("headers.zig");
pub const packet = @import("packet.zig");
pub const packet_meta = @import("packet_meta.zig");

const common = @import("common");
const BoundedArray = common.BoundedArray;
const bb = common.bb;
const stat = common.stat;

var log: common.log.GroupLog(.net) = undefined;

const ClientHost = struct {
    fd: std.posix.socket_t,
};

pub const DebugState = struct {
    rand: std.Random,
    delay: u64,
    dropchance: f32,
};

const PacketData = struct {
    acked: bool = false,
    ids: BoundedArray(u16, 64) = .{},
};

pub const LogEntry = struct {
    data: []const u8,
    address: ?std.net.Address = null,
    repeat: u8 = 1,
    push_time: u64 = 0,
};

const ReliableMessageInfo = struct {
    acked: bool = false,
    id: u16,
    data: []const u8,
    reliable: bool,
};

pub var mem: common.MemoryAllocators = .{};

pub var input_buffer_stat: stat.StatEntry = .{};
pub var output_buffer_stat: stat.StatEntry = .{};

pub const Host = struct {
    state: PeerState = .Disconnected,
    fd: std.posix.socket_t = undefined,
};

pub fn init(log_memory: *common.log.LogMemory) void {
    log = log_memory.group_log(.net);
}

pub fn bind(port: u16) ?Host {
    const addr_list = std.net.getAddressList(mem.frame, "0.0.0.0", port) catch return null;
    defer addr_list.deinit();

    const flags = posix.SOCK.DGRAM | posix.SOCK.CLOEXEC | posix.SOCK.NONBLOCK;
    for (addr_list.addrs) |a| {
        const fd = posix.socket(a.any.family, flags, 0) catch continue;
        posix.bind(fd, &a.any, a.getOsSockLen()) catch {
            posix.close(fd);
            continue;
        };
        return Host{
            .fd = fd,
        };
    }

    return null;
}

pub fn connect(host: *Host, ip: []const u8, port: u16) ?PeerIndex {
    const addr_list = std.net.getAddressList(mem.frame, ip, port) catch |err| {
        log.err("Failed to get address list ({})", .{err});
        return null;
    };
    defer addr_list.deinit();

    const flags = posix.SOCK.DGRAM | posix.SOCK.CLOEXEC | posix.SOCK.NONBLOCK;
    for (addr_list.addrs) |a| {
        const fd = posix.socket(a.any.family, flags, 0) catch |err| {
            log.info("Failed to create socket with flags {} ({})", .{ flags, err });
            continue;
        };
        posix.connect(fd, &a.any, a.getOsSockLen()) catch |err| {
            log.info("Failed to connect ({})", .{err});
            posix.close(fd);
            continue;
        };
        host.fd = fd;
        const peer_index = findAvailablePeerIndex();
        var peer = &peers.data[peer_index];
        peer.state = .Connecting;
        return peer_index;
    }

    return null;
}

pub fn disconnect(index: PeerIndex) void {
    var peer = &peers.data[index];
    std.debug.assert(peer.state != .Disconnected);

    // TODO(anjo): Send disconnect packet

    peer.state = .Disconnected;
}

pub fn pushMessage(index: PeerIndex, message: anytype) void {
    var peer = &peers.data[index];
    std.debug.assert(peer.state != .Disconnected);

    //const message_id = peer.current_message_id;
    //peer.current_message_id +%= 1;

    // Will be set to null again at the end of the frame in process
    if (peer.frame_bytes == null) {
        peer.frame_bytes = common.serialize.StringBuilder.init(mem.frame);
    }

    const kind = comptime packet_meta.mapMessageToKind(@TypeOf(message));
    common.serialize.memory_write_type(&peer.frame_bytes.?, headers.Header{
        .kind = kind,
        .id = 0,
        .reliable = false,
    }) catch {};
    common.serialize.memory_write_type(&peer.frame_bytes.?, message) catch {};
}

pub fn pushReliableMessage(index: PeerIndex, message: anytype) void {
    var peer = &peers.data[index];
    std.debug.assert(peer.state != .Disconnected);

    const message_id = peer.current_message_id;
    peer.current_message_id +%= 1;

    const builder = common.serialize.StringBuilder.init(mem.frame);
    const kind = comptime packet_meta.mapMessageToKind(@TypeOf(message));
    common.serialize.memory_write_type(&builder, headers.Header{
        .kind = kind,
        .id = message_id,
        .reliable = false,
    }) catch {};
    common.serialize.memory_write_type(&builder, message) catch {};

    const memory = builder.dump_to_buffer(mem.persistent);

    peer.messages_in_flight.set(message_id, ReliableMessageInfo{
        .id = message_id,
        .data = memory,
        .reliable = true,
    });
}

pub fn pushMessageToAllPeers(message: anytype) void {
    for (peers.data, 0..) |entry, i| {
        if (entry.state != .Connected)
            continue;
        pushMessage(@intCast(i), message);
    }
}

pub fn pushReliableMessageToAllPeers(message: anytype) void {
    for (peers.data, 0..) |entry, i| {
        if (entry.state != .Connected)
            continue;
        pushReliableMessage(@intCast(i), message);
    }
}

pub fn pushReliableMessageToAllOtherPeers(index: PeerIndex, message: anytype) void {
    for (peers.data, 0..) |entry, i| {
        if (entry.state != .Connected or i == index)
            continue;
        pushReliableMessage(@intCast(i), message);
    }
}

pub fn pushMessageToAllOtherPeers(index: PeerIndex, message: anytype) void {
    for (peers.data, 0..) |entry, i| {
        if (entry.state != .Connected or i == index)
            continue;
        pushMessage(@intCast(i), message);
    }
}

const ReceivedMessageInfo = struct {
    acked: bool = false,
    kind: packet_meta.MessageKind,
    data: []u8,
};

const ReceivedData = struct {
    peer_index: PeerIndex,
    packet_header: headers.BatchHeader,
    data: []u8,
};

const PeerState = enum(u8) {
    Disconnected,
    Connected,
    Connecting,
};

const peer_timeout = 5 * std.time.ns_per_s;

const message_receive_buffer_len = 255;

const Peer = struct {
    state: PeerState = .Disconnected,
    address: ?std.net.Address = null,
    timeout: u64 = 0,
    salt: u64 = 0,
    received_messages: bb.SequenceBuffer(ReceivedMessageInfo, u16, message_receive_buffer_len) = .{},
    packets_in_flight: bb.SequenceBuffer(PacketData, u16, message_receive_buffer_len) = .{},
    messages_in_flight: bb.SequenceBuffer(ReliableMessageInfo, u16, message_receive_buffer_len) = .{},
    frame_bytes: ?common.serialize.StringBuilder = null,

    current_packet_id: u16 = 0,
    current_message_id: u16 = 0,

    last_incoming_acked_packet_id: u16 = 0,
    last_outgoing_acked_packet_id: u16 = 0,
    last_outgoing_acked_message_id: u16 = 0,

    ack_bits: u32 = 0,
};

pub const max_peer_count = 255;

pub const PeerIndex = u8;
pub var peers: BoundedArray(Peer, max_peer_count) = .{};

fn findPeerIndex(address: std.net.Address) ?PeerIndex {
    for (peers.data, 0..) |entry, i| {
        if (entry.state != .Disconnected and entry.address != null and entry.address.?.eql(address)) {
            return @intCast(i);
        }
    }
    return null;
}

fn findAvailablePeerIndex() PeerIndex {
    std.debug.assert(peers.used < peers.data.len);
    for (peers.data, 0..) |entry, i|
        if (entry.state == .Disconnected)
            return @intCast(i);
    unreachable;
}

// TODO(anjo): We can make a better assumption as to the
// size of this buffer from connected_peers*sizeof(expected_traffic)*safety_factor.
// and push it via the temporary_allocator
var input_buffer: bb.ByteBuffer(8192) = .{};

pub fn receiveMessagesClient(host: *const Host, peer_index: PeerIndex) []Event {
    input_buffer.clear();
    while (true) {
        const nbytes = posix.recvfrom(host.fd, input_buffer.remainingData(), 0, null, null) catch 0;
        if (nbytes == 0) {
            break;
        }
        input_buffer.top += @intCast(nbytes);
    }

    log.info("Received {} bytes", .{input_buffer.top});

    var received_data: BoundedArray(ReceivedData, 128) = .{};
    var offset: usize = 0;
    while (input_buffer.hasData()) {
        var packet_header: headers.BatchHeader = undefined;
        common.serialize.memory_read_type(mem.frame, headers.BatchHeader, &input_buffer.data, &offset, &packet_header);

        if (input_buffer.size() < packet_header.size) {
            log.info("Received partial packet {}/{} bytes", .{ input_buffer.size(), packet_header.size });
            break;
        }
        if (packet_header.num_packets == 0) {
            log.info("Recieved empty packet", .{});
            break;
        }

        log.info("  Contains packet", .{});
        log.info("    num messages {}", .{packet_header.num_packets});
        log.info("    size {}", .{packet_header.size});

        const data = input_buffer.data[offset..packet_header.size];
        offset += packet_header.size;

        received_data.append(ReceivedData{
            .peer_index = 0,
            .packet_header = packet_header,
            .data = data,
        }) catch unreachable;
    }

    var peer = &peers.data[peer_index];

    var num_events: usize = 0;
    var events = mem.frame.alloc(Event, 128) catch unreachable;

    // TODO(anjo): This might be candidate for threading if there
    // are enough entries.
    log.info("Processing packets", .{});
    for (received_data.slice()) |data| {
        // TODO(anjo): Verify packet here

        if (data.packet_header.reliable) {
            ack(peer, data.packet_header.id);
        }
        process_ack(data.peer_index, data.packet_header);

        log.info("  packet id: {}", .{data.packet_header.id});

        // iterate over all message headers
        var i: u16 = 0;
        var message_offset: usize = 0;
        while (message_offset < data.data.len and i < data.packet_header.num_packets) : (i += 1) {
            var header: headers.Header = undefined;
            common.serialize.memory_read_type(mem.frame, headers.Header, data.data, &message_offset, &header);

            const size = packet_meta.getMessageSize(header.kind);
            const message = packet_meta.decodeKind(mem.frame, data.data, &message_offset, header.kind) catch unreachable;

            log.info("  Message", .{});
            log.info("    size: {}", .{size});
            log.info("    kind: {}", .{header.kind});

            if (!header.reliable or peer.received_messages.get(header.id) == null) {
                peer.received_messages.set(header.id, ReceivedMessageInfo{
                    .kind = header.kind,
                    .data = message,
                });
            }
        }
    }

    var has_sent_challenge = false;

    //
    // We deal with connections here, no need to force
    // the caller to handle it, we return an event instead.
    //
    if (peer.state == .Connecting) {
        var i: u16 = 0;
        while (i < peer.received_messages.data.len) : (i += 1) {
            if (peer.received_messages.isset(i) and !peer.received_messages.data[i].acked) {
                const rmi = peer.received_messages.data[i];
                peer.received_messages.data[i].acked = true;

                switch (rmi.kind) {
                    .ConnectionChallenge => {
                        const message: *align(1) packet.ConnectionChallenge = @ptrCast(rmi.data.ptr);
                        if (!has_sent_challenge) {
                            has_sent_challenge = true;
                            peer.salt = message.client_salt ^ message.server_salt;
                            pushMessage(peer_index, packet.ConnectionChallengeResponse{
                                .salt = peer.salt,
                            });
                            log.info("Received challenge, sending response", .{});
                        }
                    },
                    .ConnectionSuccessful => {
                        _ = input_buffer.pop(packet.ConnectionSuccessful);
                        if (peer.state == .Connecting) {
                            peer.state = .Connected;

                            events[num_events] = Event{
                                .peer_connected = .{
                                    .peer_index = peer_index,
                                },
                            };
                            num_events += 1;
                            log.info("connection successful", .{});
                        }
                    },
                    .ConnectionDenied => {
                        _ = input_buffer.pop(packet.ConnectionDenied);
                        peer.state = .Disconnected;
                        log.info("connection denied", .{});
                    },
                    else => continue,
                }

                peer.received_messages.unset(i);
            }
        }
    } else if (peer.state == .Connected) {
        //
        // Collection of messages into events
        //

        var i: u16 = 0;
        while (i < peer.received_messages.data.len) : (i += 1) {
            if (peer.received_messages.isset(i) and !peer.received_messages.data[i].acked) {
                const rmi = peer.received_messages.data[i];
                peer.received_messages.data[i].acked = true;
                events[num_events] = Event{
                    .message_received = .{
                        .peer_index = peer_index,
                        .kind = rmi.kind,
                        .data = rmi.data,
                    },
                };
                //peer.received_messages.unset(i);
                num_events += 1;
            }
        }
    }

    return events[0..num_events];
}

pub const MessageReceivedEvent = struct {
    peer_index: PeerIndex,
    kind: packet_meta.MessageKind,
    data: []u8,
};

pub const PeerConnectedEvent = struct {
    peer_index: PeerIndex,
};

pub const PeerDisconnectedEvent = struct {
    peer_index: PeerIndex,
};

pub const Event = union(enum) {
    message_received: MessageReceivedEvent,
    peer_connected: PeerConnectedEvent,
    peer_disconnected: PeerDisconnectedEvent,
};

pub fn receiveMessagesServer(fd: std.posix.socket_t) []Event {
    var their_sa: posix.sockaddr.storage = undefined;
    var sl: u32 = @sizeOf(posix.sockaddr.storage);
    var received_data: BoundedArray(ReceivedData, 128) = .{};
    var num_events: usize = 0;
    var events = mem.frame.alloc(Event, 128) catch unreachable;

    // Timeout disconnected peers
    for (&peers.data, 0..) |*peer, i| {
        if (peer.state == .Disconnected)
            continue;
        if (peer.timeout < std.time.ns_per_s / common.target_tickrate) {
            pushMessage(@intCast(i), packet.ConnectionTimeout{});
            events[num_events] = Event{
                .peer_disconnected = .{
                    .peer_index = @intCast(i),
                },
            };
            num_events += 1;
            peer.state = .Disconnected;
        } else {
            peer.timeout -= std.time.ns_per_s / common.target_tickrate;
        }
    }

    while (true) {
        input_buffer.clear();

        const nbytes = posix.recvfrom(fd, input_buffer.remainingData(), 0, @ptrCast(&their_sa), &sl) catch 0;
        if (nbytes == 0) {
            break;
        }
        if (nbytes < @sizeOf(headers.BatchHeader)) {
            log.info("Recieved less data than packet header size", .{});
            break;
        }
        input_buffer.top += @intCast(nbytes);

        const address = std.net.Address.initPosix(@ptrCast(&their_sa));

        // We reject as soon as possible
        const peer_index = findPeerIndex(address) orelse blk: {
            if (peers.used == peers.data.len) {
                // Skip all the data from this peer
                log.info("Ignoring connection attempt from {} (no free connection slots)", .{address});
                continue;
            }

            log.info("No entry found for {}, adding..", .{address});
            const index = findAvailablePeerIndex();
            log.info("  .. new index {}", .{index});
            peers.used += 1; // we are really abusing BoundedArray here
            var peer = &peers.data[index];
            std.debug.assert(peer.state == .Disconnected);
            peer.state = .Connecting;
            peer.address = address;
            peer.timeout = peer_timeout;
            peer.received_messages.clear();

            break :blk index;
        };

        // Reset peer_timeout since we received data from the peer.
        peers.data[peer_index].timeout = peer_timeout;

        log.info("received {} bytes from ({}) {}", .{ nbytes, peer_index, address });
        var offset: usize = 0;
        while (input_buffer.hasData()) {
            var packet_header: headers.BatchHeader = undefined;
            common.serialize.memory_read_type(mem.frame, headers.BatchHeader, &input_buffer.data, &offset, &packet_header);

            if (input_buffer.size() < packet_header.size) {
                log.info("Received partial packet {}/{} bytes", .{ input_buffer.size(), packet_header.size });
                break;
            }
            if (packet_header.num_packets == 0) {
                log.info("Recieved empty packet", .{});
                break;
            }

            const data = input_buffer.data[offset..packet_header.size];
            offset += packet_header.size;

            received_data.append(ReceivedData{
                .peer_index = 0,
                .packet_header = packet_header,
                .data = data,
            });
        }
    }

    var peers_with_data: BoundedArray(PeerIndex, max_peer_count) = .{};

    // TODO(anjo): This might be candidate for threading if there
    // are enough entries.
    for (received_data.slice()) |data| {
        var peer = &peers.data[data.peer_index];

        // TODO(anjo): verbose

        if (data.packet_header.reliable) {
            ack(peer, data.packet_header.id);
        }
        process_ack(data.peer_index, data.packet_header);

        // TODO(anjo): Verify packet here

        var byte_view = bb.ByteView{
            .data = data.data,
        };

        // iterate over all message headers
        var i: u16 = 0;
        while (byte_view.hasData() and i < data.packet_header.num_packets) : (i += 1) {
            const header = byte_view.pop(headers.Header);
            const size = packet_meta.getMessageSize(header.kind);

            std.debug.assert(byte_view.hasSpaceFor(@intCast(size)));

            if (!header.reliable or peer.received_messages.get(header.id) == null) {
                peer.received_messages.set(header.id, ReceivedMessageInfo{
                    .kind = header.kind,
                    .data = byte_view.data[byte_view.bottom .. byte_view.bottom + size],
                });
                peers_with_data.append(data.peer_index);
            }
            byte_view.advance(@intCast(size));
        }
    }

    for (peers_with_data.slice()) |index| {
        const peer = &peers.data[index];

        //
        // We deal with connections here, no need to force
        // the caller to handle it, we return an event instead.
        //
        if (peer.state == .Connecting) {
            var i: u16 = 0;
            while (i < peer.received_messages.data.len) : (i += 1) {
                if (peer.received_messages.isset(i)) {
                    const rmi = peer.received_messages.data[i];

                    switch (rmi.kind) {
                        .ConnectionRequest => {
                            const message: *align(1) packet.ConnectionRequest = @ptrCast(rmi.data.ptr);
                            const server_salt = std.crypto.random.int(u64);
                            peer.salt = message.client_salt ^ server_salt;

                            pushMessage(index, packet.ConnectionChallenge{
                                .client_salt = message.client_salt,
                                .server_salt = server_salt,
                            });

                            log.info("[{}/{}] {} connecting (awaiting challenge)", .{ peers.used, max_peer_count, peer.address.? });
                        },
                        .ConnectionChallengeResponse => {
                            const message: *align(1) packet.ConnectionChallengeResponse = @ptrCast(rmi.data.ptr);
                            if (peer.salt == message.salt) {
                                peer.state = .Connected;
                                pushMessage(index, packet.ConnectionSuccessful{});
                                events[num_events] = Event{
                                    .peer_connected = .{
                                        .peer_index = index,
                                    },
                                };
                                num_events += 1;
                                log.info("{} connected", .{peer.address.?});
                            } else {
                                pushMessage(index, packet.ConnectionDenied{});
                                peer.state = .Disconnected;
                                log.info("{} disconnected (failed challenge)", .{peer.address.?});
                                peers.used -= 1;
                            }
                        },
                        else => continue,
                    }

                    peer.received_messages.unset(i);
                }
            }
        } else if (peer.state == .Connected) {

            //
            // Collection of messages into events
            //

            var i: u16 = 0;
            while (i < peer.received_messages.data.len) : (i += 1) {
                if (peer.received_messages.isset(i) and !peer.received_messages.data[i].acked) {
                    peer.received_messages.data[i].acked = true;
                    const rmi = peer.received_messages.data[i];
                    events[num_events] = Event{
                        .message_received = .{
                            .peer_index = index,
                            .kind = rmi.kind,
                            .data = rmi.data,
                        },
                    };
                    num_events += 1;
                    //peer.received_messages.unset(i);
                    // TODO(anjo): verbose
                    //log.info("we got data", .{});
                }
            }
        }
    }

    return events[0..num_events];
}

pub fn processServer(host: *const Host) void {
    for (peers.data, 0..) |peer, i| {
        if (peer.state == .Disconnected)
            continue;
        process(host, @intCast(i));
    }
}

var timer: ?std.time.Timer = null;
var entries: bb.CircularArray(LogEntry, 256) = .{};
var debug: ?DebugState = null;

pub fn process(host: *const Host, peer_index: ?PeerIndex) void {
    if (timer == null) {
        timer = std.time.Timer.start() catch unreachable;
    }
    if (debug == null) {
        const crand = std.crypto.random;
        var prng = std.Random.DefaultPrng.init(crand.int(u64));

        debug = DebugState{
            .rand = prng.random(),
            .delay = 0.0 * std.time.ns_per_s,
            .dropchance = 0.0,
        };
    }

    var peer = &peers.data[peer_index.?];
    std.debug.assert(peer.state != .Disconnected);

    var total_bytes_sent: u64 = 0;

    var header = headers.BatchHeader{
        .num_packets = 0,
        .id = 0,
    };

    var packet_bytes = common.serialize.StringBuilder.init(mem.frame);

    var have_reliable_packets = false;
    var packet_data: PacketData = .{};
    if (right_wrap_distance(peer.last_outgoing_acked_message_id, peer.current_message_id, peer.messages_in_flight.data.len) > 0) {
        var id = peer.last_outgoing_acked_message_id;
        while (id != peer.current_message_id and id != (peer.last_outgoing_acked_message_id +% (message_receive_buffer_len - 1)) % peer.messages_in_flight.data.len) : (id +%= 1) {
            const index: u16 = id % @as(u16, @intCast(peer.messages_in_flight.data.len));
            if (peer.messages_in_flight.isset(index)) {
                const rmi = peer.messages_in_flight.data[index];

                std.debug.assert(rmi.reliable);

                if (!rmi.acked) {
                    packet_data.ids.append(id) catch break;
                    have_reliable_packets = true;
                } else {
                    peer.messages_in_flight.unset(index);
                    break;
                }

                packet_bytes.write_bytes(rmi.data) catch unreachable;

                header.num_packets += 1;
            }
        }
    }

    if (peer.frame_bytes) |bytes| {
        for (bytes.segments.items) |s| {
            std.log.info("writing frame w. {}/{} bytes", .{ s.used, s.data.len });
            packet_bytes.write_bytes(s.data[0..s.used]) catch unreachable;
            //std.log.info("writing frame {}", .{s});
            header.num_packets += s.num_writes;
        }
        peer.frame_bytes = null;
    }

    //var i: u8 = 0;
    //while (i < entry.repeat) : (i += 1) {
    //    if (log.debug.rand.float(f32) <= log.debug.dropchance)
    //        continue;

    if (header.num_packets > 0) {
        const size_pre_header = packet_bytes.get_size();

        {
            packet_bytes.insert = 0;
            common.serialize.memory_write_type(&packet_bytes, header) catch {};
        }

        const output_buffer = packet_bytes.dump_to_buffer(mem.frame) catch unreachable;

        header.salt = peer.salt;
        header.size = @intCast(size_pre_header);
        header.id = peer.current_packet_id;
        header.reliable = have_reliable_packets;
        header.ack_bits = peer.ack_bits;
        header.last_packet_id = peer.last_incoming_acked_packet_id;
        log.info("  pushing packet {}", .{header.id});

        peer.current_packet_id +%= 1;
        peer.packets_in_flight.set(header.id, packet_data);

        //if (log.timer.read() - entry.push_time < log.debug.delay)
        //    break;

        var entry = entries.push();
        entry.data = output_buffer;
        entry.push_time = timer.?.read();
        entry.address = peer.address;
    } else {
        log.info("  No packets in header", .{});
    }

    if (entries.size > 0) {
        var entry = entries.peek();
        if (timer.?.read() - entry.push_time >= debug.?.delay) {
            _ = entries.pop();
            const addr = if (entry.address != null) &entry.address.?.any else null;
            const len = if (entry.address != null) entry.address.?.getOsSockLen() else 0;

            const data = entry.data;
            const bytes_sent = std.posix.sendto(host.fd, data, 0, addr, len) catch 0;
            if (bytes_sent != data.len) {
                log.info("Tried to send {}, actually sent {}", .{ data.len, bytes_sent });
            } else {
                log.info("Sent {} bytes", .{bytes_sent});
            }
            std.debug.assert(bytes_sent == data.len);

            total_bytes_sent += bytes_sent;
        }
    } else {
        log.info("  No entries in queue", .{});
    }
}

//
// acking received packages
//
pub fn ack(peer: *Peer, packet_id: u16) void {
    // TODO(anjo): We have a problem here if packet_id is the first
    // acked package.  We will push a packet to ack_bits even if
    // it doesn't exist.
    // set bit corresponding to last_packet_id
    peer.ack_bits = (peer.ack_bits << 1) | 1;
    // TODO(anjo): What about overflow?
    if (peer.last_incoming_acked_packet_id > 0) {
        const shift_amount = packet_id - peer.last_incoming_acked_packet_id - 1;
        if (shift_amount < 32) {
            peer.ack_bits <<= @intCast(shift_amount);
        } else {
            peer.ack_bits = 0;
        }
    }
    peer.last_incoming_acked_packet_id = packet_id;
}

fn right_wrap_distance(a: u16, b: u16, len: u16) u16 {
    return @subWithOverflow(@addWithOverflow(b, len)[0], a)[0] % len;
}

//
// process ack bits and remove reliable packages that have been
// acked.
//
pub fn process_ack(peer_index: PeerIndex, batch: headers.BatchHeader) void {
    const peer = &peers.data[peer_index];

    // NOTE(anjo): If there's a really big delay between receiving packets
    // last_packed_id might have been overwritten and so be closer to
    // current_packet_id.
    const len = peer.packets_in_flight.data.len;
    const new_dist = right_wrap_distance(batch.last_packet_id, peer.current_packet_id, len);
    const old_dist = right_wrap_distance(peer.last_outgoing_acked_packet_id, peer.current_packet_id, len);

    if (new_dist < old_dist) {
        peer.last_outgoing_acked_packet_id = batch.last_packet_id;
    }

    // mark messages as acked
    if (peer.packets_in_flight.get(batch.last_packet_id)) |data| {
        if (!data.acked) {
            data.acked = true;
            for (data.ids.slice()) |id| {
                if (peer.messages_in_flight.isset(id)) {
                    const rmi = peer.messages_in_flight.get(id) orelse continue;
                    if (!rmi.acked) {
                        rmi.acked = true;
                        mem.persistent.free(rmi.data);
                        peer.messages_in_flight.unset(id);
                    }
                }
            }
        }
    }

    if (batch.ack_bits != 0) {
        var i: u5 = 0;
        while (i < @bitSizeOf(@TypeOf(batch.ack_bits)) - 1) : (i += 1) {
            const mask: u32 = @as(u32, 1) << i;
            if (batch.ack_bits | mask != 0) {
                // TODO(anjo) handle wrapping here
                if (batch.last_packet_id > i + 1) {
                    const packet_id = batch.last_packet_id - i - 1;
                    if (peer.packets_in_flight.get(packet_id)) |data| {
                        if (!data.acked) {
                            data.acked = true;
                            for (data.ids.slice()) |id| {
                                const rmi = peer.messages_in_flight.get(id) orelse continue;
                                if (!rmi.acked) {
                                    rmi.acked = true;
                                    mem.persistent.free(rmi.data);
                                    peer.messages_in_flight.unset(id);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    while (!peer.messages_in_flight.isset(peer.last_outgoing_acked_message_id) and
        peer.last_outgoing_acked_message_id != peer.current_message_id) : (peer.last_outgoing_acked_message_id = @addWithOverflow(peer.last_outgoing_acked_message_id, 1)[0])
    {}
}
