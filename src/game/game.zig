const std = @import("std");
const cos = std.math.cos;
const sin = std.math.sin;
const max = std.math.max;
const min = std.math.min;

const common = @import("common");
const Memory = common.Memory;
const Player = common.Player;
const Input = common.Input;

const Graph = common.Graph;
const graphAppend = common.graphAppend;

const config = common.config;
const Vars = config.Vars;

const primitive = common.primitive;
const Color = primitive.Color;

const stat = common.stat;

const bb = common.bb;
const CircularArray = bb.CircularArray;

const math = common.math;
const v4 = math.v4;
const v3 = math.v3;
const v2 = math.v2;
const m4 = math.m4;
const m4view = math.m4view;
const m4projection = math.m4projection;
const m4inverse = math.m4inverse;
const m4mulv = math.m4mulv;
const m4mul = math.m4mul;
const m4print = math.m4print;
const v2add = math.v2add;
const v2sub = math.v2sub;
const v2normalize = math.v2normalize;
const v2scale = math.v2scale;
const v3scale = math.v3scale;
const v3add = math.v3add;
const v3sub = math.v3sub;
const v3cross = math.v3cross;
const v3neg = math.v3neg;
const v3normalize = math.v3normalize;
const v3len = math.v3len;
const v3len2 = math.v3len2;
const v3dot = math.v3dot;

const draw_api = common.draw;
const pushCube = draw_api.pushCube;
const pushVector = draw_api.pushVector;
const pushPlane = draw_api.pushPlane;
const pushRectangle = draw_api.pushRectangle;
const pushLine = draw_api.pushLine;
const pushText = draw_api.pushText;
const push = draw_api.push;
const pushNoDepth = draw_api.pushNoDepth;
const begin3d = draw_api.begin3d;
const end3d = draw_api.end3d;
const begin2d = draw_api.begin2d;
const end2d = draw_api.end2d;

const widget_length = 20.0;
const widget_thickness = 2.0;
const widget_size_x = v3 {.x=widget_length,.y=widget_thickness,.z=widget_thickness};
const widget_size_y = v3 {.x=widget_thickness,.y=widget_length,.z=widget_thickness};
const widget_size_z = v3 {.x=widget_thickness,.y=widget_thickness,.z=widget_length};
const widget_plane_length = 8.0;
const widget_plane_thickness = 0.5;
const widget_size_plane_xy = v3 {.x=widget_plane_length,.y=widget_plane_length,.z=widget_plane_thickness};
const widget_size_plane_yz = v3 {.x=widget_plane_thickness,.y=widget_plane_length,.z=widget_plane_length};
const widget_size_plane_xz = v3 {.x=widget_plane_length,.y=widget_plane_thickness,.z=widget_plane_length};

const global_plane_size = v2 {.x = 100.0, .y = 100.0};

const textheight = 1.0/30.0;
const fontsize = textheight;

fn updateWidget(widget: *common.WidgetModel, input: *const Input, start: v3, dir: v3) void {
    var model = widget.model.*;

    const held = input.isset(.Interact);

    if (widget.move_normal == null) {
        const WidgetMoveDir = struct {
            intersect: IntersectResult,

            move_dir: ?v3 = null,
            move_normal: v3,

            rotate_center: ?v3 = null,
            move_type: common.WidgetMoveType = .move_axis,
        };

        const i = math.m4modelAxisI(model);
        const j = math.m4modelAxisJ(model);
        const k = math.m4modelAxisK(model);
        const pos = math.m4modelTranslation(model);

        var widgets: std.BoundedArray(WidgetMoveDir, 6) = .{};
        const move_x = intersectCubeLine(model, widget_size_x, start, dir);
        if (move_x) |intersect|
            widgets.appendAssumeCapacity(.{.intersect=intersect, .move_dir=i, .move_normal=k});
        const move_y = intersectCubeLine(model, widget_size_y, start, dir);
        if (move_y) |intersect|
            widgets.appendAssumeCapacity(.{.intersect=intersect, .move_dir=j, .move_normal=k});
        const move_z = intersectCubeLine(model, widget_size_z, start, dir);
        if (move_z) |intersect|
            widgets.appendAssumeCapacity(.{.intersect=intersect, .move_dir=k, .move_normal=i});
        const move_xy = intersectCubeLine(model, widget_size_plane_xy, start, dir);
        if (move_xy) |intersect|
            widgets.appendAssumeCapacity(.{.intersect=intersect, .move_normal=k});
        const move_yz = intersectCubeLine(model, widget_size_plane_yz, start, dir);
        if (move_yz) |intersect|
            widgets.appendAssumeCapacity(.{.intersect=intersect, .move_normal=i});
        const move_xz = intersectCubeLine(model, widget_size_plane_xz, start, dir);
        if (move_xz) |intersect|
            widgets.appendAssumeCapacity(.{.intersect=intersect, .move_normal=j});
        const rot_x = intersectAnnulusLine(pos, 9.0, 10.0, i, start,dir);
        if (rot_x) |intersect|
            widgets.appendAssumeCapacity(.{.intersect=intersect, .move_normal=i, .rotate_center=pos, .move_type=.rotate_x});
        const rot_y = intersectAnnulusLine(pos, 9.0, 10.0, j, start,dir);
        if (rot_y) |intersect|
            widgets.appendAssumeCapacity(.{.intersect=intersect, .move_normal=j, .rotate_center=pos, .move_type=.rotate_y});
        const rot_z = intersectAnnulusLine(pos, 9.0, 10.0, k, start,dir);
        if (rot_z) |intersect|
            widgets.appendAssumeCapacity(.{.intersect=intersect, .move_normal=k, .rotate_center=pos, .move_type=.rotate_z});

        var closest: ?WidgetMoveDir = null;
        for (widgets.constSlice()) |w| {
            if (closest == null or w.intersect.distance < closest.?.intersect.distance) {
                closest = w;
            }
        }

        if (closest != null) {
            widget.original_model = model;
            widget.original_interact_pos = intersectInfinitePlaneAxisLine(pos, closest.?.move_normal, start,dir).?;
            widget.move_dir = closest.?.move_dir;
            widget.move_normal = closest.?.move_normal;
            widget.rotate_center = closest.?.rotate_center;
            widget.move_type = closest.?.move_type;
        }
    } else {
        if (held) {
            const pos = math.m4modelTranslation(model);
            if (intersectInfinitePlaneAxisLine(pos, widget.move_normal.?, start,dir)) |p| {
                const delta = v3sub(p, widget.original_interact_pos);

                if (widget.move_dir) |d| {
                    // dir
                    const new_pos = v3add(pos, v3scale(v3dot(delta, d), d));
                    widget.model.* = math.m4modelSetTranslation(model, new_pos);
                    widget.original_interact_pos = p;
                } else if (widget.rotate_center) |r| {
                    // rotate
                    const l1 = v3sub(widget.original_interact_pos, r);
                    const l2 = v3sub(p, r);
                    const angle = std.math.atan2(f32, v3dot(v3cross(l1,l2), widget.move_normal.?), v3dot(l1,l2));

                    model = widget.original_model;
                    const rot = math.m4modelRot(model);
                    if (widget.move_type == .rotate_x) {
                        widget.model.* = math.m4modelSetRot(model, math.m3mul(rot, math.m3modelRotX(angle)));
                    } else if (widget.move_type == .rotate_y) {
                        widget.model.* = math.m4modelSetRot(model, math.m3mul(rot, math.m3modelRotY(angle)));
                    } else if (widget.move_type == .rotate_z) {
                        widget.model.* = math.m4modelSetRot(model, math.m3mul(rot, math.m3modelRotZ(angle)));
                    }
                } else {
                    // plane
                    const new_pos = v3add(pos, delta);
                    widget.model.* = math.m4modelSetTranslation(model, new_pos);
                    widget.original_interact_pos = p;
                }
            }
        } else {
            widget.move_dir = null;
            widget.move_normal = null;
        }
    }
}

fn drawWidget(b: *draw_api.Buffer, widget: *common.WidgetModel) void {
    const model = widget.model.*;
    // x y z axes
    push(b, primitive.Cube2 {
        .model = math.m4modelSetScale(model, v3scale(1.0, widget_size_x)),
    }, .{.r=255,.g=0,.b=0,.a=255});
    push(b, primitive.Cube2 {
        .model = math.m4modelSetScale(model, v3scale(1.0, widget_size_y)),
    }, .{.r=0,.g=255,.b=0,.a=255});
    push(b, primitive.Cube2 {
        .model = math.m4modelSetScale(model, v3scale(1.0, widget_size_z)),
    }, .{.r=0,.g=0,.b=255,.a=255});

    push(b, primitive.Cube2 {
        .model = math.m4modelSetScale(model, v3scale(1.0, widget_size_plane_xy)),
    }, .{.r=0,.g=0,.b=255,.a=255});
    push(b, primitive.Cube2 {
        .model = math.m4modelSetScale(model, v3scale(1.0, widget_size_plane_yz)),
    }, .{.r=255,.g=0,.b=0,.a=255});
    push(b, primitive.Cube2 {
        .model = math.m4modelSetScale(model, v3scale(1.0, widget_size_plane_xz)),
    }, .{.r=0,.g=255,.b=0,.a=255});

    const rot = math.m4modelRot(model);
    push(b, primitive.Circle{
        .model = math.m4modelSetRot(model, math.m3mul(rot, math.m3modelRotY(std.math.pi/2.0))),
    }, .{.r=255,.g=0,.b=0,.a=255});
    push(b, primitive.Circle{
        .model = math.m4modelSetRot(model, math.m3mul(rot, math.m3modelRotX(std.math.pi/2.0))),
    }, .{.r=0,.g=255,.b=0,.a=255});
    push(b, primitive.Circle{
        .model = math.m4modelSetRot(model, math.m3mul(rot, math.m3modelRotZ(std.math.pi/2.0))),
    }, .{.r=0,.g=0,.b=255,.a=255});
}

