const std = @import("std");

const common = @import("common.zig");
const profile = common.profile;
const primitive = common.primitive;
const math = common.math;

const logging = common.logging;
var log: logging.Log = .{
    .mirror_to_stdio = true,
};

const c = @cImport({
    @cInclude("glfw3.h");
});

//
// Generic
//

// Directories
pub const dir_res = "./res/";
pub const dir_audio = dir_res ++ "audio/";

// Memory
pub var mem: common.MemoryAllocators = .{};

pub const Id = u32;

pub fn id(comptime path: []const u8) Id {
    return comptime blk: {
        break :blk std.hash.Murmur3_32.hash(path);
    };
}

pub fn runtime_pack_id(path: []const u8) Id {
    return std.hash.Murmur3_32.hash(path);
}

pub fn readFileToMemory(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    const size = (try file.stat()).size;
    const buf = try file.readToEndAllocOptions(allocator, size, null, std.mem.Alignment.of(u64), null);
    return buf;
}

//
// Input
//

pub const Action = enum(u3) {
    release = c.GLFW_RELEASE,
    press = c.GLFW_PRESS,
    repeat = c.GLFW_REPEAT,
};

pub const GamepadButton = enum(u8) {
    a = c.GLFW_GAMEPAD_BUTTON_A,
    b = c.GLFW_GAMEPAD_BUTTON_B,
    x = c.GLFW_GAMEPAD_BUTTON_X,
    y = c.GLFW_GAMEPAD_BUTTON_Y,
    left_bumper = c.GLFW_GAMEPAD_BUTTON_LEFT_BUMPER,
    right_bumper = c.GLFW_GAMEPAD_BUTTON_RIGHT_BUMPER,
    back = c.GLFW_GAMEPAD_BUTTON_BACK,
    start = c.GLFW_GAMEPAD_BUTTON_START,
    guide = c.GLFW_GAMEPAD_BUTTON_GUIDE,
    left_thumb = c.GLFW_GAMEPAD_BUTTON_LEFT_THUMB,
    right_thumb = c.GLFW_GAMEPAD_BUTTON_RIGHT_THUMB,
    dpad_up = c.GLFW_GAMEPAD_BUTTON_DPAD_UP,
    dpad_right = c.GLFW_GAMEPAD_BUTTON_DPAD_RIGHT,
    dpad_down = c.GLFW_GAMEPAD_BUTTON_DPAD_DOWN,
    dpad_left = c.GLFW_GAMEPAD_BUTTON_DPAD_LEFT,
};

pub const GamepadAxis = enum(u8) {
    left_x = c.GLFW_GAMEPAD_AXIS_LEFT_X,
    left_y = c.GLFW_GAMEPAD_AXIS_LEFT_Y,
    right_x = c.GLFW_GAMEPAD_AXIS_RIGHT_X,
    right_y = c.GLFW_GAMEPAD_AXIS_RIGHT_Y,
    left_trigger = c.GLFW_GAMEPAD_AXIS_LEFT_TRIGGER,
    right_trigger = c.GLFW_GAMEPAD_AXIS_RIGHT_TRIGGER,
};

pub const MouseButton = enum(u8) {
    b1 = c.GLFW_MOUSE_BUTTON_1,
    b2 = c.GLFW_MOUSE_BUTTON_2,
    b3 = c.GLFW_MOUSE_BUTTON_3,
    b4 = c.GLFW_MOUSE_BUTTON_4,
    b5 = c.GLFW_MOUSE_BUTTON_5,
    b6 = c.GLFW_MOUSE_BUTTON_6,
    b7 = c.GLFW_MOUSE_BUTTON_7,
    b8 = c.GLFW_MOUSE_BUTTON_8,
    const left: u8 = c.GLFW_MOUSE_BUTTON_LEFT;
    const right: u8 = c.GLFW_MOUSE_BUTTON_RIGHT;
    const middle: u8 = c.GLFW_MOUSE_BUTTON_MIDDLE;
};

