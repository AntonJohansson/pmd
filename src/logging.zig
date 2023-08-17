const std = @import("std");

const pa = std.heap.page_allocator;
var arena = std.heap.ArenaAllocator.init(pa);
const aa = arena.allocator();

pub const Log = struct {
    messages: std.ArrayList([]const u8) = std.ArrayList([]const u8).init(pa),
    mirror_to_stdio: bool = false,
    file: ?[]const u8 = null,

    pub fn info(log: *Log, comptime fmt: []const u8, args: anytype) void {
        const message = std.fmt.allocPrint(aa, "[info] " ++ fmt ++ "\n", args) catch unreachable;
        log.messages.append(message) catch unreachable;

        if (log.file != null) {
            std.fs.cwd().makeDir("logs") catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => unreachable,
            };

            const dir = std.fs.cwd().openDir("logs", .{}) catch unreachable;
            const file = dir.createFile(log.file.?, .{}) catch unreachable;
            defer file.close();

            _ = file.write(message) catch unreachable;
        }

        if (log.mirror_to_stdio) {
            const stdout = std.io.getStdOut().writer();
            _ = stdout.write(message) catch unreachable;
        }
    }

};

pub fn free() void {
    aa.deinit();
    pa.deinit();
}
