const std = @import("std");

pub const bb = @import("bytebuffer.zig");
pub const math = @import("math.zig");
pub const stat = @import("stat.zig");
pub const config = @import("config.zig");
pub const primitive = @import("primitive.zig");
pub const code_module = @import("code_module.zig");
pub const log = @import("logging.zig");
pub const command = @import("command.zig");
pub const draw_meta = @import("draw_meta.zig");
pub const draw_api = @import("draw_api.zig");
pub const goosepack = @import("pack.zig");
pub const res = @import("res.zig");
pub const Profile = @import("profile.zig");
pub const color = @import("color.zig");

const v2 = math.v2;
const v3 = math.v3;
const m4 = math.m4;

const Camera3d = primitive.Camera3d;

pub const connect_packet_repeat_count = 10;
pub const target_fps = 165;
pub const target_tickrate = 165;

const debug_num_frames_to_record = 64;

pub const InputName = enum(u8) {
    // Movement
    MoveLeft,
    MoveRight,
    MoveForward,
    MoveBack,
    MoveUp,
    MoveDown,
    Jump,
    Crouch,
    Sprint,

    // Random
    ResetCamera,
    Interact,
    AltInteract,
    Editor,
    Console,
    Enter,
    Save,
    Load,
    pause,
    unpause,

    // Combat
    SwitchWeapon,

    // Debug
    DebugIncGamepadOffset,
    DebugDecGamepadOffset,
    DebugFramePauseDataCollection,
    DebugFrameBack,
    DebugFrameForward,
    DebugShowData,
};

pub const Input = extern struct {
    active: [@typeInfo(InputName).Enum.fields.len]bool = undefined,
    cursor_delta: v2 = .{},
    scroll: f32 = 0,

    pub fn clear(self: *@This()) void {
        @memset(&self.active, false);
        self.cursor_delta.x = 0;
        self.cursor_delta.y = 0;
        self.scroll = 0;
    }

    pub fn setto(self: *@This(), t: InputName, state: bool) void {
        self.active[@intFromEnum(t)] = state;
    }

    pub fn set(self: *@This(), t: InputName) void {
        self.active[@intFromEnum(t)] = true;
    }

    pub fn unset(self: *@This(), t: InputName) void {
        self.active[@intFromEnum(t)] = false;
    }

    pub fn isset(self: *const @This(), t: InputName) bool {
        return self.active[@intFromEnum(t)];
    }
};

pub const EntityId = u64;
pub fn newEntityId() EntityId {
    const S = struct {
        var id: EntityId = 0;
    };
    const id = S.id;
    S.id += 1;
    return id;
}

pub const Weapon = extern struct {
    type: enum(u8) {
        sniper,
        pistol,
        nade,
    } = .sniper,
    state: enum(u8) {
        normal,
        cooldown,
        zoom,
        reload,
    } = .normal,
    total_cooldown: f32,
    cooldown: f32 = 0,
    total_reload_cooldown: f32,
    total_zoom_cooldown: f32,
    kickback_time: f32,
    kickback_scale: f32,
    total_ammo: u8,
    ammo: u8,
};

pub const sniper = Weapon{
    .type = .sniper,
    .total_cooldown = 1.0,
    .total_reload_cooldown = 1.0,
    .total_zoom_cooldown = 0.5,
    .kickback_time = 0.05,
    .kickback_scale = 20.0,
    .total_ammo = 5,
    .ammo = 5,
};

pub const pistol = Weapon{
    .type = .pistol,
    .total_cooldown = 0.1,
    .total_reload_cooldown = 1.0,
    .total_zoom_cooldown = 0.2,
    .kickback_time = 0.3,
    .kickback_scale = 3.0,
    .total_ammo = 10,
    .ammo = 10,
};

