const std = @import("std");
const bb = @import("bytebuffer.zig");
const math = @import("math.zig");
const v2 = math.v2;
const v3 = math.v3;
const m4 = math.m4;

const primitive = @import("primitive.zig");
const Camera3d = primitive.Camera3d;

const stat = @import("stat.zig");

pub const connect_packet_repeat_count = 10;

pub const InputName = enum(u8) {
    MoveLeft,
    MoveRight,
    MoveForward,
    MoveBack,
    MoveUp,
    MoveDown,
    Jump,
    Crouch,
    Sprint,
    ResetCamera,
    Interact,
    AltInteract,
    Editor,
    Console,
    Enter,
    EnableCursor,
    Save,
    Load,
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

pub const PlayerId = u64;
pub fn newPlayerId() PlayerId {
    const S = struct {
        var id: PlayerId = 0;
    };
    const id = S.id;
    S.id += 1;
    return id;
}

pub const Player = extern struct {
    id: PlayerId,
    pos: v3,
    vel: v3,
    dir: v3 = .{.x = 1, .y = 0, .z = 0},
    yaw: f32,
    pitch: f32,
    editor: bool = false,
    onground: bool = false,
    crouch: bool = false,
    sprint: bool = false,
};

pub fn findIndexById(players: []Player, id: PlayerId) ?usize {
    for (players, 0..) |p,i| {
        if (p.id == id)
            return i;
    }
    return null;
}

pub fn findPlayerById(players: []Player, id: PlayerId) ?*Player {
    for (players) |*p| {
        if (p.id == id)
            return p;
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
pub const WidgetMoveType = enum {
    move_axis,
    move_plane,
    rotate_x,
    rotate_y,
    rotate_z
};
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

pub const Entity = struct {
    plane: primitive.Plane = .{
        .model =.{},
    },
};

pub const Memory = struct {
    // game state
    players: std.BoundedArray(Player, max_players) = .{},
    entities: std.BoundedArray(Entity, 64) = .{},

    camera: Camera3d = .{},
    // camera2d
    target: v2 = .{.x = 0.5, .y = 0.5},
    zoom: f32 = 1,

    // debug
    vel_graph: Graph = undefined,

    show_cursor: bool = false,
    cursor_pos: v2 = .{
        .x = 0.5,
        .y = 0.5,
    },

    console_input_index: usize = 0,
    console_input: std.BoundedArray(u8, 128) = .{},

    selected_entity: ?u32 = null,
    widget: WidgetModel = .{},

    frame_allocator: std.mem.Allocator = undefined,
    persistent_allocator: std.mem.Allocator = undefined,

    stat_data: stat.StatData = .{},

    ray_model: ?m4 = null,

    // in in ns
    time: u64 = 0,
};
