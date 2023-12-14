const common = @import("common");
const math = common.math;
const v3 = math.v3;
const v2 = math.v2;
const m4 = math.m4;

pub const Result = struct {
    pos: v3,
    normal: v3,
    distance: f32,
};

pub fn infinitePlaneAxisLine(plane_pos: v3, k: v3, line_start: v3, line_dir: v3) ?v3 {
    const pn = v3.dot(line_start, k);
    const qn = v3.dot(plane_pos,  k);
    const vn = v3.dot(line_dir,   k);
    if (vn == 0)
        return null;
    const t = (qn-pn)/vn;
    if (t < 0)
        return null;
    return v3.add(line_start, v3.scale(t, line_dir));
}

pub fn planeAxisLine(plane_pos: v3, i: v3, j: v3, k: v3, plane_size: v2, line_start: v3, line_dir: v3) ?Result {
    const pn = v3.dot(line_start, k);
    const qn = v3.dot(plane_pos,  k);
    const vn = v3.dot(line_dir,   k);
    if (vn == 0)
        return null;
    const t = (qn-pn)/vn;
    if (t < 0)
        return null;

    const p = v3.add(line_start, v3.scale(t, line_dir));

    const vec_to_origin = v3.sub(p, plane_pos);
    if (@abs(v3.dot(vec_to_origin, i)) <= plane_size.x/2.0 and
        @abs(v3.dot(vec_to_origin, j)) <= plane_size.y/2.0) {
        return .{.pos=p, .normal=k, .distance=t};
    } else {
        return null;
    }
}

pub fn planeAxisRay(plane_pos: v3, i: v3, j: v3, k: v3, plane_size: v2, ray_start: v3, ray_delta: v3) ?Result {
    const pn = v3.dot(ray_start, k);
    const qn = v3.dot(plane_pos, k);
    const vn = v3.dot(ray_delta, k);

    // check if ray_delta crosses the plane,
    // if not, return
    if ((pn-qn)*(pn-qn+vn) >= 0)
        return null;

    // distance to plane
    const t = (qn-pn)/vn;
    if (t > 1 or t < 0)
        return null;

    const p = v3.add(ray_start, v3.scale(t, ray_delta));

    const vec_to_origin = v3.sub(p, plane_pos);
    if (@abs(v3.dot(vec_to_origin, i)) <= plane_size.x/2.0 and
        @abs(v3.dot(vec_to_origin, j)) <= plane_size.y/2.0) {
        const ray_len = v3.len(ray_delta);
        return .{.pos=p, .normal=k, .distance=ray_len*t};
    } else {
        return null;
    }
}

pub fn planeModelLine(plane_model: m4, plane_size: v2, line_start: v3, line_dir: v3) ?Result {
    const i = m4.modelAxisI(plane_model);
    const j = m4.modelAxisJ(plane_model);
    const k = m4.modelAxisK(plane_model);
    const pos = m4.modelTranslation(plane_model);
    return planeAxisLine(pos,i,j,k,plane_size, line_start,line_dir);
}

pub fn planeModelRay(plane_model: m4, plane_size: v2, ray_start: v3, ray_delta: v3) ?Result {
    const i = m4.modelAxisI(plane_model);
    const j = m4.modelAxisJ(plane_model);
    const k = m4.modelAxisK(plane_model);
    const pos = m4.modelTranslation(plane_model);
    return planeAxisRay(pos,i,j,k,plane_size, ray_start,ray_delta);
}

pub fn cubeLine(cube_model: m4, cube_size: v3, line_start: v3, line_dir: v3) ?Result {
    const pos = m4.modelTranslation(cube_model);
    const i = m4.modelAxisI(cube_model);
    const j = m4.modelAxisJ(cube_model);
    const k = m4.modelAxisK(cube_model);

    const dot_i = v3.dot(line_dir, i);
    const dot_j = v3.dot(line_dir, j);
    const dot_k = v3.dot(line_dir, k);
    const sign_i = dot_i/@abs(dot_i);
    const sign_j = dot_j/@abs(dot_j);
    const sign_k = dot_k/@abs(dot_k);
    const ni = v3.scale(-sign_i, i);
    const nj = v3.scale(-sign_j, j);
    const nk = v3.scale(-sign_k, k);

    const pi = v3.add(pos, v3.scale(cube_size.x/2.0, ni));
    const pj = v3.add(pos, v3.scale(cube_size.y/2.0, nj));
    const pk = v3.add(pos, v3.scale(cube_size.z/2.0, nk));

    if (planeAxisLine(pi, nj,nk,ni, .{.x=cube_size.y,.y=cube_size.z}, line_start,line_dir)) |v| return v;
    if (planeAxisLine(pj, nk,ni,nj, .{.x=cube_size.z,.y=cube_size.x}, line_start,line_dir)) |v| return v;
    if (planeAxisLine(pk, ni,nj,nk, .{.x=cube_size.x,.y=cube_size.y}, line_start,line_dir)) |v| return v;

    return null;
}

pub fn annulusLine(pos: v3, inner_radius: f32, outer_radius: f32, k: v3, line_start: v3, line_dir: v3) ?Result {
    const p = infinitePlaneAxisLine(pos, k, line_start, line_dir) orelse return null;
    const dist2 = v3.len2(v3.sub(p, pos));
    const inside = (dist2 >= inner_radius*inner_radius and dist2 <= outer_radius*outer_radius);
    if (!inside)
        return null;
    return .{.pos = p, .normal = k, .distance = v3.len(v3.sub(p, line_start))};
}

pub fn triangleRay(a: v3, b: v3, c: v3, p: v3, d: v3) ?Result {
    const u = v3.sub(b,a);
    const v = v3.sub(c,a);
    const n = v3.cross(u,v);

    const pn = v3.dot(p, n);
    const qn = v3.dot(a, n);
    const dn = v3.dot(d, n);
    if (dn == 0)
        return null;

    const t = (qn-pn)/dn;
    if (t > 1 or t < 0)
        return null;

    const pp = v3.add(p, v3.scale(t, d));

    const w = v3.sub(pp,a);

    const n2 = v3.len2(n);
    const gamma = v3.dot(v3.cross(u,w), n)/n2;
    const beta  = v3.dot(v3.cross(w,v), n)/n2;
    const alpha = 1 - gamma - beta;

    if (alpha >= 0 and alpha <= 1 and
        beta  >= 0 and
        gamma >= 0) {
        return Result {
            .pos = pp,
            .normal = v3.normalize(n),
            .distance = t*v3.len(d),
        };
    } else {
        return null;
    }
}

pub fn triangleLine(a: v3, b: v3, c: v3, p: v3, d: v3) ?Result {
    const u = v3.sub(b,a);
    const v = v3.sub(c,a);
    const n = v3.cross(u,v);

    const pn = v3.dot(p, n);
    const qn = v3.dot(a, n);
    const dn = v3.dot(d, n);
    if (dn == 0)
        return null;
    const t = (qn-pn)/dn;
    const pp = v3.add(p, v3.scale(t, d));

    const w = v3.sub(pp,a);

    const n2 = v3.len2(n);
    const gamma = v3.dot(v3.cross(u,w), n)/n2;
    const beta  = v3.dot(v3.cross(w,v), n)/n2;
    const alpha = 1 - gamma - beta;

    if (alpha >= 0 and alpha <= 1 and
        beta  >= 0 and
        gamma >= 0) {
        return Result {
            .pos = pp,
            .normal = v3.normalize(n),
            .distance = t,
        };
    } else {
        return null;
    }
}
