const std = @import("std");
const cos = std.math.cos;
const sin = std.math.sin;
const max = std.math.max;
const min = std.math.min;

const common = @import("common");
const Memory = common.Memory;
const Player = common.Player;
const Input = common.Input;
const hsv_to_rgb = common.color.hsv_to_rgb;

const intersect = @import("intersect.zig");
const ui_profile = @import("debug/ui_profile.zig");

const Graph = common.Graph;
const graphAppend = common.graphAppend;

const config = common.config;
const Vars = config.Vars;

const primitive = common.primitive;
const Color = primitive.Color;

const bb = common.bb;
const CircularArray = bb.CircularArray;

const math = common.math;
const v2 = math.v2;
const v3 = math.v3;
const v4 = math.v4;
const m3 = math.m3;
const m4 = math.m4;

const draw_api = common.draw_api;

const zphy = @import("zphysics");

const widget_length = 20.0;
const widget_thickness = 2.0;
const widget_size_x = v3{ .x = widget_length, .y = widget_thickness, .z = widget_thickness };
const widget_size_y = v3{ .x = widget_thickness, .y = widget_length, .z = widget_thickness };
const widget_size_z = v3{ .x = widget_thickness, .y = widget_thickness, .z = widget_length };
const widget_plane_length = 8.0;
const widget_plane_thickness = 0.5;
const widget_size_plane_xy = v3{ .x = widget_plane_length, .y = widget_plane_length, .z = widget_plane_thickness };
const widget_size_plane_yz = v3{ .x = widget_plane_thickness, .y = widget_plane_length, .z = widget_plane_length };
const widget_size_plane_xz = v3{ .x = widget_plane_length, .y = widget_plane_thickness, .z = widget_plane_length };

const global_plane_size = v2{ .x = 100.0, .y = 100.0 };
const ground_plane_size = v2{ .x = 10000.0, .y = 10000.0 };

const fontsize = 1.0 / 30.0;
const window_fontsize = 1.0 / 60.0;

const grid_size = 32;
const tile_size = 32.0;
const tile_max_height = 4.0;
const tile_base_height = 2.0;

//
// PHYSICS
//

const object_layers = struct {
    const non_moving: zphy.ObjectLayer = 0;
    const moving: zphy.ObjectLayer = 1;
    const len: u32 = 2;
};

const broad_phase_layers = struct {
    const non_moving: zphy.BroadPhaseLayer = 0;
    const moving: zphy.BroadPhaseLayer = 1;
    const len: u32 = 2;
};

const BroadPhaseLayerInterface = extern struct {
    usingnamespace zphy.BroadPhaseLayerInterface.Methods(@This());
    __v: *const zphy.BroadPhaseLayerInterface.VTable = &vtable,

    object_to_broad_phase: [object_layers.len]zphy.BroadPhaseLayer = undefined,

    const vtable = zphy.BroadPhaseLayerInterface.VTable{
        .getNumBroadPhaseLayers = _getNumBroadPhaseLayers,
        .getBroadPhaseLayer = _getBroadPhaseLayer,
    };

    fn init() BroadPhaseLayerInterface {
        var layer_interface: BroadPhaseLayerInterface = .{};
        layer_interface.object_to_broad_phase[object_layers.non_moving] = broad_phase_layers.non_moving;
        layer_interface.object_to_broad_phase[object_layers.moving] = broad_phase_layers.moving;
        return layer_interface;
    }

    fn _getNumBroadPhaseLayers(_: *const zphy.BroadPhaseLayerInterface) callconv(.C) u32 {
        return broad_phase_layers.len;
    }

    fn _getBroadPhaseLayer(
        iself: *const zphy.BroadPhaseLayerInterface,
        layer: zphy.ObjectLayer,
    ) callconv(.C) zphy.BroadPhaseLayer {
        const self = @as(*const BroadPhaseLayerInterface, @ptrCast(iself));
        return self.object_to_broad_phase[layer];
    }
};

const ObjectVsBroadPhaseLayerFilter = extern struct {
    usingnamespace zphy.ObjectVsBroadPhaseLayerFilter.Methods(@This());
    __v: *const zphy.ObjectVsBroadPhaseLayerFilter.VTable = &vtable,

    const vtable = zphy.ObjectVsBroadPhaseLayerFilter.VTable{ .shouldCollide = _shouldCollide };

    fn _shouldCollide(
        _: *const zphy.ObjectVsBroadPhaseLayerFilter,
        layer1: zphy.ObjectLayer,
        layer2: zphy.BroadPhaseLayer,
    ) callconv(.C) bool {
        return switch (layer1) {
            object_layers.non_moving => layer2 == broad_phase_layers.moving,
            object_layers.moving => true,
            else => unreachable,
        };
    }
};

const ObjectLayerPairFilter = extern struct {
    usingnamespace zphy.ObjectLayerPairFilter.Methods(@This());
    __v: *const zphy.ObjectLayerPairFilter.VTable = &vtable,

    const vtable = zphy.ObjectLayerPairFilter.VTable{ .shouldCollide = _shouldCollide };

    fn _shouldCollide(
        _: *const zphy.ObjectLayerPairFilter,
        object1: zphy.ObjectLayer,
        object2: zphy.ObjectLayer,
    ) callconv(.C) bool {
        return switch (object1) {
            object_layers.non_moving => object2 == object_layers.moving,
            object_layers.moving => true,
            else => unreachable,
        };
    }
};

const ContactListener = extern struct {
    usingnamespace zphy.ContactListener.Methods(@This());
    __v: *const zphy.ContactListener.VTable = &vtable,

    const vtable = zphy.ContactListener.VTable{ .onContactValidate = _onContactValidate };

    fn _onContactValidate(
        self: *zphy.ContactListener,
        body1: *const zphy.Body,
        body2: *const zphy.Body,
        base_offset: *const [3]zphy.Real,
        collision_result: *const zphy.CollideShapeResult,
    ) callconv(.C) zphy.ValidateResult {
        _ = self;
        _ = body1;
        _ = body2;
        _ = base_offset;
        _ = collision_result;
        return .accept_all_contacts;
    }
};

//
// END PHYSICS
//

var broad_phase_layer_interface = BroadPhaseLayerInterface.init();
var object_vs_broad_phase_layer_filter: ObjectVsBroadPhaseLayerFilter = .{};
var object_layer_pair_filter: ObjectLayerPairFilter = .{};
var contact_listener: ContactListener = .{};
var physics_system: *zphy.PhysicsSystem = undefined;

export fn init(memory: *Memory) bool {
    zphy.init(memory.mem.persistent, .{}) catch return false;

    physics_system = zphy.PhysicsSystem.create(
        @as(*const zphy.BroadPhaseLayerInterface, @ptrCast(&broad_phase_layer_interface)),
        @as(*const zphy.ObjectVsBroadPhaseLayerFilter, @ptrCast(&object_vs_broad_phase_layer_filter)),
        @as(*const zphy.ObjectLayerPairFilter, @ptrCast(&object_layer_pair_filter)),
        .{
            .max_bodies = 1024,
            .num_body_mutexes = 0,
            .max_body_pairs = 1024,
            .max_contact_constraints = 1024,
        },
    ) catch return false;
    return true;
}

export fn deinit(memory: *Memory) void {
    _ = memory;
    physics_system.destroy();
    zphy.deinit();
}

fn updateWidget(widget: *common.WidgetModel, input: *const Input, start: v3, dir: v3) void {
    var model = widget.model.*;

    const held = input.isset(.Interact);

    if (widget.move_normal == null) {
        const WidgetMoveDir = struct {
            intersect: intersect.Result,

            move_dir: ?v3 = null,
            move_normal: v3,

            rotate_center: ?v3 = null,
            move_type: common.WidgetMoveType = .move_axis,
        };

        const i = m4.modelAxisI(model);
        const j = m4.modelAxisJ(model);
        const k = m4.modelAxisK(model);
        const pos = m4.modelTranslation(model);

        var widgets: std.BoundedArray(WidgetMoveDir, 6) = .{};
        const move_x = intersect.cubeLine(model, widget_size_x, start, dir);
        if (move_x) |res|
            widgets.appendAssumeCapacity(.{ .intersect = res, .move_dir = i, .move_normal = k });
        const move_y = intersect.cubeLine(model, widget_size_y, start, dir);
        if (move_y) |res|
            widgets.appendAssumeCapacity(.{ .intersect = res, .move_dir = j, .move_normal = k });
        const move_z = intersect.cubeLine(model, widget_size_z, start, dir);
        if (move_z) |res|
            widgets.appendAssumeCapacity(.{ .intersect = res, .move_dir = k, .move_normal = i });
        const move_xy = intersect.cubeLine(model, widget_size_plane_xy, start, dir);
        if (move_xy) |res|
            widgets.appendAssumeCapacity(.{ .intersect = res, .move_normal = k });
        const move_yz = intersect.cubeLine(model, widget_size_plane_yz, start, dir);
        if (move_yz) |res|
            widgets.appendAssumeCapacity(.{ .intersect = res, .move_normal = i });
        const move_xz = intersect.cubeLine(model, widget_size_plane_xz, start, dir);
        if (move_xz) |res|
            widgets.appendAssumeCapacity(.{ .intersect = res, .move_normal = j });
        const rot_x = intersect.annulusLine(pos, 9.0, 10.0, i, start, dir);
        if (rot_x) |res|
            widgets.appendAssumeCapacity(.{ .intersect = res, .move_normal = i, .rotate_center = pos, .move_type = .rotate_x });
        const rot_y = intersect.annulusLine(pos, 9.0, 10.0, j, start, dir);
        if (rot_y) |res|
            widgets.appendAssumeCapacity(.{ .intersect = res, .move_normal = j, .rotate_center = pos, .move_type = .rotate_y });
        const rot_z = intersect.annulusLine(pos, 9.0, 10.0, k, start, dir);
        if (rot_z) |res|
            widgets.appendAssumeCapacity(.{ .intersect = res, .move_normal = k, .rotate_center = pos, .move_type = .rotate_z });

        var closest: ?WidgetMoveDir = null;
        for (widgets.constSlice()) |w| {
            if (closest == null or w.intersect.distance < closest.?.intersect.distance) {
                closest = w;
            }
        }

        if (closest != null) {
            widget.original_model = model;
            widget.original_interact_pos = intersect.infinitePlaneAxisLine(pos, closest.?.move_normal, start, dir).?;
            widget.move_dir = closest.?.move_dir;
            widget.move_normal = closest.?.move_normal;
            widget.rotate_center = closest.?.rotate_center;
            widget.move_type = closest.?.move_type;
        }
    } else {
        if (held) {
            const pos = m4.modelTranslation(model);
            if (intersect.infinitePlaneAxisLine(pos, widget.move_normal.?, start, dir)) |p| {
                const delta = v3.sub(p, widget.original_interact_pos);

                if (widget.move_dir) |d| {
                    // dir
                    const new_pos = v3.add(pos, v3.scale(v3.dot(delta, d), d));
                    widget.model.* = m4.modelSetTranslation(model, new_pos);
                    widget.original_interact_pos = p;
                } else if (widget.rotate_center) |r| {
                    // rotate
                    const l1 = v3.sub(widget.original_interact_pos, r);
                    const l2 = v3.sub(p, r);
                    const angle = std.math.atan2(v3.dot(v3.cross(l1, l2), widget.move_normal.?), v3.dot(l1, l2));

                    model = widget.original_model;
                    const rot = m4.modelRot(model);
                    if (widget.move_type == .rotate_x) {
                        widget.model.* = m4.modelSetRot(model, m3.mul(rot, m3.modelRotX(angle)));
                    } else if (widget.move_type == .rotate_y) {
                        widget.model.* = m4.modelSetRot(model, m3.mul(rot, m3.modelRotY(angle)));
                    } else if (widget.move_type == .rotate_z) {
                        widget.model.* = m4.modelSetRot(model, m3.mul(rot, m3.modelRotZ(angle)));
                    }
                } else {
                    // plane
                    const new_pos = v3.add(pos, delta);
                    widget.model.* = m4.modelSetTranslation(model, new_pos);
                    widget.original_interact_pos = p;
                }
            }
        } else {
            widget.move_dir = null;
            widget.move_normal = null;
        }
    }
}

