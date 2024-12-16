const std = @import("std");
const common = @import("common");
const Memory = common.Memory;
const Input = common.Input;
const primitive = common.primitive;
const hsv_to_rgb = common.color.hsv_to_rgb;

const draw_api = common.draw_api;

const Node = struct {
    index: u16,
    parent: u16,
    children: []u16,
};

fn ff(a: i64) i64 {
    return a*2;
}

pub fn draw(memory: *Memory, b: *draw_api.CommandBuffer, input: *const Input) void {
    _ = input;
    //var nodes: []Node = undefined;
    //{
    //    const num_children = memory.mem.frame.alloc(u16, vs.len) catch unreachable;
    //    @memset(num_children, 0);

    //    for (vs) |v| {
    //        const parent_index = if (v.parent_id != 0) memory.profile.get_index(v.parent_id) else 0;
    //        num_children[parent_index] += 1;
    //    }

    //    nodes = memory.mem.frame.alloc(Node, vs.len) catch unreachable;
    //    for (vs, 0..) |v, i| {
    //        const parent_index = if (v.parent_id != 0) memory.profile.get_index(v.parent_id) else 0;
    //        nodes[i].index = @intCast(i);
    //        nodes[i].parent = @intCast(parent_index);
    //        nodes[i].children = memory.mem.frame.alloc(u16, num_children[i]) catch unreachable;
    //    }

    //    const child_index = memory.mem.frame.alloc(u16, vs.len) catch unreachable;
    //    @memset(child_index, 0);

    //    for (vs, 0..) |v, i| {
    //        const parent_index = if (v.parent_id != 0) memory.profile.get_index(v.parent_id) else 0;
    //        nodes[parent_index].children[child_index[parent_index]] = @intCast(i);
    //        child_index[parent_index] += 1;
    //    }
    //}

    //const total = memory.profile.total_elapsed();

    const draw_tree_height = 0;
    const tsc_root = memory.profile.block_last_frame.elapsed_tsc;
    const height = 0.05;

    for (memory.profile.anchor_maps_slice()) |map| {
        const vs = map.anchor_values();
        if (vs[0].hitcount == 0) {
            continue;
        }

        for (vs, 0..) |v, i| {
            var tree_height: u32 = 0;
            var pid = v.parent_id;
            var hue: f32 = @floatFromInt(360*i/vs.len);
            var pindex = i;
            while (pid > 0) : (tree_height += 1) {
                if (pid > 0) {
                    hue = @floatFromInt(360*pindex/vs.len);
                }
                pindex = if (pid != 0) map.get_index(pid).? else 0;
                pid = vs[pindex].parent_id;
            }

            if (tree_height != draw_tree_height) {
                continue;
            }

            const start_x = @as(f32, @floatFromInt(v.tsc_delta_from_root))/@as(f32, @floatFromInt(tsc_root));

            //const sat: f32 = @as(f32, @floatFromInt(tree_height + 1)) / 8.0;
            //const val: f32 = 0.8*start_x + 0.1;

            const color = hsv_to_rgb(
                hue,
                0.9,
                0.9,
                //@min(sat, 0.9),
                //@min(val, 0.9),
            );

            const width = @as(f32, @floatFromInt(v.tsc_last_elapsed_inclusive))/@as(f32, @floatFromInt(tsc_root));
            b.push(primitive.Rectangle{
                .pos = .{
                    .x = start_x,
                    .y = 0,
                },
                .size = .{
                    .x = width,
                    .y = height,
                },
            }, color);
        }
    }
}
