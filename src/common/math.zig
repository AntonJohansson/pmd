const std = @import("std");
const Camera = @import("camera.zig").Camera;

//
// v2
//

pub const v2 = extern struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
};

pub fn v2add(a: v2, b: v2) v2 {
    return v2 {
        .x = a.x + b.x,
        .y = a.y + b.y,
    };
}

pub fn v2sub(a: v2, b: v2) v2 {
    return v2 {
        .x = a.x + b.x,
        .y = a.y + b.y,
    };
}

pub fn v2neg(v: v2) v2 {
    return v2 {
        .x = -v.x,
        .y = -v.y,
    };
}

pub fn v2scale(f: f32, v: v2) v2 {
    return v2 {
        .x = f*v.x,
        .y = f*v.y,
    };
}

pub fn v2dot(a: v2, b: v2) f32 {
    return a.x*b.x + a.y*b.y;
}

pub fn v2len2(v: v2) f32 {
    return v2dot(v,v);
}

pub fn v2len(v: v2) f32 {
    return std.math.sqrt(v2len2(v));
}

pub fn v2normalize(v: v2) v2 {
    return v2scale(1.0/v2len(v), v);
}

pub fn v2ortho(v: v2) v2 {
    return v2 {.x = -v.y, .y = v.x};
}

pub fn v2angle(a: v2, b: v2) f32 {
    const s = v2len(a)*v2len(b);
    return std.math.acos(v2dot(a,b)/s);
}

pub fn v2signed_angle(a: v2, b: v2) f32 {
    var theta = std.math.atan2(a.y, a.x) - std.math.atan2(b.y, b.x);
    if (theta <= -std.math.pi) {
        theta += 2.0*std.math.pi;
    } else if (theta > std.math.pi) {
        theta -= 2.0*std.math.pi;
    }
    return theta;
}

//
// v3
//

pub const v3 = extern struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,
};

pub const v4 = extern struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,
    w: f32 = 0.0,
};

pub fn v3i(comptime T: type, x: T, y: T, z: T) v3 {
    return v3 {
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
        .z = @floatFromInt(z),
    };
}

pub fn v3eql(a: v3, b: v3) bool {
    return std.math.approxEqAbs(f32, a.x, b.x, 4.0*std.math.floatEps(f32)) and
           std.math.approxEqAbs(f32, a.y, b.y, 4.0*std.math.floatEps(f32)) and
           std.math.approxEqAbs(f32, a.z, b.z, 4.0*std.math.floatEps(f32));
}

pub fn v3neg(v: v3) v3{
    return v3 {.x = -v.x, .y = -v.y, .z = -v.z};
}

pub fn v3add(a: v3, b: v3) v3{
    return v3 {
        .x = a.x + b.x,
        .y = a.y + b.y,
        .z = a.z + b.z,
    };
}

pub fn v3sub(a: v3, b: v3) v3{
    return v3 {
        .x = a.x - b.x,
        .y = a.y - b.y,
        .z = a.z - b.z,
    };
}

pub fn v3scale(f: f32, v: v3) v3{
    return v3 {
        .x = f*v.x,
        .y = f*v.y,
        .z = f*v.z,
    };
}

pub fn v3dot(a: v3, b: v3) f32 {
    return a.x*b.x + a.y*b.y + a.z*b.z;
}

pub fn v3len2(v: v3) f32 {
    return v3dot(v,v);
}

pub fn v3len(v: v3) f32 {
    return std.math.sqrt(v3len2(v));
}

pub fn v3dist(a: v3, b: v3) f32 {
    return v3len(v3sub(a,b));
}

pub fn v3angle(a: v3, b: v3) f32 {
    const s = v3len(a)*v3len(b);
    return std.math.acos(v3dot(a,b)/s);
}

pub fn v3cross(a: v3, b: v3) v3 {
    // |x  y  z |
    // |xa ya za| = x(ya*zb-za*yb) + y(za*xb-xa*zb) + z(xa*yb-ya*xb)
    // |xb yb zb|
    return v3 {
        .x = a.y*b.z - a.z*b.y,
        .y = a.z*b.x - a.x*b.z,
        .z = a.x*b.y - a.y*b.x,
    };
}

