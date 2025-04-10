const std = @import("std");

const common = @import("common");
const Memory = common.Memory;
const primitive = common.primitive;
const draw_api = common.draw_api;
const intersect = @import("intersect.zig");
const hsv_to_rgb = common.color.hsv_to_rgb;

const math = common.math;
const v2 = math.v2;
const v3 = math.v3;
const v4 = math.v4;
const m3 = math.m3;
const m4 = math.m4;

const chunk_dim = primitive.chunk_dim;
const voxel_dim = primitive.voxel_dim;

const Map = common.Map;
const Chunk = common.Chunk;
const ChunkCoordinate = common.ChunkCoordinate;
const VoxelCoordinate = common.VoxelCoordinate;
const VoxelIndex = common.VoxelIndex;
const ChunkIndex = common.ChunkIndex;
const ChunkMap = common.ChunkMap;

const VoxelFaceArray = MultiThreadedArray(primitive.VoxelTransform, 128);

pub fn map_init(map: *Map, allocator: std.mem.Allocator) !void {
    map.* = Map{
        .chunks = ChunkMap.init(allocator),
    };
}

pub fn map_deinit(map: *Map) void {
    map.chunks.deinit();
}

fn chunk_index(c: ChunkCoordinate) ChunkIndex {
    return @as(ChunkIndex, @intCast(c[0])) + chunk_dim * @as(ChunkIndex, @intCast(c[1])) + chunk_dim * chunk_dim * @as(ChunkIndex, @intCast(c[2]));
}

pub fn add_chunk(map: *Map, c: ChunkCoordinate) !*Chunk {
    const res = try map.chunks.getOrPut(chunk_index(c));
    if (!res.found_existing) {
        const chunk = res.value_ptr;
        chunk.origin = c;
        chunk.flags = .{};
        const size = chunk_dim * chunk_dim * chunk_dim;
        const slice: [*]primitive.Voxel = @ptrCast(&chunk.voxels[0][0][0]);
        @memset(slice[0..size], .air);
    }
    return res.value_ptr;
}

pub fn remove_chunk(map: *Map, c: ChunkCoordinate) void {
    _ = map.chunks.remove(chunk_index(c));
}

pub fn chunk_build_faces(memory: *Memory, chunk: *Chunk) void {
    var chunk_faces = VoxelFaceArray.init(memory.mem.frame, memory.threadpool.threads.len + 1);

    var wg: std.Thread.WaitGroup = undefined;
    wg.reset();

    for (0..chunk_dim) |z| {
        memory.threadpool.spawnWg(&wg, build_faces_piece, .{ memory, chunk, &chunk_faces, 0, chunk_dim, 0, chunk_dim, z });
    }

    for (0..chunk_dim) |j| {
        memory.threadpool.spawnWg(&wg, build_chunk_edges, .{ memory, chunk, &chunk_faces, 0, chunk_dim, j });
    }

    memory.threadpool.waitAndWork(&wg);

    if (chunk.flags.built_faces == 1) {
        memory.mem.persistent.free(chunk.faces);
    }
    chunk.faces = chunk_faces.collect(memory.mem.persistent);
    chunk.flags.built_faces = 1;
}

const RaycastResult = struct {
    current_coord: VoxelCoordinate,
    prev_coord: VoxelCoordinate,
};

fn chunk_coord(v: VoxelCoordinate) ChunkCoordinate {
    return .{
        @intFromFloat(@floor(@as(f32, @floatFromInt(v[0])) / chunk_dim)),
        @intFromFloat(@floor(@as(f32, @floatFromInt(v[1])) / chunk_dim)),
        @intFromFloat(@floor(@as(f32, @floatFromInt(v[2])) / chunk_dim)),
    };
}

fn voxel_coord(p: v3) VoxelCoordinate {
    return .{
        @intFromFloat(@trunc(p.x / voxel_dim)),
        @intFromFloat(@trunc(p.y / voxel_dim)),
        @intFromFloat(@trunc(p.z / voxel_dim)),
    };
}

// Returns the voxel at a given voxel index in a chunk
fn chunk_voxel_at_index(chunk: *Chunk, v: VoxelIndex) primitive.Voxel {
    return chunk.voxels[v[2]][v[1]][v[0]];
}

