const math = @import("math.zig");
const v3 = math.v3;
const v3cross = math.v3cross;
const v3neg = math.v3neg;

pub const Camera = struct {
    pos: v3,
    i: v3,
    j: v3,
    k: v3,
};

pub fn create(pos: v3, dir: v3) Camera {
    const world_up = v3 {.x = 0, .y = 1, .z = 0};

    const i = v3cross(dir, world_up);
    const j = v3cross(i, dir);
    const k = v3neg(dir);

    return Camera {
        .pos = pos,
        .i = i,
        .j = j,
        .k = k,
    };
}
