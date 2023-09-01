const std = @import("std");
const cos = std.math.cos;
const sin = std.math.sin;
const max = std.math.max;
const min = std.math.min;

const common = @import("common.zig");
const Memory = common.Memory;
const Player = common.Player;
const Input = common.Input;

const Graph = common.Graph;
const graphAppend = common.graphAppend;

const config = @import("config.zig");
const Vars = config.Vars;

const primitive = @import("primitive.zig");
const Color = primitive.Color;

const math = @import("math.zig");
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

const draw_api = @import("draw.zig");
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
    const dt = 1.0/60.0;

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
        player.vel.z += vars.gravity*dt;
    }

    if (player.onground and input.isset(.Jump)) {
        player.vel.z += vars.jumpspeed;
    }

    // Compute wishdir/wishspeed and bound wishvel
    const wishdir = v3normalize(wishvel);
    var wishspeed = v3len(wishvel);
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
    var delta = v3scale(dt, player.vel);

    player.onground = false;

    // collision with planes
    const dz = @min(delta.z, -1.0);
    for (memory.entities.constSlice()) |e| {
        if (intersectPlaneModelRay(e.plane.model, .{.x=50,.y=50}, player.pos, .{.x=0,.y=0,.z=dz})) |intersect| {
            _ = intersect;
            //if (intersect.distance <= 0.5) {
                if (player.vel.z < 0) {
                    player.vel.z = 0;
                }
                if (delta.z < 0) {
                    delta.z = 0;
                }
                player.onground = true;
            //}
        }
    }

    // integrate velocity
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
    const file = std.fs.cwd().createFile(filename, .{})  catch |err|  {
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

export fn update(vars: *const Vars, memory: *Memory, player: *Player, input: *const Input) void {
    player.crouch = input.isset(.Crouch);
    player.sprint = input.isset(.Sprint);

    playerMove(vars, memory, player, input);

    if (input.isset(.Save))
        dumpEntitiesToDisk(memory.entities.slice()) catch {};
    if (input.isset(.Load))
        readEntitiesFromDisk(memory) catch {};

    // copy player pos to camera pos
    if (!vars.mode2d) {
        const height: f32 = if (player.crouch) 15 else 22;
        const offset = v3 {.x = 0, .y = 0, .z = height};
        memory.camera.pos = v3add(player.pos, offset);
        memory.camera.dir = player.dir;
        memory.camera.view = m4view(memory.camera.pos, memory.camera.dir);
        memory.camera.proj = m4projection(0.01, 1000.0, vars.aspect, vars.fov);
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

    if (input.isset(.ResetCamera)) {
        memory.target.x = 0.5;
        memory.target.y = 0.5;
        memory.zoom = 1.0;
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
                if (intersectPlaneModelLine(e.plane.model, .{.x=50,.y=50}, memory.camera.pos,memory.camera.dir)) |intersect| {
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
    if (std.math.fabs(v3dot(vec_to_origin, i)) <= plane_size.x/2.0 and
        std.math.fabs(v3dot(vec_to_origin, j)) <= plane_size.y/2.0) {
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
    if (std.math.fabs(v3dot(vec_to_origin, i)) <= plane_size.x/2.0 and
        std.math.fabs(v3dot(vec_to_origin, j)) <= plane_size.y/2.0) {
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
    const sign_i = dot_i/std.math.fabs(dot_i);
    const sign_j = dot_j/std.math.fabs(dot_j);
    const sign_k = dot_k/std.math.fabs(dot_k);
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
                ),
                );
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
        plane.model = math.m4modelSetScale(e.plane.model, .{.x=50,.y=50,.z=1});
        pushPlane(b, plane, hsvToRgb(10, 0.6, 0.7));
        plane.model = math.m4modelSetScale(e.plane.model, .{.x=50-10,.y=50-10,.z=2});
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

          const textheight = 1.0/30.0;
          const fontsize = textheight;

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
                //var x_offset: f32 = 5.0;
                //if (vars.draw_fps) {
                    for (&memory.time_stats.stat_data) |*stat| {
                        const result = stat.mean_std();
                        @memset(&text.str, 0);
                        const avg_fps = if (result.avg != 0.0) 1000000000 / result.avg else 0;
                        const str = std.fmt.bufPrint(&text.str, "fps: {:4}", .{
                            avg_fps,
                        }) catch unreachable;

                        text.len = str.len;
                        pushText(b, text, hsvToRgb(200, 0.75, 0.75));
                        text.pos.y -= fontsize;
                    }
                //}
            }

            @memset(&text.str, 0);
            {
                const str = std.fmt.bufPrint(&text.str, "speed: {d:5.0}\nonground: {}", .{v3len(memory.players.get(0).vel), memory.players.get(0).onground}) catch unreachable;
                text.len = str.len;
                pushText(b, text, hsvToRgb(200, 0.75, 0.75));
            }

        }

        if (memory.show_cursor) {
            // cursor
            const cursor_size = 0.01;
            pushRectangle(b, .{
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
            // crosshair
            const cursor_thickness = 0.005;
            const cursor_length = 0.01;
            const cursor_gap = 0.02;
            pushRectangle(b, .{
                .pos = .{
                    .x = 0.5 - cursor_gap/2.0 - cursor_length,
                    .y = 0.5 - cursor_thickness/2.0,
                },
                .size = .{
                    .x = cursor_length,
                    .y = cursor_thickness,
                },
            }, hsvToRgb(350, 0.75, 0.75));
            pushRectangle(b, .{
                .pos = .{
                    .x = 0.5 + cursor_gap/2.0,
                    .y = 0.5 - cursor_thickness/2.0,
                },
                .size = .{
                    .x = cursor_length,
                    .y = cursor_thickness,
                },
            }, hsvToRgb(350, 0.75, 0.75));
            pushRectangle(b, .{
                .pos = .{
                    .x = 0.5 - cursor_thickness/2.0,
                    .y = 0.5 + cursor_gap/2.0,
                },
                .size = .{
                    .x = cursor_thickness,
                    .y = cursor_length,
                },
            }, hsvToRgb(350, 0.75, 0.75));
            pushRectangle(b, .{
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