fn drawWidget(cmd: *draw_api.CommandBuffer, widget: *common.WidgetModel) void {
    const model = widget.model.*;
    // x y z axes
    cmd.push(primitive.Cube{
        .model = m4.modelSetScale(model, v3.scale(1.0, widget_size_x)),
    }, .{ .r = 255, .g = 0, .b = 0, .a = 255 });
    cmd.push(primitive.Cube{
        .model = m4.modelSetScale(model, v3.scale(1.0, widget_size_y)),
    }, .{ .r = 0, .g = 255, .b = 0, .a = 255 });
    cmd.push(primitive.Cube{
        .model = m4.modelSetScale(model, v3.scale(1.0, widget_size_z)),
    }, .{ .r = 0, .g = 0, .b = 255, .a = 255 });

    cmd.push(primitive.Cube{
        .model = m4.modelSetScale(model, v3.scale(1.0, widget_size_plane_xy)),
    }, .{ .r = 0, .g = 0, .b = 255, .a = 255 });
    cmd.push(primitive.Cube{
        .model = m4.modelSetScale(model, v3.scale(1.0, widget_size_plane_yz)),
    }, .{ .r = 255, .g = 0, .b = 0, .a = 255 });
    cmd.push(primitive.Cube{
        .model = m4.modelSetScale(model, v3.scale(1.0, widget_size_plane_xz)),
    }, .{ .r = 0, .g = 255, .b = 0, .a = 255 });

    const rot = m4.modelRot(model);
    cmd.push(primitive.Circle{
        .model = m4.modelSetRot(model, m3.mul(rot, m3.modelRotY(std.math.pi / 2.0))),
    }, .{ .r = 255, .g = 0, .b = 0, .a = 255 });
    cmd.push(primitive.Circle{
        .model = m4.modelSetRot(model, m3.mul(rot, m3.modelRotX(std.math.pi / 2.0))),
    }, .{ .r = 0, .g = 255, .b = 0, .a = 255 });
    cmd.push(primitive.Circle{
        .model = m4.modelSetRot(model, m3.mul(rot, m3.modelRotZ(std.math.pi / 2.0))),
    }, .{ .r = 0, .g = 0, .b = 255, .a = 255 });
}

const ground_plane_model = m4.model(.{ .x = 0, .y = 0, .z = 0 }, .{ .x = 1, .y = 1, .z = 1 });

fn move(vars: *const Vars, memory: *Memory, player: *Player, input: *const Input, dt: f32) void {
    if (memory.state == .gameplay or memory.state == .editor) {
        if (input.cursor_delta.x != 0 or input.cursor_delta.y != 0) {
            player.yaw -= input.cursor_delta.x;
            player.pitch += input.cursor_delta.y;
            player.pitch = std.math.clamp(player.pitch, -std.math.pi / 2.0 + 0.1, std.math.pi / 2.0 - 0.1);
            player.dir = v3{
                .x = cos(player.yaw) * cos(player.pitch),
                .y = sin(player.yaw) * cos(player.pitch),
                .z = -sin(player.pitch),
            };
        }
    }

    const noclip = memory.state == .editor;

    // compute wishvel
    var wishvel: v3 = .{};
    {
        var dx: f32 = -1.0 * @as(f32, @floatFromInt(@intFromBool(input.isset(.MoveForward)))) + 1.0 * @as(f32, @floatFromInt(@intFromBool(input.isset(.MoveBack))));
        var dy: f32 = -1.0 * @as(f32, @floatFromInt(@intFromBool(input.isset(.MoveLeft)))) + 1.0 * @as(f32, @floatFromInt(@intFromBool(input.isset(.MoveRight))));
        var dz: f32 = 0.0;
        if (noclip) {
            dz = 1.0 * @as(f32, @floatFromInt(@intFromBool(input.isset(.MoveUp)))) - 1.0 * @as(f32, @floatFromInt(@intFromBool(input.isset(.MoveDown))));
        }

        const len2 = dx * dx + dy * dy + dz * dz;

        if (len2 > 0.0) {
            const len = std.math.sqrt(len2);
            dx /= len;
            dy /= len;
            dz /= len;

            const up = v3{ .x = 0, .y = 0, .z = 1 };
            const forward = v3{ .x = cos(player.yaw), .y = sin(player.yaw), .z = 0 };
            const right = v3.cross(forward, up);

            const mod: f32 = if (player.sprint) vars.sprintmod else 1.0;
            wishvel = v3.add(v3.add(v3.scale(-mod * vars.forwardspeed * dx, forward), v3.scale(vars.sidespeed * dy, right)), v3.scale(vars.upspeed * dz, up));
        }
    }

    // Apply gravity
    if (!player.onground) {
        player.vel.z += dt * vars.gravity;
    }

    if (player.onground and input.isset(.Jump)) {
        player.vel.z += vars.jumpspeed;
        player.onground = false;
    }

    // Compute wishdir/wishspeed and bound wishvel
    var wishspeed = v3.len(wishvel);
    var wishdir = v3{};
    if (wishspeed != 0.0)
        wishdir = v3.scale(1.0 / wishspeed, wishvel);
    if (wishspeed > vars.maxspeed) {
        wishvel = v3.scale(vars.maxspeed / wishspeed, wishvel);
        wishspeed = vars.maxspeed;
    }

    if (noclip) {
        player.vel = wishvel;
    } else if (player.onground) {
        // on ground

        // Apply friction
        const speed = v3.len(player.vel);
        if (speed > 0) {
            const control = if (speed < vars.stopspeed) vars.stopspeed else speed;
            var newspeed = speed - dt * control * vars.friction;
            if (newspeed < 0)
                newspeed = 0;
            newspeed /= speed;
            player.vel = v3.scale(newspeed, player.vel);
        }

        const speed_in_wishdir = v3.dot(player.vel, wishdir);
        const addspeed = wishspeed - speed_in_wishdir;

        if (addspeed > 0) {
            var accelspeed = vars.acceleration * dt * wishspeed;
            if (accelspeed > addspeed)
                accelspeed = addspeed;
            player.vel = v3.add(player.vel, v3.scale(accelspeed, wishdir));
        }
    } else {
        // in air
        var huh_wishspeed = wishspeed;
        if (huh_wishspeed > vars.maxairspeed)
            huh_wishspeed = vars.maxairspeed;
        const speed_in_wishdir = v3.dot(player.vel, wishdir);
        const addspeed = huh_wishspeed - speed_in_wishdir;
        if (addspeed > 0) {
            var accelspeed = vars.acceleration * dt * wishspeed;
            if (accelspeed > addspeed)
                accelspeed = addspeed;
            player.vel = v3.add(player.vel, v3.scale(accelspeed, wishdir));
        }
    }

    // delta from movement

    // collision with planes
    var potential_delta = v3.scale(dt, player.vel);
    if (v3.len2(potential_delta) != 0.0) {
        var collided = false;
        var pos_delta = v3{ .x = 0, .y = 0, .z = 0 };
        for (memory.entities.constSlice()) |e| {
            if (intersect.planeModelRay(e.plane.model, global_plane_size, player.pos, potential_delta)) |res| {
                if (!collided) {
                    const normal = if (v3.dot(res.normal, potential_delta) < 0) res.normal else v3.neg(res.normal);

                    const ortho_dist_to_plane = v3.dot(v3.sub(player.pos, res.pos), normal);
                    pos_delta = v3.scale(0.25 - ortho_dist_to_plane, normal);

                    const dot = v3.dot(player.vel, normal);
                    const vel_delta = v3.scale(-dot, normal);
                    player.vel = v3.add(player.vel, vel_delta);
                    collided = true;
                } else {
                    player.vel = .{ .x = 0, .y = 0, .z = 0 };
                    pos_delta = .{ .x = 0, .y = 0, .z = 0 };
                }
            }
        }
        // collision with ground
        potential_delta = v3.add(v3.scale(dt, player.vel), pos_delta);
        if (intersect.planeModelRay(ground_plane_model, ground_plane_size, player.pos, potential_delta)) |res| {
            if (!collided) {
                const normal = if (v3.dot(res.normal, potential_delta) < 0) res.normal else v3.neg(res.normal);

                const ortho_dist_to_plane = v3.dot(v3.sub(player.pos, res.pos), normal);
                pos_delta = v3.scale(0.25 - ortho_dist_to_plane, normal);

                const dot = v3.dot(player.vel, normal);
                const vel_delta = v3.scale(-dot, normal);
                player.vel = v3.add(player.vel, vel_delta);
                collided = true;
            } else {
                player.vel = .{ .x = 0, .y = 0, .z = 0 };
                pos_delta = .{ .x = 0, .y = 0, .z = 0 };
            }
        }

        player.pos = v3.add(player.pos, pos_delta);
    }

    // integrate velocity
    const delta = v3.scale(dt, player.vel);
    player.pos = v3.add(player.pos, delta);

    // Check for ground touch
    player.onground = false;
    for (memory.entities.constSlice()) |e| {
        if (intersect.planeModelRay(e.plane.model, global_plane_size, player.pos, .{ .x = 0, .y = 0, .z = -0.5 })) |_| {
            player.onground = true;
        }
    }
    if (intersect.planeModelRay(ground_plane_model, ground_plane_size, player.pos, .{ .x = 0, .y = 0, .z = -0.5 })) |_| {
        player.onground = true;
    }

    // copy player pos to camera pos
    {
        const weapon = player.weapons[player.weapon_current];
        const in_zoom = weapon.type == .sniper and weapon.state == .zoom and weapon.cooldown == weapon.total_zoom_cooldown;
        const fov = if (in_zoom) vars.fov_zoom else vars.fov;

        const height: f32 = if (player.crouch) 15 else 22;
        const offset = v3{ .x = 0, .y = 0, .z = height };
        player.camera.pos = v3.add(player.pos, offset);
        player.camera.dir = player.dir;
        player.camera.view = m4.view(player.camera.pos, player.camera.dir);
        player.camera.proj = m4.projection(0.01, 100000.0, vars.aspect, fov);
    }
}

