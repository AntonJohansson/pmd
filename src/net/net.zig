const std = @import("std");
const os = std.os;
const posix = std.posix;

pub const headers = @import("headers.zig");
pub const packet = @import("packet.zig");
pub const packet_meta = @import("packet_meta.zig");

const common = @import("common");
const bb = common.bb;
const stat = common.stat;

var log: common.log.GroupLog(.net) = undefined;

const ClientHost = struct {
    fd: std.posix.socket_t,
};

pub const DebugState = struct {
    rand: std.rand.Random,
    delay: u64,
    dropchance: f32,
};

const PacketData = struct {
    acked: bool = false,
    ids: std.BoundedArray(u16, 64) = .{},
};

pub const LogEntry = struct {
    batch: BatchBuilder,
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

pub const BatchBuilder = struct {
    buffer: bb.ByteBufferSlice = undefined,
    header: *align(1) headers.BatchHeader = undefined,

    pub fn clear(self: *@This()) void {
        self.buffer.clear();
        self.buffer.push(headers.BatchHeader{
            .num_packets = 0,
            .id = 0,
        });
        self.header = @ptrCast(&self.buffer.data[0]);
    }

    pub fn copy(self: *@This(), other: @This()) void {
        self.buffer = other.buffer;
        self.header = @ptrCast(&self.buffer.data[0]);
    }
};

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
        var peer = &peers.buffer[peer_index];
        peer.state = .Connecting;
        return peer_index;
    }

    return null;
}

pub fn disconnect(index: PeerIndex) void {
    var peer = &peers.buffer[index];
    std.debug.assert(peer.state != .Disconnected);

    // TODO(anjo): Send disconnect packet

    peer.state = .Disconnected;
}

pub fn pushMessage(index: PeerIndex, message: anytype) void {
    var peer = &peers.buffer[index];
    std.debug.assert(peer.state != .Disconnected);

    const message_id = peer.current_message_id;
    peer.current_message_id = @addWithOverflow(peer.current_message_id, 1)[0];

    const size = @sizeOf(headers.Header) + @sizeOf(@TypeOf(message));
    const memory = mem.frame.alloc(u8, size) catch unreachable;
    log.info("Allocating size for message {} bytes", .{size});

    const kind = comptime packet_meta.mapMessageToKind(@TypeOf(message));
    @as(*align(1) headers.Header, @ptrCast(memory.ptr)).* = headers.Header{
        .kind = kind,
        .id = message_id,
        .reliable = false,
    };
    @as(*align(1) @TypeOf(message), @ptrCast(memory.ptr + @sizeOf(headers.Header))).* = message;

    // TODO(anjo): verbose
    log.info("Pushing message", .{});
    log.info("  message id: {}", .{message_id});
    log.info("  message kind: {}", .{kind});
    log.info("  message size: {}", .{@sizeOf(@TypeOf(message))});
    log.info("  message index: {}", .{message_id % peer.messages_in_flight.data.len});
    log.info("  message ptr: {*}", .{memory.ptr});

    peer.messages_in_flight.set(message_id, ReliableMessageInfo{
        .id = message_id,
        .data = memory,
        .reliable = false,
    });

    const ii: u16 = message_id % @as(u16, @intCast(peer.messages_in_flight.data.len));
    const rmi = peer.messages_in_flight.data[ii];

    {
        const h: *align(1) const headers.Header = @ptrCast(rmi.data.ptr);
        log.info("  ( Attempting to add message w. id {}", .{rmi.id});
        log.info("  (   header id: {}", .{h.id});
        log.info("  (   header reliable: {}", .{h.reliable});
        log.info("  (   kind: {}", .{h.kind});
        log.info("  (   size: {}", .{rmi.data.len});
        log.info("  (   ptr:  {*}", .{rmi.data.ptr});
    }
}

pub fn pushReliableMessage(index: PeerIndex, message: anytype) void {
    var peer = &peers.buffer[index];
    std.debug.assert(peer.state != .Disconnected);

    const message_id = peer.current_message_id;
    peer.current_message_id += 1;

    const size = @sizeOf(headers.Header) + @sizeOf(@TypeOf(message));
    const memory = mem.persistent.alloc(u8, size) catch unreachable;

    @as(*align(1) headers.Header, @ptrCast(memory.ptr)).* = headers.Header{
        .kind = comptime packet_meta.mapMessageToKind(@TypeOf(message)),
        .id = message_id,
        .reliable = true,
    };
    @as(*align(1) @TypeOf(message), @ptrCast(memory.ptr + @sizeOf(headers.Header))).* = message;

    peer.messages_in_flight.set(message_id, ReliableMessageInfo{
        .id = message_id,
        .data = memory,
        .reliable = true,
    });
}