pub const Key = enum(u16) {
    space = c.GLFW_KEY_SPACE,
    apostrophe = c.GLFW_KEY_APOSTROPHE,
    comma = c.GLFW_KEY_COMMA,
    minus = c.GLFW_KEY_MINUS,
    period = c.GLFW_KEY_PERIOD,
    slash = c.GLFW_KEY_SLASH,
    num_0 = c.GLFW_KEY_0,
    num_1 = c.GLFW_KEY_1,
    num_2 = c.GLFW_KEY_2,
    num_3 = c.GLFW_KEY_3,
    num_4 = c.GLFW_KEY_4,
    num_5 = c.GLFW_KEY_5,
    num_6 = c.GLFW_KEY_6,
    num_7 = c.GLFW_KEY_7,
    num_8 = c.GLFW_KEY_8,
    num_9 = c.GLFW_KEY_9,
    semicolon = c.GLFW_KEY_SEMICOLON,
    equal = c.GLFW_KEY_EQUAL,
    a = c.GLFW_KEY_A,
    b = c.GLFW_KEY_B,
    c = c.GLFW_KEY_C,
    d = c.GLFW_KEY_D,
    e = c.GLFW_KEY_E,
    f = c.GLFW_KEY_F,
    g = c.GLFW_KEY_G,
    h = c.GLFW_KEY_H,
    i = c.GLFW_KEY_I,
    j = c.GLFW_KEY_J,
    k = c.GLFW_KEY_K,
    l = c.GLFW_KEY_L,
    m = c.GLFW_KEY_M,
    n = c.GLFW_KEY_N,
    o = c.GLFW_KEY_O,
    p = c.GLFW_KEY_P,
    q = c.GLFW_KEY_Q,
    r = c.GLFW_KEY_R,
    s = c.GLFW_KEY_S,
    t = c.GLFW_KEY_T,
    u = c.GLFW_KEY_U,
    v = c.GLFW_KEY_V,
    w = c.GLFW_KEY_W,
    x = c.GLFW_KEY_X,
    y = c.GLFW_KEY_Y,
    z = c.GLFW_KEY_Z,
    left_bracket = c.GLFW_KEY_LEFT_BRACKET,
    backslash = c.GLFW_KEY_BACKSLASH,
    right_bracket = c.GLFW_KEY_RIGHT_BRACKET,
    grave_accent = c.GLFW_KEY_GRAVE_ACCENT,
    world_1 = c.GLFW_KEY_WORLD_1,
    world_2 = c.GLFW_KEY_WORLD_2,
    escape = c.GLFW_KEY_ESCAPE,
    enter = c.GLFW_KEY_ENTER,
    tab = c.GLFW_KEY_TAB,
    backspace = c.GLFW_KEY_BACKSPACE,
    insert = c.GLFW_KEY_INSERT,
    delete = c.GLFW_KEY_DELETE,
    right = c.GLFW_KEY_RIGHT,
    left = c.GLFW_KEY_LEFT,
    down = c.GLFW_KEY_DOWN,
    up = c.GLFW_KEY_UP,
    page_up = c.GLFW_KEY_PAGE_UP,
    page_down = c.GLFW_KEY_PAGE_DOWN,
    home = c.GLFW_KEY_HOME,
    end = c.GLFW_KEY_END,
    caps_lock = c.GLFW_KEY_CAPS_LOCK,
    scroll_lock = c.GLFW_KEY_SCROLL_LOCK,
    num_lock = c.GLFW_KEY_NUM_LOCK,
    print_screen = c.GLFW_KEY_PRINT_SCREEN,
    pause = c.GLFW_KEY_PAUSE,
    f1 = c.GLFW_KEY_F1,
    f2 = c.GLFW_KEY_F2,
    f3 = c.GLFW_KEY_F3,
    f4 = c.GLFW_KEY_F4,
    f5 = c.GLFW_KEY_F5,
    f6 = c.GLFW_KEY_F6,
    f7 = c.GLFW_KEY_F7,
    f8 = c.GLFW_KEY_F8,
    f9 = c.GLFW_KEY_F9,
    f10 = c.GLFW_KEY_F10,
    f11 = c.GLFW_KEY_F11,
    f12 = c.GLFW_KEY_F12,
    f13 = c.GLFW_KEY_F13,
    f14 = c.GLFW_KEY_F14,
    f15 = c.GLFW_KEY_F15,
    f16 = c.GLFW_KEY_F16,
    f17 = c.GLFW_KEY_F17,
    f18 = c.GLFW_KEY_F18,
    f19 = c.GLFW_KEY_F19,
    f20 = c.GLFW_KEY_F20,
    f21 = c.GLFW_KEY_F21,
    f22 = c.GLFW_KEY_F22,
    f23 = c.GLFW_KEY_F23,
    f24 = c.GLFW_KEY_F24,
    f25 = c.GLFW_KEY_F25,
    kp_0 = c.GLFW_KEY_KP_0,
    kp_1 = c.GLFW_KEY_KP_1,
    kp_2 = c.GLFW_KEY_KP_2,
    kp_3 = c.GLFW_KEY_KP_3,
    kp_4 = c.GLFW_KEY_KP_4,
    kp_5 = c.GLFW_KEY_KP_5,
    kp_6 = c.GLFW_KEY_KP_6,
    kp_7 = c.GLFW_KEY_KP_7,
    kp_8 = c.GLFW_KEY_KP_8,
    kp_9 = c.GLFW_KEY_KP_9,
    kp_decimal = c.GLFW_KEY_KP_DECIMAL,
    kp_divide = c.GLFW_KEY_KP_DIVIDE,
    kp_multiply = c.GLFW_KEY_KP_MULTIPLY,
    kp_subtract = c.GLFW_KEY_KP_SUBTRACT,
    kp_add = c.GLFW_KEY_KP_ADD,
    kp_enter = c.GLFW_KEY_KP_ENTER,
    kp_equal = c.GLFW_KEY_KP_EQUAL,
    left_shift = c.GLFW_KEY_LEFT_SHIFT,
    left_control = c.GLFW_KEY_LEFT_CONTROL,
    left_alt = c.GLFW_KEY_LEFT_ALT,
    left_super = c.GLFW_KEY_LEFT_SUPER,
    right_shift = c.GLFW_KEY_RIGHT_SHIFT,
    right_control = c.GLFW_KEY_RIGHT_CONTROL,
    right_alt = c.GLFW_KEY_RIGHT_ALT,
    right_super = c.GLFW_KEY_RIGHT_SUPER,
    menu = c.GLFW_KEY_MENU,
};