pub const nade = Weapon{
    .type = .nade,
    .total_cooldown = 0.1,
    .total_reload_cooldown = 1.0,
    .total_zoom_cooldown = 1.0,
    .kickback_time = 0.3,
    .kickback_scale = 3.0,
    .total_ammo = 1,
    .ammo = 1,
};

pub const Ray = extern struct {
    dir: v3,
    pos: v3,
    len: f32,
};

pub const Hitscan = extern struct {
    id_from: EntityId,
    ray: Ray,
    width: f32,
    total_time: f32,
    time_left: f32,
};

pub const Nade = extern struct {
    id_from: EntityId,
    time_left: f32,
};

pub const Explosion = extern struct {
    id_from: EntityId,
    pos: v3,
    radius: f32,
    time_left: f32,
};

pub const Damage = extern struct {
    from: EntityId,
    to: EntityId,
    damage: f32,
};

pub const Player = extern struct {
    id: EntityId,

    state: enum(u8) {
        dead,
        alive,
    } = .dead,

    // Position, velocity, and orientation
    pos: v3,
    vel: v3,
    dir: v3 = .{ .x = 1, .y = 0, .z = 0 },
    yaw: f32,
    pitch: f32,

    health: f32 = 100.0,

    aim_start_pos: v3 = .{},
    aim_dir: v3 = .{},

    weapons: [3]Weapon = .{ sniper, pistol, nade },
    weapon_current: u8 = 0,
    weapon_last: u8 = 1,

    // State
    editor: bool = false,
    onground: bool = false,
    crouch: bool = false,
    sprint: bool = false,

    // camera
    camera: Camera3d = .{},
};

pub fn findIndexById(players: []Player, id: EntityId) ?usize {
    for (players, 0..) |p, i| {
        if (p.id == id)
            return i;
    }
    return null;
}

pub fn findPlayerById(players: []Player, id: EntityId) ?*Player {
    for (players) |*p| {
        if (p.id == id)
            return p;
    }
    return null;
}

pub fn findEntityById(entities: []Entity, id: EntityId) ?*Entity {
    for (entities) |*e| {
        if (e.id == id)
            return e;
    }
    return null;
}

pub const Graph = struct {
    data: []f32,
    max: f32 = 1,
    min: f32 = 0,
    top: usize = 0,
};

pub fn graphAppend(g: *Graph, y: f32) void {
    g.data[g.top] = y;
    g.top = (g.top + 1) % g.data.len;
}

pub const WidgetMoveType = enum { move_axis, move_plane, rotate_x, rotate_y, rotate_z };

pub const WidgetModel = struct {
    model: *m4 = undefined,

    move_dir: ?v3 = null,
    move_normal: ?v3 = null,

    original_model: m4 = undefined,
    original_interact_pos: v3 = undefined,

    rotate_center: ?v3 = null,
    move_type: WidgetMoveType = .move_axis,
};

pub const max_players = 4;

pub const Entity = extern struct {
    id: EntityId,
    flags: packed struct(u8) {
        updated_server: bool = false,
        updated_client: bool = false,
        pad: u6 = 0,
        // Crashes compiler
        //pad: std.meta.Int(.unsigned, @bitSizeOf(@This())),
    },
    plane: primitive.Plane = .{
        .model = .{},
    },
};

pub const SoundType = enum(u8) {
    death,
    slide,
    sniper,
    weapon_switch,
    step,
    pip,
    explosion,
    doink,
};

pub const Sound = extern struct {
    type: SoundType,
    pos: v3,
    id_from: EntityId,
};

pub const RespawnEntry = struct {
    id: EntityId,
    time_left: f32,
};

pub const Lobby = struct {
    killfeed: bb.CircularArray(struct {
        from: EntityId,
        to: EntityId,
        time_left: f32,
    }, 8) = undefined,
};

pub const MemoryAllocators = struct {
    frame: std.mem.Allocator = undefined,
    persistent: std.mem.Allocator = undefined,
};

