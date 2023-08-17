const std = @import("std");
const config = @import("config.zig");
const Vars = config.Vars;
const net = @import("net.zig");
const packet = @import("packet.zig");
const raylib = @cImport({
    @cInclude("raylib.h");
});

fn cldrawfps() void {
    config.vars.draw_fps = !config.vars.draw_fps;
}

fn cldrawperf() void {
    config.vars.draw_perf = !config.vars.draw_perf;
}

fn cldrawnet() void {
    config.vars.draw_net = !config.vars.draw_net;
}

fn clbind(i: i32) void {
    std.log.info("wow {}", .{i});
}

fn clmode2d() void {
    config.vars.mode2d = !config.vars.mode2d;

    if (!config.vars.mode2d) {
        // 3d camera mode
        if (config.vars.mouse_enabled) {
            config.vars.mouse_enabled = false;
            raylib.DisableCursor();
        }
    } else {
        // 2d camera mode
        if (!config.vars.mouse_enabled) {
            config.vars.mouse_enabled = true;
            raylib.EnableCursor();
        }
    }
}

fn clbloomScale(scale: u32) void {
    const width  = @divTrunc(config.vars.rt.texture.width,  @as(c_int, @intCast(scale)));
    const height = @divTrunc(config.vars.rt.texture.height, @as(c_int, @intCast(scale)));
    raylib.UnloadRenderTexture(config.vars.bloom_downscale);
    config.vars.bloom_downscale = raylib.LoadRenderTexture(width, height);
    raylib.SetTextureFilter(config.vars.bloom_downscale.texture, config.vars.bloom_mode);
    raylib.SetTextureFilter(config.vars.bloom_downscale.texture, config.vars.bloom_mode);
    raylib.SetTextureWrap(config.vars.bloom_downscale.texture, raylib.TEXTURE_WRAP_CLAMP);
    config.vars.bloom_scale = scale;
}
fn clbloom() void { config.vars.bloom = !config.vars.bloom; }
fn setBloomMode(mode: c_int) void {
    raylib.SetTextureFilter(config.vars.rt.texture, mode);
    raylib.SetTextureFilter(config.vars.bloom_downscale.texture, mode);
    config.vars.bloom_mode = mode;
}
fn clbloomPoint()     void { setBloomMode(raylib.TEXTURE_FILTER_POINT); }
fn clbloomBilinear()  void { setBloomMode(raylib.TEXTURE_FILTER_BILINEAR); }
fn clbloomTrilinear() void { setBloomMode(raylib.TEXTURE_FILTER_TRILINEAR); }
fn clbloomAniso4()    void { setBloomMode(raylib.TEXTURE_FILTER_ANISOTROPIC_4X); }
fn clbloomAniso8()    void { setBloomMode(raylib.TEXTURE_FILTER_ANISOTROPIC_8X); }
fn clbloomAniso16()   void { setBloomMode(raylib.TEXTURE_FILTER_ANISOTROPIC_16X); }

fn dodo(comptime func_name: []const u8, comptime func: anytype, it: *std.mem.TokenIterator(u8)) ?std.meta.ArgsTuple(@TypeOf(func)) {
    var tuple: std.meta.ArgsTuple(@TypeOf(func)) = undefined;
    const args = @typeInfo(@TypeOf(func)).Fn.args;
    inline for (args, 0..) |arg,i| {
        comptime var buf: [128]u8 = undefined;
        comptime var name = std.fmt.bufPrint(&buf, "{d}", .{i}) catch unreachable;
        if (it.next()) |str| {
            switch (arg.arg_type.?) {
                u8,
                i8,
                u16,
                i16,
                u32,
                i32,
                u64,
                i64 => |t| {
                    @field(tuple, name) = std.fmt.parseInt(t, str, 0) catch {
                        std.log.err("failed parsing {s}, expected type {}", .{str, t});
                        return null;
                    };
                },
                f32,
                f64 => |t| {
                    @field(tuple, name) = std.fmt.parseFloat(t, str) catch {
                        std.log.err("failed parsing {s}, expected type {}", .{str, t});
                        return null;
                    };
                },
                []const u8 => @field(tuple, name) = str,
                else => {
                    @compileError("Command " ++ func_name ++ " has invalid argument type " ++ @typeName(arg.arg_type.?));
                },
            }
        } else {
            std.log.err("Too few arguments supplied, signature {}", .{@TypeOf(func)});
            return null;
        }
    }

    if (it.rest().len > 0) {
        std.log.err("Too many arguments supplied, signature {}, {s} superfluous", .{@TypeOf(func), it.rest()});
        return null;
    }

    return tuple;
}

pub fn dodododododododo(peer_index: ?net.PeerIndex, commandline: []const u8) void {
    var it = std.mem.tokenize(u8, commandline, " ");
    const command = it.next() orelse {
        std.log.err("expected command", .{});
        return;
    };
    const setall = std.mem.eql(u8, command, "setall");
    const set  = std.mem.eql(u8, command, "set");
    if (set or setall) {
        // Hardcode set command as we need to treat the value passed separately.
        if (setall and peer_index != null) {
            var command_packet = packet.Command{
                .data = undefined,
                .len = commandline.len,
            };
            std.mem.copy(u8, &command_packet.data, commandline);
            net.pushMessage(peer_index.?, command_packet);
        }

        const varname = it.next() orelse {
            std.log.err("expected variable name", .{});
            return;
        };

        inline for (@typeInfo(Vars).Struct.fields) |field| {
            if (std.mem.eql(u8, varname, field.name)) {
                const f = @field(config.vars, field.name);
                const T = @TypeOf(f);
                if (it.next()) |str| {
                    switch (T) {
                        bool => |t| {
                            if (std.mem.eql(u8, str, "true")) {
                                @field(config.vars, field.name) = true;
                            } else if (std.mem.eql(u8, str, "false")) {
                                @field(config.vars, field.name) = false;
                            } else {
                                std.log.err("failed parsing {s}, expected type {}", .{str, t});
                                return;
                            }
                        },
                        u8,
                        i8,
                        u16,
                        i16,
                        u32,
                        i32,
                        u64,
                        i64 => |t| {
                            @field(config.vars, field.name) = std.fmt.parseInt(t, str, 0) catch {
                                std.log.err("failed parsing {s}, expected type {}", .{str, t});
                                return;
                            };
                        },
                        f32,
                        f64 => |t| {
                            @field(config.vars, field.name) = std.fmt.parseFloat(t, str) catch {
                                std.log.err("failed parsing {s}, expected type {}", .{str, t});
                                return;
                            };
                        },
                        []const u8 => @field(config.vars, field.name) = str,
                        else => {
                            std.log.err("{s} has unsupported type {} for set command", .{varname, T});
                        },
                    }
                } else {
                    std.log.err("Too few arguments supplied, expected \"set varname value\"", .{});
                    return;
                }
            }
        }

    } else {
        // Here we dispatch to cl*() functions if the command == * and arguments
        // are valid.
        inline for (@typeInfo(@This()).Struct.decls) |decl| {
            const f = @field(@This(), decl.name);
            const T = @TypeOf(f);
            const ti = @typeInfo(T);
            if (ti == .Fn and decl.name.len > "cl".len and decl.name[0] == 'c' and decl.name[1] == 'l' and std.mem.eql(u8, command, decl.name["cl".len..])) {
                if (dodo(decl.name, f, &it)) |args| {
                    @call(.{}, f, args);
                }
            }
        }
    }
}