// Returns the voxel at a coordinate in the global voxel grid
fn voxel_at_coord(chunk: *Chunk, v: VoxelCoordinate) primitive.Voxel {
    const c = chunk_coord(v);

    const i: usize = @intCast(v[0] - chunk_dim * @as(i32, c[0]));
    const j: usize = @intCast(v[1] - chunk_dim * @as(i32, c[1]));
    const k: usize = @intCast(v[2] - chunk_dim * @as(i32, c[2]));

    std.debug.assert(i >= 0 and j >= 0 and k >= 0);
    std.debug.assert(i < chunk_dim and j < chunk_dim and k < chunk_dim);

    return chunk.voxels[k][j][i];
}

fn set_voxel_at_coord(chunk: *Chunk, v: VoxelCoordinate, voxel: primitive.Voxel) void {
    const c = chunk_coord(v);

    const i: usize = @intCast(v[0] - chunk_dim * @as(i32, c[0]));
    const j: usize = @intCast(v[1] - chunk_dim * @as(i32, c[1]));
    const k: usize = @intCast(v[2] - chunk_dim * @as(i32, c[2]));

    std.debug.assert(i >= 0 and j >= 0 and k >= 0);
    std.debug.assert(i < chunk_dim and j < chunk_dim and k < chunk_dim);

    chunk.voxels[k][j][i] = voxel;
}

pub fn chunk_at(map: *Map, v: VoxelCoordinate) ?*Chunk {
    return chunk_at_index(map, chunk_index(chunk_coord(v)));
}

pub fn chunk_at_index(map: *Map, index: ChunkIndex) ?*Chunk {
    return map.chunks.getPtr(index);
}

fn voxel_coord_in_chunk(chunk: *Chunk, v: VoxelCoordinate) bool {
    return v[0] >= chunk_dim * chunk.origin[0] and v[0] < chunk_dim * (chunk.origin[0] + 1) and
        v[1] >= chunk_dim * chunk.origin[1] and v[1] < chunk_dim * (chunk.origin[1] + 1) and
        v[2] >= chunk_dim * chunk.origin[2] and v[2] < chunk_dim * (chunk.origin[2] + 1);
}

fn raycast(map: *Map, p: v3, d: v3, steps: usize) RaycastResult {
    const n = v3.normalize(d);

    var dx: f32 = 0.0;
    var dy: f32 = 0.0;
    var dz: f32 = 0.0;
    if (@abs(n.x) >= @abs(n.y) and @abs(n.x) >= @abs(n.z)) {
        dx = n.x / @abs(n.x);
        dy = n.y / @abs(n.x);
        dz = n.z / @abs(n.x);
    } else if (@abs(n.y) >= @abs(n.x) and @abs(n.y) >= @abs(n.z)) {
        dx = n.x / @abs(n.y);
        dy = n.y / @abs(n.y);
        dz = n.z / @abs(n.y);
    } else {
        dx = n.x / @abs(n.z);
        dy = n.y / @abs(n.z);
        dz = n.z / @abs(n.z);
    }

    var x = p.x;
    var y = p.y;
    var z = p.z;

    var current_coord: VoxelCoordinate = voxel_coord(.{ .x = x, .y = y, .z = z });
    var prev_coord: VoxelCoordinate = .{ 0, 0, 0 };

    var chunk = chunk_at(map, current_coord) orelse return .{
        .current_coord = current_coord,
        .prev_coord = prev_coord,
    };

    for (0..steps) |_| {
        if (voxel_at_coord(chunk, current_coord) != .air) {
            break;
        }

        prev_coord = current_coord;
        current_coord = voxel_coord(.{ .x = x, .y = y, .z = z });
        x += voxel_dim * dx;
        y += voxel_dim * dy;
        z += voxel_dim * dz;

        if (!voxel_coord_in_chunk(chunk, current_coord)) {
            chunk = chunk_at(map, current_coord) orelse return .{
                .current_coord = prev_coord,
                .prev_coord = prev_coord,
            };
        }
    }

    return .{
        .current_coord = current_coord,
        .prev_coord = prev_coord,
    };
}

