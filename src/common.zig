const std = @import("std");
const bb = @import("bytebuffer.zig");
const math = @import("math.zig");
const v2 = math.v2;
const v3 = math.v3;
const m4 = math.m4;

pub const connect_packet_repeat_count = 10;

pub const InputType = enum(u8) {
    MoveLeft,
    MoveRight,
    MoveForward,
    MoveBack,
    MoveUp,
    MoveDown,
    Jump,
    ResetCamera,
    Interact,
    Editor,
};

pub const Input = extern struct {
    active: [@typeInfo(InputType).Enum.fields.len]bool = undefined,
    cursor_delta: v2 = .{},
    scroll: f32 = 0,

    pub fn clear(self: *@This()) void {
        @memset(&self.active, false);
        self.cursor_delta.x = 0;
        self.cursor_delta.y = 0;
        self.scroll = 0;
    }

    pub fn set(self: *@This(), t: InputType) void {
        self.active[@intFromEnum(t)] = true;
    }

    pub fn isset(self: *const @This(), t: InputType) bool {
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
    dir: v3,
    yaw: f32,
    pitch: f32,
    editor: bool = false,
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

pub const max_players = 4;

pub const Memory = struct {
    // game state
    players: std.BoundedArray(Player, max_players) = .{},

    // camera3d
    dir: v3 = .{},
    pos: v3 = .{},
    // camera2d
    target: v2 = .{.x = 0.5, .y = 0.5},
    zoom: f32 = 1,

    // debug
    vel_graph: Graph = undefined,
    show_console: bool = false,
    console_input_index: usize = 0,
    console_input: std.BoundedArray(u8, 128) = .{},
};