pub fn v3normalize(v: v3) v3 {
    const s = 1.0 / v3len(v);
    return v3scale(s, v);
}

//
// m4
//

pub const m4 = struct {
    m00: f32 = undefined, m01: f32 = undefined, m02: f32 = undefined, m03: f32 = undefined,
    m10: f32 = undefined, m11: f32 = undefined, m12: f32 = undefined, m13: f32 = undefined,
    m20: f32 = undefined, m21: f32 = undefined, m22: f32 = undefined, m23: f32 = undefined,
    m30: f32 = undefined, m31: f32 = undefined, m32: f32 = undefined, m33: f32 = undefined,
};

pub const m3 = struct {
    m00: f32 = undefined, m01: f32 = undefined, m02: f32 = undefined,
    m10: f32 = undefined, m11: f32 = undefined, m12: f32 = undefined,
    m20: f32 = undefined, m21: f32 = undefined, m22: f32 = undefined,
};

pub const identity = m4 {
    .m00 = 1, .m01 = 0, .m02 = 0, .m03 = 0,
    .m10 = 0, .m11 = 1, .m12 = 0, .m13 = 0,
    .m20 = 0, .m21 = 0, .m22 = 1, .m23 = 0,
    .m30 = 0, .m31 = 0, .m32 = 0, .m33 = 1,
};

pub fn f32equal(a: f32, b: f32) bool {
    const epsilon = 1e-4;
    return std.math.approxEqAbs(f32, a, b, epsilon);
}

pub fn m4equal(a: m4, b: m4) bool {
    return f32equal(a.m00, b.m00) and f32equal(a.m01, b.m01) and f32equal(a.m02, b.m02) and f32equal(a.m03, b.m03) and
           f32equal(a.m10, b.m10) and f32equal(a.m11, b.m11) and f32equal(a.m12, b.m12) and f32equal(a.m13, b.m13) and
           f32equal(a.m20, b.m20) and f32equal(a.m21, b.m21) and f32equal(a.m22, b.m22) and f32equal(a.m23, b.m23) and
           f32equal(a.m30, b.m30) and f32equal(a.m31, b.m31) and f32equal(a.m32, b.m32) and f32equal(a.m33, b.m33);
}

pub fn m4print(m: m4) void {
    std.log.info("{d:15.5}{d:15.5}{d:15.5}{d:15.5}", .{m.m00, m.m01, m.m02, m.m03});
    std.log.info("{d:15.5}{d:15.5}{d:15.5}{d:15.5}", .{m.m10, m.m11, m.m12, m.m13});
    std.log.info("{d:15.5}{d:15.5}{d:15.5}{d:15.5}", .{m.m20, m.m21, m.m22, m.m23});
    std.log.info("{d:15.5}{d:15.5}{d:15.5}{d:15.5}", .{m.m30, m.m31, m.m32, m.m33});
}

pub fn m4transpose(m: m4) m4 {
    return m4 {
        .m00 = m.m00, .m01 = m.m10, .m02 = m.m20, .m03 = m.m30,
        .m10 = m.m01, .m11 = m.m11, .m12 = m.m21, .m13 = m.m31,
        .m20 = m.m02, .m21 = m.m12, .m22 = m.m22, .m23 = m.m32,
        .m30 = m.m03, .m31 = m.m13, .m32 = m.m23, .m33 = m.m33,
    };
}