const Input = common.Input;
const InputName = common.InputName;

pub const TriggerType = enum {
    rising_edge,
    falling_edge,
    rising_or_falling_edge,
    state,
    toggle,
};

pub const MouseScrollDir = enum {
    scroll_up,
    scroll_down,
};

pub const MouseScroll = struct {
    dir: MouseScrollDir,
};

pub const GamepadAxisAbsDir = enum {
    larger_than_zero,
    smaller_than_zero,
};

pub const GamepadAxisAbs = struct {
    axis: GamepadAxis,
    dir: GamepadAxisAbsDir,
};

// Represents all platform specific inputs such as keys/mouse buttons/scroll
pub const InputType = union(enum) {
    unmapped: bool,
    key: Key,
    mouse_button: MouseButton,
    mouse_scroll: MouseScroll,
    gamepad_button: GamepadButton,
    gamepad_axis_abs: GamepadAxisAbs,
};

pub const InputState = struct {
    trigger: TriggerType = .state,
    input_type: InputType = .{ .unmapped = true },
};

pub const InputMap = struct {
    const len = @typeInfo(InputName).@"enum".fields.len;
    map: [len]InputState = [_]InputState{.{}} ** len,

    const Self = @This();

    pub fn map_key(self: *Self, input_name: InputName, trigger: TriggerType, key: Key) void {
        self.map[@intFromEnum(input_name)] = InputState{
            .trigger = trigger,
            .input_type = .{ .key = key },
        };
    }

    pub fn map_mouse_button(self: *Self, input_name: InputName, input_type: TriggerType, mouse_button: MouseButton) void {
        self.map[@intFromEnum(input_name)] = InputState{
            .trigger = input_type,
            .input_type = .{ .mouse_button = mouse_button },
        };
    }

    pub fn map_mouse_scroll(self: *Self, input_name: InputName, dir: MouseScrollDir) void {
        self.map[@intFromEnum(input_name)] = InputState{
            .trigger = .state,
            .input_type = .{ .mouse_scroll = .{ .dir = dir } },
        };
    }

    pub fn map_gamepad_button(self: *Self, input_name: InputName, trigger: TriggerType, button: GamepadButton) void {
        self.map[@intFromEnum(input_name)] = InputState{
            .trigger = trigger,
            .input_type = .{ .gamepad_button = button },
        };
    }

    pub fn map_gamepad_axis(self: *Self, input_name: InputName, trigger: TriggerType, axis: GamepadAxis) void {
        self.map[@intFromEnum(input_name)] = InputState{
            .trigger = trigger,
            .input_type = .{ .gamepad_axis = axis },
        };
    }

    pub fn map_gamepad_axis_abs(self: *Self, input_name: InputName, trigger: TriggerType, axis_abs: GamepadAxisAbs) void {
        self.map[@intFromEnum(input_name)] = InputState{
            .trigger = trigger,
            .input_type = .{ .gamepad_axis_abs = axis_abs },
        };
    }
};

