const std = @import("std");
const Arena = @import("arena.zig").Arena;
const ArrayCircular = @import("array-circular.zig").ArrayCircular;
const ArenaIntrusiveList = @import("arena-intrusive-list.zig").ArenaIntrusiveList;
const Mutex = @import("mutex.zig");

const logdir = "log";

var mutex_stdout = Mutex{};

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

pub const MessageHeader = struct {
    group: Group,
    severity: Severity,
};

const LogFn = fn ([*]const u8, usize) callconv(.c) void;

pub const LogMemory = struct {
    message_memory: ArenaIntrusiveList,
    persistent: *Arena,
    frame: *Arena,
    mirror_to_stdio: bool = false,
    stdout: *const LogFn,

    pub fn init(stdout: *const LogFn, frame: *Arena, persistent: *Arena, mirror_to_stdio: bool) !LogMemory {
        const log_memory = LogMemory{
            .message_memory = .{
                .arena = persistent,
            },
            .mirror_to_stdio = mirror_to_stdio,
            .persistent = persistent,
            .frame = frame,
            .stdout = stdout,
        };
        return log_memory;
    }

    pub fn append(log_memory: *LogMemory, comptime group: Group, comptime severity: Severity, comptime fmt: []const u8, args: anytype) void {
        const str = log_memory.frame.print(fmt, args);
        const size = str.len + @sizeOf(MessageHeader);
        if (!log_memory.message_memory.has_space(size)) {
            log_memory.message_memory.reset();
        }
        const mem = log_memory.message_memory.alloc(size);
        @as(*align(1) MessageHeader, @ptrCast(mem.ptr)).* = .{
            .group = group,
            .severity = severity,
        };
        @memcpy(mem[@sizeOf(MessageHeader)..], str);

        if (log_memory.mirror_to_stdio) {
            const msg = log_memory.frame.print("[{s}][{s}]: {s}\n", .{ @tagName(group), @tagName(severity), str});
            log_memory.stdout(msg.ptr, msg.len);
        }
    }

    pub fn group_log(log_memory: *LogMemory, comptime group: Group) GroupLog(group) {
        return .{
            .log_memory = log_memory,
        };
    }
};

pub fn GroupLog(comptime group: Group) type {
    return struct {
        log_memory: *LogMemory = undefined,

        pub fn info(self: *@This(), comptime fmt: []const u8, args: anytype) void {
            self.log_memory.append(group, .info, fmt, args);
        }

        pub fn warn(self: *@This(), comptime fmt: []const u8, args: anytype) void {
            self.log_memory.append(group, .warn, fmt, args);
        }

        pub fn err(self: *@This(), comptime fmt: []const u8, args: anytype) void {
            self.log_memory.append(group, .err, fmt, args);
        }
    };
}
