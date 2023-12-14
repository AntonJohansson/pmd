const std = @import("std");

const common = @import("common");
const Memory = common.Memory;
const Player = common.Player;
const EntityId = common.EntityId;
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
    id: EntityId,
};

pub const PeerJoined = extern struct {
    player: Player,
};

pub const PeerDisconnected = extern struct {
    id: EntityId,
};

pub const PlayerUpdate = extern struct {
    tick: u64,
    id: EntityId,
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

pub const NewSounds = extern struct {
    new_sounds:     [16]common.Sound = undefined,
    num_sounds:     u16 = 0,
};

pub const NewHitscans = extern struct {
    new_hitscans:   [16]common.Hitscan   = undefined,
    num_hitscans:   u16 = 0,
};

pub const NewExplosions = extern struct {
    new_explosions: [16]common.Explosion = undefined,
    num_explosions: u16 = 0,
};

pub const NewNades = extern struct {
    new_nades:      [16]common.Nade      = undefined,
    num_nades:      u16 = 0,
};

pub const NewDamage = extern struct {
    new_damage:     [16]common.Damage    = undefined,
    num_damage:     u16 = 0,
};

pub const Kill = extern struct {
    from: EntityId,
    to: EntityId,
};

pub const SpawnPlayer = extern struct {
    player: Player,
};

pub const EntityUpdate = extern struct {
    entity: common.Entity,
};