pub const InputMaps = struct {
    const num_states = @typeInfo(common.State).@"enum".fields.len;
    maps: [num_states]InputMap = [_]InputMap{.{}} ** num_states,

    pub fn get(self: *@This(), state: common.State) *InputMap {
        return &self.maps[@intFromEnum(state)];
    }
};

//
// Images
//

pub const Image = struct {
    pixels: []u8 = undefined,
    width: u32 = 0,
    height: u32 = 0,
    channels: u32 = 0,
};

pub const Text = struct {
    bytes: []u8 = undefined,
};

pub const FontChar = struct {
    x0: u16,
    y0: u16,
    x1: u16,
    y1: u16,
    xoff: f32,
    yoff: f32,
    xadvance: f32,
    xoff2: f32,
    yoff2: f32,
};

pub const Font = struct {
    chars: []FontChar = undefined,
    pixels: []u8 = undefined,
    width: u16 = 0,
    height: u16 = 0,
    size: u8 = 0,
};

pub const Shader = struct {
    vs_bytes: []u8 = undefined,
    fs_bytes: []u8 = undefined,
};

pub const Cubemap = struct {
    bytes: []u8 = undefined,
    width: u32 = 0,
    height: u32 = 0,
    channels: u32 = 0,

    pub fn faceSlice(cm: *const Cubemap, face: usize) []u8 {
        const bytes = cm.width * cm.height * cm.channels;
        return cm.bytes[face * bytes .. (face + 1) * bytes];
    }
};

pub const Audio = struct {
    samples: []f32 = undefined,
};

const CubemapFaceInfo = struct {
    pixels: []u8,
    path: []const u8,
};

//
// Audio
//

const SoundType = common.SoundType;

const SoundInfo = struct {
    path: []const u8,
    samples: []f32 = undefined,
    volume: f32 = 1.0,
};