pub fn pushMessageToAllPeers(message: anytype) void {
    for (peers.buffer, 0..) |entry, i| {
        if (entry.state != .Connected)
            continue;
        pushMessage(@intCast(i), message);
    }
}

pub fn pushReliableMessageToAllPeers(message: anytype) void {
    for (peers.buffer, 0..) |entry, i| {
        if (entry.state != .Connected)
            continue;
        pushReliableMessage(@intCast(i), message);
    }
}

pub fn pushReliableMessageToAllOtherPeers(index: PeerIndex, message: anytype) void {
    for (peers.buffer, 0..) |entry, i| {
        if (entry.state != .Connected or i == index)
            continue;
        pushReliableMessage(@intCast(i), message);
    }
}

pub fn pushMessageToAllOtherPeers(index: PeerIndex, message: anytype) void {
    for (peers.buffer, 0..) |entry, i| {
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

    current_packet_id: u16 = 0,
    current_message_id: u16 = 0,

    last_incoming_acked_packet_id: u16 = 0,
    last_outgoing_acked_packet_id: u16 = 0,
    last_outgoing_acked_message_id: u16 = 0,

    ack_bits: u32 = 0,
};

pub const max_peer_count = 255;

pub const PeerIndex = u8;
pub var peers: std.BoundedArray(Peer, max_peer_count) = .{};

fn findPeerIndex(address: std.net.Address) ?PeerIndex {
    for (peers.buffer, 0..) |entry, i| {
        if (entry.state != .Disconnected and entry.address != null and entry.address.?.eql(address)) {
            return @intCast(i);
        }
    }
    return null;
}

fn findAvailablePeerIndex() PeerIndex {
    std.debug.assert(peers.len < peers.buffer.len);
    for (peers.buffer, 0..) |entry, i|
        if (entry.state == .Disconnected)
            return @intCast(i);
    unreachable;
}

// TODO(anjo): We can make a better assumption as to the
// size of this buffer from connected_peers*sizeof(expected_traffic)*safety_factor.
// and push it via the temporary_allocator
var input_buffer: bb.ByteBuffer(8192) = .{};

pub fn receiveMessagesClient(host: *const Host, peer_index: PeerIndex) []Event {
    var received_data: std.BoundedArray(ReceivedData, 128) = .{};
    while (true) {
        input_buffer.clear();

        const nbytes = posix.recvfrom(host.fd, input_buffer.remainingData(), 0, null, null) catch 0;
        if (nbytes == 0) {
            break;
        }
        if (nbytes < @sizeOf(headers.BatchHeader)) {
            log.info("Recieved less data than packet header size", .{});
            break;
        }
        input_buffer.top += @intCast(nbytes);

        log.info("Received {} bytes", .{nbytes});
        while (input_buffer.hasData()) {
            const packet_header = input_buffer.pop(headers.BatchHeader);
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

            const data = mem.frame.alloc(u8, packet_header.size) catch unreachable;
            @memcpy(data[0..input_buffer.dataSlice().len], input_buffer.dataSlice());
            input_buffer.bottom += packet_header.size;

            received_data.append(ReceivedData{
                .peer_index = 0,
                .packet_header = packet_header,
                .data = data,
            }) catch unreachable;
        }
    }

    var peer = &peers.buffer[peer_index];

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

        var byte_view = bb.ByteView{
            .data = data.data,
        };

        log.info("  packet id: {}", .{data.packet_header.id});
        log.info("  packet size: {}", .{byte_view.data.len});

        // iterate over all message headers
        var i: u16 = 0;
        while (byte_view.hasData() and i < data.packet_header.num_packets) : (i += 1) {
            const header = byte_view.pop(headers.Header);
            const size = packet_meta.getMessageSize(header.kind);

            log.info("  Message", .{});
            log.info("    size: {}", .{size});
            log.info("    kind: {}", .{header.kind});

            if (!header.reliable or peer.received_messages.get(header.id) == null) {
                peer.received_messages.set(header.id, ReceivedMessageInfo{
                    .kind = header.kind,
                    .data = byte_view.data[byte_view.bottom .. byte_view.bottom + size],
                });
            }
            byte_view.advance(@intCast(size));
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
    var received_data: std.BoundedArray(ReceivedData, 128) = .{};
    var num_events: usize = 0;
    var events = mem.frame.alloc(Event, 128) catch unreachable;

    // Timeout disconnected peers
    for (&peers.buffer, 0..) |*peer, i| {
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
            if (peers.len == peers.buffer.len) {
                // Skip all the data from this peer
                log.info("Ignoring connection attempt from {} (no free connection slots)", .{address});
                continue;
            }

            log.info("No entry found for {}, adding..", .{address});
            const index = findAvailablePeerIndex();
            log.info("  .. new index {}", .{index});
            peers.len += 1; // we are really abusing BoundedArray here
            var peer = &peers.buffer[index];
            std.debug.assert(peer.state == .Disconnected);
            peer.state = .Connecting;
            peer.address = address;
            peer.timeout = peer_timeout;
            peer.received_messages.clear();

            break :blk index;
        };

        // Reset peer_timeout since we received data from the peer.
        peers.buffer[peer_index].timeout = peer_timeout;

        log.info("received {} bytes from ({}) {}", .{ nbytes, peer_index, address });
        while (input_buffer.hasData()) {
            const packet_header = input_buffer.pop(headers.BatchHeader);
            if (input_buffer.size() < packet_header.size) {
                log.info("Received partial packet {}/{} bytes", .{ input_buffer.size(), packet_header.size });
                break;
            }
            if (packet_header.num_packets == 0) {
                log.info("Recieved empty packet", .{});
                break;
            }

            const data = mem.frame.alloc(u8, packet_header.size) catch unreachable;
            @memcpy(data[0..input_buffer.dataSlice().len], input_buffer.dataSlice());
            input_buffer.bottom += packet_header.size;

            received_data.append(ReceivedData{
                .peer_index = peer_index,
                .packet_header = packet_header,
                .data = data,
            }) catch unreachable;
        }
    }

    var peers_with_data: std.BoundedArray(PeerIndex, max_peer_count) = .{};

    // TODO(anjo): This might be candidate for threading if there
    // are enough entries.
    for (received_data.slice()) |data| {
        var peer = &peers.buffer[data.peer_index];

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
                peers_with_data.append(data.peer_index) catch unreachable;
            }
            byte_view.advance(@intCast(size));
        }
    }

    for (peers_with_data.slice()) |index| {
        const peer = &peers.buffer[index];

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

                            log.info("[{}/{}] {} connecting (awaiting challenge)", .{ peers.len, max_peer_count, peer.address.? });
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
                                peers.len -= 1;
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
    for (peers.buffer, 0..) |peer, i| {
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
        var prng = std.rand.DefaultPrng.init(crand.int(u64));

        debug = DebugState{
            .rand = prng.random(),
            .delay = 0.0 * std.time.ns_per_s,
            .dropchance = 0.0,
        };
    }

    var peer = &peers.buffer[peer_index.?];
    std.debug.assert(peer.state != .Disconnected);

    var total_bytes_sent: u64 = 0;

    var output_buffer = bb.ByteBufferSlice.init(mem.frame, 8192);
    output_buffer.push(headers.BatchHeader{
        .num_packets = 0,
        .id = 0,
    });
    var header: *align(1) headers.BatchHeader = @ptrCast(&output_buffer.data[0]);

    log.info("Constructing packet", .{});
    var have_reliable_packets = false;
    var packet_data: PacketData = .{};
    if (right_wrap_distance(peer.last_outgoing_acked_message_id, peer.current_message_id, peer.messages_in_flight.data.len) > 0) {
        // TODO(anjo): verbose
        //log.info("checking if we can add messages", .{});
        var id = peer.last_outgoing_acked_message_id;
        while (id != peer.current_message_id and id != (@addWithOverflow(peer.last_outgoing_acked_message_id, message_receive_buffer_len - 1)[0]) % peer.messages_in_flight.data.len) : (id = @addWithOverflow(id, 1)[0]) {
            // TODO(anjo): verbose
            log.info("  checking id {}", .{id});

            const index: u16 = id % @as(u16, @intCast(peer.messages_in_flight.data.len));
            if (peer.messages_in_flight.isset(index)) {
                const rmi = peer.messages_in_flight.data[index];

                {
                    const h: *align(1) const headers.Header = @ptrCast(rmi.data.ptr);
                    log.info("  Attempting to add message w. id {}", .{rmi.id});
                    log.info("    ptr:  {*}", .{rmi.data.ptr});
                    log.info("    size: {}", .{rmi.data.len});
                    log.info("    header id: {}", .{h.id});
                    log.info("    header reliable: {}", .{h.reliable});
                    log.info("    kind: {}", .{h.kind});
                }

                // TODO(anjo): verbose
                //log.info("  found message in flight", .{});
                if (rmi.data.len > output_buffer.remainingSize()) {
                    log.info("  Packet {} of size {} too large for buffer {}/{}", .{ rmi.id, rmi.data.len, output_buffer.size(), output_buffer.data.len });
                    if (!rmi.reliable or rmi.acked) {
                        peer.messages_in_flight.unset(index);
                    }
                    break;
                }
                // TODO(anjo): verbose
                //log.info("  message {} fits in buffer", .{@as(*align(1) const headers.Header, @ptrCast(rmi.data.ptr)).kind});
                if (rmi.reliable and !rmi.acked) {
                    packet_data.ids.append(id) catch break;
                    have_reliable_packets = true;
                } else {
                    peer.messages_in_flight.unset(index);
                }

                log.info("  Adding data of size {} bytes", .{rmi.data.len});
                @memcpy(output_buffer.data[output_buffer.top .. output_buffer.top + rmi.data.len], rmi.data);
                output_buffer.top += @intCast(rmi.data.len);
                header.num_packets += 1;
            }
        }
    } else {
        // TODO(anjo): verbose
        //log.info("wrap {} {}", .{peer.last_outgoing_acked_message_id, peer.current_message_id});
        log.info("  No messages in queue", .{});
    }

    output_buffer_stat.samples.push(output_buffer.size());

    //var i: u8 = 0;
    //while (i < entry.repeat) : (i += 1) {
    //    if (log.debug.rand.float(f32) <= log.debug.dropchance)
    //        continue;

    if (header.num_packets > 0) {
        header.salt = peer.salt;
        header.size = @as(u16, @intCast(output_buffer.size())) - @sizeOf(headers.BatchHeader);
        header.id = peer.current_packet_id;
        header.reliable = have_reliable_packets;
        header.ack_bits = peer.ack_bits;
        header.last_packet_id = peer.last_incoming_acked_packet_id;
        log.info("  pushing packet {}", .{header.id});

        peer.current_packet_id = @addWithOverflow(peer.current_packet_id, 1)[0];
        peer.packets_in_flight.set(header.id, packet_data);

        //if (log.timer.read() - entry.push_time < log.debug.delay)
        //    break;

        var entry = entries.push();
        entry.batch.buffer = output_buffer;
        entry.batch.header = @ptrCast(&entry.batch.buffer.data[0]);
        entry.push_time = timer.?.read();
        entry.address = peer.address;
    } else {
        log.info("  No packets in header", .{});
    }

    //}

    if (entries.size > 0) {
        var entry = entries.peek();
        if (timer.?.read() - entry.push_time >= debug.?.delay) {
            _ = entries.pop();
            const addr = if (entry.address != null) &entry.address.?.any else null;
            const len = if (entry.address != null) entry.address.?.getOsSockLen() else 0;

            const data = entry.batch.buffer.data[0..entry.batch.buffer.top];
            const bytes_sent = std.posix.sendto(host.fd, data, 0, addr, len) catch 0;
            if (bytes_sent != data.len) {
                log.info("Tried to send {}, actually sent {}", .{ data.len, bytes_sent });
            } else {
                log.info("Sent {} bytes", .{bytes_sent});
            }
            std.debug.assert(bytes_sent == data.len);

            // TODO(anjo): verbose
            //log.info("sending packet {} with {} messsages in {} bytes", .{header.id, header.num_packets, output_buffer.top});

            total_bytes_sent += bytes_sent;
            //net_stats.get(.NetOut).samples.push(total_bytes_sent);
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
    const peer = &peers.buffer[peer_index];

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
