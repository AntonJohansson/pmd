const std = @import("std");

const common = @import("common");
const Memory = common.Memory;
const ThreadState = common.ThreadState;
const draw_api = common.draw_api;
const primitive = common.primitive;
const hsv_to_rgb = common.color.hsv_to_rgb;
const color = common.color;

const draw = @import("draw.zig");

const math = common.math;
const v2 = math.v2;
const v4 = math.v4;

pub const fontsize = 1.0 / 30.0;
pub const window_fontsize = 1.0 / 60.0;
pub const h_margin = window_fontsize;
pub const v_margin = window_fontsize;
pub const table_pad = 1.0 / 120.0;
pub const linespace = 1.0 / 240.0;

const button_padding = v2{
    .x = 0.015,
    .y = 0.005,
};

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
            index: u8,
        },
    },
};

var input: *const common.Input = undefined;
var cmdlist = common.IntrusiveList(Cmd){};
var current_window: *common.WindowState = undefined;
const CmdIt = common.IntrusiveList(Cmd).Item;

pub fn width() f32 {
    return common.memory.aspect_ratio;
}

pub fn set_input(i: *const common.Input) void {
    input = i;
}

pub fn begin_window(ts: *ThreadState, memory: *Memory, window_type: common.WindowType, title: []const u8, x: f32, y: f32) bool {
    cmdlist = .{
        .arena = &ts.arena_frame,
    };
    const persistent = &memory.windows_persistent[@intFromEnum(window_type)];
    if (!persistent.initialized) {
        @branchHint(.unlikely);
        persistent.pos.x = x;
        persistent.pos.y = y;
        persistent.size.x = 0.01;
        persistent.size.y = 0.01;
        persistent.initialized = true;
    }

    memory.windows.append(.{
        .persistent = persistent,
        .title = title,
        .cursor_x = 0 + h_margin / persistent.size.x,
        .cursor_y = 1 - v_margin / persistent.size.y,
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
    _ = ts;
    const index = current_window.button_index;
    current_window.button_index += 1;

    const ctext = cstr(text);
    cmdlist.append(.{
        .color = hsv_to_rgb(.{0,0,0}),
        .data = .{
            .button = .{
                .text = ctext,
                .state = .reset,
                .index = index,
            },
        },
    });
    const state = current_window.persistent.button_state[index];
    current_window.persistent.button_state[index] = 0;
    return state == 1;
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
    _ = ts;
    const ctext = cstr(text);
    cmdlist.append(.{
        .color = hsv_to_rgb(.{0,0,0}),
        .data = .{
            .text = ctext,
        },
    });
}

pub fn push_text_fmt(ts: *ThreadState, comptime fmt: []const u8, args: anytype) void {
    const ctext = common.cstr_fmt(&ts.arena_frame, fmt, args);
    cmdlist.append(.{
        .color = hsv_to_rgb(.{0,0,0}),
        .data = .{
            .text = ctext,
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
                .x = textwidth(memory, window_fontsize, b.text) + 2*button_padding.x,
                .y = window_fontsize + 2*button_padding.y +  linespace,
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
            const col_fg = color.scale_v(window.color, 2.0);
            cmdbuf.push(primitive.Text{
                .pos = .{
                    .x = window.persistent.pos.x + window.persistent.size.x * window.cursor_x + h_margin,
                    .y = window.persistent.pos.y + window.persistent.size.y * window.cursor_y - top_bar_height - window_fontsize - v_margin,
                },
                .str = t,
                .size = window_fontsize,
                .bg = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
                .fg = hsv_to_rgb(col_fg),
            }, it.*.?.value.color);

            if (!inhibit_newline) {
                window.cursor_y -= (window_fontsize + linespace) / window.persistent.size.y;
            }
        },
        .table => |t| {
            for (0..t.rows) |r| {
                for (0..t.cols) |c| {
                    it.* = it.*.?.next;
                    window.cursor_x += (table_pad) / window.persistent.size.x;
                    cmd_draw(memory, cmdbuf, it, window, true);
                    window.cursor_x += (t.computed_col_widths[c] + table_pad) / window.persistent.size.x;
                }
                window.cursor_x = 0;
                window.cursor_y -= (t.computed_row_heights[r] + linespace) / window.persistent.size.y;
            }
        },
        .button => |*b| {
            const s = v2{
                .x = textwidth(memory, window_fontsize, b.text) + 2*button_padding.x,
                .y = window_fontsize + 2*button_padding.y,
            };
            const p = v2{
                .x = window.persistent.pos.x + window.persistent.size.x * window.cursor_x + h_margin,
                .y = window.persistent.pos.y + window.persistent.size.y * window.cursor_y - top_bar_height - window_fontsize - v_margin,
            };
            const p_button = v2.add(p, .{.x = 0, .y = -2*button_padding.y - linespace});
            var col_fg: color.HSV = undefined;
            var col_button_bg: color.HSV = undefined;
            var col_button_fg: color.HSV = undefined;
            // update button state
            if (pos_in_rect(memory.cursor_pos, p_button, s)) {
                if (input.get(.Interact) == .high) {
                    b.state = .press;
                } else if (input.get(.Interact) == .falling) {
                    window.persistent.button_state[b.index] = 1;
                    b.state = .release;
                } else {
                    b.state = .hover;
                }
            } else {
                b.state = .reset;
            }
            switch (b.state) {
                .reset => {
                    col_fg = color.scale_v(window.color, 2.0);
                    col_button_bg = color.scale_v(window.color, 0.75);
                    col_button_fg = color.scale_v(window.color, 1.25);
                },
                .hover => {
                    col_fg = color.scale_v(window.color, 0.5);
                    col_button_bg = color.scale_v(window.color, 1.25);
                    col_button_fg = color.scale_v(window.color, 0.75);
                },
                .press => {
                    col_fg = color.scale_v(window.color, 2.0);
                    col_button_bg = color.scale_v(window.color, 0.50);
                    col_button_fg = color.scale_v(window.color, 1.25);
                },
                .release => {
                    col_fg = color.scale_v(window.color, 2.0);
                    col_button_bg = color.scale_v(window.color, 0.50);
                    col_button_fg = color.scale_v(window.color, 1.25);
                },
            }
            draw.rectangle_outline(cmdbuf, p_button, s, 0.0008,
                hsv_to_rgb(col_button_bg),
                hsv_to_rgb(col_button_fg));

            cmdbuf.push(primitive.Text{
                .pos = v2.add(p, .{.x = button_padding.x, .y = -button_padding.y}),
                .str = b.text,
                .size = window_fontsize,
                .bg = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
                .fg = hsv_to_rgb(col_fg),
            }, .{.r = 0, .g = 0, .b = 0, .a = 0});

            if (!inhibit_newline) {
                window.cursor_y -= (s.y + linespace) / window.persistent.size.y;
            }
        },
    }
}

const top_bar_height = 0.025;
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

    //const y_diff = @max(window.persistent.size.y, max.y) - window.persistent.size.y;
    window.persistent.size.x = @max(window.persistent.size.x, max.x);
    window.persistent.size.y = @max(window.persistent.size.y, max.y);

    if (window.persistent.pos.x == 0 and window.persistent.pos.y == 0) {
        window.persistent.pos.x = width()/2.0 - window.persistent.size.x/2.0;
        window.persistent.pos.y = 1.0/2.0 - window.persistent.size.y/2.0;
    }

    // background
    cmd.push(primitive.Rectangle{ .pos = .{
        .x = window.persistent.pos.x,
        .y = window.persistent.pos.y,
    }, .size = .{
        .x = window.persistent.size.x,
        .y = window.persistent.size.y - top_bar_height,
    } }, hsv_to_rgb(window.color));

    var top_bar_color_factor: f32 = 1.5;
    var top_bar_title_factor: f32 = 0.5;
    if (window.persistent.moving) {
        top_bar_color_factor = 0.5;
        top_bar_title_factor = 2.0;
    } else if (window.persistent.hover_top_bar) {
        top_bar_color_factor = 0.8;
        top_bar_title_factor = 1.5;
    }

    // top bar
    const ctitle = cstr(window.title);
    const pad = @max(0, 0.3*window_fontsize);
    cmd.push(primitive.Rectangle{ .pos = .{
        .x = window.persistent.pos.x,
        .y = window.persistent.pos.y + window.persistent.size.y - top_bar_height,
    }, .size = .{
        .x = @max(window.persistent.size.x, max.x),
        .y = top_bar_height,
    } }, hsv_to_rgb(color.scale_v(window.color, top_bar_color_factor)));
    cmd.push(primitive.Text{
        .pos = .{
            .x = window.persistent.pos.x + 0.01,
            .y = window.persistent.pos.y + window.persistent.size.y - top_bar_height + pad,
        },
        .str = ctitle,
        .size = window_fontsize,
        .bg = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
        .fg = hsv_to_rgb(color.scale_v(window.color, top_bar_title_factor)),
    }, .{.r = 0, .g = 0, .b = 0, .a = 0});
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

pub fn window_mouse_collision(memory: *Memory) void {
    var maybew = memory.windows.head;
    while (maybew) |item| {
        var w = &item.value;
        if (pos_in_rect(memory.cursor_pos, w.persistent.pos, w.persistent.size)) {
            if (memory.cursor_pos.y > w.persistent.pos.y + w.persistent.size.y - top_bar_height) {
                // hover over top bar
                w.persistent.hover_top_bar = true;
                if (input.get(.Interact) == .rising) {
                    memory.window_moving_offset = v2.sub(.{ .x = w.persistent.pos.x, .y = w.persistent.pos.y }, memory.cursor_pos);
                    w.persistent.moving = true;
                }
            } else {
                // hover over window body
                w.persistent.hover_top_bar = false;
                w.persistent.hover_body = true;
            }
        } else {
            w.persistent.hover_top_bar = false;
            w.persistent.hover_body = false;
        }

        if (w.persistent.moving) {
            w.persistent.pos = v2.add(memory.cursor_pos, memory.window_moving_offset);
            if (input.get(.Interact) == .falling) {
                w.persistent.moving = false;
            }
        }

        maybew = item.next;
    }
}

fn textwidth(memory: *Memory, size: f32, str: [:0]const u8) f32 {
    const scale = size / (@as(f32, @floatFromInt(memory.font.size)));
    var w: f32 = 0;
    for (str[0..str.len]) |c| {
        const off = c - 32;
        w += scale * memory.font.chars[off].xadvance;
    }
    return w;
}

fn pos_in_rect(p: v2, r: v2, s: v2) bool {
    return p.x >= r.x and
           p.y >= r.y and
           p.x <= r.x + s.x and
           p.y <= r.y + s.y;
}

fn cstr(str: []const u8) [:0]const u8 {
    const cs = common.thread.arena_frame.alloc(u8, str.len + 1);
    @memcpy(cs[0..str.len], str);
    cs[str.len] = 0;
    return @ptrCast(cs[0..str.len]);
}