pub fn m4mul(a: m4, b: m4) m4 {
    var res: m4 = undefined;

    res.m00 = a.m00*b.m00 + a.m01*b.m10 + a.m02*b.m20 + a.m03*b.m30;
    res.m01 = a.m00*b.m01 + a.m01*b.m11 + a.m02*b.m21 + a.m03*b.m31;
    res.m02 = a.m00*b.m02 + a.m01*b.m12 + a.m02*b.m22 + a.m03*b.m32;
    res.m03 = a.m00*b.m03 + a.m01*b.m13 + a.m02*b.m23 + a.m03*b.m33;

    res.m10 = a.m10*b.m00 + a.m11*b.m10 + a.m12*b.m20 + a.m13*b.m30;
    res.m11 = a.m10*b.m01 + a.m11*b.m11 + a.m12*b.m21 + a.m13*b.m31;
    res.m12 = a.m10*b.m02 + a.m11*b.m12 + a.m12*b.m22 + a.m13*b.m32;
    res.m13 = a.m10*b.m03 + a.m11*b.m13 + a.m12*b.m23 + a.m13*b.m33;

    res.m20 = a.m20*b.m00 + a.m21*b.m10 + a.m22*b.m20 + a.m23*b.m30;
    res.m21 = a.m20*b.m01 + a.m21*b.m11 + a.m22*b.m21 + a.m23*b.m31;
    res.m22 = a.m20*b.m02 + a.m21*b.m12 + a.m22*b.m22 + a.m23*b.m32;
    res.m23 = a.m20*b.m03 + a.m21*b.m13 + a.m22*b.m23 + a.m23*b.m33;

    res.m30 = a.m30*b.m00 + a.m31*b.m10 + a.m32*b.m20 + a.m33*b.m30;
    res.m31 = a.m30*b.m01 + a.m31*b.m11 + a.m32*b.m21 + a.m33*b.m31;
    res.m32 = a.m30*b.m02 + a.m31*b.m12 + a.m32*b.m22 + a.m33*b.m32;
    res.m33 = a.m30*b.m03 + a.m31*b.m13 + a.m32*b.m23 + a.m33*b.m33;

    return res;
}

pub fn v3tov4(v: v3) v4 {
    return v4 {.x = v.x, .y = v.y, .z = v.z, .w = 1};
}

pub fn v4tov3(v: v4) v3 {
    return v3 {.x = v.x, .y = v.y, .z = v.z};
}

pub fn m3transpose(m: m3) m3 {
    return m3 {
        .m00 = m.m00, .m01 = m.m10, .m02 = m.m20,
        .m10 = m.m01, .m11 = m.m11, .m12 = m.m21,
        .m20 = m.m02, .m21 = m.m12, .m22 = m.m22,
    };
}

pub fn m3mul(a: m3, b: m3) m3 {
    var res: m3 = undefined;

    res.m00 = a.m00*b.m00 + a.m01*b.m10 + a.m02*b.m20;
    res.m01 = a.m00*b.m01 + a.m01*b.m11 + a.m02*b.m21;
    res.m02 = a.m00*b.m02 + a.m01*b.m12 + a.m02*b.m22;

    res.m10 = a.m10*b.m00 + a.m11*b.m10 + a.m12*b.m20;
    res.m11 = a.m10*b.m01 + a.m11*b.m11 + a.m12*b.m21;
    res.m12 = a.m10*b.m02 + a.m11*b.m12 + a.m12*b.m22;

    res.m20 = a.m20*b.m00 + a.m21*b.m10 + a.m22*b.m20;
    res.m21 = a.m20*b.m01 + a.m21*b.m11 + a.m22*b.m21;
    res.m22 = a.m20*b.m02 + a.m21*b.m12 + a.m22*b.m22;

    return res;
}

pub fn m3mulv(m: m3, v: v3) v3 {
    return v3 {
        .x = v.x*m.m00 + v.y*m.m01 + v.z*m.m02,
        .y = v.x*m.m10 + v.y*m.m11 + v.z*m.m12,
        .z = v.x*m.m20 + v.y*m.m21 + v.z*m.m22,
    };
}

pub fn m4mulv(m: m4, v: v4) v4 {
    return v4 {
        .x = v.x*m.m00 + v.y*m.m01 + v.z*m.m02 + v.w*m.m03,
        .y = v.x*m.m10 + v.y*m.m11 + v.z*m.m12 + v.w*m.m13,
        .z = v.x*m.m20 + v.y*m.m21 + v.z*m.m22 + v.w*m.m23,
        .w = v.x*m.m30 + v.y*m.m31 + v.z*m.m32 + v.w*m.m33,
    };
}

