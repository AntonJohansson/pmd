const common = @import("common");
const v2 = common.math.v2;
const hsv_to_rgb = common.color.hsv_to_rgb;
const CommandBuffer = common.draw_api.CommandBuffer;
const Color = common.primitive.Color;
const Rectange = common.primitive.Rectangle;

pub fn rectangle_outline(cmd: *CommandBuffer, pos: v2, size: v2, border_thickness: f32, body_color: Color, border_color: Color) void {
    cmd.push(Rectange{
        .pos = pos,
        .size = size,
    }, border_color);

    const t = v2 {
        .x = border_thickness,
        .y = border_thickness,
    };
    cmd.push(Rectange{
        .pos = v2.add(pos, t),
        .size = v2.sub(size, v2.scale(2, t)),
    }, body_color);
}