fn dumpTypeToDisk(writer: anytype, value: anytype) !void {
    const ti = @typeInfo(@TypeOf(value));
    switch (ti) {
        .Int => {
            try std.fmt.formatInt(value, 10, .lower, .{}, writer);
            try writer.writeByte('\n');
        },
        .Float => {
            try writer.print("{}\n", .{value});
        },
        .Struct => |s| {
            try writer.writeAll("struct:\n");
            inline for (s.fields) |field| {
                try writer.writeAll(field.name);
                try writer.writeAll(": ");
                try dumpTypeToDisk(writer, @field(value, field.name));
            }
        },
        else => std.log.err("Unhandled type in writing entities: {}", .{ti}),
    }
}

fn dumpEntitiesToDisk(entities: []common.Entity) !void {
    const filename = "entities.data";
    const file = std.fs.cwd().createFile(filename, .{}) catch |err| {
        std.log.err("Failed to open file: {s} ({})", .{ filename, err });
        return;
    };
    defer file.close();
    const writer = file.writer();

    for (entities) |e| {
        try dumpTypeToDisk(writer, e);
    }
}

fn readTypeFromDisk(it: *std.mem.TokenIterator(u8, .any), value: anytype) !void {
    const base_type = @typeInfo(@TypeOf(value)).Pointer.child;
    const ti = @typeInfo(base_type);
    switch (ti) {
        .Int => {
            value.* = std.fmt.parseInt(base_type, it.next().?, 0) catch return;
        },
        .Float => {
            value.* = std.fmt.parseFloat(base_type, it.next().?) catch return;
        },
        .Struct => |s| {
            _ = it.next(); // consume "struct:"
            inline for (s.fields) |field| {
                _ = it.next(); // consume "field.name:"
                try readTypeFromDisk(it, &@field(value, field.name));
            }
        },
        else => std.log.err("Unhandled type in writing entities: {}", .{ti}),
    }
}

fn readEntitiesFromDisk(memory: *common.Memory) !void {
    const filename = "entities.data";
    const file = std.fs.cwd().openFile(filename, .{}) catch |err| {
        std.log.err("Failed to open file: {s} ({})", .{ filename, err });
        return;
    };
    defer file.close();

    var data: std.BoundedArray(u8, 4096) = .{};
    const bytes = try file.readAll(&data.buffer);
    data.len = @intCast(bytes);

    var it = std.mem.tokenize(u8, data.slice(), " \n");

    while (it.peek() != null) {
        var entity: common.Entity = undefined;
        try readTypeFromDisk(&it, &entity);
        memory.entities.appendAssumeCapacity(entity);
    }
}

fn pushWindow(memory: *Memory, cmd: *draw_api.CommandBuffer, title: []const u8, x: f32, y: f32) bool {
    var persistent: ?*common.WindowPersistentState = null;
    for (memory.windows_persistent.items) |*p| {
        if (std.mem.eql(u8, p.title, title)) {
            persistent = p;
            //win.children = std.ArrayList(common.WindowItem).init(memory.mem.frame);
            //memory.current_window = i;
        }
    }

    if (persistent == null) {
        persistent = memory.windows_persistent.addOne() catch unreachable;
        persistent.?.* = .{
            .title = title,
            .x = x,
            .y = y,
            .w = 0.20,
            .h = 0.20,
        };
    }

    const window = memory.windows.addOne() catch unreachable;
    window.* = .{
        .persistent = persistent.?,
        .cursor_x = 0,
        .cursor_y = 1,
    };

    memory.current_window = memory.windows.items.len - 1;

    drawWindow(cmd, window);

    return true;
}

fn pushText(memory: *Memory, cmd: *draw_api.CommandBuffer, text: []const u8) void {
    const index = memory.current_window.?;
    const window = &memory.windows.items[index];

    var text_prim = primitive.Text{
        .pos = .{
            .x = window.persistent.x + window.persistent.w * window.cursor_x,
            .y = window.persistent.y + window.persistent.h * window.cursor_y - top_bar_height - window_fontsize,
        },
        .str = undefined,
        .len = text.len,
        .size = window_fontsize,
        .bg = .{ .x = 0, .y = 0, .z = 0, .w = 0 },
        .fg = .{ .x = 0, .y = 1, .z = 0, .w = 1 },
    };
    @memset(&text_prim.str, 0);
    const dst: []u8 = &text_prim.str;
    @memcpy(dst[0..text.len], text);
    cmd.push(text_prim, hsv_to_rgb(100, 0.5, 0.5));
    window.cursor_y -= window_fontsize / window.persistent.h;

    //memory.windows.items[index].children.append(.{
    //    .text = .{
    //        .str = text,
    //    },
    //}) catch unreachable;
}