pub fn draw(memory: *Memory, cmd: *draw_api.CommandBuffer, player: *common.Player, input: *const common.Input, map: *Map) void {
    _ = input;
    _ = memory;
    // Submit all chunks for rendering
    {
        var it = map.chunks.iterator();
        while (it.next()) |entry| {
            const chunk = entry.value_ptr;
            cmd.push(primitive.VoxelChunk{
                .origin_x = chunk.origin[0],
                .origin_y = chunk.origin[1],
                .origin_z = chunk.origin[2],
                .voxels = chunk.faces,
                .dirty = chunk.flags.dirty,
            }, hsv_to_rgb(80.0 + 10.0 * (2.0 * 0.5 - 1.0), 0.8 + 0.2 * (2.0 * 0.5 - 1.0), 0.5 + 0.2 * (2.0 * 0.5 - 1.0)));
            chunk.flags.dirty = 0;
        }
    }

    if (player.in_editor) {
        // Draw chunk outlines
        {
            var it = map.chunks.iterator();
            while (it.next()) |entry| {
                const chunk = entry.value_ptr;
                cmd.push(primitive.CubeOutline{
                    .model = m4.modelWithRotations(
                        .{
                            .x = @floatFromInt(voxel_dim * chunk_dim * @as(i32, chunk.origin[0]) + voxel_dim * chunk_dim / 2),
                            .y = @floatFromInt(voxel_dim * chunk_dim * @as(i32, chunk.origin[1]) + voxel_dim * chunk_dim / 2),
                            .z = @floatFromInt(voxel_dim * chunk_dim * @as(i32, chunk.origin[2]) + voxel_dim * chunk_dim / 2),
                        },
                        .{ .x = voxel_dim * chunk_dim, .y = voxel_dim * chunk_dim, .z = voxel_dim * chunk_dim },
                        .{ .x = 0, .y = 0, .z = 0 },
                    ),
                    .thickness = 5,
                }, hsv_to_rgb(80.0 + 10.0 * (2.0 * 0.5 - 1.0), 0.8 + 0.2 * (2.0 * 0.5 - 1.0), 0.5 + 0.2 * (2.0 * 0.5 - 1.0)));
            }
        }

        // Draw outline of selected voxel
        {
            var p: v3 = .{};
            p.x = voxel_dim / 2.0 + voxel_dim * @as(f32, @floatFromInt(player.edit.coord[0]));
            p.y = voxel_dim / 2.0 + voxel_dim * @as(f32, @floatFromInt(player.edit.coord[1]));
            p.z = voxel_dim / 2.0 + voxel_dim * @as(f32, @floatFromInt(player.edit.coord[2]));
            cmd.push(primitive.CubeOutline{
                .model = m4.modelWithRotations(
                    p,
                    .{ .x = voxel_dim, .y = voxel_dim, .z = voxel_dim },
                    .{ .x = 0, .y = 0, .z = 0 },
                ),
                .thickness = 0.5,
            }, hsv_to_rgb(80.0 + 10.0 * (2.0 * 0.5 - 1.0), 0.8 + 0.2 * (2.0 * 0.5 - 1.0), 0.5 + 0.2 * (2.0 * 0.5 - 1.0)));
        }

        // Draw selected region
        if (player.edit.selected_0) {
            const bound_i0 = @min(player.edit.region_i0, player.edit.coord[0]);
            const bound_j0 = @min(player.edit.region_j0, player.edit.coord[1]);
            const bound_k0 = @min(player.edit.region_k0, player.edit.coord[2]);
            const bound_i1 = @max(player.edit.region_i0, player.edit.coord[0]) + 1;
            const bound_j1 = @max(player.edit.region_j0, player.edit.coord[1]) + 1;
            const bound_k1 = @max(player.edit.region_k0, player.edit.coord[2]) + 1;
            cmd.push(primitive.CubeOutline{
                .model = m4.modelWithRotations(
                    .{
                        .x = voxel_dim * @as(f32, @floatFromInt(@as(i32, @intCast(bound_i1)) + @as(i32, @intCast(bound_i0)))) / 2,
                        .y = voxel_dim * @as(f32, @floatFromInt(@as(i32, @intCast(bound_j1)) + @as(i32, @intCast(bound_j0)))) / 2,
                        .z = voxel_dim * @as(f32, @floatFromInt(@as(i32, @intCast(bound_k1)) + @as(i32, @intCast(bound_k0)))) / 2,
                    },
                    .{
                        .x = voxel_dim * @as(f32, @floatFromInt(@abs(@as(i32, @intCast(bound_i1)) - @as(i32, @intCast(bound_i0))))),
                        .y = voxel_dim * @as(f32, @floatFromInt(@abs(@as(i32, @intCast(bound_j1)) - @as(i32, @intCast(bound_j0))))),
                        .z = voxel_dim * @as(f32, @floatFromInt(@abs(@as(i32, @intCast(bound_k1)) - @as(i32, @intCast(bound_k0))))),
                    },
                    .{ .x = 0, .y = 0, .z = 0 },
                ),
                .thickness = 1,
            }, hsv_to_rgb(80.0 + 10.0 * (2.0 * 0.5 - 1.0), 0.8 + 0.2 * (2.0 * 0.5 - 1.0), 0.5 + 0.2 * (2.0 * 0.5 - 1.0)));
        }

        // draw block in hand
        {
            const m = m4.modelWithRotations(player.camera.pos, .{ .x = 1, .y = 1, .z = 1 }, .{
                .x = 0,
                .y = player.pitch,
                .z = player.yaw,
            });
            const right = v3.neg(m4.modelAxisJ(m));
            const forward = m4.modelAxisI(m);
            const up = m4.modelAxisK(m);

            const diff = v3.add(v3.scale(0.1 * voxel_dim, right), v3.scale(-0.1 * voxel_dim, up));
            const p = v3.add(v3.add(player.camera.pos, v3.scale(0.25 * voxel_dim, forward)), diff);

            if (player.edit.selected_block == .air) {
                cmd.push(primitive.CubeOutline{
                    .model = m4.modelFromXDir(
                        p,
                        .{ .x = 0.05 * voxel_dim, .y = 0.05 * voxel_dim, .z = 0.05 * voxel_dim },
                        forward,
                    ),
                }, hsv_to_rgb(80.0 + 10.0 * (2.0 * 0.5 - 1.0), 0.8 + 0.2 * (2.0 * 0.5 - 1.0), 0.5 + 0.2 * (2.0 * 0.5 - 1.0)));
            } else {
                const colors = [5]primitive.Color{
                    .{},
                    .{ .r = @round(0.2 * 255), .g = @round(0.4 * 255), .b = @round(0.2 * 255), .a = 255 },
                    .{ .r = @round(0.4 * 255), .g = @round(0.4 * 255), .b = @round(0.4 * 255), .a = 255 },
                    .{ .r = @round(0.5 * 255), .g = @round(0.44 * 255), .b = @round(0.2 * 255), .a = 255 },
                    .{},
                };

                cmd.push(primitive.Cube{
                    .model = m4.modelFromXDir(
                        p,
                        .{ .x = 0.05 * voxel_dim, .y = 0.05 * voxel_dim, .z = 0.05 * voxel_dim },
                        forward,
                    ),
                }, colors[@intFromEnum(player.edit.selected_block)]);
            }
        }
    }
}