pub fn m4scale(scale: v3) m4 {
    return m4 {
        .m00 = scale.x, .m01 = 0, .m02 = 0, .m03 = 0,
        .m10 = 0, .m11 = scale.y, .m12 = 0, .m13 = 0,
        .m20 = 0, .m21 = 0, .m22 = scale.z, .m23 = 0,
        .m30 = 0, .m31 = 0, .m32 = 0, .m33 = 1,
    };
}

pub fn m4modelSetScale(m: m4, scale: v3) m4 {
    return m4 {
        .m00 = scale.x*m.m00, .m01 = scale.y*m.m01, .m02 = scale.z*m.m02, .m03 = m.m03,
        .m10 = scale.x*m.m10, .m11 = scale.y*m.m11, .m12 = scale.z*m.m12, .m13 = m.m13,
        .m20 = scale.x*m.m20, .m21 = scale.y*m.m21, .m22 = scale.z*m.m22, .m23 = m.m23,
        .m30 = m.m30,         .m31 = m.m31,         .m32 = m.m32,         .m33 = m.m33,
    };
}

pub fn m4modelSetTranslation(m: m4, t: v3) m4 {
    return m4 {
        .m00 = m.m00, .m01 = m.m01, .m02 = m.m02, .m03 = t.x,
        .m10 = m.m10, .m11 = m.m11, .m12 = m.m12, .m13 = t.y,
        .m20 = m.m20, .m21 = m.m21, .m22 = m.m22, .m23 = t.z,
        .m30 = m.m30, .m31 = m.m31, .m32 = m.m32, .m33 = m.m33,
    };
}


pub fn m4modelInverse(m: m4) m4 {
    // Extract upper tranpose of rotation matrix
    const RT = m3 {
        .m00 = m.m00, .m01 = m.m10, .m02 = m.m20,
        .m10 = m.m01, .m11 = m.m11, .m12 = m.m21,
        .m20 = m.m02, .m21 = m.m12, .m22 = m.m22,
    };
    // Extract negtaive translation matrix
    const nt = v3 {.x = -m.m03, .y = -m.m13, .z = -m.m23};
    const new_t = m3mulv(RT, nt);
    return m4 {
        .m00 = RT.m00,.m01 = RT.m01,.m02 = RT.m02,    .m03 = new_t.x,
        .m10 = RT.m10,.m11 = RT.m11,.m12 = RT.m12,    .m13 = new_t.y,
        .m20 = RT.m20,.m21 = RT.m21,.m22 = RT.m22,    .m23 = new_t.z,
        .m30 = 0,     .m31 = 0,     .m32 = 0,         .m33 = 1,
    };
}