fn playerMove(vars: *const Vars, memory: *Memory, player: *Player, input: *const Input) void {
    const dt = 1.0/165.0;

    if (!memory.show_cursor) {
        if (input.cursor_delta.x != 0 or input.cursor_delta.y != 0) {
            player.yaw   -= input.cursor_delta.x;
            player.pitch += input.cursor_delta.y;
            player.pitch = std.math.clamp(player.pitch, -std.math.pi/2.0+0.1, std.math.pi/2.0-0.1);
            player.dir = v3 {
                .x = cos(player.yaw)*cos(player.pitch),
                .y = sin(player.yaw)*cos(player.pitch),
                .z = -sin(player.pitch),
            };
        }
    }

    const noclip = input.isset(.Editor);

    // compute wishvel
    var wishvel: v3 = .{};
    {
        var dx: f32 = -1.0*@as(f32, @floatFromInt(@intFromBool(input.isset(.MoveForward)))) + 1.0*@as(f32, @floatFromInt(@intFromBool(input.isset(.MoveBack))));
        var dy: f32 = -1.0*@as(f32, @floatFromInt(@intFromBool(input.isset(.MoveLeft))))    + 1.0*@as(f32, @floatFromInt(@intFromBool(input.isset(.MoveRight))));
        var dz: f32 =  0.0;
        if (noclip) {
            dz = 1.0*@as(f32, @floatFromInt(@intFromBool(input.isset(.MoveUp)))) - 1.0*@as(f32, @floatFromInt(@intFromBool(input.isset(.MoveDown))));
        }

        const len2 = dx*dx + dy*dy + dz*dz;

        if (len2 > 0.0) {
            const len = std.math.sqrt(len2);
            dx /= len;
            dy /= len;
            dz /= len;

            const up      = v3 {.x = 0, .y = 0, .z = 1};
            const forward = v3 {.x = cos(player.yaw), .y = sin(player.yaw), .z = 0};
            const right   = v3cross(forward, up);

            const mod: f32 = if (player.sprint) vars.sprintmod else 1.0;
            wishvel = v3add(v3add(v3scale(-mod*vars.forwardspeed*dx, forward), v3scale(vars.sidespeed*dy, right)), v3scale(vars.upspeed*dz, up));
        }
    }

    // Apply gravity
    if (!player.onground) {
        player.vel.z += dt*vars.gravity;
    }

    if (player.onground and input.isset(.Jump)) {
        player.vel.z += vars.jumpspeed;
    }

    // Compute wishdir/wishspeed and bound wishvel
    var wishspeed = v3len(wishvel);
    var wishdir = v3 {};
    if (wishspeed != 0.0)
        wishdir = v3scale(1.0/wishspeed, wishvel);
    if (wishspeed > vars.maxspeed) {

        wishvel = v3scale(vars.maxspeed/wishspeed, wishvel);
        wishspeed = vars.maxspeed;
    }

    if (noclip) {
        player.vel = wishvel;
    } else if (player.onground) {
        // on ground

        // Apply friction
        const speed = v3len(player.vel);
        if (speed > 0) {
            const control = if (speed < vars.stopspeed) vars.stopspeed else speed;
            var newspeed = speed - dt*control*vars.friction;
            if (newspeed < 0)
                newspeed = 0;
            newspeed /= speed;
            player.vel = v3scale(newspeed, player.vel);
        }

        const speed_in_wishdir = v3dot(player.vel, wishdir);
        const addspeed = wishspeed - speed_in_wishdir;

        if (addspeed > 0) {
            var accelspeed = vars.acceleration*dt*wishspeed;
            if (accelspeed > addspeed)
                accelspeed = addspeed;
            player.vel = v3add(player.vel, v3scale(accelspeed, wishdir));
        }
    } else {
        // in air
        var huh_wishspeed = wishspeed;
	if (huh_wishspeed > vars.maxairspeed)
		huh_wishspeed = vars.maxairspeed;
        const speed_in_wishdir = v3dot(player.vel, wishdir);
        const addspeed = huh_wishspeed - speed_in_wishdir;
        if (addspeed > 0) {
            var accelspeed = vars.acceleration*dt*wishspeed;
            if (accelspeed > addspeed)
                accelspeed = addspeed;
            player.vel = v3add(player.vel, v3scale(accelspeed, wishdir));
        }
    }

    // delta from movement
    var potential_delta = v3scale(dt, player.vel);

    // collision with planes
    //const dir_len = v3len(delta);
    //if (dir_len != 0.0) {
    //    const dir = v3scale(@max(0.5, dir_len)/dir_len, delta);
    //    for (memory.entities.constSlice()) |e| {
    //        if (intersectPlaneModelRay(e.plane.model, global_plane_size, player.pos, dir)) |intersect| {

    //            if (intersect.pos.z <= player.pos.z and intersect.distance <= 0.5) {
    //                player.vel.z = 0.0;
    //                player.onground = true;
    //            }

    //            const len = v3len(delta);
    //            const delta_dir = v3scale(1.0/len, delta);
    //            const dist = @max(intersect.distance-0.5, 0.0);
    //            delta = v3scale(dist, delta_dir);

    //            //var behind_plane = v3scale(len-dist, delta_dir);
    //            //const len_to_plane = v3dot(behind_plane, intersect.normal);
    //            //behind_plane = v3sub(behind_plane, v3scale(len_to_plane, intersect.normal));

    //            //player.onground = true;

    //            //delta = v3add(delta, behind_plane);

    //            const speed = v3len(player.vel);
    //            if (speed != 0.0) {
    //                const vel_proj = v3scale(v3dot(player.vel, intersect.normal), intersect.normal);
    //                const new_vel_dir = v3normalize(v3sub(player.vel, vel_proj));
    //                player.vel = v3scale(speed, new_vel_dir);
    //            }

    //            //_ = intersect;
    //            ////if (intersect.distance <= 0.5) {
    //            //    if (player.vel.z < 0) {
    //            //        player.vel.z = 0;
    //            //    }
    //            //    if (delta.z < 0) {
    //            //        delta.z = 0;
    //            //    }
    //            //    player.onground = true;
    //            ////}
    //        }
    //    }
    //}
    if (v3len2(potential_delta) != 0.0) {
        for (memory.entities.constSlice()) |e| {
            if (intersectPlaneModelRay(e.plane.model, global_plane_size, player.pos, potential_delta)) |intersect| {

                // If we cross the plane we completely cancel out the normal component of the movement
                //{
                //const d = v3dot(delta, intersect.normal);
                //delta = v3add(delta, v3scale(-d, intersect.normal));
                //}

                {
                    const ortho_dist_to_plane = v3dot(v3sub(player.pos, intersect.pos), intersect.normal);
                    player.pos = v3add(player.pos, v3scale(0.25 - ortho_dist_to_plane, intersect.normal));

                    const dot = v3dot(player.vel, intersect.normal);
                    player.vel = v3add(player.vel, v3scale(-dot, intersect.normal));
                }


                //const speed = v3len(player.vel);
                //if (speed != 0.0) {
                //    const vel_proj = v3scale(v3dot(player.vel, intersect.normal), intersect.normal);
                //    const new_vel_dir = v3normalize(v3sub(player.vel, vel_proj));
                //    player.vel = v3scale(speed, new_vel_dir);
                //}
            }
        }
    }

    player.onground = false;
    for (memory.entities.constSlice()) |e| {
        if (intersectPlaneModelRay(e.plane.model, global_plane_size, player.pos, .{.x=0,.y=0,.z=-0.5})) |intersect| {
            _ = intersect;
            player.onground = true;
        }
    }

    // integrate velocity
    const delta = v3scale(dt, player.vel);
    player.pos = v3add(player.pos, delta);

    // collision z dir
    if (player.pos.z < 0) {
        player.pos.z = 0;
        player.vel.z = 0;
    }
    if (player.pos.z == 0)
        player.onground = true;
}

fn dumpTypeToDisk(writer: anytype, value: anytype) !void {
    const ti = @typeInfo(@TypeOf(value));
    switch (ti) {
        .Int => {
            try std.fmt.formatInt(value, 10, .lower, .{}, writer);
            try writer.writeByte('\n');
        },
        .Float => {
            try std.fmt.formatFloatDecimal(value, .{}, writer);
            try writer.writeByte('\n');
        },
        .Struct => |s| {
            try writer.writeAll("struct:\n");
            inline for (s.fields) |field| {
                try writer.writeAll(field.name);
                try writer.writeAll(": ");
                try dumpTypeToDisk(writer, @field(value, field.name));
            }
        },
        else => std.log.err("Unhandled type in writing entities: {}", ti),
    }
}

fn dumpEntitiesToDisk(entities: []common.Entity) !void {
    const filename = "entities.data";
    const file = std.fs.cwd().createFile(filename, .{}) catch |err|  {
        std.log.err("Failed to open file: {s} ({})", .{filename, err});
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
        else => std.log.err("Unhandled type in writing entities: {}", ti),
    }
}