export fn update(vars: *const Vars, memory: *Memory, player: *Player, input: *const Input, dt: f32) void {
    // Update hitscans
    // @client
    {
        var i: usize = 0;
        while (i < memory.hitscans.len) {
            const h = &memory.hitscans.slice()[i];
            h.time_left -= @min(dt, h.time_left);
            if (h.time_left == 0.0) {
                _ = memory.hitscans.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    // Update killfeed
    {
        var i: usize = 0;
        while (i < memory.killfeed.size) {
            const index = (memory.killfeed.bottom + i) % memory.killfeed.data.len;

            memory.killfeed.data[index].time_left -= dt;
            if (memory.killfeed.data[index].time_left <= 0.0) {
                // Assumes oldest entries always appear first
                _ = memory.killfeed.pop();
            } else {
                i += 1;
            }
        }
    }

    // Player movement
    if (player.state == .alive) {
        player.crouch = input.isset(.Crouch);
        player.sprint = input.isset(.Sprint);
        move(vars, memory, player, input, dt);
        aim(vars, memory, player);

        if (memory.state == .gameplay) {
            weaponUpdate(memory, player, input, dt);
        }
    }

    // Process some random inputs...
    if (input.isset(.ResetCamera)) {
        memory.target.x = 0.5;
        memory.target.y = 0.5;
        memory.zoom = 1.0;
    }

    // select entity
    //if (input.isset(.Editor) or input.isset(.pause)) {
    //    if (input.isset(.Interact)) {
    //        var closest: ?intersect.Result = null;
    //        var closest_entity_id: ?u32 = null;
    //        for (memory.entities.constSlice(), 0..) |e, i| {
    //            if (intersect.planeModelLine(e.plane.model, global_plane_size, player.camera.pos, player.camera.dir)) |res| {
    //                if (closest == null or res.distance < closest.?.distance) {
    //                    closest = res;
    //                    closest_entity_id = @intCast(i);
    //                }
    //            }
    //        }

    //        if (closest_entity_id) |id| {
    //            memory.selected_entity = closest_entity_id;
    //            memory.widget.model = &memory.entities.buffer[id].plane.model;
    //        }
    //    }

    //    if (memory.selected_entity != null) {
    //        updateWidget(&memory.widget, input, player.camera.pos, player.camera.dir);
    //        var e = &memory.entities.slice()[memory.selected_entity.?];
    //        e.flags.updated_client = true;
    //    }
    //}

    if (input.isset(.Save)) {
        dumpEntitiesToDisk(memory.entities.slice()) catch {};
    }
    if (input.isset(.Load)) {
        readEntitiesFromDisk(memory) catch {};
    }

}

export fn authorizedPlayerUpdate(vars: *const Vars, memory: *Memory, player: *Player, input: *const Input, dt: f32) void {
    _ = dt;
    _ = vars;
    if (input.isset(.Editor)) {
        // Create new entity
        if (input.isset(.AltInteract)) {
            const id = common.newEntityId();
            memory.entities.appendAssumeCapacity(.{
                .id = id,
                .flags = .{ .updated_server = true },
                .plane = .{
                    .model = m4.model(v3.add(player.camera.pos, v3.scale(20, player.camera.dir)), .{ .x = 1, .y = 1, .z = 1 }),
                },
            });
        }
    }
}

export fn authorizedUpdate(vars: *const Vars, memory: *Memory, dt: f32) void {
    _ = vars;

    // Handle respawns
    // TODO: Move to some sort of "lobby" update
    if (memory.respawns.len > 0) {
        var i: usize = 0;
        while (i < memory.respawns.len) {
            var r = &memory.respawns.slice()[i];

            r.time_left -= dt;
            if (r.time_left <= 0.0) {
                const player = common.findPlayerById(memory.players.slice(), r.id) orelse {
                    continue;
                };
                player.* = .{
                    .id = r.id,
                    .state = .alive,
                    .pos = v3{ .x = 0, .y = 0, .z = 10 },
                    .vel = v3{ .x = 0, .y = 0, .z = 0 },
                    .dir = v3{ .x = 1, .y = 0, .z = 0 },
                    .yaw = 0,
                    .pitch = 0,
                };
                memory.new_spawns.appendAssumeCapacity(player);

                _ = memory.respawns.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    // Handle damage
    if (memory.new_damage.len > 0) {
        for (memory.new_damage.constSlice()) |d| {
            var player = &memory.players.slice()[d.to];
            if (player.state == .dead)
                continue;
            player.health -= @min(d.damage, player.health);
            if (player.health == 0.0) {
                player.state = .dead;
                memory.respawns.appendAssumeCapacity(.{
                    .id = d.to,
                    .time_left = 2.0,
                });
                memory.new_sounds.appendAssumeCapacity(.{
                    .type = .death,
                    .pos = .{ .x = 0, .y = 0, .z = 0 },
                    .id_from = d.to,
                });
                memory.new_kills.appendAssumeCapacity(.{
                    .from = d.from,
                    .to = d.to,
                });
            }
        }
    }
}

fn weaponUpdate(memory: *Memory, player: *Player, input: *const Input, dt: f32) void {
    const weapon = &player.weapons[player.weapon_current];

    switch (weapon.state) {
        .normal => {
            // fire
            const can_fire = weapon.cooldown <= 0;
            if (can_fire and input.isset(.Interact)) {
                switch (weapon.type) {
                    .sniper => {
                        memory.new_sounds.appendAssumeCapacity(.{
                            .type = .sniper,
                            .pos = .{ .x = 0, .y = 0, .z = 0 },
                            .id_from = player.id,
                        });
                        fireSniperHitscan(memory, player);
                    },
                    .pistol => {
                        memory.new_sounds.appendAssumeCapacity(.{
                            .type = .sniper,
                            .pos = .{ .x = 0, .y = 0, .z = 0 },
                            .id_from = player.id,
                        });
                        firePistolHitscan(memory, player);
                    },
                    .nade => {
                        memory.new_sounds.appendAssumeCapacity(.{
                            .type = .pip,
                            .pos = .{ .x = 0, .y = 0, .z = 0 },
                            .id_from = player.id,
                        });
                    },
                }

                weapon.ammo -= 1;
                if (weapon.ammo == 0) {
                    weapon.cooldown = 1.0;
                    weapon.state = .reload;
                } else {
                    weapon.cooldown = weapon.total_cooldown;
                    weapon.state = .cooldown;
                }
            } else if (input.isset(.AltInteract)) {
                weapon.state = .zoom;
            }
        },
        .cooldown => {
            weapon.cooldown -= dt;
            if (weapon.cooldown <= 0) {
                weapon.cooldown = 0;
                weapon.state = .normal;
            }
        },
        .zoom => {
            if (input.isset(.AltInteract)) {
                if (weapon.cooldown < weapon.total_zoom_cooldown) {
                    weapon.cooldown += dt;
                } else {
                    weapon.cooldown = weapon.total_zoom_cooldown;
                }

                if (input.isset(.Interact) and weapon.cooldown == weapon.total_zoom_cooldown) {
                    switch (weapon.type) {
                        .sniper => {
                            memory.new_sounds.appendAssumeCapacity(.{
                                .type = .sniper,
                                .pos = .{ .x = 0, .y = 0, .z = 0 },
                                .id_from = player.id,
                            });
                            fireSniperHitscan(memory, player);
                        },
                        .pistol => {
                            memory.new_sounds.appendAssumeCapacity(.{
                                .type = .sniper,
                                .pos = .{ .x = 0, .y = 0, .z = 0 },
                                .id_from = player.id,
                            });
                            firePistolHitscan(memory, player);
                        },
                        else => unreachable,
                    }
                }
            } else {
                weapon.cooldown -= dt;
                if (weapon.cooldown <= 0) {
                    weapon.cooldown = 0;
                    weapon.state = .normal;
                }
            }
        },

        .reload => {
            weapon.cooldown -= dt;
            if (weapon.cooldown <= 0) {
                weapon.cooldown = 0;
                weapon.ammo = weapon.total_ammo;
                weapon.state = .normal;
            }
        },
    }

    if (input.isset(.SwitchWeapon)) {
        weapon.cooldown = 0.0;

        // Switch current and last weapon
        const tmp = player.weapon_current;
        player.weapon_current = player.weapon_last;
        player.weapon_last = tmp;

        memory.new_sounds.appendAssumeCapacity(.{
            .type = .weapon_switch,
            .pos = .{ .x = 0, .y = 0, .z = 0 },
            .id_from = player.id,
        });
    }
}

fn aim(vars: *const Vars, memory: *Memory, player: *Player) void {
    // Default to aiming in camera dir, that is straight ahead

    var start_pos = v3{};
    {
        const up = v3{ .x = 0, .y = 0, .z = 1 };
        const i = player.camera.dir;
        const j = v3.neg(v3.cross(i, up));
        const k = v3.cross(i, j);

        const weapon = player.weapons[player.weapon_current];
        switch (weapon.type) {
            .sniper => {
                var base = player.camera.pos;
                base = v3.add(base, v3.scale(-vars.sniper_off_x, j));
                base = v3.add(base, v3.scale(vars.sniper_len / 2 + vars.sniper_off_y, i));
                base = v3.add(base, v3.scale(vars.sniper_off_z, k));
                start_pos = base;
            },
            .pistol => {
                var base = player.camera.pos;
                base = v3.add(base, v3.scale(-vars.pistol_off_x, j));
                base = v3.add(base, v3.scale(vars.pistol_len / 2 + vars.pistol_off_y, i));
                base = v3.add(base, v3.scale(vars.pistol_off_z, k));
                start_pos = base;
            },
            else => unreachable,
        }
    }
    player.aim_start_pos = start_pos;
    player.aim_dir = v3.normalize(v3.sub(v3.add(player.camera.pos, v3.scale(1000.0, player.camera.dir)), player.aim_start_pos));

    // Raycast from camera to find what we're aiming at
    const camera_cast = raycastAgainstEntities(memory, player.camera.pos, player.camera.dir, player.id) orelse {
        return;
    };

    var gun_ray_pos = v3{};
    var gun_ray_dir = v3{};
    {
        const up = v3{ .x = 0, .y = 0, .z = 1 };
        const i = player.camera.dir;
        const j = v3.neg(v3.cross(i, up));
        const k = v3.cross(i, j);

        const weapon = player.weapons[player.weapon_current];
        switch (weapon.type) {
            .sniper => {
                var base = player.camera.pos;
                base = v3.add(base, v3.scale(-vars.sniper_off_x, j));
                base = v3.add(base, v3.scale(vars.sniper_off_z, k));

                var new_ray = v3.sub(camera_cast.intersect.pos, base);
                const new_ray_len = v3.len(new_ray);
                new_ray = v3.scale(1.0 / new_ray_len, new_ray);

                gun_ray_pos = v3.add(base, v3.scale(vars.sniper_len / 2 + vars.sniper_off_y, new_ray));
                gun_ray_dir = new_ray;
            },
            .pistol => {
                var base = player.camera.pos;
                base = v3.add(base, v3.scale(-vars.pistol_off_x, j));
                base = v3.add(base, v3.scale(vars.pistol_off_z, k));

                var new_ray = v3.sub(camera_cast.intersect.pos, base);
                const new_ray_len = v3.len(new_ray);
                new_ray = v3.scale(1.0 / new_ray_len, new_ray);

                gun_ray_pos = v3.add(base, v3.scale(vars.pistol_len / 2 + vars.pistol_off_y, new_ray));
                gun_ray_dir = new_ray;
            },
            else => unreachable,
        }
    }

    player.aim_dir = gun_ray_dir;
}

fn firePistolHitscan(memory: *Memory, player: *Player) void {
    var ray = common.Ray{
        .pos = player.aim_start_pos,
        .dir = player.aim_dir,
        .len = 1000.0,
    };

    if (raycastAgainstEntities(memory, player.aim_start_pos, player.aim_dir, player.id)) |cast| {
        if (cast.is_player) {
            memory.new_damage.appendAssumeCapacity(.{
                .from = player.id,
                .to = cast.id,
                .damage = 10.0,
            });
            memory.new_sounds.appendAssumeCapacity(.{
                .type = .death,
                .pos = .{ .x = 0, .y = 0, .z = 0 },
                .id_from = cast.id,
            });
        } else {
            memory.new_sounds.appendAssumeCapacity(.{
                .type = .pip,
                .pos = .{ .x = 0, .y = 0, .z = 0 },
                .id_from = cast.id,
            });
        }

        ray.pos = player.aim_start_pos;
        ray.dir = player.aim_dir;
        ray.len = cast.intersect.distance;
    }

    // Add tracer for shot
    memory.new_hitscans.appendAssumeCapacity(common.Hitscan{
        .id_from = player.id,
        .ray = ray,
        .width = 0.5,
        .time_left = 0.5,
        .total_time = 0.5,
    });
}

fn fireSniperHitscan(memory: *Memory, player: *Player) void {
    var ray = common.Ray{
        .pos = player.aim_start_pos,
        .dir = player.aim_dir,
        .len = 1000.0,
    };

    if (raycastAgainstEntities(memory, player.aim_start_pos, player.aim_dir, player.id)) |cast| {
        if (cast.is_player) {
            memory.new_damage.appendAssumeCapacity(.{
                .from = player.id,
                .to = cast.id,
                .damage = 80.0,
            });
            memory.new_sounds.appendAssumeCapacity(.{
                .type = .death,
                .pos = .{ .x = 0, .y = 0, .z = 0 },
                .id_from = cast.id,
            });
        } else {
            memory.new_sounds.appendAssumeCapacity(.{
                .type = .pip,
                .pos = .{ .x = 0, .y = 0, .z = 0 },
                .id_from = cast.id,
            });
        }

        ray.pos = player.aim_start_pos;
        ray.dir = player.aim_dir;
        ray.len = cast.intersect.distance;
    }

    // Add tracer for shot
    memory.new_hitscans.appendAssumeCapacity(common.Hitscan{
        .id_from = player.id,
        .ray = ray,
        .width = 1.0,
        .time_left = 2.0,
        .total_time = 2.0,
    });
}

const PlayerRaycast = struct {
    intersect: intersect.Result,
    id: common.EntityId,
    is_player: bool,
};

fn raycastAgainstEntities(memory: *Memory, pos: v3, dir: v3, skip_id: ?common.EntityId) ?PlayerRaycast {
    const player_cube_size = 10;

    var closest: ?intersect.Result = null;
    var closest_entity_id: ?u64 = null;
    var is_player: bool = false;

    for (memory.players.constSlice()) |p| {
        if (skip_id != null and p.id == skip_id.?)
            continue;
        const height: f32 = if (p.crouch) 15 else 22;
        const rot = v3{
            .x = 0,
            .y = p.pitch,
            .z = p.yaw,
        };
        const scale = v3{
            .x = player_cube_size,
            .y = player_cube_size,
            .z = height,
        };
        const model = m4.modelWithRotations(.{
            .x = p.pos.x,
            .y = p.pos.y,
            .z = p.pos.z + tile_base_height + tile_max_height + height / 2,
        }, .{ .x = 1, .y = 1, .z = 1 }, rot);
        if (intersect.cubeLine(model, scale, pos, dir)) |res| {
            if (closest == null or res.distance < closest.?.distance) {
                closest = res;
                closest_entity_id = @intCast(p.id);
                is_player = true;
            }
        }
    }

    for (memory.entities.constSlice()) |e| {
        if (intersect.planeModelLine(e.plane.model, global_plane_size, pos, dir)) |res| {
            if (closest == null or res.distance < closest.?.distance) {
                closest = res;
                closest_entity_id = e.id;
                is_player = false;
            }
        }
    }

    if (closest_entity_id) |id| {
        return PlayerRaycast{
            .intersect = closest.?,
            .id = id,
            .is_player = is_player,
        };
    } else {
        return null;
    }
}

//fn calculateWindowSizes(windows: *std.ArrayList(Window), index: usize) void {
//    const window = &windows.items[index];
//
//    for (window.children.items) |j| {
//        calculateWindowSizes(windows, j);
//        //window.x = @min(window.x, window.x + windows.items[j].x);
//        //window.y = @min(window.y, window.y + windows.items[j].y);
//        window.w = @max(window.w, windows.items[j].w);
//        window.h = @max(window.h, windows.items[j].h);
//    }
//}

const top_bar_height = 0.01;
fn drawWindow(cmd: *draw_api.CommandBuffer, window: *common.WindowState) void {
    //var parent = if (window.parent) |p| &windows.items[p] else null;
    //var w = if (parent) |p| p.w else 1;
    //_ = w;
    //var h = if (parent) |p| p.h else 1;
    //_ = h;
    //if (parent) |p| {
    //    p.cursor_y -= window.h;
    //}
    //var x = if (parent) |p| p.x + p.cursor_x else 0;
    //var y = if (parent) |p| p.y + p.cursor_y else 0;

    // background
    cmd.push(primitive.Rectangle{ .pos = .{
        .x = window.persistent.x,
        .y = window.persistent.y,
    }, .size = .{
        .x = window.persistent.w,
        .y = window.persistent.h - top_bar_height,
    } }, hsv_to_rgb(
        window.color.x,
        window.color.y,
        window.color.z,
    ));

    const top_bar_color_factor: f32 = if (window.persistent.moving or window.hover) 0.8 else 1.5;

    // top bar
    cmd.push(primitive.Rectangle{ .pos = .{
        .x = window.persistent.x,
        .y = window.persistent.y + window.persistent.h - top_bar_height,
    }, .size = .{
        .x = window.persistent.w,
        .y = top_bar_height,
    } }, hsv_to_rgb(
        window.color.x,
        window.color.y,
        window.color.z * top_bar_color_factor,
    ));

    window.cursor_x = 0;
    window.cursor_y = 1;
    //for (window.children.items) |item| {
    //    switch (item) {
    //        .text => |t| {
    //            var text = primitive.Text{
    //                .pos = .{
    //                    .x = window.x + window.w * window.cursor_x,
    //                    .y = window.y + window.h * window.cursor_y - top_bar_height - window_fontsize,
    //                },
    //                .str = undefined,
    //                .len = t.str.len,
    //                .size = window_fontsize,
    //                .bg = .{ .x = 0, .y = 0, .z = 0, .w = 0 },
    //                .fg = .{ .x = 0, .y = 1, .z = 0, .w = 1 },
    //            };
    //            @memset(&text.str, 0);
    //            const dst: []u8 = &text.str;
    //            @memcpy(dst[0..t.str.len], t.str);
    //            cmd.push(text, hsv_to_rgb(t.color.x, t.color.y, t.color.z));

    //            window.cursor_y -= window_fontsize / window.h;
    //        },
    //        else => {},
    //    }
    //}
}

const dim = 64;
var voxels: [dim][dim][dim]u1 = .{.{.{0} ** dim} ** dim} ** dim;
var built_terrain = false;

fn addVoxelFaceIfSet(faces: []primitive.VoxelTransform, len: *usize, x: usize, y: usize, z: usize, face: primitive.VoxelTransform.FaceDir) void {
    if (voxels[z][y][x] == 1) {
        faces[len] = .{
            .x = @intCast(x),
            .y = @intCast(y),
            .z = @intCast(z),
            .face = face,
        };
        len.* += 1;
    }
}

const VoxelFaceArray = MultiThreadedArray(primitive.VoxelTransform, 128);

fn build_terrain(memory: *Memory, x0: usize, x1: usize, y0: usize, y1: usize, z: usize) void {
    const block = memory.profile.begin(@src().fn_name, (x1 - x0) * (y1 - y0) / 8);
    defer memory.profile.end(block);

    for (y0..y1) |y| {
        for (x0..x1) |x| {
            const halfdim = dim / 2.0;
            const d = v3{
                .x = @as(f32, @floatFromInt(x)) + 0.5 - halfdim,
                .y = @as(f32, @floatFromInt(y)) + 0.5 - halfdim,
                .z = @as(f32, @floatFromInt(z)) + 0.5 - halfdim,
            };
            if (v3.len(d) <= halfdim) {
                voxels[z][y][x] = 1;
            }
        }
    }
}

fn build_faces(memory: *Memory, faces: *VoxelFaceArray, x0: usize, x1: usize, y0: usize, y1: usize, z: usize) void {
    const profile_block = memory.profile.begin(@src().fn_name, 6 * (x1 - x0) * (y1 - y0) / 8);
    defer memory.profile.end(profile_block);

    var block = faces.head();

    for (y0..y1) |y| {
        for (x0..x1) |x| {
            if (voxels[z][y][x] > 0) {
                continue;
            }

            const n = dim - 1;
            const f = if (x < n) voxels[z][y][x + 1] else 0;
            const b = if (x > 0) voxels[z][y][x - 1] else 0;
            const r = if (y < n) voxels[z][y + 1][x] else 0;
            const l = if (y > 0) voxels[z][y - 1][x] else 0;
            const u = if (z < n) voxels[z + 1][y][x] else 0;
            const d = if (z > 0) voxels[z - 1][y][x] else 0;

            if (f == 1) {
                VoxelFaceArray.push(&block, .{
                    .x = @intCast(x + 1),
                    .y = @intCast(y),
                    .z = @intCast(z),
                    .face = .back,
                });
            }
            if (b == 1) {
                VoxelFaceArray.push(&block, .{
                    .x = @intCast(x - 1),
                    .y = @intCast(y),
                    .z = @intCast(z),
                    .face = .front,
                });
            }
            if (r == 1) {
                VoxelFaceArray.push(&block, .{
                    .x = @intCast(x),
                    .y = @intCast(y + 1),
                    .z = @intCast(z),
                    .face = .left,
                });
            }
            if (l == 1) {
                VoxelFaceArray.push(&block, .{
                    .x = @intCast(x),
                    .y = @intCast(y - 1),
                    .z = @intCast(z),
                    .face = .right,
                });
            }
            if (u == 1) {
                VoxelFaceArray.push(&block, .{
                    .x = @intCast(x),
                    .y = @intCast(y),
                    .z = @intCast(z + 1),
                    .face = .down,
                });
            }
            if (d == 1) {
                VoxelFaceArray.push(&block, .{
                    .x = @intCast(x),
                    .y = @intCast(y),
                    .z = @intCast(z - 1),
                    .face = .up,
                });
            }
        }
    }
}

fn build_chunk_edges(memory: *Memory, faces: *VoxelFaceArray, _i0: usize, _i1: usize, j: usize) void {
    const profile_block = memory.profile.begin(@src().fn_name, (_i1 - _i0) / 8);
    defer memory.profile.end(profile_block);

    var block = faces.head();

    for (_i0.._i1) |i| {
        const n = dim - 1;
        if (voxels[0][j][i] > 0) {
            VoxelFaceArray.push(&block, .{
                .x = @intCast(i),
                .y = @intCast(j),
                .z = @intCast(0),
                .face = .down,
            });
        }
        if (voxels[n][j][i] > 0) {
            VoxelFaceArray.push(&block, .{
                .x = @intCast(i),
                .y = @intCast(j),
                .z = @intCast(n),
                .face = .up,
            });
        }
        if (voxels[j][0][i] > 0) {
            VoxelFaceArray.push(&block, .{
                .x = @intCast(i),
                .y = @intCast(0),
                .z = @intCast(j),
                .face = .left,
            });
        }
        if (voxels[j][n][i] > 0) {
            VoxelFaceArray.push(&block, .{
                .x = @intCast(i),
                .y = @intCast(n),
                .z = @intCast(j),
                .face = .right,
            });
        }
        if (voxels[j][i][0] > 0) {
            VoxelFaceArray.push(&block, .{
                .x = @intCast(0),
                .y = @intCast(i),
                .z = @intCast(j),
                .face = .back,
            });
        }
        if (voxels[j][i][n] > 0) {
            VoxelFaceArray.push(&block, .{
                .x = @intCast(n),
                .y = @intCast(i),
                .z = @intCast(j),
                .face = .front,
            });
        }
    }
}

const bl = 100;
const a0 = math.Quat.fromAxisAngle(.{.x=1}, 0);
const a1 = math.Quat.fromAxisAngle(.{.x=1}, 0);
const b0 = math.Quat.fromAxisAngle(.{.x=1}, std.math.pi/4.0);
const b1 = math.Quat.fromAxisAngle(.{.x=1}, std.math.pi/4.0);

export fn draw(vars: *const Vars, memory: *Memory, cmd: *draw_api.CommandBuffer, player_id: common.EntityId, input: *const Input) void {
    if (!built_terrain) {
        var wg: std.Thread.WaitGroup = undefined;
        wg.reset();
        for (0..dim) |z| {
            memory.threadpool.spawnWg(&wg, build_terrain, .{ memory, 0, dim, 0, dim, z });
        }
        built_terrain = true;
        memory.threadpool.waitAndWork(&wg);
    }

    const player = common.findPlayerById(memory.players.slice(), player_id) orelse return;
    if (player.state == .dead) {
        return;
    }
    const camera = player.camera;

    cmd.push(camera, .{});

    cmd.push(primitive.Mesh{
        .model = m4.modelWithRotations(.{ .x = 50, .y = 0, .z = 20 }, .{ .x = 20, .y = 20, .z = 20 }, .{
            .x = 0,
            .y = 0,
            .z = @as(f32, @floatFromInt(memory.time)) / 1e9,
        }),
        .name = "res/models/brog/frog",
        .draw_children = true,
    }, .{ .r = 255, .g = 255, .b = 255, .a = 255 });

    cmd.push(primitive.Mesh{
        .model = m4.modelWithRotations(.{ .x = 100, .y = 0, .z = 20 }, .{ .x = 10, .y = 10, .z = 10 }, .{
            .x = 0,
            .y = 0,
            .z = @as(f32, @floatFromInt(memory.time)) / 1e9,
        }),
        .name = "res/models/weapons/granat",
        .draw_children = true,
    }, .{ .r = 255, .g = 255, .b = 255, .a = 255 });


    //cmd.push(primitive.Cube{
    //    .model = m4.modelWithRotations(
    //        .{
    //            .x = 50,
    //            .y = 0,
    //            .z = 0,
    //        },
    //        .{ .x = 100, .y = 10, .z = 10 },
    //        .{ .x = 0, .y = 0, .z = 0 },
    //    ),
    //}, .{ .r = 255, .g = 0, .b = 0, .a = 255 });
    //cmd.push(primitive.Cube{
    //    .model = m4.modelWithRotations(
    //        .{
    //            .x = 0,
    //            .y = 50,
    //            .z = 0,
    //        },
    //        .{ .x = 10, .y = 100, .z = 10 },
    //        .{ .x = 0, .y = 0, .z = 0 },
    //    ),
    //}, .{ .r = 0, .g = 255, .b = 0, .a = 255 });
    //cmd.push(primitive.Cube{
    //    .model = m4.modelWithRotations(
    //        .{
    //            .x = 0,
    //            .y = 0,
    //            .z = 50,
    //        },
    //        .{ .x = 10, .y = 10, .z = 100 },
    //        .{ .x = 0, .y = 0, .z = 0 },
    //    ),
    //}, .{ .r = 0, .g = 0, .b = 255, .a = 255 });

    //const selected_index: usize = 0;

    //const max_faces = 6*n*n + n*(4*n + 2*n*(n-1)) + (n-1)*n*n;
    //const max_faces_per_thread = dim*(4*dim + 2*dim*(dim-1));
    //const faces_thread = memory.mem.frame.alloc(primitive.VoxelTransform, memory.threadpool.threads.len*max_faces_per_thread) catch unreachable;

    {
        const c0 = .{ .r = 255, .g = 0, .b = 0, .a = 255 };
        const c1 = .{ .r = 0, .g = 255, .b = 0, .a = 255 };
        const p0: v4 = .{.w=1};
        cmd.push(primitive.Cube{
            .model = m4.modelWithRotations(.{.x=p0.x, .y=p0.y, .z=p0.z}, .{.x=25,.y=25,.z=25}, .{}),
        }, c0);
        var p1: v3 = .{};
        p1.z += bl;
        const t = @as(f32, @floatFromInt(memory.time % 1000000000)) / 1e9;
        const qb0 = math.Quat.lerp(a0, b0, t);
        p1 = math.Quat.rotate(qb0, p1);
        //p1 = m4.mulv(b0, p1);
        cmd.push(primitive.Cube{
            .model = m4.modelWithRotations(p1, .{.x=25,.y=25,.z=25}, .{}),
        }, c0);
        var p2: v3 = .{};
        p2.z += bl;
        //p2 = m4.mulv(m4.mul(b1, b0), p2);
        const qb1 = math.Quat.lerp(a1, b1, t);
        const q2 = math.Quat.mul(qb1, qb0);
        p2 = math.Quat.rotate(q2, p2);
        p2 = v3.add(p2, p1);
        cmd.push(primitive.Cube{
            .model = m4.modelWithRotations(p2, .{.x=25,.y=25,.z=25}, .{}),
        }, c1);
    }

    var faces = VoxelFaceArray.init(memory.mem.frame, memory.threadpool.threads.len + 1);

    {
        var wg: std.Thread.WaitGroup = undefined;
        wg.reset();

        for (0..dim) |z| {
            memory.threadpool.spawnWg(&wg, build_faces, .{ memory, &faces, 0, dim, 0, dim, z });
        }

        for (0..dim) |j| {
            memory.threadpool.spawnWg(&wg, build_chunk_edges, .{ memory, &faces, 0, dim, j });
        }

        memory.threadpool.waitAndWork(&wg);

        {
            const block = memory.profile.begin("collect voxel faces", 0);
            defer memory.profile.end(block);

            cmd.push(primitive.VoxelChunk{
                .dim = dim,
                .voxels = faces.collect(memory.mem.frame),
            }, hsv_to_rgb(80.0 + 10.0 * (2.0 * 0.5 - 1.0), 0.8 + 0.2 * (2.0 * 0.5 - 1.0), 0.5 + 0.2 * (2.0 * 0.5 - 1.0)));
        }
    }

    if (intersect.planeModelLine(math.m4.model(.{ .x = 0, .y = 0, .z = tile_size / 2.0 }, .{ .x = 1, .y = 1, .z = 1 }), .{ .x = 1000000.0, .y = 1000000.0 }, player.camera.pos, player.camera.dir)) |res| {
        if (res.pos.x > 0 and res.pos.y > 0 and res.pos.z > 0) {
            const i: usize = @intFromFloat(@trunc(res.pos.x / tile_size));
            const j: usize = @intFromFloat(@trunc(res.pos.y / tile_size));
            const k: usize = @intFromFloat(@trunc(res.pos.z / tile_size));
            if (i < dim and j < dim and k < dim) {
                if (input.isset(.Interact)) {
                    voxels[k][j][i] = ~voxels[k][j][i];
                }
                var p: v3 = .{};
                p.x = tile_size / 2.0 + tile_size * @as(f32, @floatFromInt(i));
                p.y = tile_size / 2.0 + tile_size * @as(f32, @floatFromInt(j));
                p.z = tile_size / 2.0 + tile_size * @as(f32, @floatFromInt(k));
                cmd.push(primitive.CubeOutline{
                    .model = m4.modelWithRotations(
                        p,
                        .{ .x = tile_size, .y = tile_size, .z = tile_size },
                        .{ .x = 0, .y = 0, .z = 0 },
                    ),
                }, hsv_to_rgb(80.0 + 10.0 * (2.0 * 0.5 - 1.0), 0.8 + 0.2 * (2.0 * 0.5 - 1.0), 0.5 + 0.2 * (2.0 * 0.5 - 1.0)));
            }
        }
    }

    // Draw map(?)
    var prng = std.rand.DefaultPrng.init(0);
    const rand = prng.random();
    //{
    //    var i: usize = 0;
    //    while (i < grid_size) : (i += 1) {
    //        var j: usize = 0;
    //        while (j < grid_size) : (j += 1) {
    //            cmd.push(primitive.Cube{
    //                .model = m4.modelWithRotations(
    //                    .{
    //                        .x = tile_size * @as(f32, @floatFromInt(i)) - tile_size * @as(f32, @floatFromInt(grid_size)) / 2 + tile_size / 2.0,
    //                        .y = tile_size * @as(f32, @floatFromInt(j)) - tile_size * @as(f32, @floatFromInt(grid_size)) / 2 + tile_size / 2.0,
    //                        .z = (tile_base_height + tile_max_height * rand.float(f32)) / 2.0,
    //                    },
    //                    .{
    //                        .x = tile_size,
    //                        .y = tile_size,
    //                        .z = tile_base_height + tile_max_height * rand.float(f32),
    //                    },
    //                    .{ .x = 0, .y = 0, .z = 0 },
    //                ),
    //            }, hsv_to_rgb(80.0 + 10.0 * (2.0 * rand.float(f32) - 1.0), 0.8 + 0.2 * (2.0 * rand.float(f32) - 1.0), 0.5 + 0.2 * (2.0 * rand.float(f32) - 1.0)));
    //        }
    //    }
    //}

    // pick
    {
        const vp = m4.mul(camera.proj, camera.view);
        const inv_vp = m4.inverse(vp);

        const dev_x = 2 * (memory.cursor_pos.x - 0.5);
        const dev_y = 2 * (memory.cursor_pos.y - 0.5);
        var near = m4.mulv(inv_vp, v4{ .x = dev_x, .y = dev_y, .z = 0.0, .w = 1 });
        near.x /= near.w;
        near.y /= near.w;
        near.z /= near.w;
        var far = m4.mulv(inv_vp, v4{ .x = dev_x, .y = dev_y, .z = 1.0, .w = 1 });
        far.x /= far.w;
        far.y /= far.w;
        far.z /= far.w;

        const d = v3.normalize(v3.sub(.{ .x = far.x, .y = far.y, .z = far.z }, .{ .x = near.x, .y = near.y, .z = near.z }));
        const p = v3.add(camera.pos, v3.scale(15.0, d));
        _ = p;

        //cmd.push(primitive.Cube{
        //    .model = m4.modelWithRotations(
        //        p,
        //        .{ .x = 20, .y = 20, .z = 20 },
        //        .{ .x = 0, .y = 0, .z = 0 },
        //    ),
        //}, hsv_to_rgb(80.0 + 10.0 * (2.0 * 0.5 - 1.0), 0.8 + 0.2 * (2.0 * 0.5 - 1.0), 0.5 + 0.2 * (2.0 * 0.5 - 1.0)));
    }

    for (memory.entities.constSlice()) |e| {
        var plane = e.plane;
        plane.model = m4.modelSetScale(e.plane.model, .{ .x = global_plane_size.x, .y = global_plane_size.y, .z = 1 });
        cmd.push(plane, hsv_to_rgb(10, 0.6, 0.7));
        plane.model = m4.modelSetScale(e.plane.model, .{ .x = global_plane_size.x - 10, .y = global_plane_size.y - 10, .z = 2 });
        cmd.push(plane, hsv_to_rgb(10, 0.6, 0.5));
    }

    if (input.isset(.Editor) and memory.selected_entity != null) {
        drawWidget(cmd, &memory.widget);
    }

    // Draw players
    const player_cube_size = 10;
    for (memory.players.slice()) |p| {
        if (p.id == player_id)
            continue;
        if (p.state == .alive) {
            const height: f32 = if (p.crouch) 15 else 22;

            const pos = v3{
                .x = p.pos.x,
                .y = p.pos.y,
                .z = p.pos.z + tile_base_height + tile_max_height + height / 2,
            };
            const scale = v3{
                .x = player_cube_size,
                .y = player_cube_size,
                .z = height,
            };
            const rot = v3{
                .x = 0,
                .y = p.pitch,
                .z = p.yaw,
            };
            const model = m4.modelWithRotations(pos, scale, rot);
            cmd.push(primitive.Cube{
                .model = model,
            }, playerRandomColor(p.id, rand));
        } else {
            const height: f32 = 22;

            const pos = v3{
                .x = p.pos.x,
                .y = p.pos.y,
                .z = p.pos.z + tile_base_height + tile_max_height + height / 2,
            };
            const scale = v3{
                .x = player_cube_size,
                .y = player_cube_size,
                .z = height,
            };
            const rot = v3{
                .x = 0,
                .y = p.pitch + std.math.pi / 2.0,
                .z = p.yaw,
            };
            const model = m4.modelWithRotations(pos, scale, rot);
            cmd.push(primitive.Cube{
                .model = model,
            }, playerRandomColor(p.id, rand));
        }
    }

    //cmd.push(primitive.Cube{
    //    .model = m4.modelWithRotations(.{ .x = -20, .y = 500 * @sin(0.1 * @as(f32, @floatFromInt(memory.time)) / 1e9), .z = 40 }, .{ .x = 10, .y = 10, .z = 10 }, .{
    //        .x = 0,
    //        .y = 0,
    //        .z = 0,
    //    }),
    //}, .{ .r = 255, .g = 255, .b = 255, .a = 255 });

    for (memory.players.slice()) |p| {
        if (p.state == .dead)
            continue;
        // Draw weapons
        if (!input.isset(.Editor)) {
            // TODO(anjo): Store this somewhere...

            // Get player model and extract right/forward/up
            const m = m4.modelWithRotations(p.camera.pos, .{ .x = 1, .y = 1, .z = 1 }, .{
                .x = 0,
                .y = p.pitch,
                .z = p.yaw,
            });
            const right = v3.neg(m4.modelAxisJ(m));
            const forward = m4.modelAxisI(m);
            const up = m4.modelAxisK(m);

            // Dynamic offset due to movement and rotation
            var move_offset = v3.scale(-0.0025, p.vel);
            const view_delta =
                v3.add(v3.scale(-10 * input.cursor_delta.x, right), v3.scale(10 * input.cursor_delta.y, up));
            move_offset = v3.add(move_offset, view_delta);

            const weapon = p.weapons[p.weapon_current];

            var shoot_offset: v3 = .{ .x = 0, .y = 0, .z = 0 };
            switch (weapon.state) {
                .cooldown => {
                    const total_cd = weapon.total_cooldown;
                    const kt = weapon.kickback_time;
                    const cd = (total_cd - weapon.cooldown) / total_cd;
                    const cd_scale = @as(f32, @floatFromInt(@intFromBool(cd < kt))) * (if (cd < kt / 2.0) cd else kt - cd);
                    shoot_offset = v3.scale(-weapon.kickback_scale * cd_scale, p.aim_dir);
                },
                .reload => {
                    const total_cd = weapon.total_reload_cooldown;
                    const cd = (total_cd - weapon.cooldown) / total_cd;
                    const cd_scale = @as(f32, @floatFromInt(@intFromBool(cd < 1.0))) * (if (cd < 0.5) cd else 1.0 - cd);
                    shoot_offset = v3.scale(-10.0 * cd_scale, up);
                },
                else => {},
            }

            move_offset = v3.add(move_offset, shoot_offset);

            switch (weapon.type) {
                .sniper => {
                    const start_offset = v3.add(v3.add(v3.scale(vars.sniper_len / 2 + vars.sniper_off_y, forward), v3.scale(vars.sniper_off_x, right)), v3.scale(vars.sniper_off_z, up));

                    const zoom_fire = p.id == player_id and weapon.state == .zoom and weapon.cooldown / weapon.total_zoom_cooldown == 1.0;

                    var offset: v3 = .{};
                    if (weapon.state == .zoom) {
                        const t = weapon.cooldown / weapon.total_zoom_cooldown;
                        const end_offset = v3.add(v3.add(v3.scale(vars.sniper_scope_off_x + 8.0, forward), v3.scale(0.0, right)), v3.scale(vars.sniper_scope_off_z - 2.5, up));
                        offset = v3.lerp(start_offset, end_offset, t);
                        offset = v3.add(offset, v3.scale(1.0 - t, move_offset));
                    } else {
                        offset = v3.add(start_offset, move_offset);
                    }

                    if (!zoom_fire) {
                        const aim_dir = if (zoom_fire) p.camera.dir else p.aim_dir;
                        const model_sniper = m4.modelFromXDir(v3.add(p.camera.pos, offset), .{ .x = 1, .y = 1, .z = 1 }, aim_dir);

                        cmd.push(primitive.Mesh{
                            .model = model_sniper,
                            .name = "res/models/weapons/sniper",
                            .draw_children = true,
                        }, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
                    }
                },
                .pistol => {
                    const start_offset = v3.add(v3.add(v3.scale(vars.pistol_len / 2 + vars.pistol_off_y, forward), v3.scale(vars.pistol_off_x, right)), v3.scale(vars.pistol_off_z, up));

                    var offset: v3 = .{};
                    if (weapon.state == .zoom) {
                        const t = weapon.cooldown / weapon.total_zoom_cooldown;
                        const end_offset = v3.add(v3.add(v3.scale(vars.pistol_handle_off_x + 12.0, forward), v3.scale(0.0, right)), v3.scale(vars.pistol_handle_off_z - 0.4, up));
                        offset = v3.lerp(start_offset, end_offset, t);
                        offset = v3.add(offset, v3.scale(1.0 - t, move_offset));
                    } else {
                        offset = v3.add(start_offset, move_offset);
                    }

                    const zoom_fire = weapon.cooldown / weapon.total_zoom_cooldown == 1.0;
                    const aim_dir = if (zoom_fire) p.camera.dir else p.aim_dir;
                    const model_pistol = m4.modelFromXDir(v3.add(p.camera.pos, offset), .{ .x = 1, .y = 1, .z = 1 }, aim_dir);

                    cmd.push(primitive.Mesh{
                        .model = model_pistol,
                        .name = "res/models/weapons/pistol",
                        .draw_children = true,
                    }, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
                },
                .nade => {},
            }
        }
    }

    // Draw tracers for hitscans
    for (memory.hitscans.constSlice()) |h| {
        var col = playerRandomColor(h.id_from, rand);
        col.a = @intFromFloat(255.0 * h.time_left / h.total_time);
        cmd.push(primitive.Cube{
            .model = m4.modelFromXDir(
                v3.add(h.ray.pos, v3.scale(h.ray.len / 2 + 2, h.ray.dir)),
                .{ .x = h.ray.len, .y = h.width, .z = h.width },
                h.ray.dir,
            ),
        }, col);
    }

    cmd.push(primitive.End3d{}, .{});

    cmd.push(primitive.Camera2d{
        .target = memory.target,
        .zoom = memory.zoom,
    }, .{});
    //    if (vars.speedometer) {
    //        graphAppend(&memory.vel_graph, v3.len(memory.players.buffer[0].vel));
    //        drawGraph(b, &memory.vel_graph,
    //            .{.x = 10, .y = 80 + 200},
    //            .{.x = 200, .y = 100},
    //            .{.x = 10, .y = 10},
    //            15, 0.75, 0.5);
    //    }

    if (memory.state == .pause) {
        if (pushWindow(memory, cmd, "wow", 0.5, 0.5)) {
            pushText(memory, cmd, "haha");
            pushText(memory, cmd, "abcarstratrastarst");
            pushText(memory, cmd, "haha");
            pushText(memory, cmd, "haha");
            pushText(memory, cmd, "haha");
            pushText(memory, cmd, "haha");
            pushText(memory, cmd, "haha");
            pushText(memory, cmd, "haha");
            //const index = memory.current_window.?;
            //memory.windows.?.items[index].children.append(.{
            //    .text = .{
            //        .str = memory.console_input.slice(),
            //    },
            //}) catch unreachable;
        }
    }

    if (memory.state == .pause) {
        // update cursor position
        memory.cursor_pos.x += input.cursor_delta.x;
        memory.cursor_pos.y -= input.cursor_delta.y;
        memory.cursor_pos.x = std.math.clamp(memory.cursor_pos.x, 0, 1);
        memory.cursor_pos.y = std.math.clamp(memory.cursor_pos.y, 0, 1);

        // check window collisions
        for (memory.windows.items) |*win| {
            if (memory.cursor_pos.x >= win.persistent.x and
                memory.cursor_pos.y >= win.persistent.y + win.persistent.h - top_bar_height and
                memory.cursor_pos.x <= win.persistent.x + win.persistent.w and
                memory.cursor_pos.y <= win.persistent.y + win.persistent.h) {
                win.hover = true;
            } else {
                win.hover = false;
            }

            if (input.isset(.Interact)) {
                if (win.persistent.moving) {
                    win.persistent.moving = false;
                } else if (win.hover) {
                    memory.window_moving_offset = v2.sub(.{ .x = win.persistent.x, .y = win.persistent.y }, memory.cursor_pos);
                    win.persistent.moving = true;
                }
            }

            if (win.persistent.moving) {
                win.persistent.x = memory.cursor_pos.x + memory.window_moving_offset.x;
                win.persistent.y = memory.cursor_pos.y + memory.window_moving_offset.y;
            }
        }

        //for (memory.windows.?.items) |*win| {
        //    if (win.moving) {}
        //}
    }

    if (input.isset(.Console)) {
        //    if (!mouse_enabled) {
        //        mouse_enabled = true;
        //        raylib.EnableCursor();
        //    }
        const console_height = 1.0 / 3.0;
        cmd.push(primitive.Rectangle{ .pos = .{
            .x = 0,
            .y = 1 - (console_height - fontsize),
        }, .size = .{
            .x = 1,
            .y = console_height,
        } }, hsv_to_rgb(200, 0.5, 0.25));
        cmd.push(primitive.Rectangle{ .pos = .{
            .x = 0,
            .y = 1 - console_height,
        }, .size = .{
            .x = 1,
            .y = fontsize,
        } }, hsv_to_rgb(200, 0.5, 0.1));

        {
            var text = primitive.Text{
                .pos = .{
                    .x = 0,
                    .y = 1.0 - console_height,
                },
                .str = undefined,
                .len = memory.console_input.len,
                .size = fontsize,
                .bg = .{ .x = 0, .y = 0, .z = 0, .w = 0 },
                .fg = .{ .x = 0, .y = 1, .z = 0, .w = 1 },
            };
            @memset(&text.str, 0);
            const dst: []u8 = &text.str;
            @memcpy(dst[0..memory.console_input.slice().len], memory.console_input.slice());
            cmd.push(text, hsv_to_rgb(200, 0.75, 0.75));
        }
    }

    {
        const y: f32 = 1.0 - fontsize;
        var text = primitive.Text{
            .pos = .{
                .x = 0,
                .y = y,
            },
            .str = undefined,
            .len = 0,
            .size = fontsize,
            .bg = .{ .x = 0, .y = 0, .z = 0, .w = 0 },
            .fg = .{ .x = 0, .y = 1, .z = 0, .w = 1 },
        };
        @memset(&text.str, 0);

        @memset(&text.str, 0);
        {
            const elapsed: f32 = @floatFromInt(memory.profile.block_last_frame.elapsed_tsc);
            const freq: f32 = @floatFromInt(memory.profile.timer_freq);
            const last_frametime = freq / elapsed;
            const str = std.fmt.bufPrint(&text.str, "fps: {d:5.0}", .{last_frametime}) catch unreachable;
            text.len = str.len;
            text.pos.x = 0.0;
            cmd.push(text, hsv_to_rgb(200, 0.75, 0.75));
        }

        @memset(&text.str, 0);
        {
            const str = std.fmt.bufPrint(&text.str, "speed: {d:5.0}", .{v3.len(memory.players.get(0).vel)}) catch unreachable;
            text.len = str.len;
            text.pos.x = 1.0 - 0.3;
            cmd.push(text, hsv_to_rgb(200, 0.75, 0.75));
        }

        // ammo
        @memset(&text.str, 0);
        {
            const size = 0.05;
            const str = std.fmt.bufPrint(&text.str, "{}", .{player.weapons[player.weapon_current].ammo}) catch unreachable;
            text.len = str.len;
            text.pos.x = 1.0 - 3 * size + size + size / 4.0;
            text.pos.y = 0.05;
            cmd.push(text, hsv_to_rgb(200, 0.75, 0.75));
        }

        // killfeed
        {
            var i: usize = 0;
            while (i < memory.killfeed.size) : (i += 1) {
                const index = (memory.killfeed.bottom + i) % memory.killfeed.data.len;
                const entry = &memory.killfeed.data[index];

                const size = 0.05;
                cmd.push(primitive.Rectangle{
                    .pos = .{
                        .x = 1.0 - 3 * size,
                        .y = 1.0 - (size + 1.5 * size * @as(f32, @floatFromInt(i))),
                    },
                    .size = .{ .x = size, .y = size },
                }, playerColor(entry.from));

                cmd.push(primitive.Rectangle{
                    .pos = .{
                        .x = 1.0 - 3 * size + 2 * size,
                        .y = 1.0 - (size + 1.5 * size * @as(f32, @floatFromInt(i))),
                    },
                    .size = .{ .x = size, .y = size },
                }, playerColor(entry.to));

                @memset(&text.str, 0);
                {
                    const str = std.fmt.bufPrint(&text.str, ">", .{}) catch unreachable;
                    text.len = str.len;
                    text.pos.x = 1.0 - 3 * size + size + size / 4.0;
                    text.pos.y = 1.0 - (size - size / 4.0 + 1.5 * size * @as(f32, @floatFromInt(i)));
                    cmd.push(text, hsv_to_rgb(200, 0.75, 0.75));
                }
            }
        }
    }

    if (memory.state == .pause) {
        // cursor
        const cursor_size = 0.01;
        cmd.push(primitive.Rectangle{
            .pos = .{
                .x = memory.cursor_pos.x - cursor_size / 2.0,
                .y = memory.cursor_pos.y - cursor_size / 2.0,
            },
            .size = .{
                .x = cursor_size,
                .y = cursor_size,
            },
        }, hsv_to_rgb(350, 0.75, 0.75));
    } else {
        const weapon = player.weapons[player.weapon_current];
        const zoom_fire = weapon.type == .sniper and weapon.state == .zoom and weapon.cooldown / weapon.total_zoom_cooldown == 1.0;

        // Crosshair
        if (memory.state == .pause) {
            const cursor_thickness = 0.004;
            const color = hsv_to_rgb(
                (360.0 / 8.0) * @as(f32, @floatFromInt(player_id % 8)),
                0.3,
                0.9,
            );
            cmd.push(primitive.Rectangle{
                .pos = .{
                    .x = 0.5 - cursor_thickness / 2.0,
                    .y = 0.5 - cursor_thickness / 2.0,
                },
                .size = .{
                    .x = cursor_thickness,
                    .y = cursor_thickness,
                },
            }, color);
        } else if (!zoom_fire) {
            //const cursor_thickness = 0.004;
            //const cursor_length = 0.01;
            //const cursor_gap = 0.03;
            //const color = hsv_to_rgb(
            //    (360.0 / 8.0) * @as(f32, @floatFromInt(player_id % 8)),
            //    0.3,
            //    0.9,
            //);
            //cmd.push(primitive.Rectangle{
            //    .pos = .{
            //        .x = 0.5 - cursor_gap / 2.0 - cursor_length,
            //        .y = 0.5 - cursor_thickness / 2.0,
            //    },
            //    .size = .{
            //        .x = cursor_length,
            //        .y = cursor_thickness,
            //    },
            //}, color);
            //cmd.push(primitive.Rectangle{
            //    .pos = .{
            //        .x = 0.5 + cursor_gap / 2.0,
            //        .y = 0.5 - cursor_thickness / 2.0,
            //    },
            //    .size = .{
            //        .x = cursor_length,
            //        .y = cursor_thickness,
            //    },
            //}, color);
            //cmd.push(primitive.Rectangle{
            //    .pos = .{
            //        .x = 0.5 - cursor_thickness / 2.0,
            //        .y = 0.5 + cursor_gap / 2.0,
            //    },
            //    .size = .{
            //        .x = cursor_thickness,
            //        .y = cursor_length,
            //    },
            //}, color);
            //cmd.push(primitive.Rectangle{
            //    .pos = .{
            //        .x = 0.5 - cursor_thickness / 2.0,
            //        .y = 0.5 - cursor_gap / 2.0 - cursor_length,
            //    },
            //    .size = .{
            //        .x = cursor_thickness,
            //        .y = cursor_length,
            //    },
            //}, color);
        } else if (zoom_fire) {
            // Sniper crosshair
            const cursor_thickness = 0.0025;
            const gap = 0.75;

            const color = Color{.r=0,.g=0,.b=0,.a=255};

            cmd.push(primitive.Rectangle{
                .pos = .{
                    .x = 0.0,
                    .y = 0.5 - cursor_thickness / 2.0,
                },
                .size = .{
                    .x = 1.0,
                    .y = cursor_thickness,
                },
            }, color);
            cmd.push(primitive.Rectangle{
                .pos = .{
                    .x = 0.5 - cursor_thickness / 2.0,
                    .y = 0.0,
                },
                .size = .{
                    .x = cursor_thickness,
                    .y = 1.0,
                },
            }, color);

            cmd.push(primitive.Rectangle{
                .pos = .{
                    .x = 0.0,
                    .y = 0.5 + gap / 2.0,
                },
                .size = .{
                    .x = 1.0,
                    .y = 0.5 - gap / 2.0,
                },
            }, color);
            cmd.push(primitive.Rectangle{
                .pos = .{
                    .x = 0.0,
                    .y = 0.0,
                },
                .size = .{
                    .x = 1.0,
                    .y = 0.5 - gap / 2.0,
                },
            }, color);

            cmd.push(primitive.Rectangle{
                .pos = .{
                    .x = 0.5 + gap / 2.0,
                    .y = 0.0,
                },
                .size = .{
                    .x = 0.5 - gap / 2.0,
                    .y = 1.0,
                },
            }, color);
            cmd.push(primitive.Rectangle{
                .pos = .{
                    .x = 0.0,
                    .y = 0.0,
                },
                .size = .{
                    .x = 0.5 - gap / 2.0,
                    .y = 1.0,
                },
            }, color);
        }
    }

    if (input.isset(.DebugShowData)) {
        ui_profile.draw(memory, cmd, input);
    }

    cmd.push(primitive.End2d{}, .{});
}

fn playerColor(id: common.EntityId) Color {
    return hsv_to_rgb(
        (360.0 / 8.0) * @as(f32, @floatFromInt(id % 8)),
        0.8,
        0.5,
    );
}

fn playerRandomColor(id: common.EntityId, rand: std.rand.Random) Color {
    return hsv_to_rgb((360.0 / 8.0) * @as(f32, @floatFromInt(id % 8)) + 10.0 * (2.0 * rand.float(f32) - 1.0), 0.8 + 0.2 * (2.0 * rand.float(f32) - 1.0), 0.5 + 0.2 * (2.0 * rand.float(f32) - 1.0));
}

fn drawCenteredLine(cmd: *draw_api.Buffer, start: v2, end: v2, thickness: f32, color: Color) void {
    const dir = v2.normalize(v2.sub(end, start));
    const ortho = v2{ .x = -dir.y, .y = dir.x };

    const new_start = v2.add(start, v2.scale(thickness / 2.0, ortho));
    const new_end = v2.add(end, v2.scale(thickness / 2.0, ortho));

    cmd.push(cmd, primitive.Line{
        .start = new_start,
        .end = new_end,
        .thickness = thickness,
    }, color);
}

fn drawGraph(cmd: *draw_api.Buffer, g: *Graph, pos: v2, size: v2, margin: v2, h: f32, s: f32, v: f32) void {
    var bg = hsv_to_rgb(50.0, 0.75, 0.05);
    bg.a = @intFromFloat(0.75 * 255.0);
    cmd.push(cmd, primitive.Rectangle{
        .pos = pos,
        .size = size,
    }, bg);

    // Find max/min
    for (g.data) |y| {
        if (y < g.min) {
            g.min = y;
        } else if (y > g.max) {
            g.max = y;
        }
    }

    const scale_x = (size.x - 2 * margin.x) / @as(f32, @floatFromInt(g.data.len - 1));
    const scale_y = (size.y - 2 * margin.y) / (g.max - g.min);

    var last_x: f32 = 0;
    var last_y: f32 = 0;
    for (g.data, 0..) |data_y, i| {
        const x = pos.x + margin.x + scale_x * @as(f32, @floatFromInt(i));
        const y = pos.y - margin.y + size.y - (scale_y * data_y - scale_y * g.min);

        const last_index = (g.top + g.data.len - 1) % g.data.len;
        const dist = (g.data.len + last_index - i) % g.data.len;

        const color = hsv_to_rgb(h, s, v - 0.4 * @as(f32, @floatFromInt(dist)) / @as(f32, @floatFromInt(g.data.len)));
        if (i > 0) {
            drawCenteredLine(cmd, v2{ .x = last_x, .y = last_y }, v2{ .x = x, .y = y }, 2.0, color);
        }

        //push(b, primitive.Cirlce {
        //    .pos = .{.x = x, .y = y},
        //    .radius = 4.0,
        //}, color);

        last_x = x;
        last_y = y;
    }

    cmd.push(primitive.Line{
        .start = .{
            .x = pos.x + margin.x + scale_x * @as(f32, @floatFromInt(g.top)),
            .y = pos.y,
        },
        .end = .{
            .x = pos.x + margin.y + scale_x * @as(f32, @floatFromInt(g.top)),
            .y = pos.y + size.y,
        },
        .thickness = 1.0,
    }, Color{ .r = 128, .g = 128, .b = 128, .a = 255 });
}

fn MultiThreadedArray(comptime T: type, comptime blocksize: usize) type {
    return struct {
        const Self = @This();
        const Block = struct {
            allocator: std.mem.Allocator = undefined,
            next: ?*Block = null,
            head: **Block = undefined,
            used: usize = 0,
            memory: [blocksize]T = undefined,
        };

        roots: []*Block = undefined,
        heads: []*Block = undefined,
        thread_indices: []usize = undefined,
        used_thread_indices: std.atomic.Value(u8) = undefined,

        fn push(self: **Block, t: T) void {
            if (self.*.used == self.*.memory.len) {
                std.debug.assert(self.*.next == null);
                const block = self.*.allocator.alloc(Block, 1) catch unreachable;
                self.*.next = @ptrCast(block.ptr);
                self.*.head.* = self.*.next.?;
                self.*.next.?.* = Block{
                    .allocator = self.*.allocator,
                    .head = self.*.head,
                };
                self.* = self.*.next.?;
            }

            self.*.memory[self.*.used] = t;
            self.*.used += 1;
        }

        fn init(allocator: std.mem.Allocator, num_cpus: usize) Self {
            var self = Self{
                .used_thread_indices = std.atomic.Value(u8).init(0),
            };

            self.roots = allocator.alloc(*Block, num_cpus) catch unreachable;
            self.heads = allocator.alloc(*Block, num_cpus) catch unreachable;
            self.thread_indices = allocator.alloc(usize, num_cpus) catch unreachable;

            for (0..num_cpus) |i| {
                const block = allocator.alloc(Block, 1) catch unreachable;
                self.roots[i] = @ptrCast(block.ptr);
                self.roots[i].* = Block{
                    .allocator = allocator,
                    .head = &self.heads[i],
                };
                self.heads[i] = self.roots[i];
            }

            return self;
        }

        fn get_thread_index(self: *Self) usize {
            const id = std.Thread.getCurrentId();
            for (self.thread_indices[0..self.used_thread_indices.load(.monotonic)], 0..) |_id, i| {
                if (id == _id) {
                    return i;
                }
            }

            const i = self.used_thread_indices.fetchAdd(1, .monotonic);
            self.thread_indices[i] = id;
            return i;
        }

        fn head(self: *Self) *Block {
            const index = self.get_thread_index();
            return self.heads[index];
        }

        fn collect(self: *Self, allocator: std.mem.Allocator) []T {
            var len: usize = 0;
            for (self.roots) |r| {
                var b: ?*Block = r;
                while (true) {
                    len += b.?.used;
                    b = b.?.next;
                    if (b == null) {
                        break;
                    }
                }
            }

            const memory = allocator.alloc(T, len) catch unreachable;
            var index: usize = 0;
            for (self.roots) |r| {
                var b: ?*Block = r;
                while (true) {
                    @memcpy(memory[index..(index + b.?.used)], b.?.memory[0..b.?.used]);
                    index += b.?.used;

                    b = b.?.next;
                    if (b == null) {
                        break;
                    }
                }
            }

            return memory;
        }
    };
}
