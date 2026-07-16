const std = @import("std");

const common = @import("common");
const Memory = common.Memory;
const ThreadState = common.ThreadState;
const draw_api = common.draw_api;
const primitive = common.primitive;
const hsv_to_rgb = common.color.hsv_to_rgb;

const math = common.math;
const v2 = math.v2;
const v4 = math.v4;

pub const fontsize = 1.0 / 30.0;
pub const window_fontsize = 1.0 / 60.0;
pub const h_margin = window_fontsize;
pub const v_margin = window_fontsize;
pub const table_pad = 1.0 / 120.0;
pub const linespace = 1.0 / 240.0;

const Cmd = struct {
    color: primitive.Color,
    data: union(enum) {
        text: [:0]const u8,
        table: struct {
            rows: usize,
            cols: usize,
            computed_col_widths: []f32,
            computed_row_heights: []f32,
        },
        button: struct {
            text: [:0]const u8,
            state: enum {
                reset,
                hover,
                press,
                release,
            } = .reset,
        },
    },
};

var cmdlist = common.IntrusiveList(Cmd){};
var current_window: *common.WindowState = undefined;
const CmdIt = common.IntrusiveList(Cmd).Item;

pub fn begin_window(ts: *ThreadState, memory: *Memory, window_type: common.WindowType, title: []const u8, x: f32, y: f32) bool {
    cmdlist = .{
        .arena = &ts.arena_frame,
    };
    const persistent = &memory.windows_persistent[@intFromEnum(window_type)];
    if (!persistent.initialized) {
        @branchHint(.unlikely);
        persistent.x = x;
        persistent.y = y;
        persistent.w = 0.1;
        persistent.h = 0.1;
        persistent.initialized = true;
    }

    memory.windows.append(.{
        .persistent = persistent,
        .title = title,
        .cursor_x = 0 + h_margin / persistent.w,
        .cursor_y = 1 - v_margin / persistent.h,
    });
    current_window = &memory.windows.tail.?.value;

    return true;
}

pub fn end_window(memory: *Memory, cmd: *draw_api.CommandBuffer) void {
    draw_window(memory, cmd, current_window);
    var it = cmdlist.head;
    while (it != null) {
        cmd_draw(memory, cmd, &it, current_window, false);
        it = it.?.next;
    }
}

pub fn button(ts: *ThreadState, text: []const u8) bool {
    const cstr = ts.arena_frame.alloc(u8, text.len + 1);
    @memcpy(cstr[0..text.len], text);
    cstr[text.len] = 0;
    cmdlist.append(.{
        .color = hsv_to_rgb(100, 0.5, 0.5),
        .data = .{
            .button = .{
                .text = @ptrCast(cstr[0..text.len]),
                .state = .reset,
            },
        },
    });
    return false;
}

pub fn begin_table(ts: *ThreadState, rows: usize, cols: usize) void {
    const computed_cols = ts.arena_frame.alloc(f32, cols);
    const computed_rows = ts.arena_frame.alloc(f32, rows);
    @memset(computed_cols, 0);
    @memset(computed_rows, 0);
    cmdlist.append(.{
        .color = undefined,
        .data = .{
            .table = .{
                .rows = rows,
                .cols = cols,
                .computed_col_widths = computed_cols,
                .computed_row_heights = computed_rows,
            },
        },
    });
}

pub fn push_text(ts: *ThreadState, text: []const u8) void {
    const cstr = ts.arena_frame.alloc(u8, text.len + 1);
    @memcpy(cstr[0..text.len], text);
    cstr[text.len] = 0;
    cmdlist.append(.{
        .color = hsv_to_rgb(100, 0.5, 0.5),
        .data = .{
            .text = @ptrCast(cstr[0..text.len]),
        },
    });
}

pub fn push_text_fmt(ts: *ThreadState, comptime fmt: []const u8, args: anytype) void {
    const cstr = common.cstr_fmt(&ts.arena_frame, fmt, args);
    cmdlist.append(.{
        .color = hsv_to_rgb(100, 0.5, 0.5),
        .data = .{
            .text = cstr,
        },
    });
}

fn cmd_size(memory: *Memory, max: *v2, it: *?*CmdIt, inhibit_newline: bool) v2 {
    if (it.* == null) {
        return .{};
    }
    switch (it.*.?.value.data) {
        .text => |t| {
            const ret = v2{
                .x = textwidth(memory, window_fontsize, t),
                .y = window_fontsize + linespace,
            };
            max.* = .{
                .x = @max(max.x, ret.x),
                .y = if (!inhibit_newline) max.y + ret.y else max.y,
            };
            return ret;
        },
        .table => |t| {
            for (0..t.rows) |r| {
                var height: f32 = 0;
                for (0..t.cols) |c| {
                    it.* = it.*.?.next;
                    const size = cmd_size(memory, max, it, true);
                    t.computed_col_widths[c] = @max(t.computed_col_widths[c], size.x);
                    height = @max(height, size.y);
                }
                t.computed_row_heights[r] = height;
            }

            var total = v2{};
            for (0..t.cols) |c| {
                total.x += t.computed_col_widths[c] + 2 * table_pad;
            }
            for (0..t.rows) |r| {
                total.y += t.computed_row_heights[r];
            }
            total.y += linespace * @as(f32, @floatFromInt(t.rows - 1));
            max.* = .{
                .x = @max(max.x, total.x),
                .y = max.y + total.y,
            };
            return total;
        },
        .button => |b| {
            const ret = v2{
                .x = textwidth(memory, window_fontsize, b.text),
                .y = window_fontsize + linespace,
            };
            max.* = .{
                .x = @max(max.x, ret.x),
                .y = if (!inhibit_newline) max.y + ret.y else max.y,
            };
            return ret;
        },
    }
}