fn readEntitiesFromDisk(memory: *common.Memory) !void {
    const filename = "entities.data";
    const file = std.fs.cwd().openFile(filename, .{})  catch |err|  {
        std.log.err("Failed to open file: {s} ({})", .{filename, err});
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

// https://paulbourke.net/geometry/polygonise/
const edges = [256]u12{
    0x0  , 0x109, 0x203, 0x30a, 0x406, 0x50f, 0x605, 0x70c,
    0x80c, 0x905, 0xa0f, 0xb06, 0xc0a, 0xd03, 0xe09, 0xf00,
    0x190, 0x99 , 0x393, 0x29a, 0x596, 0x49f, 0x795, 0x69c,
    0x99c, 0x895, 0xb9f, 0xa96, 0xd9a, 0xc93, 0xf99, 0xe90,
    0x230, 0x339, 0x33 , 0x13a, 0x636, 0x73f, 0x435, 0x53c,
    0xa3c, 0xb35, 0x83f, 0x936, 0xe3a, 0xf33, 0xc39, 0xd30,
    0x3a0, 0x2a9, 0x1a3, 0xaa , 0x7a6, 0x6af, 0x5a5, 0x4ac,
    0xbac, 0xaa5, 0x9af, 0x8a6, 0xfaa, 0xea3, 0xda9, 0xca0,
    0x460, 0x569, 0x663, 0x76a, 0x66 , 0x16f, 0x265, 0x36c,
    0xc6c, 0xd65, 0xe6f, 0xf66, 0x86a, 0x963, 0xa69, 0xb60,
    0x5f0, 0x4f9, 0x7f3, 0x6fa, 0x1f6, 0xff , 0x3f5, 0x2fc,
    0xdfc, 0xcf5, 0xfff, 0xef6, 0x9fa, 0x8f3, 0xbf9, 0xaf0,
    0x650, 0x759, 0x453, 0x55a, 0x256, 0x35f, 0x55 , 0x15c,
    0xe5c, 0xf55, 0xc5f, 0xd56, 0xa5a, 0xb53, 0x859, 0x950,
    0x7c0, 0x6c9, 0x5c3, 0x4ca, 0x3c6, 0x2cf, 0x1c5, 0xcc ,
    0xfcc, 0xec5, 0xdcf, 0xcc6, 0xbca, 0xac3, 0x9c9, 0x8c0,
    0x8c0, 0x9c9, 0xac3, 0xbca, 0xcc6, 0xdcf, 0xec5, 0xfcc,
    0xcc , 0x1c5, 0x2cf, 0x3c6, 0x4ca, 0x5c3, 0x6c9, 0x7c0,
    0x950, 0x859, 0xb53, 0xa5a, 0xd56, 0xc5f, 0xf55, 0xe5c,
    0x15c, 0x55 , 0x35f, 0x256, 0x55a, 0x453, 0x759, 0x650,
    0xaf0, 0xbf9, 0x8f3, 0x9fa, 0xef6, 0xfff, 0xcf5, 0xdfc,
    0x2fc, 0x3f5, 0xff , 0x1f6, 0x6fa, 0x7f3, 0x4f9, 0x5f0,
    0xb60, 0xa69, 0x963, 0x86a, 0xf66, 0xe6f, 0xd65, 0xc6c,
    0x36c, 0x265, 0x16f, 0x66 , 0x76a, 0x663, 0x569, 0x460,
    0xca0, 0xda9, 0xea3, 0xfaa, 0x8a6, 0x9af, 0xaa5, 0xbac,
    0x4ac, 0x5a5, 0x6af, 0x7a6, 0xaa , 0x1a3, 0x2a9, 0x3a0,
    0xd30, 0xc39, 0xf33, 0xe3a, 0x936, 0x83f, 0xb35, 0xa3c,
    0x53c, 0x435, 0x73f, 0x636, 0x13a, 0x33 , 0x339, 0x230,
    0xe90, 0xf99, 0xc93, 0xd9a, 0xa96, 0xb9f, 0x895, 0x99c,
    0x69c, 0x795, 0x49f, 0x596, 0x29a, 0x393, 0x99 , 0x190,
    0xf00, 0xe09, 0xd03, 0xc0a, 0xb06, 0xa0f, 0x905, 0x80c,
    0x70c, 0x605, 0x50f, 0x406, 0x30a, 0x203, 0x109, 0x0
};

const triangles = [256][16]i8{
    .{-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{0, 8, 3, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{0, 1, 9, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{1, 8, 3, 9, 8, 1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{1, 2, 10, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{0, 8, 3, 1, 2, 10, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{9, 2, 10, 0, 2, 9, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{2, 8, 3, 2, 10, 8, 10, 9, 8, -1, -1, -1, -1, -1, -1, -1},
    .{3, 11, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{0, 11, 2, 8, 11, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{1, 9, 0, 2, 3, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{1, 11, 2, 1, 9, 11, 9, 8, 11, -1, -1, -1, -1, -1, -1, -1},
    .{3, 10, 1, 11, 10, 3, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{0, 10, 1, 0, 8, 10, 8, 11, 10, -1, -1, -1, -1, -1, -1, -1},
    .{3, 9, 0, 3, 11, 9, 11, 10, 9, -1, -1, -1, -1, -1, -1, -1},
    .{9, 8, 10, 10, 8, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{4, 7, 8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{4, 3, 0, 7, 3, 4, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{0, 1, 9, 8, 4, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{4, 1, 9, 4, 7, 1, 7, 3, 1, -1, -1, -1, -1, -1, -1, -1},
    .{1, 2, 10, 8, 4, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{3, 4, 7, 3, 0, 4, 1, 2, 10, -1, -1, -1, -1, -1, -1, -1},
    .{9, 2, 10, 9, 0, 2, 8, 4, 7, -1, -1, -1, -1, -1, -1, -1},
    .{2, 10, 9, 2, 9, 7, 2, 7, 3, 7, 9, 4, -1, -1, -1, -1},
    .{8, 4, 7, 3, 11, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{11, 4, 7, 11, 2, 4, 2, 0, 4, -1, -1, -1, -1, -1, -1, -1},
    .{9, 0, 1, 8, 4, 7, 2, 3, 11, -1, -1, -1, -1, -1, -1, -1},
    .{4, 7, 11, 9, 4, 11, 9, 11, 2, 9, 2, 1, -1, -1, -1, -1},
    .{3, 10, 1, 3, 11, 10, 7, 8, 4, -1, -1, -1, -1, -1, -1, -1},
    .{1, 11, 10, 1, 4, 11, 1, 0, 4, 7, 11, 4, -1, -1, -1, -1},
    .{4, 7, 8, 9, 0, 11, 9, 11, 10, 11, 0, 3, -1, -1, -1, -1},
    .{4, 7, 11, 4, 11, 9, 9, 11, 10, -1, -1, -1, -1, -1, -1, -1},
    .{9, 5, 4, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{9, 5, 4, 0, 8, 3, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{0, 5, 4, 1, 5, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{8, 5, 4, 8, 3, 5, 3, 1, 5, -1, -1, -1, -1, -1, -1, -1},
    .{1, 2, 10, 9, 5, 4, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{3, 0, 8, 1, 2, 10, 4, 9, 5, -1, -1, -1, -1, -1, -1, -1},
    .{5, 2, 10, 5, 4, 2, 4, 0, 2, -1, -1, -1, -1, -1, -1, -1},
    .{2, 10, 5, 3, 2, 5, 3, 5, 4, 3, 4, 8, -1, -1, -1, -1},
    .{9, 5, 4, 2, 3, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{0, 11, 2, 0, 8, 11, 4, 9, 5, -1, -1, -1, -1, -1, -1, -1},
    .{0, 5, 4, 0, 1, 5, 2, 3, 11, -1, -1, -1, -1, -1, -1, -1},
    .{2, 1, 5, 2, 5, 8, 2, 8, 11, 4, 8, 5, -1, -1, -1, -1},
    .{10, 3, 11, 10, 1, 3, 9, 5, 4, -1, -1, -1, -1, -1, -1, -1},
    .{4, 9, 5, 0, 8, 1, 8, 10, 1, 8, 11, 10, -1, -1, -1, -1},
    .{5, 4, 0, 5, 0, 11, 5, 11, 10, 11, 0, 3, -1, -1, -1, -1},
    .{5, 4, 8, 5, 8, 10, 10, 8, 11, -1, -1, -1, -1, -1, -1, -1},
    .{9, 7, 8, 5, 7, 9, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{9, 3, 0, 9, 5, 3, 5, 7, 3, -1, -1, -1, -1, -1, -1, -1},
    .{0, 7, 8, 0, 1, 7, 1, 5, 7, -1, -1, -1, -1, -1, -1, -1},
    .{1, 5, 3, 3, 5, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{9, 7, 8, 9, 5, 7, 10, 1, 2, -1, -1, -1, -1, -1, -1, -1},
    .{10, 1, 2, 9, 5, 0, 5, 3, 0, 5, 7, 3, -1, -1, -1, -1},
    .{8, 0, 2, 8, 2, 5, 8, 5, 7, 10, 5, 2, -1, -1, -1, -1},
    .{2, 10, 5, 2, 5, 3, 3, 5, 7, -1, -1, -1, -1, -1, -1, -1},
    .{7, 9, 5, 7, 8, 9, 3, 11, 2, -1, -1, -1, -1, -1, -1, -1},
    .{9, 5, 7, 9, 7, 2, 9, 2, 0, 2, 7, 11, -1, -1, -1, -1},
    .{2, 3, 11, 0, 1, 8, 1, 7, 8, 1, 5, 7, -1, -1, -1, -1},
    .{11, 2, 1, 11, 1, 7, 7, 1, 5, -1, -1, -1, -1, -1, -1, -1},
    .{9, 5, 8, 8, 5, 7, 10, 1, 3, 10, 3, 11, -1, -1, -1, -1},
    .{5, 7, 0, 5, 0, 9, 7, 11, 0, 1, 0, 10, 11, 10, 0, -1},
    .{11, 10, 0, 11, 0, 3, 10, 5, 0, 8, 0, 7, 5, 7, 0, -1},
    .{11, 10, 5, 7, 11, 5, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{10, 6, 5, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{0, 8, 3, 5, 10, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{9, 0, 1, 5, 10, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{1, 8, 3, 1, 9, 8, 5, 10, 6, -1, -1, -1, -1, -1, -1, -1},
    .{1, 6, 5, 2, 6, 1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{1, 6, 5, 1, 2, 6, 3, 0, 8, -1, -1, -1, -1, -1, -1, -1},
    .{9, 6, 5, 9, 0, 6, 0, 2, 6, -1, -1, -1, -1, -1, -1, -1},
    .{5, 9, 8, 5, 8, 2, 5, 2, 6, 3, 2, 8, -1, -1, -1, -1},
    .{2, 3, 11, 10, 6, 5, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{11, 0, 8, 11, 2, 0, 10, 6, 5, -1, -1, -1, -1, -1, -1, -1},
    .{0, 1, 9, 2, 3, 11, 5, 10, 6, -1, -1, -1, -1, -1, -1, -1},
    .{5, 10, 6, 1, 9, 2, 9, 11, 2, 9, 8, 11, -1, -1, -1, -1},
    .{6, 3, 11, 6, 5, 3, 5, 1, 3, -1, -1, -1, -1, -1, -1, -1},
    .{0, 8, 11, 0, 11, 5, 0, 5, 1, 5, 11, 6, -1, -1, -1, -1},
    .{3, 11, 6, 0, 3, 6, 0, 6, 5, 0, 5, 9, -1, -1, -1, -1},
    .{6, 5, 9, 6, 9, 11, 11, 9, 8, -1, -1, -1, -1, -1, -1, -1},
    .{5, 10, 6, 4, 7, 8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{4, 3, 0, 4, 7, 3, 6, 5, 10, -1, -1, -1, -1, -1, -1, -1},
    .{1, 9, 0, 5, 10, 6, 8, 4, 7, -1, -1, -1, -1, -1, -1, -1},
    .{10, 6, 5, 1, 9, 7, 1, 7, 3, 7, 9, 4, -1, -1, -1, -1},
    .{6, 1, 2, 6, 5, 1, 4, 7, 8, -1, -1, -1, -1, -1, -1, -1},
    .{1, 2, 5, 5, 2, 6, 3, 0, 4, 3, 4, 7, -1, -1, -1, -1},
    .{8, 4, 7, 9, 0, 5, 0, 6, 5, 0, 2, 6, -1, -1, -1, -1},
    .{7, 3, 9, 7, 9, 4, 3, 2, 9, 5, 9, 6, 2, 6, 9, -1},
    .{3, 11, 2, 7, 8, 4, 10, 6, 5, -1, -1, -1, -1, -1, -1, -1},
    .{5, 10, 6, 4, 7, 2, 4, 2, 0, 2, 7, 11, -1, -1, -1, -1},
    .{0, 1, 9, 4, 7, 8, 2, 3, 11, 5, 10, 6, -1, -1, -1, -1},
    .{9, 2, 1, 9, 11, 2, 9, 4, 11, 7, 11, 4, 5, 10, 6, -1},
    .{8, 4, 7, 3, 11, 5, 3, 5, 1, 5, 11, 6, -1, -1, -1, -1},
    .{5, 1, 11, 5, 11, 6, 1, 0, 11, 7, 11, 4, 0, 4, 11, -1},
    .{0, 5, 9, 0, 6, 5, 0, 3, 6, 11, 6, 3, 8, 4, 7, -1},
    .{6, 5, 9, 6, 9, 11, 4, 7, 9, 7, 11, 9, -1, -1, -1, -1},
    .{10, 4, 9, 6, 4, 10, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{4, 10, 6, 4, 9, 10, 0, 8, 3, -1, -1, -1, -1, -1, -1, -1},
    .{10, 0, 1, 10, 6, 0, 6, 4, 0, -1, -1, -1, -1, -1, -1, -1},
    .{8, 3, 1, 8, 1, 6, 8, 6, 4, 6, 1, 10, -1, -1, -1, -1},
    .{1, 4, 9, 1, 2, 4, 2, 6, 4, -1, -1, -1, -1, -1, -1, -1},
    .{3, 0, 8, 1, 2, 9, 2, 4, 9, 2, 6, 4, -1, -1, -1, -1},
    .{0, 2, 4, 4, 2, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{8, 3, 2, 8, 2, 4, 4, 2, 6, -1, -1, -1, -1, -1, -1, -1},
    .{10, 4, 9, 10, 6, 4, 11, 2, 3, -1, -1, -1, -1, -1, -1, -1},
    .{0, 8, 2, 2, 8, 11, 4, 9, 10, 4, 10, 6, -1, -1, -1, -1},
    .{3, 11, 2, 0, 1, 6, 0, 6, 4, 6, 1, 10, -1, -1, -1, -1},
    .{6, 4, 1, 6, 1, 10, 4, 8, 1, 2, 1, 11, 8, 11, 1, -1},
    .{9, 6, 4, 9, 3, 6, 9, 1, 3, 11, 6, 3, -1, -1, -1, -1},
    .{8, 11, 1, 8, 1, 0, 11, 6, 1, 9, 1, 4, 6, 4, 1, -1},
    .{3, 11, 6, 3, 6, 0, 0, 6, 4, -1, -1, -1, -1, -1, -1, -1},
    .{6, 4, 8, 11, 6, 8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{7, 10, 6, 7, 8, 10, 8, 9, 10, -1, -1, -1, -1, -1, -1, -1},
    .{0, 7, 3, 0, 10, 7, 0, 9, 10, 6, 7, 10, -1, -1, -1, -1},
    .{10, 6, 7, 1, 10, 7, 1, 7, 8, 1, 8, 0, -1, -1, -1, -1},
    .{10, 6, 7, 10, 7, 1, 1, 7, 3, -1, -1, -1, -1, -1, -1, -1},
    .{1, 2, 6, 1, 6, 8, 1, 8, 9, 8, 6, 7, -1, -1, -1, -1},
    .{2, 6, 9, 2, 9, 1, 6, 7, 9, 0, 9, 3, 7, 3, 9, -1},
    .{7, 8, 0, 7, 0, 6, 6, 0, 2, -1, -1, -1, -1, -1, -1, -1},
    .{7, 3, 2, 6, 7, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{2, 3, 11, 10, 6, 8, 10, 8, 9, 8, 6, 7, -1, -1, -1, -1},
    .{2, 0, 7, 2, 7, 11, 0, 9, 7, 6, 7, 10, 9, 10, 7, -1},
    .{1, 8, 0, 1, 7, 8, 1, 10, 7, 6, 7, 10, 2, 3, 11, -1},
    .{11, 2, 1, 11, 1, 7, 10, 6, 1, 6, 7, 1, -1, -1, -1, -1},
    .{8, 9, 6, 8, 6, 7, 9, 1, 6, 11, 6, 3, 1, 3, 6, -1},
    .{0, 9, 1, 11, 6, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{7, 8, 0, 7, 0, 6, 3, 11, 0, 11, 6, 0, -1, -1, -1, -1},
    .{7, 11, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{7, 6, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{3, 0, 8, 11, 7, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{0, 1, 9, 11, 7, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{8, 1, 9, 8, 3, 1, 11, 7, 6, -1, -1, -1, -1, -1, -1, -1},
    .{10, 1, 2, 6, 11, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{1, 2, 10, 3, 0, 8, 6, 11, 7, -1, -1, -1, -1, -1, -1, -1},
    .{2, 9, 0, 2, 10, 9, 6, 11, 7, -1, -1, -1, -1, -1, -1, -1},
    .{6, 11, 7, 2, 10, 3, 10, 8, 3, 10, 9, 8, -1, -1, -1, -1},
    .{7, 2, 3, 6, 2, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{7, 0, 8, 7, 6, 0, 6, 2, 0, -1, -1, -1, -1, -1, -1, -1},
    .{2, 7, 6, 2, 3, 7, 0, 1, 9, -1, -1, -1, -1, -1, -1, -1},
    .{1, 6, 2, 1, 8, 6, 1, 9, 8, 8, 7, 6, -1, -1, -1, -1},
    .{10, 7, 6, 10, 1, 7, 1, 3, 7, -1, -1, -1, -1, -1, -1, -1},
    .{10, 7, 6, 1, 7, 10, 1, 8, 7, 1, 0, 8, -1, -1, -1, -1},
    .{0, 3, 7, 0, 7, 10, 0, 10, 9, 6, 10, 7, -1, -1, -1, -1},
    .{7, 6, 10, 7, 10, 8, 8, 10, 9, -1, -1, -1, -1, -1, -1, -1},
    .{6, 8, 4, 11, 8, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{3, 6, 11, 3, 0, 6, 0, 4, 6, -1, -1, -1, -1, -1, -1, -1},
    .{8, 6, 11, 8, 4, 6, 9, 0, 1, -1, -1, -1, -1, -1, -1, -1},
    .{9, 4, 6, 9, 6, 3, 9, 3, 1, 11, 3, 6, -1, -1, -1, -1},
    .{6, 8, 4, 6, 11, 8, 2, 10, 1, -1, -1, -1, -1, -1, -1, -1},
    .{1, 2, 10, 3, 0, 11, 0, 6, 11, 0, 4, 6, -1, -1, -1, -1},
    .{4, 11, 8, 4, 6, 11, 0, 2, 9, 2, 10, 9, -1, -1, -1, -1},
    .{10, 9, 3, 10, 3, 2, 9, 4, 3, 11, 3, 6, 4, 6, 3, -1},
    .{8, 2, 3, 8, 4, 2, 4, 6, 2, -1, -1, -1, -1, -1, -1, -1},
    .{0, 4, 2, 4, 6, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{1, 9, 0, 2, 3, 4, 2, 4, 6, 4, 3, 8, -1, -1, -1, -1},
    .{1, 9, 4, 1, 4, 2, 2, 4, 6, -1, -1, -1, -1, -1, -1, -1},
    .{8, 1, 3, 8, 6, 1, 8, 4, 6, 6, 10, 1, -1, -1, -1, -1},
    .{10, 1, 0, 10, 0, 6, 6, 0, 4, -1, -1, -1, -1, -1, -1, -1},
    .{4, 6, 3, 4, 3, 8, 6, 10, 3, 0, 3, 9, 10, 9, 3, -1},
    .{10, 9, 4, 6, 10, 4, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{4, 9, 5, 7, 6, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{0, 8, 3, 4, 9, 5, 11, 7, 6, -1, -1, -1, -1, -1, -1, -1},
    .{5, 0, 1, 5, 4, 0, 7, 6, 11, -1, -1, -1, -1, -1, -1, -1},
    .{11, 7, 6, 8, 3, 4, 3, 5, 4, 3, 1, 5, -1, -1, -1, -1},
    .{9, 5, 4, 10, 1, 2, 7, 6, 11, -1, -1, -1, -1, -1, -1, -1},
    .{6, 11, 7, 1, 2, 10, 0, 8, 3, 4, 9, 5, -1, -1, -1, -1},
    .{7, 6, 11, 5, 4, 10, 4, 2, 10, 4, 0, 2, -1, -1, -1, -1},
    .{3, 4, 8, 3, 5, 4, 3, 2, 5, 10, 5, 2, 11, 7, 6, -1},
    .{7, 2, 3, 7, 6, 2, 5, 4, 9, -1, -1, -1, -1, -1, -1, -1},
    .{9, 5, 4, 0, 8, 6, 0, 6, 2, 6, 8, 7, -1, -1, -1, -1},
    .{3, 6, 2, 3, 7, 6, 1, 5, 0, 5, 4, 0, -1, -1, -1, -1},
    .{6, 2, 8, 6, 8, 7, 2, 1, 8, 4, 8, 5, 1, 5, 8, -1},
    .{9, 5, 4, 10, 1, 6, 1, 7, 6, 1, 3, 7, -1, -1, -1, -1},
    .{1, 6, 10, 1, 7, 6, 1, 0, 7, 8, 7, 0, 9, 5, 4, -1},
    .{4, 0, 10, 4, 10, 5, 0, 3, 10, 6, 10, 7, 3, 7, 10, -1},
    .{7, 6, 10, 7, 10, 8, 5, 4, 10, 4, 8, 10, -1, -1, -1, -1},
    .{6, 9, 5, 6, 11, 9, 11, 8, 9, -1, -1, -1, -1, -1, -1, -1},
    .{3, 6, 11, 0, 6, 3, 0, 5, 6, 0, 9, 5, -1, -1, -1, -1},
    .{0, 11, 8, 0, 5, 11, 0, 1, 5, 5, 6, 11, -1, -1, -1, -1},
    .{6, 11, 3, 6, 3, 5, 5, 3, 1, -1, -1, -1, -1, -1, -1, -1},
    .{1, 2, 10, 9, 5, 11, 9, 11, 8, 11, 5, 6, -1, -1, -1, -1},
    .{0, 11, 3, 0, 6, 11, 0, 9, 6, 5, 6, 9, 1, 2, 10, -1},
    .{11, 8, 5, 11, 5, 6, 8, 0, 5, 10, 5, 2, 0, 2, 5, -1},
    .{6, 11, 3, 6, 3, 5, 2, 10, 3, 10, 5, 3, -1, -1, -1, -1},
    .{5, 8, 9, 5, 2, 8, 5, 6, 2, 3, 8, 2, -1, -1, -1, -1},
    .{9, 5, 6, 9, 6, 0, 0, 6, 2, -1, -1, -1, -1, -1, -1, -1},
    .{1, 5, 8, 1, 8, 0, 5, 6, 8, 3, 8, 2, 6, 2, 8, -1},
    .{1, 5, 6, 2, 1, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{1, 3, 6, 1, 6, 10, 3, 8, 6, 5, 6, 9, 8, 9, 6, -1},
    .{10, 1, 0, 10, 0, 6, 9, 5, 0, 5, 6, 0, -1, -1, -1, -1},
    .{0, 3, 8, 5, 6, 10, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{10, 5, 6, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{11, 5, 10, 7, 5, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{11, 5, 10, 11, 7, 5, 8, 3, 0, -1, -1, -1, -1, -1, -1, -1},
    .{5, 11, 7, 5, 10, 11, 1, 9, 0, -1, -1, -1, -1, -1, -1, -1},
    .{10, 7, 5, 10, 11, 7, 9, 8, 1, 8, 3, 1, -1, -1, -1, -1},
    .{11, 1, 2, 11, 7, 1, 7, 5, 1, -1, -1, -1, -1, -1, -1, -1},
    .{0, 8, 3, 1, 2, 7, 1, 7, 5, 7, 2, 11, -1, -1, -1, -1},
    .{9, 7, 5, 9, 2, 7, 9, 0, 2, 2, 11, 7, -1, -1, -1, -1},
    .{7, 5, 2, 7, 2, 11, 5, 9, 2, 3, 2, 8, 9, 8, 2, -1},
    .{2, 5, 10, 2, 3, 5, 3, 7, 5, -1, -1, -1, -1, -1, -1, -1},
    .{8, 2, 0, 8, 5, 2, 8, 7, 5, 10, 2, 5, -1, -1, -1, -1},
    .{9, 0, 1, 5, 10, 3, 5, 3, 7, 3, 10, 2, -1, -1, -1, -1},
    .{9, 8, 2, 9, 2, 1, 8, 7, 2, 10, 2, 5, 7, 5, 2, -1},
    .{1, 3, 5, 3, 7, 5, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{0, 8, 7, 0, 7, 1, 1, 7, 5, -1, -1, -1, -1, -1, -1, -1},
    .{9, 0, 3, 9, 3, 5, 5, 3, 7, -1, -1, -1, -1, -1, -1, -1},
    .{9, 8, 7, 5, 9, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{5, 8, 4, 5, 10, 8, 10, 11, 8, -1, -1, -1, -1, -1, -1, -1},
    .{5, 0, 4, 5, 11, 0, 5, 10, 11, 11, 3, 0, -1, -1, -1, -1},
    .{0, 1, 9, 8, 4, 10, 8, 10, 11, 10, 4, 5, -1, -1, -1, -1},
    .{10, 11, 4, 10, 4, 5, 11, 3, 4, 9, 4, 1, 3, 1, 4, -1},
    .{2, 5, 1, 2, 8, 5, 2, 11, 8, 4, 5, 8, -1, -1, -1, -1},
    .{0, 4, 11, 0, 11, 3, 4, 5, 11, 2, 11, 1, 5, 1, 11, -1},
    .{0, 2, 5, 0, 5, 9, 2, 11, 5, 4, 5, 8, 11, 8, 5, -1},
    .{9, 4, 5, 2, 11, 3, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{2, 5, 10, 3, 5, 2, 3, 4, 5, 3, 8, 4, -1, -1, -1, -1},
    .{5, 10, 2, 5, 2, 4, 4, 2, 0, -1, -1, -1, -1, -1, -1, -1},
    .{3, 10, 2, 3, 5, 10, 3, 8, 5, 4, 5, 8, 0, 1, 9, -1},
    .{5, 10, 2, 5, 2, 4, 1, 9, 2, 9, 4, 2, -1, -1, -1, -1},
    .{8, 4, 5, 8, 5, 3, 3, 5, 1, -1, -1, -1, -1, -1, -1, -1},
    .{0, 4, 5, 1, 0, 5, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{8, 4, 5, 8, 5, 3, 9, 0, 5, 0, 3, 5, -1, -1, -1, -1},
    .{9, 4, 5, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{4, 11, 7, 4, 9, 11, 9, 10, 11, -1, -1, -1, -1, -1, -1, -1},
    .{0, 8, 3, 4, 9, 7, 9, 11, 7, 9, 10, 11, -1, -1, -1, -1},
    .{1, 10, 11, 1, 11, 4, 1, 4, 0, 7, 4, 11, -1, -1, -1, -1},
    .{3, 1, 4, 3, 4, 8, 1, 10, 4, 7, 4, 11, 10, 11, 4, -1},
    .{4, 11, 7, 9, 11, 4, 9, 2, 11, 9, 1, 2, -1, -1, -1, -1},
    .{9, 7, 4, 9, 11, 7, 9, 1, 11, 2, 11, 1, 0, 8, 3, -1},
    .{11, 7, 4, 11, 4, 2, 2, 4, 0, -1, -1, -1, -1, -1, -1, -1},
    .{11, 7, 4, 11, 4, 2, 8, 3, 4, 3, 2, 4, -1, -1, -1, -1},
    .{2, 9, 10, 2, 7, 9, 2, 3, 7, 7, 4, 9, -1, -1, -1, -1},
    .{9, 10, 7, 9, 7, 4, 10, 2, 7, 8, 7, 0, 2, 0, 7, -1},
    .{3, 7, 10, 3, 10, 2, 7, 4, 10, 1, 10, 0, 4, 0, 10, -1},
    .{1, 10, 2, 8, 7, 4, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{4, 9, 1, 4, 1, 7, 7, 1, 3, -1, -1, -1, -1, -1, -1, -1},
    .{4, 9, 1, 4, 1, 7, 0, 8, 1, 8, 7, 1, -1, -1, -1, -1},
    .{4, 0, 3, 7, 4, 3, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{4, 8, 7, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{9, 10, 8, 10, 11, 8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{3, 0, 9, 3, 9, 11, 11, 9, 10, -1, -1, -1, -1, -1, -1, -1},
    .{0, 1, 10, 0, 10, 8, 8, 10, 11, -1, -1, -1, -1, -1, -1, -1},
    .{3, 1, 10, 11, 3, 10, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{1, 2, 11, 1, 11, 9, 9, 11, 8, -1, -1, -1, -1, -1, -1, -1},
    .{3, 0, 9, 3, 9, 11, 1, 2, 9, 2, 11, 9, -1, -1, -1, -1},
    .{0, 2, 11, 8, 0, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{3, 2, 11, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{2, 3, 8, 2, 8, 10, 10, 8, 9, -1, -1, -1, -1, -1, -1, -1},
    .{9, 10, 2, 0, 9, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{2, 3, 8, 2, 8, 10, 0, 1, 8, 1, 10, 8, -1, -1, -1, -1},
    .{1, 10, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{1, 3, 8, 9, 1, 8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{0, 9, 1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{0, 3, 8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1},
    .{-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1}
};

fn pointInTriangle(a: v3, b: v3, c: v3, p: v3) ?v3 {
    // https://math.stackexchange.com/questions/544946/determine-if-projection-of-3d-point-onto-plane-is-within-a-triangle
    // https://math.stackexchange.com/questions/4322/check-whether-a-point-is-within-a-3d-triangle/2209636

    const u = v3sub(b,a);
    const v = v3sub(c,a);
    const n = v3cross(u,v);
    const w = v3sub(p,a);

    const n2 = v3len2(n);
    const gamma = v3dot(v3cross(u,w), n)/n2;
    const beta  = v3dot(v3cross(w,v), n)/n2;
    const alpha = 1 - gamma - beta;

    if (alpha > 0 and beta > 0 and gamma > 0 and alpha < 1) {
        return v3add(v3add(v3scale(alpha, a),
                           v3scale(beta, b)),
                     v3scale(gamma, c));
    } else {
        return null;
    }
}

const mapsize = 1000.0;
const gridsize = 32;
const element_size: f32 = mapsize/@as(f32, gridsize-1);
var samples: [gridsize][gridsize][gridsize]f32 = undefined;
var num_triangles: usize = 0;
var tr: []v3 = undefined;

fn collideMarch(memory: *Memory) ?v3 {
    var closest_distance = std.math.floatMax(f32);
    var result: ?v3 = null;
    for (0..num_triangles) |i| {
        const a = tr[3*i+0];
        const b = tr[3*i+1];
        const c = tr[3*i+2];

        const start = math.m4modelTranslation(memory.ray_model.?);
        if (pointInTriangle(a,b,c, start)) |pp| {
            const diff = v3sub(pp, start);
            const dist = v3len(diff);
            if (dist < closest_distance and std.math.approxEqAbs(f32, v3dot(diff, memory.camera.dir), dist, 0.001)) {
                closest_distance = dist;
                result = pp;
            }
        }
    }
    return result;
}

fn march(memory: *Memory, b: *draw_api.Buffer) void {
    var min_value: f32 = std.math.floatMax(f32);
    var max_value: f32 = std.math.floatMin(f32);
    for (0..gridsize) |k| {
        for (0..gridsize) |j| {
            for (0..gridsize) |i| {

                //const dist_to_center = @as(f32, @floatFromInt(gridsize-1))/2.0;
                //const center = v3{.x=dist_to_center, .y=dist_to_center, .z=dist_to_center};
                const pos = v3{.x = @floatFromInt(i), .y = @floatFromInt(j), .z = @floatFromInt(k)};

                //const dist = math.v3dist(pos, center);

                //const value = dist - dist_to_center;
                //samples[k][j][i] = value;

                const dt = (gridsize-1)/8*sin(2.0*std.math.pi * @as(f32, @floatFromInt(memory.time))/10e9);
                const value = pos.z - (dt*sin(pos.x)*sin(pos.y) + (gridsize-1)/7);
                samples[k][j][i] = value;

                if (value < min_value)
                    min_value = value;
                if (value > max_value)
                    max_value = value;
            }
        }
    }


    // TODO(anjo): Add instancing...
    //for (0..gridsize) |k| {
    //    for (0..gridsize) |j| {
    //        for (0..gridsize) |i| {
    //            const col = samples[k][j][i];
    //            pushCube(b, .{
    //                .pos = .{
    //                    .x = 0.0   + @as(f32, @floatFromInt(i))*element_size,
    //                    .y = 0.0   + @as(f32, @floatFromInt(j))*element_size,
    //                    .z = 0.0   + @as(f32, @floatFromInt(k))*element_size,
    //                },
    //                .size = .{
    //                    .x = 5.0,
    //                    .y = 5.0,
    //                    .z = 5.0,
    //                },
    //            },
    //            hsvToRgb(
    //                0.0,
    //                0.0,
    //                (col - min_value) / (max_value-min_value),
    //            ),
    //            );
    //        }
    //    }
    //}

    num_triangles = 0;
    tr = memory.frame_allocator.alloc(v3, (gridsize-1)*(gridsize-1)*(gridsize-1)*5*3) catch {
        return;
    };

    for (0..gridsize-1) |k| {
        for (0..gridsize-1) |j| {
            for (0..gridsize-1) |i| {
                const values = [8]f32{
                    samples[k][j][i],
                    samples[k][j][i+1],
                    samples[k][j+1][i+1],
                    samples[k][j+1][i],

                    samples[k+1][j][i],
                    samples[k+1][j][i+1],
                    samples[k+1][j+1][i+1],
                    samples[k+1][j+1][i],
                };
                const points = [8]v3{
                    v3scale(element_size, math.v3i(usize, i,   j,   k)),
                    v3scale(element_size, math.v3i(usize, i+1, j,   k)),
                    v3scale(element_size, math.v3i(usize, i+1, j+1, k)),
                    v3scale(element_size, math.v3i(usize, i,   j+1, k)),

                    v3scale(element_size, math.v3i(usize, i,   j,   k+1)),
                    v3scale(element_size, math.v3i(usize, i+1, j,   k+1)),
                    v3scale(element_size, math.v3i(usize, i+1, j+1, k+1)),
                    v3scale(element_size, math.v3i(usize, i,   j+1, k+1)),
                };

                const iso: f32 = 0.0;
                var cubeindex: u8 = 0;
                inline for (values, 0..values.len) |v,ind| {
                    if (v < iso) cubeindex |= (1 << ind);
                }

                if (edges[cubeindex] != 0) {
                    var verts: [12]v3 = undefined;
                    for (&verts) |*v| {
                        v.x = 0;
                        v.y = 0;
                        v.z = 0;
                    }
                    if (edges[cubeindex] & 1    != 0) verts[0]  = v3interp(iso,points[0],points[1],values[0],values[1]);
                    if (edges[cubeindex] & 2    != 0) verts[1]  = v3interp(iso,points[1],points[2],values[1],values[2]);
                    if (edges[cubeindex] & 4    != 0) verts[2]  = v3interp(iso,points[2],points[3],values[2],values[3]);
                    if (edges[cubeindex] & 8    != 0) verts[3]  = v3interp(iso,points[3],points[0],values[3],values[0]);
                    if (edges[cubeindex] & 16   != 0) verts[4]  = v3interp(iso,points[4],points[5],values[4],values[5]);
                    if (edges[cubeindex] & 32   != 0) verts[5]  = v3interp(iso,points[5],points[6],values[5],values[6]);
                    if (edges[cubeindex] & 64   != 0) verts[6]  = v3interp(iso,points[6],points[7],values[6],values[7]);
                    if (edges[cubeindex] & 128  != 0) verts[7]  = v3interp(iso,points[7],points[4],values[7],values[4]);
                    if (edges[cubeindex] & 256  != 0) verts[8]  = v3interp(iso,points[0],points[4],values[0],values[4]);
                    if (edges[cubeindex] & 512  != 0) verts[9]  = v3interp(iso,points[1],points[5],values[1],values[5]);
                    if (edges[cubeindex] & 1024 != 0) verts[10] = v3interp(iso,points[2],points[6],values[2],values[6]);
                    if (edges[cubeindex] & 2048 != 0) verts[11] = v3interp(iso,points[3],points[7],values[3],values[7]);

                    var index: usize = 0;
                    while (triangles[cubeindex][index] != -1) : (index += 3) {
                        tr[3*num_triangles+0] = verts[@intCast(triangles[cubeindex][index+0])];
                        tr[3*num_triangles+1] = verts[@intCast(triangles[cubeindex][index+1])];
                        tr[3*num_triangles+2] = verts[@intCast(triangles[cubeindex][index+2])];
                        num_triangles += 1;
                    }
                }
            }
        }
    }

    if (num_triangles > 0) {
        push(b, primitive.Mesh{
            .verts = tr[0..3*num_triangles],
        },
        hsvToRgb(
            0.0,
            0.8,
            0.5,
        ));
    }
    //tr[0] = v3scale(100.0, .{.x=-0.5,.y=-0.5,.z=1.0});
    //tr[1] = v3scale(100.0, .{.x= 0.0,.y= 0.5,.z=1.0});
    //tr[2] = v3scale(100.0, .{.x= 0.5,.y=-0.5,.z=1.0});

    //push(b, primitive.Mesh{
    //    .verts = tr,
    //},
    //hsvToRgb(
    //    0.0,
    //    0.8,
    //    0.5,
    //));
}

fn v3interp(iso: f32, p0: v3, p1: v3, v0: f32, v1: f32) v3 {
   if (@abs(iso - v0) < 0.0001) return p0;
   if (@abs(iso - v1) < 0.0001) return p1;
   if (@abs(v0 - v1) < 0.0001) return p0;
   const mu = (iso - v0) / (v1 - v0);
   return v3 {
       .x = p0.x + mu*(p1.x - p0.x),
       .y = p0.y + mu*(p1.y - p0.y),
       .z = p0.z + mu*(p1.z - p0.z),
   };
}

export fn update(vars: *const Vars, memory: *Memory, player: *Player, input: *const Input) void {
    // Player movement
    player.crouch = input.isset(.Crouch);
    player.sprint = input.isset(.Sprint);
    playerMove(vars, memory, player, input);

    // copy player pos to camera pos
    if (!vars.mode2d) {
        const height: f32 = if (player.crouch) 15 else 22;
        const offset = v3 {.x = 0, .y = 0, .z = height};
        memory.camera.pos = v3add(player.pos, offset);
        memory.camera.dir = player.dir;
        memory.camera.view = m4view(memory.camera.pos, memory.camera.dir);
        memory.camera.proj = m4projection(0.01, 10000.0, vars.aspect, vars.fov);
    } else {
        if (input.isset(.Interact)) {
            memory.target.x -= input.cursor_delta.x / memory.zoom;
            memory.target.y -= input.cursor_delta.y / memory.zoom;
        }
        if (input.scroll != 0) {
            memory.zoom += input.scroll;
            if (memory.zoom < 0.1)
                memory.zoom = 0.1;
        }
    }

    // Process some random inputs...
    if (input.isset(.ResetCamera)) {
        memory.target.x = 0.5;
        memory.target.y = 0.5;
        memory.zoom = 1.0;
    }

    if (input.isset(.AltInteract)) {
        memory.ray_model = math.m4modelWithRotations(memory.camera.pos, .{.x=1000,.y=10,.z=10}, .{.x=0,.y=player.pitch,.z=player.yaw});
    }

    if (input.isset(.Editor)) {
        // spawn plane
        if (input.isset(.AltInteract)) {
            const entity = memory.entities.addOneAssumeCapacity();
            entity.plane.model = math.m4model(v3add(memory.camera.pos, v3scale(20, memory.camera.dir)), .{.x=1,.y=1,.z=1});
        }

        if (input.isset(.Interact)) {
            var closest: ?IntersectResult = null;
            var closest_entity_id: ?u32 = null;
            for (memory.entities.constSlice(), 0..) |e,i| {
                if (intersectPlaneModelLine(e.plane.model, global_plane_size, memory.camera.pos,memory.camera.dir)) |intersect| {
                    if (closest == null or intersect.distance < closest.?.distance) {
                        closest = intersect;
                        closest_entity_id = @intCast(i);
                    }
                }
            }

            if (closest_entity_id) |id| {
                memory.selected_entity = closest_entity_id;
                memory.widget.model = &memory.entities.buffer[id].plane.model;
            }
        }

        if (memory.selected_entity != null)
            updateWidget(&memory.widget, input, memory.camera.pos, memory.camera.dir);
    }

    if (input.isset(.Save))
        dumpEntitiesToDisk(memory.entities.slice()) catch {};
    if (input.isset(.Load))
        readEntitiesFromDisk(memory) catch {};

    // ?
    if (memory.show_cursor) {
        memory.cursor_pos.x += input.cursor_delta.x;
        memory.cursor_pos.y -= input.cursor_delta.y;
        memory.cursor_pos.x = std.math.clamp(memory.cursor_pos.x, 0, 1);
        memory.cursor_pos.y = std.math.clamp(memory.cursor_pos.y, 0, 1);
    }
}

fn f(h: f32, s: f32, v: f32, n: f32) f32 {
    const k = @mod(n + h/60.0, 6.0);
    return v - v*s*@max(0.0, @min(@min(k, 4 - k), 1));
}

fn hsvToRgb(h: f32, s: f32, v: f32) Color {
    return .{
        .r = @intFromFloat(255.0*f(h,s,v, 5.0)),
        .g = @intFromFloat(255.0*f(h,s,v, 3.0)),
        .b = @intFromFloat(255.0*f(h,s,v, 1.0)),
        .a = 255,
    };
}

pub const IntersectResult = struct {
    pos: v3,
    normal: v3,
    distance: f32,
};

fn intersectInfinitePlaneAxisLine(plane_pos: v3, k: v3, line_start: v3, line_dir: v3) ?v3 {
    const pn = v3dot(line_start, k);
    const qn = v3dot(plane_pos,  k);
    const vn = v3dot(line_dir,   k);
    if (vn == 0)
        return null;
    const t = (qn-pn)/vn;
    return v3add(line_start, v3scale(t, line_dir));
}

fn intersectPlaneAxisLine(plane_pos: v3, i: v3, j: v3, k: v3, plane_size: v2, line_start: v3, line_dir: v3) ?IntersectResult {
    const pn = v3dot(line_start, k);
    const qn = v3dot(plane_pos,  k);
    const vn = v3dot(line_dir,   k);
    if (vn == 0)
        return null;
    const t = (qn-pn)/vn;

    const p = v3add(line_start, v3scale(t, line_dir));

    const vec_to_origin = v3sub(p, plane_pos);
    if (@abs(v3dot(vec_to_origin, i)) <= plane_size.x/2.0 and
        @abs(v3dot(vec_to_origin, j)) <= plane_size.y/2.0) {
        return .{.pos=p, .normal=k, .distance=t};
    } else {
        return null;
    }
}

fn intersectPlaneAxisRay(plane_pos: v3, i: v3, j: v3, k: v3, plane_size: v2, ray_start: v3, ray_delta: v3) ?IntersectResult {
    const pn = v3dot(ray_start, k);
    const qn = v3dot(plane_pos, k);
    const vn = v3dot(ray_delta, k);
    // check if ray_delta crosses the plane,
    // if not, return
    if ((pn-qn)*(pn-qn+vn) >= 0)
        return null;

    // distance to plane
    const t = (qn-pn)/vn;

    const p = v3add(ray_start, v3scale(t, ray_delta));

    const vec_to_origin = v3sub(p, plane_pos);
    if (@abs(v3dot(vec_to_origin, i)) <= plane_size.x/2.0 and
        @abs(v3dot(vec_to_origin, j)) <= plane_size.y/2.0) {
        return .{.pos=p, .normal=k, .distance=t};
    } else {
        return null;
    }
}

fn intersectPlaneModelLine(plane_model: m4, plane_size: v2, line_start: v3, line_dir: v3) ?IntersectResult {
    const i = math.m4modelAxisI(plane_model);
    const j = math.m4modelAxisJ(plane_model);
    const k = math.m4modelAxisK(plane_model);
    const pos = math.m4modelTranslation(plane_model);
    return intersectPlaneAxisLine(pos,i,j,k,plane_size, line_start,line_dir);
}

fn intersectPlaneModelRay(plane_model: m4, plane_size: v2, ray_start: v3, ray_delta: v3) ?IntersectResult {
    const i = math.m4modelAxisI(plane_model);
    const j = math.m4modelAxisJ(plane_model);
    const k = math.m4modelAxisK(plane_model);
    const pos = math.m4modelTranslation(plane_model);
    return intersectPlaneAxisRay(pos,i,j,k,plane_size, ray_start,ray_delta);
}

fn intersectCubeLine(cube_model: m4, cube_size: v3, line_start: v3, line_dir: v3) ?IntersectResult {
    const pos = math.m4modelTranslation(cube_model);
    const i = math.m4modelAxisI(cube_model);
    const j = math.m4modelAxisJ(cube_model);
    const k = math.m4modelAxisK(cube_model);

    const dot_i = v3dot(line_dir, i);
    const dot_j = v3dot(line_dir, j);
    const dot_k = v3dot(line_dir, k);
    const sign_i = dot_i/@abs(dot_i);
    const sign_j = dot_j/@abs(dot_j);
    const sign_k = dot_k/@abs(dot_k);
    const ni = v3scale(-sign_i, i);
    const nj = v3scale(-sign_j, j);
    const nk = v3scale(-sign_k, k);

    const pi = v3add(pos, v3scale(cube_size.x/2.0, ni));
    const pj = v3add(pos, v3scale(cube_size.y/2.0, nj));
    const pk = v3add(pos, v3scale(cube_size.z/2.0, nk));

    if (intersectPlaneAxisLine(pi, nj,nk,ni, .{.x=cube_size.y,.y=cube_size.z}, line_start,line_dir)) |v| return v;
    if (intersectPlaneAxisLine(pj, nk,ni,nj, .{.x=cube_size.z,.y=cube_size.x}, line_start,line_dir)) |v| return v;
    if (intersectPlaneAxisLine(pk, ni,nj,nk, .{.x=cube_size.x,.y=cube_size.y}, line_start,line_dir)) |v| return v;

    return null;
}

fn intersectAnnulusLine(pos: v3, inner_radius: f32, outer_radius: f32, k: v3, line_start: v3, line_dir: v3) ?IntersectResult {
    const p = intersectInfinitePlaneAxisLine(pos, k, line_start, line_dir) orelse return null;
    const dist2 = v3len2(v3sub(p, pos));
    const inside = (dist2 >= inner_radius*inner_radius and dist2 <= outer_radius*outer_radius);
    if (!inside)
        return null;
    return .{.pos = p, .normal = k, .distance = v3len(v3sub(p, line_start))};
}

export fn draw(vars: *const Vars, memory: *Memory, b: *draw_api.Buffer, player_id: common.PlayerId, input: *const Input) void {
    begin3d(b, memory.camera);
    _ = vars;

    // Draw map(?)
    const grid_size = 32;
    const tile_size = 32.0;
    const tile_max_height = 4.0;
    const tile_base_height = 2.0;
    var prng = std.rand.DefaultPrng.init(0);
    const rand = prng.random();
    {
        var i: usize = 0;
        while (i < grid_size) : (i += 1) {
            var j: usize = 0;
            while (j < grid_size) : (j += 1) {
                pushCube(b, .{
                    .pos = .{
                        .x = tile_size*@as(f32, @floatFromInt(i)) - tile_size*@as(f32, @floatFromInt(grid_size))/2,
                        .y = tile_size*@as(f32, @floatFromInt(j)) - tile_size*@as(f32, @floatFromInt(grid_size))/2,
                        .z = 0.0,
                    },
                    .size = .{
                        .x = tile_size,
                        .y = tile_size,
                        .z = tile_base_height + tile_max_height*rand.float(f32),
                    },
                },
                hsvToRgb(
                    80.0 + 10.0*(2.0*rand.float(f32)-1.0),
                    0.8 +  0.2*(2.0*rand.float(f32)-1.0),
                    0.5 +  0.2*(2.0*rand.float(f32)-1.0)
                ));
            }
        }
    }

    // pick
    {
        const vp = m4mul(memory.camera.proj, memory.camera.view);
        const inv_vp = m4inverse(vp);

        const dev_x = 2*(memory.cursor_pos.x-0.5);
        const dev_y = 2*(memory.cursor_pos.y-0.5);
        var near = m4mulv(inv_vp, v4 {.x=dev_x,.y=dev_y,.z=0.0,.w=1});
        near.x /= near.w;
        near.y /= near.w;
        near.z /= near.w;
        var far  = m4mulv(inv_vp, v4 {.x=dev_x,.y=dev_y,.z=1.0,.w=1});
        far.x /= far.w;
        far.y /= far.w;
        far.z /= far.w;

        const d = v3normalize(v3sub(.{.x=far.x, .y=far.y, .z=far.z}, .{.x=near.x, .y=near.y, .z=near.z}));
        const p = v3add(memory.camera.pos, v3scale(15.0, d));
        _ = p;
    }

    for (memory.entities.constSlice()) |e| {
        var plane = e.plane;
        plane.model = math.m4modelSetScale(e.plane.model, .{.x=global_plane_size.x,.y=global_plane_size.y,.z=1});
        pushPlane(b, plane, hsvToRgb(10, 0.6, 0.7));
        plane.model = math.m4modelSetScale(e.plane.model, .{.x=global_plane_size.x-10,.y=global_plane_size.y-10,.z=2});
        pushPlane(b, plane, hsvToRgb(10, 0.6, 0.5));
    }

    if (input.isset(.Editor) and memory.selected_entity != null)
        drawWidget(b, &memory.widget);

    // Draw players
    const player_cube_size = 10;
    for (memory.players.slice()) |player| {
        if (player.id == player_id)
            continue;
        const height: f32 = if (player.crouch) 15 else 22;
        pushCube(b, .{
            .pos = .{
                .x = player.pos.x - player_cube_size/2.0,
                .y = player.pos.y - player_cube_size/2.0,
                .z = player.pos.z + tile_base_height + tile_max_height,
            },
            .size = .{
                .x = player_cube_size,
                .y = player_cube_size,
                .z = height,
            },
        },
        hsvToRgb(180, 0.75, 0.75),
        );
    }

    memory.stat_data.start("march");
    march(memory, b);
    memory.stat_data.end();

    if (memory.ray_model) |model| {
        push(b, primitive.Cube2 {
            .model = model,
        }, hsvToRgb(
            20.0 + 10.0*(2.0*rand.float(f32)-1.0),
            0.8 +  0.2*(2.0*rand.float(f32)-1.0),
            0.5 +  0.2*(2.0*rand.float(f32)-1.0)
        ));

        if (collideMarch(memory)) |p| {
            pushCube(b, .{
                .pos = p,
                .size = .{
                    .x = 20.0,
                    .y = 20.0,
                    .z = 20.0,
                },
            }, hsvToRgb(
                0.9,
                0.5,
                0.8,
            ));
        }
    }

    end3d(b);

    begin2d(b, primitive.Camera2d {
        .target = memory.target,
        .zoom = memory.zoom,
    });
    //    if (vars.speedometer) {
    //        graphAppend(&memory.vel_graph, v3len(memory.players.buffer[0].vel));
    //        drawGraph(b, &memory.vel_graph,
    //            .{.x = 10, .y = 80 + 200},
    //            .{.x = 200, .y = 100},
    //            .{.x = 10, .y = 10},
    //            15, 0.75, 0.5);
    //    }

        if (input.isset(.Console)) {
        //    if (!mouse_enabled) {
        //        mouse_enabled = true;
        //        raylib.EnableCursor();
        //    }
            const console_height = 1.0/3.0;
            pushRectangle(b, .{
                .pos = .{
                    .x = 0,
                    .y = 1 - (console_height - textheight),
                },
                .size = .{
                    .x = 1,
                    .y = console_height,
                }
            }, hsvToRgb(200, 0.5, 0.25));
            pushRectangle(b, .{
                .pos = .{
                    .x = 0,
                    .y = 1 - console_height,
                },
                .size = .{
                    .x = 1,
                    .y = textheight,
                }
            }, hsvToRgb(200, 0.5, 0.1));

            {
                var text = primitive.Text{
                    .pos = .{
                        .x = 0,
                        .y = 1.0 - console_height,
                    },
                    .str = undefined,
                    .len = memory.console_input.len,
                    .size = fontsize,
                };
                @memset(&text.str, 0);
                std.mem.copy(u8, &text.str, memory.console_input.slice());
                pushText(b, text, hsvToRgb(200, 0.75, 0.75));
            }
        }

        {
            var y: f32 = 1.0 - fontsize;
            var text = primitive.Text{
                .pos = .{
                    .x = 0,
                    .y = y,
                },
                .str = undefined,
                .len = 0,
                .size = fontsize,
            };
            @memset(&text.str, 0);

            {

                drawProfileData(memory, b);
                //var x_offset: f32 = 5.0;
                //if (vars.draw_fps) {

                    //for (&memory.time_stats.stat_data) |*stat| {
                    //    const result = stat.mean_std();
                    //    @memset(&text.str, 0);
                    //    const avg_fps = if (result.avg != 0.0) 1000000000 / result.avg else 0;
                    //    const str = std.fmt.bufPrint(&text.str, "fps: {:4}", .{
                    //        avg_fps,
                    //    }) catch unreachable;

                    //    text.len = str.len;
                    //    pushText(b, text, hsvToRgb(200, 0.75, 0.75));
                    //    text.pos.y -= fontsize;
                    //}
                //}
            }

            //@memset(&text.str, 0);
            //{
            //    const str = std.fmt.bufPrint(&text.str, "speed: {d:5.0}\nonground: {}", .{v3len(memory.players.get(0).vel), memory.players.get(0).onground}) catch unreachable;
            //    text.len = str.len;
            //    pushText(b, text, hsvToRgb(200, 0.75, 0.75));
            //}

        }

        if (memory.show_cursor) {
            // cursor
            const cursor_size = 0.01;
            push(b, primitive.Rectangle {
                .pos = .{
                    .x = memory.cursor_pos.x - cursor_size/2.0,
                    .y = memory.cursor_pos.y - cursor_size/2.0,
                },
                .size = .{
                    .x = cursor_size,
                    .y = cursor_size,
                },
            }, hsvToRgb(350, 0.75, 0.75));

        } else {
            // Crosshair
            const cursor_thickness = 0.005;
            const cursor_length = 0.01;
            const cursor_gap = 0.02;
            push(b, primitive.Rectangle {
                .pos = .{
                    .x = 0.5 - cursor_gap/2.0 - cursor_length,
                    .y = 0.5 - cursor_thickness/2.0,
                },
                .size = .{
                    .x = cursor_length,
                    .y = cursor_thickness,
                },
            }, hsvToRgb(350, 0.75, 0.75));
            push(b, primitive.Rectangle {
                .pos = .{
                    .x = 0.5 + cursor_gap/2.0,
                    .y = 0.5 - cursor_thickness/2.0,
                },
                .size = .{
                    .x = cursor_length,
                    .y = cursor_thickness,
                },
            }, hsvToRgb(350, 0.75, 0.75));
            push(b, primitive.Rectangle {
                .pos = .{
                    .x = 0.5 - cursor_thickness/2.0,
                    .y = 0.5 + cursor_gap/2.0,
                },
                .size = .{
                    .x = cursor_thickness,
                    .y = cursor_length,
                },
            }, hsvToRgb(350, 0.75, 0.75));
            push(b, primitive.Rectangle {
                .pos = .{
                    .x = 0.5 - cursor_thickness/2.0,
                    .y = 0.5 - cursor_gap/2.0 - cursor_length,
                },
                .size = .{
                    .x = cursor_thickness,
                    .y = cursor_length,
                },
            }, hsvToRgb(350, 0.75, 0.75));
        }
    end2d(b);
}

fn drawCenteredLine(b: *draw_api.Buffer, start: v2, end: v2, thickness: f32, color: Color) void {
    const dir = v2normalize(v2sub(end, start));
    const ortho = v2 { .x = -dir.y, .y = dir.x };

    const new_start = v2add(start, v2scale(thickness/2.0, ortho));
    const new_end = v2add(end, v2scale(thickness/2.0, ortho));

    pushLine(b, .{
        .start = new_start,
        .end = new_end,
        .thickness = thickness,
    }, color);
}

fn drawGraph(b: *draw_api.Buffer, g: *Graph, pos: v2, size: v2, margin: v2, h: f32, s: f32, v: f32) void {
    var bg = hsvToRgb(50.0, 0.75, 0.05);
    bg.a = @intFromFloat(0.75 * 255.0);
    pushRectangle(b, .{
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

    const scale_x = (size.x - 2*margin.x) / @as(f32, @floatFromInt(g.data.len-1));
    const scale_y = (size.y - 2*margin.y) / (g.max - g.min);

    var last_x: f32 = 0;
    var last_y: f32 = 0;
    for (g.data, 0..) |data_y,i| {
        const x = pos.x + margin.x + scale_x * @as(f32, @floatFromInt(i));
        const y = pos.y - margin.y + size.y - (scale_y*data_y - scale_y*g.min);

        const last_index = (g.top + g.data.len - 1) % g.data.len;
        const dist = (g.data.len + last_index - i) % g.data.len;

        const color = hsvToRgb(h,s,v - 0.4*@as(f32, @floatFromInt(dist))/@as(f32, @floatFromInt(g.data.len)));
        if (i > 0) {
            drawCenteredLine(b,
                v2 {.x = last_x, .y = last_y},
                v2 {.x = x, .y = y},
                2.0, color);
        }

        //push(b, primitive.Cirlce {
        //    .pos = .{.x = x, .y = y},
        //    .radius = 4.0,
        //}, color);

        last_x = x;
        last_y = y;
    }

    pushLine(b, .{
        .start =.{
            .x = pos.x + margin.x + scale_x * @as(f32, @floatFromInt(g.top)),
            .y = pos.y,
        },
        .end = .{
             .x = pos.x + margin.y + scale_x * @as(f32, @floatFromInt(g.top)),
             .y = pos.y + size.y,
        },
        .thickness = 1.0,
    }, Color{.r = 128, .g = 128, .b = 128, .a = 255});
}

fn drawProfileData(memory: *Memory, b: *draw_api.Buffer) void {
    var worklist: std.BoundedArray(struct {
        entry: *stat.StatEntry = undefined,
        depth: u32 = 0,
    } , 64) = .{};

    // Add root nodes to worklist
    for (memory.stat_data.entries.slice()) |*s| {
        if (!s.is_root)
            continue;
        worklist.appendAssumeCapacity(.{.entry=s});
    }

    var y: f32 = 1.0 - fontsize;

    var text = primitive.Text{
        .pos = .{
            .x = 0,
            .y = y,
        },
        .str = undefined,
        .len = 0,
        .size = fontsize,
    };

    while (worklist.len > 0) {
        const work = worklist.pop();

        const result = work.entry.mean_std();
        @memset(&text.str, 0);
        const str = std.fmt.bufPrint(&text.str, "{s}: {:4} us", .{
            work.entry.name,
            result.avg/1000,
        }) catch unreachable;

        text.len = str.len;
        text.pos.x = fontsize*@as(f32, @floatFromInt(work.depth));
        pushText(b, text, hsvToRgb(200, 0.75, 0.75));
        text.pos.y -= fontsize;

        for (work.entry.children.slice()) |i| {
            const entry = &memory.stat_data.entries.slice()[i];
            worklist.appendAssumeCapacity(.{
                .entry = entry,
                .depth = work.depth+1,
            });
        }
    }
}
