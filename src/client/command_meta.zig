const std = @import("std");
const config = @import("config.zig");
const Vars = config.Vars;
const commands = @import("command_client.zig");

fn check_args(comptime func_name: []const u8, comptime func: anytype, it: *std.mem.TokenIterator(u8, .any)) ?std.meta.ArgsTuple(@TypeOf(func)) {
    var tuple: std.meta.ArgsTuple(@TypeOf(func)) = undefined;
    const args = @typeInfo(@TypeOf(func)).Fn.params;
    inline for (args, 0..) |arg, i| {
        comptime var buf: [128]u8 = undefined;
        const name = comptime std.fmt.bufPrint(&buf, "{d}", .{i}) catch unreachable;
        if (it.next()) |str| {
            switch (arg.type.?) {
                u8, i8, u16, i16, u32, i32, u64, i64 => |t| {
                    @field(tuple, name) = std.fmt.parseInt(t, str, 0) catch {
                        std.log.err("failed parsing {s}, expected type {}", .{ str, t });
                        return null;
                    };
                },
                f32, f64 => |t| {
                    @field(tuple, name) = std.fmt.parseFloat(t, str) catch {
                        std.log.err("failed parsing {s}, expected type {}", .{ str, t });
                        return null;
                    };
                },
                []const u8 => @field(tuple, name) = str,
                else => {
                    @compileError("Command " ++ func_name ++ " has invalid argument type " ++ @typeName(arg.type.?));
                },
            }
        } else {
            std.log.err("Too few arguments supplied, signature {}", .{@TypeOf(func)});
            return null;
        }
    }

    if (it.rest().len > 0) {
        std.log.err("Too many arguments supplied, signature {}, {s} superfluous", .{ @TypeOf(func), it.rest() });
        return null;
    }

    return tuple;
}

pub fn run(commandline: []const u8) void {
    var it = std.mem.tokenize(u8, commandline, " ");
    const command = it.next() orelse {
        std.log.err("expected command", .{});
        return;
    };

    if (std.mem.eql(u8, command, "set")) {
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
                                std.log.err("failed parsing {s}, expected type {}", .{ str, t });
                                return;
                            }
                        },
                        u8, i8, u16, i16, u32, i32, u64, i64 => |t| {
                            @field(config.vars, field.name) = std.fmt.parseInt(t, str, 0) catch {
                                std.log.err("failed parsing {s}, expected type {}", .{ str, t });
                                return;
                            };
                        },
                        f32, f64 => |t| {
                            @field(config.vars, field.name) = std.fmt.parseFloat(t, str) catch {
                                std.log.err("failed parsing {s}, expected type {}", .{ str, t });
                                return;
                            };
                        },
                        []const u8 => @field(config.vars, field.name) = str,
                        else => {
                            std.log.err("{s} has unsupported type {} for set command", .{ varname, T });
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
        inline for (@typeInfo(commands).Struct.decls) |decl| {
            const f = @field(commands, decl.name);
            const T = @TypeOf(f);
            const ti = @typeInfo(T);
            if (ti == .Fn and std.mem.eql(u8, command, decl.name)) {
                if (check_args(decl.name, f, &it)) |args| {
                    @call(.auto, f, args);
                }
            }
        }
    }
}
