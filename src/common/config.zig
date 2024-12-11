const std = @import("std");
//const raylib = @cImport({
//    @cInclude("raylib.h");
//});

pub const Vars = struct {
    draw_fps: bool = false,
    draw_perf: bool = false,
    draw_net: bool = false,
    mode2d: bool = false,

    bloom: bool = false,

    //rt: raylib.RenderTexture = undefined,
    bloom_scale: u32 = 2,
    //bloom_mode: c_int = raylib.TEXTURE_FILTER_POINT,
    //bloom_downscale: raylib.RenderTexture = undefined,
    //bloom_upscale: raylib.RenderTexture = undefined,

    maxspeed: f32 = 2000,
    friction: f32 = 4,
    acceleration: f32 = 10,
    stopspeed: f32 = 100,

    upspeed: f32 = 200,
    forwardspeed: f32 = 320,
    backspeed: f32 = 320,
    sidespeed: f32 = 320,
    sprintmod: f32 = 2,

    sensitivity: f32 = 0.001,

    //cvar_t	cl_upspeed = {"cl_upspeed","200"};
    //cvar_t	cl_forwardspeed = {"cl_forwardspeed","200", true};
    //cvar_t	cl_backspeed = {"cl_backspeed","200", true};
    //cvar_t	cl_sidespeed = {"cl_sidespeed","350"};
    //cvar_t	cl_movespeedkey = {"cl_movespeedkey","2.0"};
    //cvar_t	cl_yawspeed = {"cl_yawspeed","140"};
    //cvar_t	cl_pitchspeed = {"cl_pitchspeed","150"};
    //cvar_t	cl_anglespeedkey = {"cl_anglespeedkey","1.5"};

    gravity: f32 = -800,
    jumpspeed: f32 = 270,
    maxairspeed: f32 = 30,

    speedometer: bool = false,

    mouse_enabled: bool = false,

    // camera stuffs
    fov: f32 = 80.0,
    fov_zoom: f32 = 40.0,
    aspect: f32 = 16.0 / 9.0,

    // weapon model stuff
    sniper_len: f32 = 75.0,
    sniper_w: f32 = 1.0,
    sniper_off_x: f32 = 8.0,
    sniper_off_y: f32 = -20,
    sniper_off_z: f32 = -7,

    sniper_stock_len: f32 = 2.0,
    sniper_stock_w: f32 = 2.0,
    sniper_stock_h: f32 = 3.0,
    sniper_stock_off_x: f32 = -8.0,
    sniper_stock_off_y: f32 = 0.0,
    sniper_stock_off_z: f32 = -1.5,

    sniper_scope_len: f32 = 6,
    sniper_scope_w: f32 = 1.5,
    sniper_scope_h: f32 = 1.5,
    sniper_scope_off_x: f32 = -2.0,
    sniper_scope_off_y: f32 = -0.0,
    sniper_scope_off_z: f32 = -5,

    pistol_len: f32 = 5.0,
    pistol_w: f32 = 1.0,
    pistol_off_x: f32 = 6.0,
    pistol_off_y: f32 = 8.0,
    pistol_off_z: f32 = -5.0,
    pistol_scope_len: f32 = 4.5,
    pistol_scope_w: f32 = 0.05,
    pistol_scope_h: f32 = 0.2,

    pistol_handle_len: f32 = 2.0,
    pistol_handle_w: f32 = 0.8,
    pistol_handle_off_x: f32 = -2.0,
    pistol_handle_off_y: f32 = 0.0,
    pistol_handle_off_z: f32 = -1.2,
};

pub var vars: Vars = .{};