pub fn apply_modify(memory: *Memory, map: *Map, mods: []common.MapModify) []ChunkIndex {
    var dirty_chunks: std.ArrayList(*Chunk) = .{};
    var dirty_chunk_indices: std.ArrayList(ChunkIndex) = .{};

    for (mods) |mod| {
        const chunk = chunk_at(map, mod.coord) orelse continue;

        if (mod.is_region) {
            var rchunk = chunk;
            var rcoord = mod.coord;
            rchunk.flags.dirty = 1;
            dirty_chunks.append(memory.mem.frame, rchunk) catch unreachable;
            dirty_chunk_indices.append(memory.mem.frame, chunk_index(chunk_coord(rcoord))) catch unreachable;

            var rk: i16 = mod.coord[2];
            while (rk < mod.to_coord[2]) : (rk += 1) {
                var rj: i16 = mod.coord[1];
                while (rj < mod.to_coord[1]) : (rj += 1) {
                    var ri: i16 = mod.coord[0];
                    while (ri < mod.to_coord[0]) : (ri += 1) {
                        rchunk.flags.dirty = 1;
                        if (!voxel_coord_in_chunk(rchunk, .{ ri, rj, rk })) {
                            rcoord = .{ ri, rj, rk };
                            rchunk = chunk_at(map, rcoord) orelse {
                                continue;
                            };
                            if (rchunk.flags.dirty == 0) {
                                dirty_chunk_indices.append(memory.mem.frame, chunk_index(chunk_coord(rcoord))) catch unreachable;
                                dirty_chunks.append(memory.mem.frame, rchunk) catch unreachable;
                                rchunk.flags.dirty = 1;
                            }
                        }
                        set_voxel_at_coord(rchunk, .{ ri, rj, rk }, mod.voxel);
                    }
                }
            }
        } else {
            set_voxel_at_coord(chunk, mod.coord, mod.voxel);
            chunk.flags.dirty = 1;
            dirty_chunk_indices.append(memory.mem.frame, chunk_index(chunk_coord(mod.coord))) catch unreachable;
            dirty_chunks.append(memory.mem.frame, chunk) catch unreachable;
        }
    }

    // Clear dirty flags
    for (dirty_chunks.items) |chunk| {
        chunk.flags.dirty = 0;
    }

    return dirty_chunk_indices.items;
}

