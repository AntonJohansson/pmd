const std = @import("std");
//const raylib = @cImport({
//    @cInclude("raylib.h");
//});

pub const Vars = struct {
    draw_fps:  bool = false,
    draw_perf: bool = false,
    draw_net:  bool = false,
    mode2d:    bool = false,

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
    //sidespeed: f32 = 350,
    sprintmod: f32 = 2,

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
    fov: f32 = 45.0,
    aspect: f32 = 4.0/3.0,
};

pub var vars: Vars = .{};
