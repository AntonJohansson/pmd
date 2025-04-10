const std = @import("std");
const cos = std.math.cos;
const sin = std.math.sin;
const max = std.math.max;
const min = std.math.min;

const voxels = @import("voxels.zig");

const common = @import("common");
const BoundedArray = common.BoundedArray;
const Memory = common.Memory;
const Player = common.Player;
const Input = common.Input;
const hsv_to_rgb = common.color.hsv_to_rgb;
const TransformTree = common.TransformTree;
const TransformTreeNode = common.TransformTreeNode;
const TransformTreeSaveNode = common.TransformTreeSaveNode;

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

var map: common.Map = undefined;

const goosepack = common.goosepack;

var sniper_bolt_back_animation: common.res.Animation = undefined;
var sniper_bolt_forward_animation: common.res.Animation = undefined;
var sniper_trigger_animation: common.res.Animation = undefined;

var weapon_model: m4 = undefined;

export fn init(memory: *Memory) bool {
    voxels.map_init(&map, memory.mem.persistent) catch return false;
    const chunk = voxels.add_chunk(&map, .{ 1, 0, 0 }) catch return false;
    voxels.chunk_build_terrain(memory, chunk);
    voxels.chunk_build_faces(memory, chunk);
    goosepack.setAllocators(memory.mem.frame, memory.mem.persistent);

    common.sniper.tree = from_model(memory, "res/models/weapons/sniper v2", &.{
        .{ .id = common.res.id("res/models/weapons/sniper bolt"), .index = &common.sniper.id_bolt },
        .{ .id = common.res.id("res/models/weapons/sniper bullet exit"), .index = &common.sniper.id_barrel },
        .{ .id = common.res.id("res/models/weapons/sniper iron sight aim"), .index = &common.sniper.id_aim },
    }) orelse {
        return false;
    };

    common.pistol.tree = from_model(memory, "res/models/weapons/pittol", &.{
        .{ .id = common.res.id("res/models/weapons/pittol bullet exit"), .index = &common.pistol.id_barrel },
        .{ .id = common.res.id("res/models/weapons/pittol iron sight"), .index = &common.pistol.id_aim },
    }) orelse {
        return false;
    };

    {
        const anim_name = "res/models/weapons/animation/bolt back";
        const anim_node_entry_info = goosepack.entry_lookup(&memory.pack, anim_name) orelse {
            std.log.info("unable to find animation {s}", .{anim_name});
            return false;
        };
        sniper_bolt_back_animation = goosepack.getResource(&memory.pack, anim_node_entry_info.index).animation;
    }

    {
        const anim_name = "res/models/weapons/animation/bolt forward";
        const anim_node_entry_info = goosepack.entry_lookup(&memory.pack, anim_name) orelse {
            std.log.info("unable to find animation {s}", .{anim_name});
            return false;
        };
        sniper_bolt_forward_animation = goosepack.getResource(&memory.pack, anim_node_entry_info.index).animation;
    }

    {
        const anim_name = "res/models/weapons/animation/fire";
        const anim_node_entry_info = goosepack.entry_lookup(&memory.pack, anim_name) orelse {
            std.log.info("unable to find animation {s}", .{anim_name});
            return false;
        };
        sniper_trigger_animation = goosepack.getResource(&memory.pack, anim_node_entry_info.index).animation;
    }

    return true;
}