const sound_info_map = blk: {
    var map: [@typeInfo(SoundType).Enum.fields.len]SoundInfo = undefined;
    map[@intFromEnum(.death)] = .{ .path = dir_audio ++ "kill.ogg", .volume = 0.7 };
    map[@intFromEnum(.slide)] = .{ .path = dir_audio ++ "slide.ogg", .volume = 0.7 };
    map[@intFromEnum(.sniper)] = .{ .path = dir_audio ++ "sniper.ogg", .volume = 0.7 };
    map[@intFromEnum(.weapon_switch)] = .{ .path = dir_audio ++ "switch.ogg", .volume = 0.2 };
    map[@intFromEnum(.step)] = .{ .path = dir_audio ++ "step.ogg", .volume = 0.7 };
    map[@intFromEnum(.pip)] = .{ .path = dir_audio ++ "pip.ogg", .volume = 0.7 };
    map[@intFromEnum(.explosion)] = .{ .path = dir_audio ++ "explosion.ogg", .volume = 0.7 };
    map[@intFromEnum(.doink)] = .{ .path = dir_audio ++ "doink.ogg", .volume = 0.7 };
    break :blk map;
};

pub fn loadAudio(st: SoundType) !void {
    const info = sound_info_map[@intFromEnum(st)];
    const buf = try readFileToMemory(info.path);

    var err: c_int = undefined;
    const vorbis = c.stb_vorbis_open_memory(buf.ptr, @intCast(buf.len), &err, null) orelse {
        log.err("Failed to decode file: {s}", .{info.path});
        return;
    };
    std.debug.assert(err == 0);

    const vorbis_info = c.stb_vorbis_get_info(vorbis);
    const num_samples: usize = @as(c_uint, @intCast(vorbis_info.channels)) * c.stb_vorbis_stream_length_in_samples(vorbis);
    info.samples = try mem.persistent.alloc(f32, num_samples);
    const samples_per_channel = c.stb_vorbis_get_samples_float_interleaved(vorbis, vorbis_info.channels, &info.samples[0], @intCast(num_samples));
    std.debug.assert(samples_per_channel * 2 == num_samples);
}

//
// Model
//

pub const VertexAttribute = enum(u8) {
    position = 0,
    normal = 1,
    texcoord = 2,
    color0 = 3,
};
const SLOT_tex = 0;
const SLOT_smp = 0;
const SLOT_vs_params = 0;

pub const bt_position: u8 = 1;
pub const bt_normals: u8 = 2;
pub const bt_texcoords: u8 = 4;
pub const bt_indices: u8 = 8;

pub const MeshIndex = u32;

pub const ModelNode = struct {
    root_entry_relative_index: i32 = 0,
    //transform: math.m4 = undefined,
    tree: common.TransformTree = undefined,
};

pub const MaterialIndex = u16;

pub const Mesh = struct {
    primitives: []MeshPrimitive = undefined,
};

pub const MeshPrimitive = struct {
    buffer_types: u8 = 0,
    pos: ?[]u8 = null,
    normals: ?[]u8 = null,
    texcoords: ?[]u8 = null,
    indices: ?[]u8 = null,
    material_index: MaterialIndex = 0,
};

pub const Model = struct {
    id: u64 = undefined,
    binary_data: []u8 = undefined,
    meshes: []Mesh = undefined,
    materials: ?[]Material = null,
    nodes: []u32 = undefined,
};

pub const Material = struct {
    // metallic
    base_color: math.v4 = .{},
    image: ?Image = null,
};

pub const Animation = struct {
    translation: ?AnimationTranslation = null,
    scale: ?AnimationScale = null,
    rotation: ?AnimationRotation = null,
    target: []u8 = undefined,
};

pub const AnimationTranslation = struct {
    time: []f32 = undefined,
    data: []math.v3 = undefined,
};

pub const AnimationScale = struct {
    time: []f32 = undefined,
    data: []math.v3 = undefined,
};

pub const AnimationRotation = struct {
    time: []f32 = undefined,
    data: []math.Quat = undefined,
};
