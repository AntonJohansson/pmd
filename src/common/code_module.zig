const std = @import("std");
const builtin = @import("builtin");
const common = @import("common.zig");
const ArenaFreelist = @import("arena-freelist.zig").ArenaFreelist;

pub fn CodeModule(comptime function_table_type: type) type {
    return struct {
        lib: std.DynLib = undefined,
        dir: []const u8,
        path_running: []const u8,
        name: []const u8,
        name_running: []const u8,
        function_table: function_table_type = undefined,
        last_mod_time: i128 = 0,
        arena: *ArenaFreelist = undefined,

        const Self = @This();
        pub fn init(arena: *ArenaFreelist, dir: []const u8, name: []const u8) !Self {
            const prefix = switch (builtin.os.tag) {
                .linux, .freebsd, .openbsd => "lib",
                .windows => "",
                .macos, .tvos, .watchos, .ios => "",
                else => return,
            };
            const ext = switch (builtin.os.tag) {
                .linux, .freebsd, .openbsd => ".so",
                .windows => ".dll",
                .macos, .tvos, .watchos, .ios => ".dylib",
                else => return,
            };
            const libname = common.str_concat(arena, &[_][]const u8{ prefix, name, ext });
            const libname_running = common.str_concat(arena, &[_][]const u8{ prefix, name, ".running", ext });

            const libpath_running = common.path_concat(arena, &[_][]const u8{ dir, libname_running });
            return Self{
                .dir = dir,
                .path_running = libpath_running,
                .name = libname,
                .name_running = libname_running,
                .function_table = undefined,
                .arena = arena,
            };
        }

        fn open_in_dir(self: *Self, dir: std.fs.Dir) !void {
            try std.fs.Dir.copyFile(dir, self.name, dir, self.name_running, .{});

            self.lib = try std.DynLib.open(self.path_running);
            inline for (@typeInfo(@TypeOf(self.function_table)).@"struct".fields) |f| {
                // Allocate space for a null-terminated string
                var name: [:0]u8 = @ptrCast(self.arena.alloc(u8, f.name.len + 1));
                @memcpy(name[0..f.name.len], f.name);
                name[f.name.len] = 0;

                @field(self.function_table, f.name) = self.lib.lookup(f.type, name) orelse {
                    std.log.info("failed loading function {s}", .{f.name});
                    return;
                };

                self.arena.free(@as([]u8, @ptrCast(name)));
            }
        }

        pub fn open(self: *Self) !void {
            var dir = try std.fs.cwd().openDir(self.dir, .{});
            defer dir.close();

            const stat = try dir.statFile(self.name);
            self.last_mod_time = stat.mtime;

            return try open_in_dir(self, dir);
        }

        pub fn close(self: *Self) void {
            self.lib.close();
        }

        pub fn reload_if_changed(self: *Self) !bool {
            var dir = try std.fs.cwd().openDir(self.dir, .{});
            defer dir.close();

            const stat = try dir.statFile(self.name);
            const new_mod_time = stat.mtime;
            if (new_mod_time > self.last_mod_time) {
                self.last_mod_time = new_mod_time;
                self.close();
                try open_in_dir(self, dir);
                return true;
            }
            return false;
        }
    };
}

//    var last_mod_time = try dir.statFile(libname);
//        const new_mod_time = try dir.statFile(libname);
//        if (new_mod_time.mtime > last_mod_time.mtime) {
//            last_mod_time = new_mod_time;
//            dynlib.close();
//            std.fs.Dir.copyFile(dir, libname, dir, libname_running, .{}) catch return;
//            dynlib = try std.DynLib.open(libpath_running);
//            fofo = dynlib.lookup(*fn()i32, "fofo") orelse return;
//            std.log.info("{}", .{fofo()});
//        }