fn cmd_draw(memory: *Memory, cmdbuf: *draw_api.CommandBuffer, it: *?*CmdIt, window: *common.WindowState, inhibit_newline: bool) void {
    if (it.* == null) {
        return;
    }
    switch (it.*.?.value.data) {
        .text => |t| {
            cmdbuf.push(primitive.Text{
                .pos = .{
                    .x = window.persistent.x + window.persistent.w * window.cursor_x + h_margin,
                    .y = window.persistent.y + window.persistent.h * window.cursor_y - top_bar_height - window_fontsize - v_margin,
                },
                .str = t,
                .size = window_fontsize,
                .bg = .{ .x = 0, .y = 0, .z = 0, .w = 0 },
                .fg = .{ .x = 0, .y = 1, .z = 0, .w = 1 },
            }, it.*.?.value.color);

            if (!inhibit_newline) {
                window.cursor_y -= (window_fontsize + linespace) / window.persistent.h;
            }
        },
        .table => |t| {
            for (0..t.rows) |r| {
                for (0..t.cols) |c| {
                    it.* = it.*.?.next;
                    window.cursor_x += (table_pad) / window.persistent.w;
                    cmd_draw(memory, cmdbuf, it, window, true);
                    window.cursor_x += (t.computed_col_widths[c] + table_pad) / window.persistent.w;
                }
                window.cursor_x = 0;
                window.cursor_y -= (t.computed_row_heights[r] + linespace) / window.persistent.h;
            }
        },
        .button => |b| {
            const s = v2{
                .x = textwidth(memory, window_fontsize, b.text),
                .y = (window_fontsize + linespace),
            };
            const p = v2{
                .x = window.persistent.x + window.persistent.w * window.cursor_x + h_margin,
                .y = window.persistent.y + window.persistent.h * window.cursor_y - top_bar_height - window_fontsize - v_margin,
            };
            var col = v4{ .x = 0, .y = 1, .z = 0, .w = 1 };
            if (memory.cursor_pos.x >= p.x and
                memory.cursor_pos.y >= p.y and
                memory.cursor_pos.x <= p.x + s.x and
                memory.cursor_pos.y <= p.y + s.y)
            {
                col = v4{ .x = 1, .y = 1, .z = 0, .w = 1 };
            }
            cmdbuf.push(primitive.Text{
                .pos = p,
                .str = b.text,
                .size = window_fontsize,
                .bg = .{ .x = 0, .y = 0, .z = 0, .w = 0 },
                .fg = col,
            }, it.*.?.value.color);

            if (!inhibit_newline) {
                window.cursor_y -= (window_fontsize + linespace) / window.persistent.h;
            }
        },
    }
}

const top_bar_height = 0.01;
fn draw_window(memory: *Memory, cmd: *draw_api.CommandBuffer, window: *common.WindowState) void {
    var max: v2 = .{ .x = 0, .y = 0 };
    var it = cmdlist.head;
    while (it != null) {
        _ = cmd_size(memory, &max, &it, false);
        it = it.?.next;
    }

    max.x += 2 * h_margin;
    max.y += top_bar_height + 2 * v_margin - linespace + window_fontsize;

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
        .y = window.persistent.y - (@max(window.persistent.h, max.y) - window.persistent.h),
    }, .size = .{
        .x = @max(window.persistent.w, max.x),
        .y = @max(window.persistent.h, max.y) - top_bar_height,
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
        .x = @max(window.persistent.w, max.x),
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

pub fn window_mouse_collision(memory: *Memory, input: *const common.Input) void {
    var maybew = memory.windows.head;
    while (maybew) |item| {
        var w = &item.value;
        if (memory.cursor_pos.x >= w.persistent.x and
            memory.cursor_pos.y >= w.persistent.y + w.persistent.h - top_bar_height and
            memory.cursor_pos.x <= w.persistent.x + w.persistent.w and
            memory.cursor_pos.y <= w.persistent.y + w.persistent.h)
        {
            w.hover = true;
        } else {
            w.hover = false;
        }

        if (input.isset(.Interact)) {
            if (w.persistent.moving) {
                w.persistent.moving = false;
            } else if (w.hover) {
                memory.window_moving_offset = v2.sub(.{ .x = w.persistent.x, .y = w.persistent.y }, memory.cursor_pos);
                w.persistent.moving = true;
            }
        }

        if (w.persistent.moving) {
            w.persistent.x = memory.cursor_pos.x + memory.window_moving_offset.x;
            w.persistent.y = memory.cursor_pos.y + memory.window_moving_offset.y;
        }

        maybew = item.next;
    }
}

var font: ?common.res.Font = null;
fn textwidth(memory: *Memory, size: f32, str: [:0]const u8) f32 {
    if (font == null) {
        @branchHint(.cold);
        font = common.goosepack.resource_lookup(&memory.pack, "res/fonts/MononokiNerdFontMono-Regular").?.font;
    }
    const scale = size / (@as(f32, @floatFromInt(font.?.size)));
    var w: f32 = 0;
    for (str[0..str.len]) |c| {
        const off = c - 32;
        w += scale * font.?.chars[off].xadvance;
    }
    return w;
}