export fn deinit(memory: *Memory) void {
    _ = memory;
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

        var widgets: BoundedArray(WidgetMoveDir, 6) = .{};
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

fn player_height(p: *const Player) f32 {
    return if (p.crouch) 15 else 22;
}

fn move(vars: *const Vars, memory: *Memory, player: *Player, input: *const Input, dt: f32) void {
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

    const noclip = player.in_editor;

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
    if (wishspeed != 0.0) {
        wishdir = v3.scale(1.0 / wishspeed, wishvel);
    }
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
            const control = @max(speed, vars.stopspeed);
            const newspeed = @max(speed - dt * control * vars.friction, 0);
            player.vel = v3.scale(newspeed / speed, player.vel);
        }

        const speed_in_wishdir = v3.dot(player.vel, wishdir);
        const addspeed = wishspeed - speed_in_wishdir;

        if (addspeed > 0) {
            var accelspeed = vars.acceleration * dt * wishspeed;
            if (accelspeed > addspeed) {
                accelspeed = addspeed;
            }
            player.vel = v3.add(player.vel, v3.scale(accelspeed, wishdir));
        }
    } else {
        // in air
        var huh_wishspeed = wishspeed;
        if (huh_wishspeed > vars.maxairspeed) {
            huh_wishspeed = vars.maxairspeed;
        }
        const speed_in_wishdir = v3.dot(player.vel, wishdir);
        const addspeed = huh_wishspeed - speed_in_wishdir;
        if (addspeed > 0) {
            var accelspeed = vars.acceleration * dt * wishspeed;
            if (accelspeed > addspeed) {
                accelspeed = addspeed;
            }
            player.vel = v3.add(player.vel, v3.scale(accelspeed, wishdir));
        }
    }

    // delta from movement

    // collision with planes
    var potential_delta = v3.scale(dt, player.vel);
    if (v3.len2(potential_delta) != 0.0) {
        var collided = false;
        var pos_delta = v3{ .x = 0, .y = 0, .z = 0 };
        for (memory.entities.slice()) |e| {
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
    for (memory.entities.slice()) |e| {
        if (intersect.planeModelRay(e.plane.model, global_plane_size, player.pos, .{ .x = 0, .y = 0, .z = -0.5 })) |_| {
            player.onground = true;
        }
    }
    if (intersect.planeModelRay(ground_plane_model, ground_plane_size, player.pos, .{ .x = 0, .y = 0, .z = -0.5 })) |_| {
        player.onground = true;
    }

    // copy player pos to camera pos
    {
        //const weapon = player.weapons[player.weapon_current];
        const in_zoom = false; //weapon.type == .sniper and weapon.state == .zoom and weapon.cooldown == weapon.total_zoom_cooldown;
        const fov = if (in_zoom) vars.fov_zoom else vars.fov;

        const height = player_height(player);
        const offset = v3{ .x = 0, .y = 0, .z = height };
        player.camera.pos = v3.add(player.pos, offset);
        player.camera.dir = player.dir;
        player.camera.view = m4.view(player.camera.pos, player.camera.dir);
        player.camera.proj = m4.projection(0.01, 100000.0, vars.aspect, fov);
    }
}

fn dumpTypeToDisk(writer: *std.Io.Writer, value: anytype) !void {
    const ti = @typeInfo(@TypeOf(value));
    switch (ti) {
        .int => {
            try writer.printInt(value, 10, .lower, .{});
            try writer.writeByte('\n');
        },
        .float => {
            try writer.print("{}\n", .{value});
        },
        .@"struct" => |s| {
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
    var buffer: [1024]u8 = undefined;
    var writer = file.writer(&buffer);

    for (entities) |e| {
        try dumpTypeToDisk(&writer.interface, e);
    }
}

fn readTypeFromDisk(it: *std.mem.TokenIterator(u8, .any), value: anytype) !void {
    const base_type = @typeInfo(@TypeOf(value)).pointer.child;
    const ti = @typeInfo(base_type);
    switch (ti) {
        .int => {
            value.* = std.fmt.parseInt(base_type, it.next().?, 0) catch return;
        },
        .float => {
            value.* = std.fmt.parseFloat(base_type, it.next().?) catch return;
        },
        .@"struct" => |s| {
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

    var buffer: BoundedArray(u8, 4096) = .{};
    const bytes = try file.readAll(&buffer.data);
    buffer.used = @intCast(bytes);

    var it = std.mem.tokenizeAny(u8, buffer.slice(), " \n");

    while (it.peek() != null) {
        var entity: common.Entity = undefined;
        try readTypeFromDisk(&it, &entity);
        memory.entities.append(entity);
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
        persistent = memory.windows_persistent.addOne(memory.mem.persistent) catch unreachable;
        persistent.?.* = .{
            .title = title,
            .x = x,
            .y = y,
            .w = 0.20,
            .h = 0.20,
        };
    }

    const window = memory.windows.addOne(memory.mem.frame) catch unreachable;
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
    if (player.in_editor) {
        voxels.edit(memory, player, input, &map) catch {};
    }

    // TODO(anjo): move
    if (player.weapons[0] == null) {
        player.weapons[0] = common.sniper;
        player.weapons[1] = common.pistol;
        player.weapons[2] = common.nade;
    }

    // Update hitscans
    // @client
    {
        var i: usize = 0;
        while (i < memory.hitscans.used) {
            const h = &memory.hitscans.slice()[i];
            h.time_left -= @min(dt, h.time_left);
            if (h.time_left == 0.0) {
                _ = memory.hitscans.swap_remove(i);
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

    // animation
    {
        const tree = &player.weapons[0].?.tree;
        if (input.isset(.bolt_back)) {
            memory.animation_states.append(memory.mem.persistent, .{
                .begin_time = time_seconds(memory),
                .playback_speed = 1.5,
                .animation = &sniper_bolt_back_animation,
                .tree = tree,
                .index = common.sniper.id_bolt,
            }) catch unreachable;
        }
        if (input.isset(.bolt_forward)) {
            memory.animation_states.append(memory.mem.persistent, .{
                .begin_time = time_seconds(memory),
                .playback_speed = 1.5,
                .animation = &sniper_bolt_forward_animation,
                .tree = tree,
                .index = common.sniper.id_bolt,
            }) catch unreachable;
        }

        // TODO(anjo): @parallelize
        for (memory.animation_states.items) |*state| {
            transform_animation(state, time_seconds(memory));
        }

        var i: usize = 0;
        while (i < memory.animation_states.items.len) {
            if (memory.animation_states.items[i].finished) {
                _ = memory.animation_states.swapRemove(i);
            } else {
                i += 1;
            }
        }

        {
            var anim_map = std.AutoHashMap(struct { res_id: common.res.Id, id: u8 }, std.ArrayList(*common.AnimationState)).init(memory.mem.frame);
            for (memory.animation_states.items) |*state| {
                if (anim_map.getPtr(.{ .res_id = state.tree.id, .id = state.index })) |arr| {
                    var inserted = false;
                    for (arr.items, 0..) |x, j| {
                        if (state.begin_time < x.begin_time) {
                            arr.insert(memory.mem.frame, j, state) catch unreachable;
                            inserted = true;
                            break;
                        }
                    }
                    if (!inserted) {
                        arr.append(memory.mem.persistent, state) catch unreachable;
                    }
                } else {
                    var arr = std.ArrayList(*common.AnimationState){};
                    arr.append(memory.mem.frame, state) catch unreachable;
                    anim_map.put(.{ .res_id = state.tree.id, .id = state.index }, arr) catch unreachable;
                }
            }

            const t = time_seconds(memory);
            var it = anim_map.iterator();
            while (it.next()) |pair| {
                std.log.info("blending: {}", .{pair.value_ptr.items.len});

                if (pair.value_ptr.items.len > 1) {
                    const weights = memory.mem.frame.alloc(f32, pair.value_ptr.items.len) catch unreachable;
                    const tfs = memory.mem.frame.alloc(math.Transform, pair.value_ptr.items.len) catch unreachable;

                    var max_index: usize = 0;
                    var max_time: f32 = 0;
                    for (pair.value_ptr.items, 0..) |state, j| {
                        if (state.end_time > max_time) {
                            max_time = state.end_time;
                            max_index = j;
                        }
                    }

                    for (pair.value_ptr.items, 0..) |state, j| {
                        const half_len = 0.5 * (state.end_time - state.begin_time) / state.playback_speed;
                        const middle = state.begin_time + half_len;
                        tfs[j] = .{ .position = state.translation, .rotation = state.rotation, .scale = state.scale };
                        if (j == 0) {
                            weights[j] = 1.0 - (1.0 / (2.0 * half_len)) * (t - state.begin_time);
                        } else if (j == max_index) {
                            weights[j] = (1.0 / (2.0 * half_len)) * (t - state.begin_time);
                        } else {
                            weights[j] = 1.0 - (1.0 / half_len) * @abs(t - middle);
                        }
                    }
                    const node = &pair.value_ptr.items[0].tree.nodes[pair.key_ptr.id];
                    const tf = math.transform_blend(tfs, weights);
                    node.transform = m4.from_transform(tf);
                } else {
                    const state = pair.value_ptr.items[0];
                    const node = &state.tree.nodes[pair.key_ptr.id];
                    const tf = math.Transform{ .position = state.translation, .rotation = state.rotation, .scale = state.scale };
                    node.transform = m4.from_transform(tf);
                }
            }

            for (memory.animation_states.items) |*state| {
                transform_animation(state, time_seconds(memory));
                if (state.tree.flags.dirty == 1) {
                    update_dirty_nodes(state.tree);
                }
            }
        }
    }

    if (input.isset(.to_editor)) {
        player.in_editor = !player.in_editor;
    }

    // Player movement
    if (player.state == .alive) {
        player.crouch = input.isset(.Crouch);
        player.sprint = input.isset(.Sprint);
        move(vars, memory, player, input, dt);
        aim(vars, memory, player);

        if (!player.in_editor) {
            weaponUpdate(vars, memory, player, input, dt);
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
    if (player.in_editor) {
        // Create new entity
        if (input.isset(.AltInteract)) {
            const id = common.newEntityId();
            memory.entities.append(.{
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
    if (memory.respawns.used > 0) {
        var i: usize = 0;
        while (i < memory.respawns.used) {
            var r = &memory.respawns.data[i];

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
                memory.new_spawns.append(player);

                _ = memory.respawns.swap_remove(i);
            } else {
                i += 1;
            }
        }
    }

    // Handle damage
    if (memory.new_damage.used > 0) {
        for (memory.new_damage.slice()) |d| {
            var player = &memory.players.slice()[d.to];
            if (player.state == .dead)
                continue;
            player.health -= @min(d.damage, player.health);
            if (player.health == 0.0) {
                player.state = .dead;
                memory.respawns.append(.{
                    .id = d.to,
                    .time_left = 2.0,
                });
                memory.new_sounds.append(.{
                    .type = .death,
                    .pos = .{ .x = 0, .y = 0, .z = 0 },
                    .id_from = d.to,
                });
                memory.new_kills.append(.{
                    .from = d.from,
                    .to = d.to,
                });
            }
        }
    }
}

export fn server_update(vars: *const Vars, memory: *Memory, dt: f32) void {
    _ = dt;
    _ = vars;
    if (memory.map_mods.items.len > 0) {
        _ = voxels.apply_modify(memory, &map, memory.map_mods.items);
    }
}

export fn client_update(vars: *const Vars, memory: *Memory, dt: f32) void {
    _ = dt;
    _ = vars;
    if (memory.map_mods.items.len > 0) {
        const dirty_chunks = voxels.apply_modify(memory, &map, memory.map_mods.items);
        voxels.rebuild_chunks(memory, &map, dirty_chunks);
    }
}

fn weaponUpdate(vars: *const Vars, memory: *Memory, player: *Player, input: *const Input, dt: f32) void {
    const weapon = &player.weapons[player.weapon_current].?;

    {
        const m = m4.modelWithRotations(player.camera.pos, .{ .x = 1, .y = 1, .z = 1 }, .{
            .x = 0,
            .y = player.pitch,
            .z = player.yaw,
        });
        const right = v3.neg(m4.modelAxisJ(m));
        const forward = m4.modelAxisI(m);
        const up = m4.modelAxisK(m);

        // Dynamic offset due to movement and rotation
        var move_offset = v3.scale(-0.0025, player.vel);
        const view_delta =
            v3.add(v3.scale(-10 * input.cursor_delta.x, right), v3.scale(10 * input.cursor_delta.y, up));
        move_offset = v3.add(move_offset, view_delta);

        var shoot_offset: v3 = .{ .x = 0, .y = 0, .z = 0 };
        switch (weapon.state) {
            .cooldown => {
                const total_cd = weapon.total_cooldown;
                const kt = weapon.kickback_time;
                const cd = (total_cd - weapon.cooldown) / total_cd;
                const cd_scale = @as(f32, @floatFromInt(@intFromBool(cd < kt))) * (if (cd < kt / 2.0) cd else kt - cd);
                shoot_offset = v3.scale(-weapon.kickback_scale * cd_scale, player.aim_dir);
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

                var offset: v3 = .{};
                if (weapon.state == .zoom) {
                    const t = weapon.cooldown / weapon.total_zoom_cooldown;

                    const tmp_model = m4.modelFromXDir(.{}, .{ .x = 1, .y = 1, .z = 1 }, player.camera.dir);
                    const aim_model = m4.mul(tmp_model, weapon.tree.nodes[weapon.id_aim].root_transform);
                    const zoom_end_offset = m4.modelTranslation(aim_model);

                    const zoom_end = v3.add(zoom_end_offset, v3.scale(-10.0, player.camera.dir));
                    offset = v3.lerp(start_offset, zoom_end.neg(), t);
                    offset = v3.add(offset, v3.scale(1.0 - t, move_offset));
                } else {
                    offset = v3.add(start_offset, move_offset);
                }

                const aim_dir = player.camera.dir;
                //const aim_dir = player.aim_dir;
                weapon_model = m4.modelFromXDir(v3.add(player.camera.pos, offset), .{ .x = 1, .y = 1, .z = 1 }, aim_dir);
            },
            .pistol => {
                const start_offset = v3.add(v3.add(v3.scale(vars.pistol_len / 2 + vars.pistol_off_y, forward), v3.scale(vars.pistol_off_x, right)), v3.scale(vars.pistol_off_z, up));

                const rrot = m4.modelWithRotations(.{}, .{ .x = 1, .y = 1, .z = 1 }, .{ .x = -std.math.pi / 4.0, .y = 0, .z = 0 });

                var offset: v3 = .{};
                if (weapon.state == .zoom) {
                    const t = weapon.cooldown / weapon.total_zoom_cooldown;

                    const tmp_model = m4.mul(m4.modelFromXDir(.{}, .{ .x = 1, .y = 1, .z = 1 }, player.camera.dir), rrot);
                    const aim_model = m4.mul(tmp_model, weapon.tree.nodes[weapon.id_aim].root_transform);
                    const zoom_end_offset = m4.modelTranslation(aim_model);

                    const zoom_end = v3.add(zoom_end_offset, v3.scale(-10.0, player.camera.dir));
                    offset = v3.lerp(start_offset, zoom_end.neg(), t);
                    offset = v3.add(offset, v3.scale(1.0 - t, move_offset));
                } else {
                    offset = v3.add(start_offset, move_offset);
                }

                {
                    const aim_dir = player.camera.dir;
                    weapon_model = m4.mul(m4.modelFromXDir(v3.add(player.camera.pos, offset), .{ .x = 1, .y = 1, .z = 1 }, aim_dir), rrot);
                }
            },
            .nade => {},
        }
    }

    switch (weapon.state) {
        .normal => {
            // fire
            const can_fire = weapon.cooldown <= 0;
            if (can_fire and input.isset(.Interact)) {
                switch (weapon.type) {
                    .sniper => {
                        memory.new_sounds.append(.{
                            .type = .sniper,
                            .pos = .{ .x = 0, .y = 0, .z = 0 },
                            .id_from = player.id,
                        });
                        fireSniperHitscan(memory, player);
                    },
                    .pistol => {
                        memory.new_sounds.append(.{
                            .type = .sniper,
                            .pos = .{ .x = 0, .y = 0, .z = 0 },
                            .id_from = player.id,
                        });
                        firePistolHitscan(memory, player);
                    },
                    .nade => {
                        memory.new_sounds.append(.{
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
                            memory.new_sounds.append(.{
                                .type = .sniper,
                                .pos = .{ .x = 0, .y = 0, .z = 0 },
                                .id_from = player.id,
                            });
                            fireSniperHitscan(memory, player);
                        },
                        .pistol => {
                            memory.new_sounds.append(.{
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

        memory.new_sounds.append(.{
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

        const weapon = player.weapons[player.weapon_current].?;
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

        const weapon = player.weapons[player.weapon_current].?;
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
    const weapon = &player.weapons[1].?;
    const m = m4.mul(weapon_model, weapon.tree.nodes[weapon.id_barrel].root_transform);
    const aim_dir = v3.normalize(m4.modelAxisI(m));
    const start_pos = m4.modelTranslation(m);
    var ray = common.Ray{
        .pos = start_pos,
        .dir = aim_dir,
        .len = 1000.0,
    };

    if (raycastAgainstEntities(memory, start_pos, aim_dir, player.id)) |cast| {
        if (cast.is_player) {
            memory.new_damage.append(.{
                .from = player.id,
                .to = cast.id,
                .damage = 10.0,
            });
            memory.new_sounds.append(.{
                .type = .death,
                .pos = .{ .x = 0, .y = 0, .z = 0 },
                .id_from = cast.id,
            });
        } else {
            memory.new_sounds.append(.{
                .type = .pip,
                .pos = .{ .x = 0, .y = 0, .z = 0 },
                .id_from = cast.id,
            });
        }

        ray.pos = start_pos;
        ray.dir = aim_dir;
        ray.len = cast.intersect.distance;
    }

    // Add tracer for shot
    memory.new_hitscans.append(common.Hitscan{
        .id_from = player.id,
        .ray = ray,
        .width = 0.5,
        .time_left = 0.5,
        .total_time = 0.5,
    });
}

fn fireSniperHitscan(memory: *Memory, player: *Player) void {
    const weapon = &player.weapons[0].?;
    const m = m4.mul(weapon_model, weapon.tree.nodes[weapon.id_barrel].root_transform);
    const aim_dir = v3.normalize(m4.modelAxisI(m));
    const start_pos = m4.modelTranslation(m);

    var ray = common.Ray{
        .pos = start_pos,
        .dir = aim_dir,
        .len = 1000.0,
    };

    if (raycastAgainstEntities(memory, start_pos, aim_dir, player.id)) |cast| {
        if (cast.is_player) {
            memory.new_damage.append(.{
                .from = player.id,
                .to = cast.id,
                .damage = 80.0,
            });
            memory.new_sounds.append(.{
                .type = .death,
                .pos = .{ .x = 0, .y = 0, .z = 0 },
                .id_from = cast.id,
            });
        } else {
            memory.new_sounds.append(.{
                .type = .pip,
                .pos = .{ .x = 0, .y = 0, .z = 0 },
                .id_from = cast.id,
            });
        }

        ray.pos = start_pos;
        ray.dir = aim_dir;
        ray.len = cast.intersect.distance;
    }

    // Add tracer for shot
    memory.new_hitscans.append(common.Hitscan{
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

    for (memory.players.slice()) |p| {
        if (skip_id != null and p.id == skip_id.?)
            continue;
        const height = player_height(&p);
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

    for (memory.entities.slice()) |e| {
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

const bl = 100;
const a0 = math.Quat.fromAxisAngle(.{ .x = 1 }, 0);
const a1 = math.Quat.fromAxisAngle(.{ .x = 1 }, 0);
const b0 = math.Quat.fromAxisAngle(.{ .x = 1 }, std.math.pi / 4.0);
const b1 = math.Quat.fromAxisAngle(.{ .x = 1 }, std.math.pi / 4.0);

export fn draw(vars: *const Vars, memory: *Memory, cmd: *draw_api.CommandBuffer, player_id: common.EntityId, input: *const Input) void {
    _ = vars;
    const player = common.findPlayerById(memory.players.slice(), player_id) orelse return;
    if (player.state == .dead) {
        return;
    }
    const camera = player.camera;

    cmd.push(camera, .{});

    //draw_model(memory, cmd, "res/models/brog/frog", true, m4.modelWithRotations(.{ .x = 50, .y = 0, .z = 20 }, .{ .x = 20, .y = 20, .z = 20 }, .{
    //    .x = 0,
    //    .y = 0,
    //    .z = @as(f32, @floatFromInt(memory.time)) / 1e9,
    //}));

    if (player.weapons[0]) |weapon| {
        draw_model(cmd, &weapon.tree, m4.modelWithRotations(.{ .x = 100, .y = 0, .z = 20 }, .{ .x = 10, .y = 10, .z = 10 }, .{
            .x = 0,
            .y = 0,
            .z = -std.math.pi / 2.0, //@as(f32, @floatFromInt(memory.time)) / 1e9,
        }), true);
    }

    {
        const tree = from_model(memory, "res/models/weapons/.308 bullet", &.{}) orelse {
            return;
        };
        draw_model(cmd, &tree, m4.mul(m4.modelWithRotations(.{ .x = 100, .y = 0, .z = 20 }, .{ .x = 10, .y = 10, .z = 10 }, .{
            .x = 0,
            .y = 0,
            .z = -std.math.pi / 2.0, //@as(f32, @floatFromInt(memory.time)) / 1e9,
        }), common.sniper.tree.nodes[common.sniper.id_bolt].root_transform), true);
    }

    voxels.draw(memory, cmd, player, input, &map);

    // Draw map(?)
    var prng = std.Random.DefaultPrng.init(0);
    const rand = prng.random();

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

    for (memory.entities.slice()) |e| {
        var plane = e.plane;
        plane.model = m4.modelSetScale(e.plane.model, .{ .x = global_plane_size.x, .y = global_plane_size.y, .z = 1 });
        cmd.push(plane, hsv_to_rgb(10, 0.6, 0.7));
        plane.model = m4.modelSetScale(e.plane.model, .{ .x = global_plane_size.x - 10, .y = global_plane_size.y - 10, .z = 2 });
        cmd.push(plane, hsv_to_rgb(10, 0.6, 0.5));
    }

    if (player.in_editor and memory.selected_entity != null) {
        drawWidget(cmd, &memory.widget);
    }

    // Draw players
    const player_cube_size = 10;
    for (memory.players.slice()) |p| {
        if (p.id == player_id)
            continue;
        if (p.state == .alive) {
            const height = player_height(&p);

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
            const height = player_height(&p);

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
        if (p.state == .dead) {
            continue;
        }
        // Draw weapons
        if (!player.in_editor) {
            if (p.weapons[p.weapon_current]) |weapon| {
                switch (weapon.type) {
                    .sniper => {
                        draw_model(cmd, &weapon.tree, weapon_model, true);
                    },
                    .pistol => {
                        draw_model(cmd, &weapon.tree, weapon_model, true);
                    },
                    .nade => {},
                }
            }
        }
    }

    // Draw tracers for hitscans
    for (memory.hitscans.slice()) |h| {
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

    if (memory.active_state == .pause) {
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

    if (memory.active_state == .pause) {
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
                memory.cursor_pos.y <= win.persistent.y + win.persistent.h)
            {
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

    if (memory.active_state == .console) {
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
                .len = memory.console_input.used,
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
            const str = std.fmt.bufPrint(&text.str, "speed: {d:5.0}", .{v3.len(memory.players.data[0].vel)}) catch unreachable;
            text.len = str.len;
            text.pos.x = 1.0 - 0.3;
            cmd.push(text, hsv_to_rgb(200, 0.75, 0.75));
        }

        // ammo
        @memset(&text.str, 0);
        if (player.weapons[player.weapon_current]) |weapon| {
            const size = 0.05;
            const str = std.fmt.bufPrint(&text.str, "{}", .{weapon.ammo}) catch unreachable;
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

    if (memory.active_state == .pause) {
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
        //const weapon = player.weapons[player.weapon_current];
        const zoom_fire = false; //weapon.type == .sniper and weapon.state == .zoom and weapon.cooldown / weapon.total_zoom_cooldown == 1.0;

        // Crosshair
        if (memory.active_state == .pause) {
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

            const color = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };

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

fn playerRandomColor(id: common.EntityId, rand: std.Random) Color {
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

fn from_model(memory: *Memory, name: []const u8, save_nodes: ?[]const TransformTreeSaveNode) ?TransformTree {
    const node_entry_info = goosepack.entry_lookup(&memory.pack, name) orelse {
        std.log.info("unable to find pack entry {s}", .{name});
        return null;
    };
    const node = goosepack.getResource(&memory.pack, node_entry_info.index).model_node;

    if (save_nodes != null) {
        for (node.tree.node_ids, 0..) |id, i| {
            for (save_nodes.?) |s| {
                if (id == s.id) {
                    s.index.* = @intCast(i);
                }
            }
        }
    }

    return node.tree;

    //const model = goosepack.getResource(&memory.pack, @intCast(@as(i32, @intCast(node_entry_info.index)) + node.root_entry_relative_index)).model;
    //
    //    var nodes = std.ArrayList(TransformTreeNode).initCapacity(memory.mem.frame, 8) catch unreachable;
    //
    //    var stack = std.ArrayList(struct {
    //        info: goosepack.EntryInfo,
    //        parent_transform: m4,
    //        parent_index: u8,
    //    }).initCapacity(memory.mem.frame, 16) catch unreachable;
    //    stack.append(.{
    //        .info = node_entry_info,
    //        .parent_transform = math.m4_identity,
    //        .parent_index = 0,
    //    }) catch unreachable;
    //
    //    while (stack.popOrNull()) |item| {
    //        const mesh_node = goosepack.getResource(&memory.pack, item.info.index).model_node;
    //        const transform = m4.mul(item.parent_transform, mesh_node.transform);
    //        if (save_nodes != null) {
    //            for (save_nodes.?) |s| {
    //                if (item.info.entry.id == s.id) {
    //                    s.index.* = @intCast(nodes.items.len);
    //                }
    //            }
    //        }
    //        nodes.append(.{
    //            .transform = transform,
    //            .root_transform = math.m4_identity,
    //            .mesh_index = mesh_node.mesh_index,
    //            .parent = item.parent_index,
    //            .flags = .{
    //                .dirty = 1,
    //            },
    //        }) catch unreachable;
    //        if (item.info.entry.children) |children| {
    //            for (children) |c| {
    //                const index: u32 = @intCast(@as(i32, @intCast(item.info.index)) + c);
    //                const entry = memory.pack.entries.?.items[index];
    //                stack.append(.{
    //                    .info = .{ .entry = entry, .index = index },
    //                    .parent_transform = transform,
    //                    .parent_index = @intCast(nodes.items.len - 1),
    //                }) catch unreachable;
    //            }
    //        }
    //    }
    //
    //    const tree = TransformTree{
    //        .nodes = memory.mem.persistent.alloc(TransformTreeNode, nodes.items.len) catch unreachable,
    //        .model = model,
    //        .flags = .{
    //            .dirty = 1,
    //        },
    //    };
    //    @memcpy(tree.nodes, nodes.items);
    //
    //    return tree;

}

fn update_dirty_nodes(tree: *const TransformTree) void {
    std.debug.assert(tree.flags.dirty == 1);
    var found_dirty = false;
    for (tree.nodes[1..]) |*n| {
        if (!found_dirty and n.flags.dirty == 1) {
            found_dirty = true;
        }
        if (found_dirty) {
            n.root_transform = m4.mul(tree.nodes[n.parent].root_transform, n.transform);
        }
    }
}

fn transform_tree(tree: *const TransformTree, transform: m4) void {
    for (tree.nodes[0..]) |*n| {
        n.new_transform = m4.mul(transform, n.root_transform);
    }
}

fn transform_animation(state: *common.AnimationState, time: f32) void {
    if (state.finished) {
        return;
    }

    const node = &state.tree.nodes[state.index];
    const t = time - state.begin_time;
    var finished = true;

    var end_time: f32 = 0;
    if (state.animation.rotation) |rotation| {
        end_time = @max(end_time, rotation.time[rotation.time.len - 1]);
        const len = (rotation.time[rotation.time.len - 1] - rotation.time[0]) / state.playback_speed;
        const dt = len / @as(f32, @floatFromInt(rotation.time.len - 1));
        if (t <= len) {
            const ti0: usize = @intFromFloat(@floor(t / dt));
            const ti1: usize = @intFromFloat(@ceil(t / dt));
            std.debug.assert(ti0 >= 0 and ti0 < rotation.time.len);
            std.debug.assert(ti1 >= 0 and ti1 < rotation.time.len);
            const it = @mod(t, dt) / dt;
            const q0 = rotation.data[ti0];
            const q1 = rotation.data[ti1];
            state.rotation = math.Quat.lerp(q0, q1, it);
            finished = false;
        }
    }

    if (state.animation.scale) |scale| {
        end_time = @max(end_time, scale.time[scale.time.len - 1]);
        const len = (scale.time[scale.time.len - 1] - scale.time[0]) / state.playback_speed;
        const dt = len / @as(f32, @floatFromInt(scale.time.len - 1));
        if (t <= len) {
            const ti0: usize = @intFromFloat(@floor(t / dt));
            const ti1: usize = @intFromFloat(@ceil(t / dt));
            std.debug.assert(ti0 >= 0 and ti0 < scale.time.len);
            std.debug.assert(ti1 >= 0 and ti1 < scale.time.len);
            const it = @mod(t, dt) / dt;
            const v0 = scale.data[ti0];
            const v1 = scale.data[ti1];
            state.scale = v3.lerp(v0, v1, it);
            finished = false;
        }
    }

    if (state.animation.translation) |translation| {
        end_time = @max(end_time, translation.time[translation.time.len - 1]);
        const len = (translation.time[translation.time.len - 1] - translation.time[0]) / state.playback_speed;
        const dt = len / @as(f32, @floatFromInt(translation.time.len - 1));
        if (t <= len) {
            const ti0: usize = @intFromFloat(@floor(t / dt));
            const ti1: usize = @intFromFloat(@ceil(t / dt));
            std.debug.assert(ti0 >= 0 and ti0 < translation.time.len);
            std.debug.assert(ti1 >= 0 and ti1 < translation.time.len);
            const it = @mod(t, dt) / dt;
            const v0 = translation.data[ti0];
            const v1 = translation.data[ti1];
            state.translation = v3.lerp(v0, v1, it);
            finished = false;
        }
    }

    state.end_time = state.begin_time + end_time;

    if (!finished) {
        node.flags.dirty = 1;
        state.tree.flags.dirty = 1;
    } else {
        state.finished = true;
    }
}

fn time_seconds(memory: *const Memory) f32 {
    return @as(f32, @floatFromInt(memory.time)) / 1e9;
}

fn draw_model(cmd: *draw_api.CommandBuffer, tree: *const TransformTree, model_transform: math.m4, root: bool) void {
    for (tree.nodes) |n| {
        if (n.mesh_index) |mesh_index| {
            const transform = if (root) n.root_transform else n.transform;
            cmd.push(primitive.Mesh{
                .transform = m4.mul(model_transform, transform),
                .mesh_index = mesh_index,
                .model_id = tree.id,
            }, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
        }
    }

    //const node_entry_info = goosepack.entry_lookup(&memory.pack, name) orelse {
    //    std.log.info("unable to find pack entry {s}", .{name});
    //    return;
    //};
    //const node = goosepack.getResource(&memory.pack, node_entry_info.index).model_node;
    //const model = goosepack.getResource(&memory.pack, @intCast(@as(i32, @intCast(node_entry_info.index)) + node.root_entry_relative_index)).model;

    //if (draw_children and node_entry_info.entry.children != null) {
    //    var stack = std.ArrayList(struct {
    //        info: goosepack.EntryInfo,
    //        parent_transform: m4,
    //    }).initCapacity(memory.mem.frame, 128) catch unreachable;
    //    stack.appendAssumeCapacity(.{ .info = node_entry_info, .parent_transform = model_transform });
    //    while (stack.popOrNull()) |item| {
    //        const mesh_node = goosepack.getResource(&memory.pack, item.info.index).model_node;

    //        var animation_transform = math.m4_identity;
    //        if (std.mem.eql(u8, item.info.entry.name, animation.?.target)) {
    //            if (animation.?.rotation) |rotation| {
    //                const len = rotation.time[rotation.time.len - 1] - rotation.time[0];
    //                const dt = len / @as(f32, @floatFromInt(rotation.time.len - 1));
    //                const t = @mod(@as(f32, @floatFromInt(memory.time)) / 1e9, len);
    //                const ti0: usize = @intFromFloat(@floor(t / dt));
    //                const ti1: usize = @intFromFloat(@ceil(t / dt));
    //                std.debug.assert(ti0 >= 0 and ti0 < rotation.time.len);
    //                std.debug.assert(ti1 >= 0 and ti1 < rotation.time.len);
    //                const it = @mod(t, dt) / dt;
    //                const q0 = rotation.data[ti0];
    //                const q1 = rotation.data[ti1];
    //                const q = math.Quat.lerp(q0, q1, it);
    //                animation_transform = m4.mul(m4.fromQuat(q), animation_transform);
    //            }
    //            if (animation.?.scale) |scale| {
    //                const len = scale.time[scale.time.len - 1] - scale.time[0];
    //                const dt = len / @as(f32, @floatFromInt(scale.time.len - 1));
    //                const t = @mod(@as(f32, @floatFromInt(memory.time)) / 1e9, len);
    //                const ti0: usize = @intFromFloat(@floor(t / dt));
    //                const ti1: usize = @intFromFloat(@ceil(t / dt));
    //                std.debug.assert(ti0 >= 0 and ti0 < scale.time.len);
    //                std.debug.assert(ti1 >= 0 and ti1 < scale.time.len);
    //                const it = @mod(t, dt) / dt;
    //                const v0 = scale.data[ti0];
    //                const v1 = scale.data[ti1];
    //                const v = v3.lerp(v0, v1, it);
    //                animation_transform = m4.mul(m4.fromScale(v), animation_transform);
    //            }
    //            if (animation.?.translation) |translation| {
    //                const len = translation.time[translation.time.len - 1] - translation.time[0];
    //                const dt = len / @as(f32, @floatFromInt(translation.time.len - 1));
    //                const t = @mod(@as(f32, @floatFromInt(memory.time)) / 1e9, len);
    //                const ti0: usize = @intFromFloat(@floor(t / dt));
    //                const ti1: usize = @intFromFloat(@ceil(t / dt));
    //                std.debug.assert(ti0 >= 0 and ti0 < translation.time.len);
    //                std.debug.assert(ti1 >= 0 and ti1 < translation.time.len);
    //                const it = @mod(t, dt) / dt;
    //                const v0 = translation.data[ti0];
    //                const v1 = translation.data[ti1];
    //                const v = v3.lerp(v0, v1, it);
    //                animation_transform = m4.mul(m4.fromTranslation(v), animation_transform);
    //            }
    //        } else {
    //            animation_transform = mesh_node.transform;
    //        }

    //        const transform = m4.mul(item.parent_transform, animation_transform);
    //        if (mesh_node.mesh_index) |mesh_index| {
    //            const mesh = model.meshes[mesh_index];
    //            cmd.push(primitive.Mesh{
    //                .transform = transform,
    //                .mesh = mesh,
    //                .mesh_index = mesh_index,
    //                .model_id = model.id,
    //                .materials = model.materials,
    //            }, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
    //        }

    //        if (item.info.entry.children) |children| {
    //            for (children) |c| {
    //                const index: u32 = @intCast(@as(i32, @intCast(item.info.index)) + c);
    //                const entry = memory.pack.entries.?.items[index];
    //                stack.appendAssumeCapacity(.{ .info = .{ .entry = entry, .index = index }, .parent_transform = transform });
    //            }
    //        }
    //    }
    //} else {
    //    const transform = m4.mul(model_transform, node.transform);
    //    if (node.mesh_index) |mesh_index| {
    //        const mesh = model.meshes[mesh_index];
    //        cmd.push(primitive.Mesh{
    //            .transform = transform,
    //            .mesh = mesh,
    //            .mesh_index = mesh_index,
    //            .model_id = model.id,
    //            .materials = model.materials,
    //        }, .{ .r = 255, .g = 255, .b = 255, .a = 255 });
    //    }
    //}
}