pub fn m4inverse(m: m4) m4 {
    //
    // M^-1 = (1/det(M)) * adj(M)
    //
    // adj(M) = transpose(cofactor(M))
    //

    //
    // 00  01  02  03
    // 10  11  12  13
    // 20  21  22  23
    // 30  31  32  33
    //
    // + - + -
    // - + - +
    // + - + -
    // - + - +
    //

    // TODO: There might be something wrong here, the top to elements in the last column have a larger error ~0.000* than
    // all other terms

    // Compute cofactor matrix
    const c00 =   (m.m11*(m.m22*m.m33 - m.m23*m.m32) + m.m12*(m.m23*m.m31 - m.m21*m.m33) + m.m13*(m.m21*m.m32 - m.m22*m.m31));
    const c01 = - (m.m10*(m.m22*m.m33 - m.m23*m.m32) + m.m12*(m.m23*m.m30 - m.m20*m.m33) + m.m13*(m.m20*m.m32 - m.m22*m.m30));
    const c02 =   (m.m10*(m.m21*m.m33 - m.m23*m.m31) + m.m11*(m.m23*m.m30 - m.m20*m.m33) + m.m13*(m.m20*m.m31 - m.m21*m.m30));
    const c03 = - (m.m10*(m.m21*m.m32 - m.m22*m.m31) + m.m11*(m.m22*m.m30 - m.m20*m.m32) + m.m12*(m.m20*m.m31 - m.m21*m.m30));

    const c10 = - (m.m01*(m.m22*m.m33 - m.m23*m.m32) + m.m02*(m.m23*m.m31 - m.m21*m.m33) + m.m03*(m.m21*m.m32 - m.m22*m.m31));
    const c11 =   (m.m00*(m.m22*m.m33 - m.m23*m.m32) + m.m02*(m.m23*m.m30 - m.m20*m.m33) + m.m03*(m.m20*m.m32 - m.m22*m.m30));
    const c12 = - (m.m00*(m.m21*m.m33 - m.m23*m.m31) + m.m01*(m.m23*m.m30 - m.m20*m.m33) + m.m03*(m.m20*m.m31 - m.m21*m.m30));
    const c13 =   (m.m00*(m.m21*m.m32 - m.m22*m.m31) + m.m01*(m.m22*m.m30 - m.m20*m.m32) + m.m02*(m.m20*m.m31 - m.m21*m.m30));

    const c20 =   (m.m01*(m.m12*m.m33 - m.m13*m.m32) + m.m02*(m.m13*m.m31 - m.m11*m.m33) + m.m03*(m.m11*m.m32 - m.m12*m.m31));
    const c21 = - (m.m00*(m.m12*m.m33 - m.m13*m.m32) + m.m02*(m.m13*m.m30 - m.m10*m.m33) + m.m03*(m.m10*m.m32 - m.m12*m.m30));
    const c22 =   (m.m00*(m.m11*m.m33 - m.m13*m.m31) + m.m01*(m.m13*m.m30 - m.m10*m.m33) + m.m03*(m.m10*m.m31 - m.m11*m.m30));
    const c23 = - (m.m00*(m.m11*m.m32 - m.m12*m.m31) + m.m01*(m.m12*m.m30 - m.m10*m.m32) + m.m02*(m.m10*m.m31 - m.m11*m.m30));

    const c30 = - (m.m01*(m.m12*m.m23 - m.m13*m.m22) + m.m02*(m.m13*m.m21 - m.m11*m.m23) + m.m03*(m.m11*m.m22 - m.m12*m.m21));
    const c31 =   (m.m00*(m.m12*m.m23 - m.m13*m.m22) + m.m02*(m.m13*m.m20 - m.m10*m.m23) + m.m03*(m.m10*m.m22 - m.m12*m.m20));
    const c32 = - (m.m00*(m.m11*m.m23 - m.m13*m.m21) + m.m01*(m.m13*m.m20 - m.m10*m.m23) + m.m03*(m.m10*m.m21 - m.m11*m.m20));
    const c33 =   (m.m00*(m.m11*m.m22 - m.m12*m.m21) + m.m01*(m.m12*m.m20 - m.m10*m.m22) + m.m02*(m.m10*m.m21 - m.m11*m.m20));

    // Compute determinant from cofactors from a row expansion along the first row
    const determinant = m.m00*c00 + m.m01*c01 + m.m02*c02 + m.m03*c03;
    std.debug.assert(!f32equal(determinant, 0.0));

    const scale = 1.0 / determinant;

    // Compute adjugate by transposing cofactor, the inverse
    // is then obtained by scaling with one over the determinant.
    const inverse = m4 {
        .m00 = scale*c00, .m01 = scale*c10, .m02 = scale*c20, .m03 = scale*c30,
        .m10 = scale*c01, .m11 = scale*c11, .m12 = scale*c21, .m13 = scale*c31,
        .m20 = scale*c02, .m21 = scale*c12, .m22 = scale*c22, .m23 = scale*c32,
        .m30 = scale*c03, .m31 = scale*c13, .m32 = scale*c23, .m33 = scale*c33,
    };

    return inverse;
}