pub const WindowItem = union(enum) {
    text: struct {
        str: []const u8,
        color: v3 = .{ .x = 30, .y = 0.8, .z = 0.8 },
    },
    input_text: struct {
        str: []const u8,
        color: v3 = .{ .x = 30, .y = 0.8, .z = 0.8 },
    },
};

pub const WindowPersistentState = struct {
    title: []const u8,
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    moving: bool = false,
};

pub const WindowState = struct {
    persistent: *WindowPersistentState,
    cursor_x: f32 = 0,
    cursor_y: f32 = 0,
    color: v3 = .{ .x = 60, .y = 0.5, .z = 0.5 },
    hover: bool = false,
};

pub const State = enum {
    gameplay,
    editor,
    pause,
    mainmenu,
};

pub fn update_game_state(memory: *Memory, input: *const Input) void {
    switch (memory.state) {
        .gameplay => {
            if (input.isset(.pause)) {
                memory.state = .pause;
            }
        },
        .editor => {
            if (input.isset(.pause)) {
                memory.state = .pause;
            } else if (input.isset(.Editor)) {
                memory.state = .gameplay;
            }
        },
        .pause => {
            if (input.isset(.unpause)) {
                memory.state = .gameplay;
            }
        },
        .mainmenu => {
        },
    }
}

pub const Memory = struct {
    // System, things not relevant to gamestate
    pack: goosepack.Pack = undefined,
    mem: MemoryAllocators = .{},
    threadpool: std.Thread.Pool = undefined,
    log_memory: log.LogMemory = undefined,

    // game state
    state: State = .gameplay,
    players: std.BoundedArray(Player, max_players) = .{},
    entities: std.BoundedArray(Entity, 64) = .{},

    windows_persistent: std.ArrayList(WindowPersistentState) = undefined,
    windows: std.ArrayList(WindowState) = undefined,

    current_window: ?usize = null,
    window_moving_offset: v2 = .{},

    // TODO: move to frame allocator
    new_sounds: std.BoundedArray(Sound, 64) = .{},
    new_hitscans: std.BoundedArray(Hitscan, 64) = .{},
    new_nades: std.BoundedArray(Nade, 64) = .{},
    new_explosions: std.BoundedArray(Explosion, 64) = .{},
    new_damage: std.BoundedArray(Damage, 64) = .{},

    sounds: std.BoundedArray(Sound, 64) = .{},
    hitscans: std.BoundedArray(Hitscan, 64) = .{},
    nades: std.BoundedArray(Nade, 64) = .{},
    explosions: std.BoundedArray(Explosion, 64) = .{},

    // camera2d
    target: v2 = .{ .x = 0.5, .y = 0.5 },
    zoom: f32 = 1,

    // debug
    vel_graph: Graph = undefined,

    cursor_pos: v2 = .{
        .x = 0.5,
        .y = 0.5,
    },

    // Console
    console_input_index: usize = 0,
    console_input: std.BoundedArray(u8, 128) = .{},

    // Editor
    selected_entity: ?u32 = null,
    widget: WidgetModel = .{},

    profile: Profile = .{},
    debug_frame_data: bb.CircularBuffer(DebugFrameData, debug_num_frames_to_record) = .{},
    debug_data_collection_paused: bool = false,

    ray_model: ?m4 = null,

    respawns: std.BoundedArray(RespawnEntry, 8) = .{},
    // TODO: move to frame allocator
    new_spawns: std.BoundedArray(*Player, 8) = .{},

    new_kills: std.BoundedArray(struct {
        from: EntityId,
        to: EntityId,
    }, 8) = .{},

    // @client
    // TODO: Move to some sort of "lobby"
    killfeed: bb.CircularArray(struct {
        from: EntityId,
        to: EntityId,
        time_left: f32,
    }, 8) = undefined,

    // in in ns
    time: u64 = 0,
};

pub const DebugFrameData = struct {
    profile: *Profile,
    used: bool = false,
};