pub fn rebuild_chunks(memory: *Memory, map: *Map, dirty: []ChunkIndex) void {
    for (dirty) |index| {
        const chunk = chunk_at_index(map, index) orelse {
            continue;
        };
        chunk_build_faces(memory, chunk);
        chunk.flags.dirty = 1;
    }
}

pub fn edit(memory: *Memory, player: *common.Player, input: *const common.Input, map: *Map) !void {
    if (input.isset(.SelectBlock1)) {
        player.edit.selected_block = .air;
    }
    if (input.isset(.SelectBlock2)) {
        player.edit.selected_block = .grass;
    }
    if (input.isset(.SelectBlock3)) {
        player.edit.selected_block = .stone;
    }
    if (input.isset(.SelectBlock4)) {
        player.edit.selected_block = .wood;
    }
    if (input.isset(.SelectBlock5)) {
        player.edit.selected_block = .air;
    }
    if (input.isset(.TogglePlacementMode)) {
        player.edit.placement_mode = if (player.edit.placement_mode == .air) .adjacent else .air;
    }
    if (input.isset(.add_chunk)) {
        const coord = chunk_coord(voxel_coord(player.camera.pos));
        const chunk = add_chunk(map, coord) catch return;
        chunk_build_terrain(memory, chunk);
        chunk_build_faces(memory, chunk);
    }
    if (input.isset(.remove_chunk)) {
        const coord = chunk_coord(voxel_coord(player.camera.pos));
        _ = remove_chunk(map, coord);
    }

    const range: usize = if (player.edit.placement_mode == .air) 5 else 1000;
    const r = raycast(map, player.camera.pos, player.camera.dir, range);
    const current_chunk = chunk_at(map, r.current_coord) orelse return;
    const prev_chunk = chunk_at(map, r.prev_coord) orelse return;
    const chunk = if (!occupied(voxel_at_coord(current_chunk, r.current_coord)) or player.edit.selected_block == .air) current_chunk else prev_chunk;
    _ = chunk;
    player.edit.coord = if (!occupied(voxel_at_coord(current_chunk, r.current_coord)) or player.edit.selected_block == .air) r.current_coord else r.prev_coord;

    if (input.isset(.SelectRegion)) {
        if (!player.edit.selected_0) {
            // select first corner
            player.edit.region_i0 = player.edit.coord[0];
            player.edit.region_j0 = player.edit.coord[1];
            player.edit.region_k0 = player.edit.coord[2];
            player.edit.selected_0 = true;
        } else {
            // select second corner
            player.edit.region_i1 = player.edit.coord[0];
            player.edit.region_j1 = player.edit.coord[1];
            player.edit.region_k1 = player.edit.coord[2];

            const bound_i0 = @min(player.edit.region_i0, player.edit.region_i1);
            const bound_j0 = @min(player.edit.region_j0, player.edit.region_j1);
            const bound_k0 = @min(player.edit.region_k0, player.edit.region_k1);
            const bound_i1 = @max(player.edit.region_i0, player.edit.region_i1) + 1;
            const bound_j1 = @max(player.edit.region_j0, player.edit.region_j1) + 1;
            const bound_k1 = @max(player.edit.region_k0, player.edit.region_k1) + 1;

            try memory.map_mods.append(memory.mem.frame, .{
                .coord = .{ bound_i0, bound_j0, bound_k0 },
                .voxel = player.edit.selected_block,
                .is_region = true,
                .to_coord = .{ bound_i1, bound_j1, bound_k1 },
            });

            player.edit.selected_0 = false;
        }
    } else if (input.isset(.PlaceBlock)) {
        try memory.map_mods.append(memory.mem.frame, .{
            .coord = player.edit.coord,
            .voxel = player.edit.selected_block,
        });
    }
}

