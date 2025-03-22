const std = @import("std");
const common = @import("common");
const Draw = @import("../draw.zig");
const Memory = common.Memory;
const Input = common.Input;
const primitive = common.primitive;
const Color = primitive.Color;
const hsv_to_rgb = common.color.hsv_to_rgb;
const Rectangle = common.primitive.Rectangle;
const CommandBuffer = draw_api.CommandBuffer;
const Profile = common.Profile;

const draw_api = common.draw_api;

var pause_index: usize = 0;

pub fn draw(memory: *Memory, cmd: *CommandBuffer, input: *const Input) void {
    var profile = &memory.profile;

    const current_frame_index = memory.debug_frame_data.peek_index(1);
    if (input.isset(.DebugFramePauseDataCollection)) {
        memory.debug_data_collection_paused = !memory.debug_data_collection_paused;
        pause_index = current_frame_index;
    }

    if (memory.debug_data_collection_paused) {
        const data_len = memory.debug_frame_data.data.len;
        if (input.isset(.DebugFrameForward)) {
            pause_index = (pause_index + 1) % data_len;
        }

        if (input.isset(.DebugFrameBack)) {
            pause_index = (pause_index + data_len - 1) % data_len;
        }

        if (pause_index != current_frame_index) {
            profile = memory.debug_frame_data.data[pause_index].profile;
        }
    }

    //const frame_tsc = profile.block_last_frame.elapsed_tsc;
    const target_frame_tsc = profile.timer_freq / common.target_fps;
    const max_frame_tsc = 3*target_frame_tsc/2;

    draw_frame_bar(memory, cmd, target_frame_tsc);
    draw_profile_data(cmd, profile, max_frame_tsc);
}

pub fn draw_frame_bar(memory: *Memory, cmd: *CommandBuffer, target_frame_tsc: usize) void {
    const size = 0.009;
    const border = 0.08 * size;

    const black = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
    const white = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    const current_index = memory.debug_frame_data.peek_index(1);
    for (memory.debug_frame_data.data, 0..) |d, i| {
        const next_index = (i + 1) % memory.debug_frame_data.data.len;
        const next_data = memory.debug_frame_data.data[next_index];
        if (!next_data.used) {
            continue;
        }
        const tsc: f32 = if (d.used) @floatFromInt(next_data.profile.block_last_frame.elapsed_tsc) else 0;
        const ratio = tsc / @as(f32, @floatFromInt(target_frame_tsc));
        const hue = 100.0 * (1.0 - (@max(0.8, @min(ratio, 1.6)) - 0.8) / (1.6 - 0.8));

        const dist: f32 = @floatFromInt(memory.debug_frame_data.dist(current_index, i));
        const sat = if (d.used) 0.8 * (dist / @as(f32, @floatFromInt(memory.debug_frame_data.data.len))) else 0;
        const border_color = if (i == current_index) white else black;
        const body_color = if (i == current_index) white else hsv_to_rgb(hue, 0.8, 0.1 + sat);
        const height_scale: f32 = if (memory.debug_data_collection_paused and i == pause_index) 1.5 else 1.0;
        Draw.rectangle_outline(cmd, .{
            .x = size + size * @as(f32, @floatFromInt(i)),
            .y = 0.8,
        }, .{
            .x = size,
            .y = 2 * size * height_scale,
        }, border, body_color, border_color);
    }
}

fn draw_profile_data(cmd: *CommandBuffer, profile: *Profile, max_frame_tsc: usize) void {
    const height = 0.0125;
    const border = height * 0.1;
    const border_bg = height * 0.1;

    for (profile.anchor_maps_slice(), 0..) |*map, thread_index| {
        const vs = map.anchor_values();
        if (vs[0].hitcount == 0) {
            continue;
        }

        Draw.rectangle_outline(cmd, .{
            .x = 0.0,
            .y = @as(f32, @floatFromInt(thread_index)) * (height + 2 * border_bg) - border_bg,
        }, .{
            .x = 1.0,
            .y = height + 2 * border_bg,
        }, border_bg, .{ .r = 20, .g = 20, .b = 20, .a = 200 }, .{ .r = 60, .g = 60, .b = 60, .a = 200 });

        for (vs, 0..) |v, i| {
            if (!v.active_last_frame) {
                continue;
            }

            var tree_height: u32 = 0;
            var pid = v.parent_id;
            var hue: f32 = @floatFromInt(360 * i / vs.len);
            var pindex = i;
            while (pid > 0) : (tree_height += 1) {
                if (pid > 0) {
                    hue = @floatFromInt(360 * pindex / vs.len);
                }
                pindex = if (pid != 0) map.get_index(pid).? else 0;
                pid = vs[pindex].parent_id;
            }

            //if (tree_height != draw_tree_height) {
            //    continue;
            //}

            const start_x = @as(f32, @floatFromInt(v.tsc_delta_from_root)) / @as(f32, @floatFromInt(max_frame_tsc));

            //const sat: f32 = @as(f32, @floatFromInt(tree_height + 1)) / 8.0;
            //const val: f32 = 0.8*start_x + 0.1;

            const color = hsv_to_rgb(
                hue,
                0.9,
                0.9,
                //@min(sat, 0.9),
                //@min(val, 0.9),
            );

            const width = @as(f32, @floatFromInt(v.tsc_last_elapsed_inclusive)) / @as(f32, @floatFromInt(max_frame_tsc));
            Draw.rectangle_outline(cmd, .{
                .x = start_x,
                .y = @as(f32, @floatFromInt(thread_index)) * (height + 2 * border_bg),
            }, .{
                .x = width,
                .y = height,
            }, border, color, .{ .r = 0, .g = 0, .b = 0, .a = 255 });
        }
    }
}
