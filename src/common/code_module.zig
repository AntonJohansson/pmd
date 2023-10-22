const std = @import("std");
const builtin = @import("builtin");

fn osPath(path: *[]const u8) void {
    for (path) |*byte| {
        switch (byte) {
            '/', '\\' => byte.* = std.fs.path.sep,
            else => {},
        }
    }
}

pub fn CodeModule(comptime function_table_type: type) type {

    return struct {
        lib: std.DynLib = undefined,
        dir: []const u8,
        path_running: []const u8,
        name: []const u8,
        name_running: []const u8,
        function_table: function_table_type = undefined,
        last_mod_time: i128 = 0,

        const Self = @This();
        pub fn init(allocator: std.mem.Allocator, dir: []const u8, name: []const u8) !Self {
            const prefix = switch (builtin.os.tag) {
                .linux, .freebsd, .openbsd    => "lib",
                .windows                      => "",
                .macos, .tvos, .watchos, .ios => "",
                else => return,
            };
            const ext = switch (builtin.os.tag) {
                .linux, .freebsd, .openbsd    => ".so",
                .windows                      => ".dll",
                .macos, .tvos, .watchos, .ios => ".dylib",
                else => return,
            };
            const libname         = try std.mem.concat(allocator, u8, &[_][]const u8{prefix, name, ext});
            const libname_running = try std.mem.concat(allocator, u8, &[_][]const u8{prefix, name, ".running", ext});

            const libpath_running = try std.fs.path.join(allocator, &[_][]const u8{dir, libname_running});
            return Self {
                .dir = dir,
                .path_running = libpath_running,
                .name = libname,
                .name_running = libname_running,
                .function_table = undefined,
            };
        }

        fn openInDir(self: *Self, allocator: std.mem.Allocator, dir: std.fs.Dir) !void {
            try std.fs.Dir.copyFile(dir, self.name, dir, self.name_running, .{});

            self.lib = try std.DynLib.open(self.path_running);
            inline for (@typeInfo(@TypeOf(self.function_table)).Struct.fields) |f| {
                // Allocate space for a null-terminated string
                var name: [:0]u8 = @ptrCast(try allocator.alloc(u8, f.name.len+1));
                std.mem.copy(u8, name, f.name);
                name[f.name.len] = 0;

                @field(self.function_table, f.name) = self.lib.lookup(f.type, name) orelse {
                    std.log.info("failed loading function {s}", .{f.name});
                    return;
                };

                allocator.free(@as([]u8, @ptrCast(name)));
            }
        }

        pub fn open(self: *Self, allocator: std.mem.Allocator) !void {
            var dir = try std.fs.cwd().openDir(self.dir, .{});
            defer dir.close();

            const stat = try dir.statFile(self.name);
            self.last_mod_time = stat.mtime;

            return try openInDir(self, allocator, dir);
        }

        pub fn close(self: *Self) void {
            self.lib.close();
        }

        pub fn reloadIfChanged(self: *Self, allocator: std.mem.Allocator) !bool {
            var dir = try std.fs.cwd().openDir(self.dir, .{});
            defer dir.close();

            const stat = try dir.statFile(self.name);
            const new_mod_time = stat.mtime;
            if (new_mod_time > self.last_mod_time) {
                self.last_mod_time = new_mod_time;
                self.close();
                try openInDir(self, allocator, dir);
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