pub fn m4model(translation: v3, scale: v3) m4 {
    return m4 {
        .m00 = scale.x, .m01 = 0, .m02 = 0, .m03 = translation.x,
        .m10 = 0, .m11 = scale.y, .m12 = 0, .m13 = translation.y,
        .m20 = 0, .m21 = 0, .m22 = scale.z, .m23 = translation.z,
        .m30 = 0, .m31 = 0, .m32 = 0, .m33 = 1,
    };
}

pub fn m4modelAxisI(m: m4) v3 {
    return v3 {
        .x = m.m00,
        .y = m.m10,
        .z = m.m20,
    };
}
pub fn m4modelAxisJ(m: m4) v3 {
    return v3 {
        .x = m.m01,
        .y = m.m11,
        .z = m.m21,
    };
}
pub fn m4modelAxisK(m: m4) v3 {
    return v3 {
        .x = m.m02,
        .y = m.m12,
        .z = m.m22,
    };
}
pub fn m4modelTranslation(m: m4) v3 {
    return v3 {
        .x = m.m03,
        .y = m.m13,
        .z = m.m23,
    };
}

const sin = std.math.sin;
const cos = std.math.cos;

pub fn m3modelRotX(angle: f32) m3 {
    const cosa = cos(angle);
    const sina = sin(angle);
    return m3 {
        .m00 = 1, .m01 = 0,    .m02 = 0,
        .m10 = 0, .m11 = cosa, .m12 = -sina,
        .m20 = 0, .m21 = sina, .m22 = cosa,
    };
}
pub fn m3modelRotY(angle: f32) m3 {
    const cosa = cos(angle);
    const sina = sin(angle);
    return m3 {
        .m00 = cosa,  .m01 = 0, .m02 = sina,
        .m10 = 0,     .m11 = 1, .m12 = 0,
        .m20 = -sina, .m21 = 0, .m22 = cosa,
    };
}
pub fn m3modelRotZ(angle: f32) m3 {
    const cosa = cos(angle);
    const sina = sin(angle);
    return m3 {
        .m00 = cosa, .m01 = -sina, .m02 = 0,
        .m10 = sina, .m11 = cosa,  .m12 = 0,
        .m20 = 0,    .m21 = 0,     .m22 = 1,
    };
}

pub fn m4modelRot(m: m4) m3 {
    return m3 {
        .m00 = m.m00,.m01 = m.m01,.m02 = m.m02,
        .m10 = m.m10,.m11 = m.m11,.m12 = m.m12,
        .m20 = m.m20,.m21 = m.m21,.m22 = m.m22,
    };
}

pub fn m4modelSetRot(m: m4, r: m3) m4 {
    return m4 {
        .m00=r.m00,.m01=r.m01,.m02=r.m02,.m03=m.m03,
        .m10=r.m10,.m11=r.m11,.m12=r.m12,.m13=m.m13,
        .m20=r.m20,.m21=r.m21,.m22=r.m22,.m23=m.m23,
        .m30=m.m30,.m31=m.m31,.m32=m.m32,.m33=m.m33,
    };
}

pub fn m4modelWithRotations(translation: v3, scale: v3, angles: v3) m4 {
    // a around z
    // b around y
    // c around x
    const cosa = cos(angles.z);
    const sina = sin(angles.z);
    const cosb = cos(angles.y);
    const sinb = sin(angles.y);
    const cosc = cos(angles.x);
    const sinc = sin(angles.x);
    return m4 {
        .m00 = scale.x*(cosa*cosb),   .m01 = scale.y*(cosa*sinb*sinc-sina*cosc),    .m02 = scale.z*(cosa*sinb*cosc+sina*sinc),    .m03 = translation.x,
        .m10 = scale.x*(sina*cosb),   .m11 = scale.y*(sina*sinb*sinc+cosa*cosc),    .m12 = scale.z*(sina*sinb*cosc-cosa*sinc),    .m13 = translation.y,
        .m20 = scale.x*(-sinb),       .m21 = scale.y*(cosb*sinc),                   .m22 = scale.z*(cosb*cosc),                   .m23 = translation.z,
        .m30 = 0,                     .m31 = 0,                                     .m32 = 0,                                     .m33 = 1,
    };
}

