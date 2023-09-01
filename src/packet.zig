const std = @import("std");

const common = @import("common.zig");
const Memory = common.Memory;
const Player = common.Player;
const PlayerId = common.PlayerId;
const Input = common.Input;

//
// Debug packets
//

pub const Command = extern struct {
    data: [128]u8,
    len: usize,
};


//
// Connection packets
//

pub const ConnectionRequest = extern struct {
    client_salt: u64,
};

pub const ConnectionChallenge = extern struct {
    client_salt: u64,
    server_salt: u64,
};

pub const ConnectionChallengeResponse = extern struct {
    salt: u64,
};

pub const ConnectionSuccessful = extern struct {
};

pub const ConnectionDenied = extern struct {
};

pub const ConnectionTimeout = extern struct {
};

//
// Game packets
//

pub const Pong = extern struct {
    num: u32,
};

pub const Joined = extern struct {
    tick: u64,
};

pub const PlayerJoinRequest = extern struct {
};

pub const PlayerJoinResponse = extern struct {
    player: Player,
};

pub const PeerJoined = extern struct {
    player: Player,
};

pub const PeerDisconnected = extern struct {
    id: PlayerId,
};

pub const PlayerUpdate = extern struct {
    tick: u64,
    id: PlayerId,
    input: Input,
};

pub const PlayerUpdateAuth = extern struct {
    tick: u64,
    player: Player,
};

pub const ServerPlayerUpdate = extern struct {
    players: [common.max_players]Player,
    num_players: usize,
};
