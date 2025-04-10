const std = @import("std");

const logdir = "log";

pub const Group = enum(u8) {
    general,
    net,
    draw,
    game,
};

pub const Severity = enum(u8) {
    info,
    warn,
    err,
};

pub const Message = struct {
    group: Group,
    severity: Severity,
    message: []const u8,
};

pub const LogMemory = struct {
    messages: std.ArrayList(Message) = undefined,
    mirror_to_stdio: bool = false,
    file: ?std.fs.File = null,
    persistent: std.mem.Allocator,
    frame: std.mem.Allocator,

    pub fn init(persistent: std.mem.Allocator, frame: std.mem.Allocator, file: ?[]const u8, mirror_to_stdio: bool) !LogMemory {
        var logmem = LogMemory{
            .messages = std.ArrayList(Message){},
            .mirror_to_stdio = mirror_to_stdio,
            .persistent = persistent,
            .frame = frame,
        };

        if (file != null) {
            std.fs.cwd().makeDir(logdir) catch |dir_err| switch (dir_err) {
                error.PathAlreadyExists => {},
                else => unreachable,
            };

            const dir = try std.fs.cwd().openDir(logdir, .{});
            logmem.file = try dir.createFile(file.?, .{});
        }

        return logmem;
    }

    pub fn deinit() void {}

    pub fn append(memory: *LogMemory, comptime group: Group, comptime severity: Severity, comptime fmt: []const u8, args: anytype) void {
        const str = std.fmt.allocPrint(memory.persistent, fmt, args) catch return;

        memory.messages.append(memory.persistent, .{
            .group = group,
            .severity = severity,
            .message = str,
        }) catch return;

        if (memory.mirror_to_stdio) {
            const head = std.fmt.allocPrint(memory.frame, "[{s}] [{s}]: ", .{ @tagName(group), @tagName(severity) }) catch return;
            var stdout = std.fs.File.stdout();
            var buffer: [1024]u8 = undefined;
            var stdout_writer = stdout.writer(&buffer);
            const writer = &stdout_writer.interface;
            _ = writer.writeAll(head) catch return;
            _ = writer.writeAll(str) catch return;
            _ = writer.writeAll("\n") catch return;
        }
    }

    pub fn group_log(memory: *LogMemory, comptime group: Group) GroupLog(group) {
        return .{
            .memory = memory,
        };
    }
};

pub fn GroupLog(comptime group: Group) type {
    return struct {
        memory: *LogMemory = undefined,

        pub fn info(log: *@This(), comptime fmt: []const u8, args: anytype) void {
            log.memory.append(group, .info, fmt, args);
        }

        pub fn warn(log: *@This(), comptime fmt: []const u8, args: anytype) void {
            log.memory.append(group, .warn, fmt, args);
        }

        pub fn err(log: *@This(), comptime fmt: []const u8, args: anytype) void {
            log.memory.append(group, .err, fmt, args);
        }
    };
}