pub fn m4modelFromZDir(translation: v3, scale: v3, dir: v3) m4 {
    const up = v3 {.x=0, .y=0, .z=1};

    const i = v3cross(dir, up);
    const j = v3cross(i, dir);
    const k = v3neg(dir);

    return m4 {
        .m00 = scale.x*i.x,   .m01 = scale.y*j.x,   .m02 = scale.z*k.x,   .m03 = translation.x,
        .m10 = scale.x*i.y,   .m11 = scale.y*j.y,   .m12 = scale.z*k.y,   .m13 = translation.y,
        .m20 = scale.x*i.z,   .m21 = scale.y*j.z,   .m22 = scale.z*k.z,   .m23 = translation.z,
        .m30 = 0,             .m31 = 0,             .m32 = 0,             .m33 = 1,
    };
}

pub fn m4model2d(translation: v2, scale: v2) m4 {
    return m4 {
        .m00 = scale.x, .m01 = 0,       .m02 = 0,   .m03 = translation.x,
        .m10 = 0,       .m11 = scale.y, .m12 = 0,   .m13 = translation.y,
        .m20 = 0,       .m21 = 0,       .m22 = 1,   .m23 = 0,
        .m30 = 0,       .m31 = 0,       .m32 = 0,   .m33 = 1,
    };
}

pub fn m4rotz(angle: f32) m4 {
    return m4 {
        .m00 = cos(angle), .m01 = -sin(angle), .m02 = 0, .m03 = 0,
        .m10 = sin(angle), .m11 = cos(angle), .m12 = 0, .m13 = 0,
        .m20 = 0, .m21 = 0, .m22 = 1, .m23 = 0,
        .m30 = 0, .m31 = 0, .m32 = 0, .m33 = 1,
    };
}

pub fn m4view_from_camera(camera: Camera) m4 {
    const view_to_world = m4 {
        .m00 = camera.i.x,   .m01 = camera.j.x,   .m02 = camera.k.x,   .m03 = camera.pos.x,
        .m10 = camera.i.y,   .m11 = camera.j.y,   .m12 = camera.k.y,   .m13 = camera.pos.y,
        .m20 = camera.i.z,   .m21 = camera.j.z,   .m22 = camera.k.z,   .m23 = camera.pos.z,
        .m30 = 0,            .m31 = 0,            .m32 = 0,            .m33 = 1,
    };

    //const world_to_view = m4inverse(view_to_world);
    const world_to_view = m4modelInverse(view_to_world);

    // Here we perform a redudency check to make sure the matrix
    // inverse is actually the inverse.
    std.debug.assert(m4equal(m4mul(world_to_view, view_to_world), identity));

    return world_to_view;
}

// We use norm(A) = sum(A[ij]^2)
pub fn m4norm(m: m4) f32 {
    return m.m00*m.m00 +
           m.m10*m.m10 +
           m.m20*m.m20 +
           m.m30*m.m30 +
           m.m01*m.m01 +
           m.m11*m.m11 +
           m.m21*m.m21 +
           m.m31*m.m31 +
           m.m02*m.m02 +
           m.m12*m.m12 +
           m.m22*m.m22 +
           m.m32*m.m32 +
           m.m03*m.m03 +
           m.m13*m.m13 +
           m.m23*m.m23 +
           m.m33*m.m33;
}