pub fn chunk_build_terrain(memory: *Memory, chunk: *Chunk) void {
    var wg: std.Thread.WaitGroup = undefined;
    wg.reset();
    for (0..chunk_dim) |z| {
        memory.threadpool.spawnWg(&wg, build_terrain_piece, .{ memory, chunk, 0, chunk_dim, 0, chunk_dim, z });
    }
    memory.threadpool.waitAndWork(&wg);
}

fn addVoxelFaceIfSet(chunk: *Chunk, faces: []primitive.VoxelTransform, len: *usize, x: usize, y: usize, z: usize, face: primitive.VoxelTransform.FaceDir) void {
    if (chunk.voxels[z][y][x] == 1) {
        faces[len] = .{
            .x = @intCast(x),
            .y = @intCast(y),
            .z = @intCast(z),
            .face = face,
        };
        len.* += 1;
    }
}

fn occupied(voxel: primitive.Voxel) bool {
    return voxel != .air;
}

fn build_faces_piece(memory: *Memory, chunk: *const Chunk, faces: *VoxelFaceArray, x0: usize, x1: usize, y0: usize, y1: usize, z: usize) void {
    const profile_block = memory.profile.begin(@src().fn_name, 6 * (x1 - x0) * (y1 - y0) / 8);
    defer memory.profile.end(profile_block);

    var block = faces.head();

    for (y0..y1) |y| {
        for (x0..x1) |x| {
            if (occupied(chunk.voxels[z][y][x])) {
                continue;
            }

            const n = chunk_dim - 1;
            const f = if (x < n) chunk.voxels[z][y][x + 1] else .air;
            const b = if (x > 0) chunk.voxels[z][y][x - 1] else .air;
            const r = if (y < n) chunk.voxels[z][y + 1][x] else .air;
            const l = if (y > 0) chunk.voxels[z][y - 1][x] else .air;
            const u = if (z < n) chunk.voxels[z + 1][y][x] else .air;
            const d = if (z > 0) chunk.voxels[z - 1][y][x] else .air;

            if (occupied(f)) {
                VoxelFaceArray.push(&block, .{
                    .pos = .{
                        @intCast(x + 1),
                        @intCast(y),
                        @intCast(z),
                    },
                    .face = .back,
                    .kind = f,
                });
            }
            if (occupied(b)) {
                VoxelFaceArray.push(&block, .{
                    .pos = .{
                        @intCast(x - 1),
                        @intCast(y),
                        @intCast(z),
                    },
                    .face = .front,
                    .kind = b,
                });
            }
            if (occupied(r)) {
                VoxelFaceArray.push(&block, .{
                    .pos = .{
                        @intCast(x),
                        @intCast(y + 1),
                        @intCast(z),
                    },
                    .face = .left,
                    .kind = r,
                });
            }
            if (occupied(l)) {
                VoxelFaceArray.push(&block, .{
                    .pos = .{
                        @intCast(x),
                        @intCast(y - 1),
                        @intCast(z),
                    },
                    .face = .right,
                    .kind = l,
                });
            }
            if (occupied(u)) {
                VoxelFaceArray.push(&block, .{
                    .pos = .{
                        @intCast(x),
                        @intCast(y),
                        @intCast(z + 1),
                    },
                    .face = .down,
                    .kind = u,
                });
            }
            if (occupied(d)) {
                VoxelFaceArray.push(&block, .{
                    .pos = .{
                        @intCast(x),
                        @intCast(y),
                        @intCast(z - 1),
                    },
                    .face = .up,
                    .kind = d,
                });
            }
        }
    }
}

