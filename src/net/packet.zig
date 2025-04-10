const std = @import("std");

const common = @import("common");
const Memory = common.Memory;
const Player = common.Player;
const EntityId = common.EntityId;
const Input = common.Input;

//
// Debug packets
//

pub const Command = struct {
    data: [128]u8,
    len: usize,
};

//
// Connection packets
//

pub const ConnectionRequest = struct {
    client_salt: u64,
};

pub const ConnectionChallenge = struct {
    client_salt: u64,
    server_salt: u64,
};

pub const ConnectionChallengeResponse = struct {
    salt: u64,
};

pub const ConnectionSuccessful = struct {};

pub const ConnectionDenied = struct {};

pub const ConnectionTimeout = struct {};

//
// Game packets
//

pub const Pong = struct {
    num: u32,
};

pub const Joined = struct {
    tick: u64,
};

pub const PlayerJoinRequest = struct {};

pub const PlayerJoinResponse = struct {
    id: EntityId,
};

pub const PeerJoined = struct {
    player: Player,
};

pub const PeerDisconnected = struct {
    id: EntityId,
};

pub const PlayerUpdate = struct {
    tick: u64,
    id: EntityId,
    input: Input,
    in_editor: u8,
};

pub const PlayerUpdateAuth = struct {
    tick: u64,
    player: Player,
};

pub const ServerPlayerUpdate = struct {
    players: [common.max_players]Player,
    num_players: usize,
};

pub const NewSounds = struct {
    new_sounds: [16]common.Sound = undefined,
    num_sounds: u16 = 0,
};

pub const NewHitscans = struct {
    new_hitscans: [16]common.Hitscan = undefined,
    num_hitscans: u16 = 0,
};

pub const NewExplosions = struct {
    new_explosions: [16]common.Explosion = undefined,
    num_explosions: u16 = 0,
};

pub const NewNades = struct {
    new_nades: [16]common.Nade = undefined,
    num_nades: u16 = 0,
};

pub const NewDamage = struct {
    new_damage: [16]common.Damage = undefined,
    num_damage: u16 = 0,
};

pub const NewMapMods = struct {
    mods: [8]common.MapModify = undefined,
    num_mods: u16 = 0,
};

pub const Kill = struct {
    from: EntityId,
    to: EntityId,
};

pub const SpawnPlayer = struct {
    player: Player,
};

pub const EntityUpdate = struct {
    entity: common.Entity,
};