pub fn m4view(pos: v3, dir: v3) m4 {
    const world_up = v3 {
        .x = 0,
        .y = 0,
        .z = 1,
    };

    const ndir = v3normalize(dir);

    const i = v3normalize(v3cross(ndir, world_up));
    const j = v3cross(i, ndir);
    const k = v3neg(ndir);

    const view_to_world = m4 {
        .m00 = i.x,   .m01 = j.x,   .m02 = k.x,   .m03 = pos.x,
        .m10 = i.y,   .m11 = j.y,   .m12 = k.y,   .m13 = pos.y,
        .m20 = i.z,   .m21 = j.z,   .m22 = k.z,   .m23 = pos.z,
        .m30 = 0,     .m31 = 0,     .m32 = 0,     .m33 = 1,
    };

    const world_to_view = m4inverse(view_to_world);
    //const world_to_view = m4modelInverse(view_to_world);

    // Here we perform a redudency check to make sure the matrix
    // inverse is actually the inverse.
    if (!f32equal(4.0, m4norm(m4mul(world_to_view, view_to_world)))) {
        std.log.info("Numerical instability in matrix inverse inv(A)*A = ", .{});
        m4print(m4mul(world_to_view, view_to_world));
    }
    return world_to_view;
}

pub fn m4projection(near: f32, far: f32, aspect: f32, fov: f32) m4 {

    //                  A  right
    //                  +-----+
    //                oo|oo   |
    //            oooo__|__oooo-------+
    //          oo\     |     /oo     |
    //         o   \   fov   /   o    |
    //        8     \   |   /     8   | near
    //       8       \  |  /       8  |
    //       8        \ | /        8  |
    //      8          \|/ angle    8 |
    // <----------------+-------------+->
    //
    // tan(angle) = near/right
    // => right = near/tan(angle)

    const angle = std.math.pi*(1.0 - fov/180.0)/2.0;
    const right = near/std.math.tan(angle);
    const top = right/aspect;

    return m4 {
        .m00 = near/right, .m01 = 0,        .m02 = 0,                      .m03 =   0,
        .m10 = 0,          .m11 = near/top, .m12 = 0,                      .m13 =   0,
        .m20 = 0,          .m21 = 0,        .m22 = -(far+near)/(far-near), .m23 =   -2.0*near*far/(far-near),
        .m30 = 0,          .m31 = 0,        .m32 = -1.0,                   .m33 =   0,
    };
}

//var yaw: f32 = -std.math.pi / 2.0;
//var pitch: f32 = 0.0;
//var pos = v3 {.x = -5.0, .y = -5.0, .z = 0.0};
//var mvp: m4 = undefined;
//{
//    //const delta = raylib.GetMouseDelta();
//    //yaw += 0.001*delta.x;
//    //pitch += 0.001*delta.y;
//    //pitch = std.math.clamp(pitch, -std.math.pi/2.0+0.01, std.math.pi/2.0-0.01);

//    //const dir = v3 {
//    //    //.x = std.math.cos(yaw)*std.math.cos(pitch),
//    //    //.y = -std.math.sin(pitch),
//    //    //.z = std.math.sin(yaw)*std.math.cos(pitch),
//    //    .x = 1.0/std.math.sqrt(2),
//    //    .y = 1.0/std.math.sqrt(2),
//    //    .z = 0.0,
//    //};
//    //var c = camera.create(pos, dir);

//    //var move_delta = v3 {};
//    //if (raylib.IsKeyDown(raylib.KEY_A)) move_delta = v3add(move_delta, v3scale(-1.0, c.i));
//    //if (raylib.IsKeyDown(raylib.KEY_D)) move_delta = v3add(move_delta, v3scale( 1.0, c.i));
//    //if (raylib.IsKeyDown(raylib.KEY_W)) move_delta = v3add(move_delta, v3scale(-1.0, c.k));
//    //if (raylib.IsKeyDown(raylib.KEY_S)) move_delta = v3add(move_delta, v3scale( 1.0, c.k));

//    //if (!f32equal(v3len2(move_delta), 0.0)) {
//    //    c.pos = v3add(c.pos, v3scale(0.025, v3normalize(move_delta)));
//    //    pos = c.pos;
//    //}

//    // model:       model space -> world space
//    // view:        world space -> view space
//    // projection:  view space  -> homogenous clip space
//    //const model = m4model(v3 {.x = 0.0, .y = 0.0, .z = 0.0});
//    //const view = m4view_from_camera(c);
//    //const projection = m4projection(0.1, 10.0, 16.0/9.0, 40.0);

//    //mvp = m4transpose(m4mul(projection, m4mul(view, model)));
//}