fn build_chunk_edges(memory: *Memory, chunk: *const Chunk, faces: *VoxelFaceArray, _i0: usize, _i1: usize, j: usize) void {
    const profile_block = memory.profile.begin(@src().fn_name, (_i1 - _i0) / 8);
    defer memory.profile.end(profile_block);

    var block = faces.head();

    for (_i0.._i1) |i| {
        const n = chunk_dim - 1;
        if (occupied(chunk.voxels[0][j][i])) {
            VoxelFaceArray.push(&block, .{
                .pos = .{
                    @intCast(i),
                    @intCast(j),
                    @intCast(0),
                },
                .face = .down,
                .kind = chunk.voxels[0][j][i],
            });
        }
        if (occupied(chunk.voxels[n][j][i])) {
            VoxelFaceArray.push(&block, .{
                .pos = .{
                    @intCast(i),
                    @intCast(j),
                    @intCast(n),
                },
                .face = .up,
                .kind = chunk.voxels[n][j][i],
            });
        }
        if (occupied(chunk.voxels[j][0][i])) {
            VoxelFaceArray.push(&block, .{
                .pos = .{
                    @intCast(i),
                    @intCast(0),
                    @intCast(j),
                },
                .face = .left,
                .kind = chunk.voxels[j][0][i],
            });
        }
        if (occupied(chunk.voxels[j][n][i])) {
            VoxelFaceArray.push(&block, .{
                .pos = .{
                    @intCast(i),
                    @intCast(n),
                    @intCast(j),
                },
                .face = .right,
                .kind = chunk.voxels[j][n][i],
            });
        }
        if (occupied(chunk.voxels[j][i][0])) {
            VoxelFaceArray.push(&block, .{
                .pos = .{
                    @intCast(0),
                    @intCast(i),
                    @intCast(j),
                },
                .face = .back,
                .kind = chunk.voxels[j][i][0],
            });
        }
        if (occupied(chunk.voxels[j][i][n])) {
            VoxelFaceArray.push(&block, .{
                .pos = .{
                    @intCast(n),
                    @intCast(i),
                    @intCast(j),
                },
                .face = .front,
                .kind = chunk.voxels[j][i][n],
            });
        }
    }
}

fn build_terrain_piece(memory: *Memory, chunk: *Chunk, x0: usize, x1: usize, y0: usize, y1: usize, z: usize) void {
    const block = memory.profile.begin(@src().fn_name, (x1 - x0) * (y1 - y0) / 8);
    defer memory.profile.end(block);

    for (y0..y1) |y| {
        for (x0..x1) |x| {
            const halfdim = chunk_dim / 2.0;
            const d = v3{
                .x = @as(f32, @floatFromInt(x)) + 0.5 - halfdim,
                .y = @as(f32, @floatFromInt(y)) + 0.5 - halfdim,
                .z = @as(f32, @floatFromInt(z)) + 0.5 - halfdim,
            };
            if (v3.len(d) <= halfdim) {
                chunk.voxels[z][y][x] = .grass;
            }
        }
    }
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
        num_cpus: usize = 0,
        used_thread_indices: std.atomic.Value(u8) = undefined,
        allocator: std.mem.Allocator = undefined,

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
                .num_cpus = num_cpus,
                .allocator = allocator,
            };

            self.reset();

            return self;
        }

        fn deinit(self: *Self) void {
            _ = self;
        }

        fn reset(self: *Self) void {
            self.used_thread_indices = std.atomic.Value(u8).init(0);

            self.roots = self.allocator.alloc(*Block, self.num_cpus) catch unreachable;
            self.heads = self.allocator.alloc(*Block, self.num_cpus) catch unreachable;
            self.thread_indices = self.allocator.alloc(usize, self.num_cpus) catch unreachable;

            for (0..self.num_cpus) |i| {
                const block = self.allocator.alloc(Block, 1) catch unreachable;
                self.roots[i] = @ptrCast(block.ptr);
                self.roots[i].* = Block{
                    .allocator = self.allocator,
                    .head = &self.heads[i],
                };
                self.heads[i] = self.roots[i];
            }
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
