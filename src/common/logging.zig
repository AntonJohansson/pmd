const std = @import("std");
const common = @import("common");
const Arena = common.Arena;
const Pool = common.Pool;

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

fn arena_print(arena: *Arena, fmt: []const u8, args: anytype) []u8 {
    const buf = arena.memory[arena.top..];
    const str = std.fmt.bufPrint(buf, fmt, args) catch unreachable;
    arena.top += str.len;
    return str;
}

pub const LogMemory = struct {
    messages: Pool(Message),
    persistent: Arena,
    frame: *Arena,
    mirror_to_stdio: bool = false,
    file: ?std.fs.File = null,

    pub fn init(frame: *Arena, persistent: Arena, messages: Pool, file: ?[]const u8, mirror_to_stdio: bool) !LogMemory {
        var logmem = LogMemory{
            .messages = messages,
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

    pub fn append(memory: *LogMemory, comptime group: Group, comptime severity: Severity, comptime fmt: []const u8, args: anytype) void {
        const str = arena_print(&memory.persistent, fmt, args);
        const message = memory.messages.alloc();
        message.* = .{
            .group = group,
            .severity = severity,
            .message = str,
        };

        if (memory.mirror_to_stdio) {
            const head = arena_print(memory.frame, "[{s}][{s}]: ", .{ @tagName(group), @tagName(severity) });
            var stdout = std.fs.File.stdout();
            var buffer: [1024]u8 = undefined; // TODO(anjo): move somewhere
            var stdout_writer = stdout.writer(&buffer);
            const writer = &stdout_writer.interface;
            _ = writer.writeAll(head) catch return;
            _ = writer.writeAll(str) catch return;
            _ = writer.writeAll("\n") catch return;
            writer.flush() catch return;
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
