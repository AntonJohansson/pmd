const std = @import("std");
const common = @import("common");
const Draw = @import("../draw.zig");
const ui = @import("../ui.zig");
const Memory = common.Memory;
const ThreadState = common.ThreadState;
const Input = common.Input;
const primitive = common.primitive;
const Color = primitive.Color;
const hsv_to_rgb = common.color.hsv_to_rgb;
const Rectangle = common.primitive.Rectangle;
const CommandBuffer = draw_api.CommandBuffer;
const Profile = common.Profile;

const draw_api = common.draw_api;

var pause_index: usize = 0;

pub fn draw(ts: *ThreadState, memory: *Memory, cmd: *CommandBuffer, input: *const Input) void {
    var profile = &ts.profile;

    const current_frame_index = ts.debug_frame_data.peek_index(1);

    var pi = pause_index;

    if (ts.is_main()) {
        if (input.isset(.DebugFramePauseDataCollection)) {
            memory.debug_data_collection_paused = !memory.debug_data_collection_paused;
            pi = current_frame_index;
        }

        if (memory.debug_data_collection_paused) {
            const data_len = ts.debug_frame_data.data.len;
            if (input.isset(.DebugFrameForward)) {
                pi = (pi + 1) % data_len;
            }

            if (input.isset(.DebugFrameBack)) {
                pi = (pi + data_len - 1) % data_len;
            }
        }
    }

    if (pi != current_frame_index) {
        profile = ts.debug_frame_data.data[pi].profile;
    }

    if (ts.is_main()) {
        pause_index = pi;
    }

    //const frame_tsc = profile.block_last_frame.elapsed_tsc;
    const target_frame_tsc = profile.timer_freq / common.target_fps;
    const max_frame_tsc = 3 * target_frame_tsc / 2;

    if (ts.is_main()) {
        draw_frame_bar(ts, memory, cmd, target_frame_tsc);
        draw_fn_times(ts, memory, cmd);
    }
    draw_profile_data(cmd, ts.id, profile, max_frame_tsc);
}

pub fn draw_fn_times(ts: *ThreadState, memory: *Memory, cmd: *CommandBuffer) void {
    if (ui.begin_window(ts, memory, .debug_fns, "wow", 0.1, 0.5)) {
        const total = ts.profile.total_elapsed();
        //const frame = ts.profile.block_last_frame.elapsed_tsc;
        const sec = total.tsc_elapsed / ts.profile.timer_freq;
        ui.push_text_fmt(ts, "total time: {} s", .{sec});


        ui.begin_table(ts, ts.profile.map.anchor_values().len+1, 7);
        ui.push_text(ts, "block");
        ui.push_text(ts, "time avg. (us)");
        ui.push_text(ts, "time (%)");
        ui.push_text(ts, "cm avg.");
        ui.push_text(ts, "cm (%)");
        ui.push_text(ts, "pf avg.");
        ui.push_text(ts, "pf (%)");
        for (ts.profile.map.anchor_values()) |a| {
            const sec_avg = 1000000 * @divTrunc(@as(u64, @intCast(a.tsc_elapsed_exclusive)), a.hitcount) / ts.profile.timer_freq;
            const sec_proc = @divTrunc(100 * @as(u64, @intCast(a.tsc_elapsed_exclusive)), total.tsc_elapsed);
            const cm_avg = @divTrunc(@as(u64, @intCast(a.cachemiss_elapsed_exclusive)), a.hitcount);
            const cm_proc = @divTrunc(100 * @as(u64, @intCast(a.cachemiss_elapsed_exclusive)), total.cachemiss_elapsed);
            const pf_avg = @divTrunc(@as(u64, @intCast(a.pagefault_elapsed_exclusive)), a.hitcount);
            const pf_proc = @divTrunc(100 * @as(u64, @intCast(a.pagefault_elapsed_exclusive)), total.pagefault_elapsed);
            ui.push_text(ts, a.label);
            ui.push_text_fmt(ts, "{}", .{sec_avg});
            ui.push_text_fmt(ts, "{}", .{sec_proc});
            ui.push_text_fmt(ts, "{}", .{cm_avg});
            ui.push_text_fmt(ts, "{}", .{cm_proc});
            ui.push_text_fmt(ts, "{}", .{pf_avg});
            ui.push_text_fmt(ts, "{}", .{pf_proc});
        }

        ui.end_window(memory, cmd);
    }
}

pub fn draw_frame_bar(ts: *ThreadState, memory: *Memory, cmd: *CommandBuffer, target_frame_tsc: usize) void {
    const size = 0.009;
    const border = 0.08 * size;

    const black = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
    const white = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    const current_index = ts.debug_frame_data.peek_index(1);
    for (ts.debug_frame_data.data, 0..) |d, i| {
        const next_index = (i + 1) % ts.debug_frame_data.data.len;
        const next_data = ts.debug_frame_data.data[next_index];
        if (!next_data.used) {
            continue;
        }
        const tsc: f32 = if (d.used) @floatFromInt(next_data.profile.block_last_frame.elapsed_tsc) else 0;
        const ratio = tsc / @as(f32, @floatFromInt(target_frame_tsc));
        const hue = 100.0 * (1.0 - (@max(0.8, @min(ratio, 1.6)) - 0.8) / (1.6 - 0.8));

        const dist: f32 = @floatFromInt(ts.debug_frame_data.dist(current_index, i));
        const sat = if (d.used) 0.8 * (dist / @as(f32, @floatFromInt(ts.debug_frame_data.data.len))) else 0;
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

fn draw_profile_data(cmd: *CommandBuffer, id: u8, profile: *Profile, max_frame_tsc: usize) void {
    const height = 0.0125;
    const border = height * 0.1;
    const border_bg = height * 0.1;

    {
        const vs = profile.map.anchor_values();
        if (vs[0].hitcount == 0) {
            return;
        }

        Draw.rectangle_outline(cmd, .{
            .x = 0.0,
            .y = @as(f32, @floatFromInt(id)) * (height + 2 * border_bg) - border_bg,
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
                pindex = if (pid != 0) profile.map.get_index(pid).? else 0;
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
                .y = @as(f32, @floatFromInt(id)) * (height + 2 * border_bg),
            }, .{
                .x = width,
                .y = height,
            }, border, color, .{ .r = 0, .g = 0, .b = 0, .a = 255 });
        }
    }
}
