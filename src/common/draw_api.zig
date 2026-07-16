const std = @import("std");

const bb = @import("bytebuffer.zig");
const meta = @import("draw_meta.zig");
const primitive = @import("primitive.zig");
const Color = primitive.Color;

pub const CommandBuffer = struct {
    bytes: bb.ByteBuffer(128 * 8192) = .{},
    mutex: std.Thread.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator) CommandBuffer {
        return .{
            .bytes = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn push(b: *CommandBuffer, p: anytype, color: Color) void {
        b.mutex.lock();
        defer b.mutex.unlock();

        b.bytes.push(Header{
            .kind = meta.mapPrimitiveToKind(@TypeOf(p)),
            .color = color,
        });
        b.bytes.push(p);
    }

    pub fn pop(b: *CommandBuffer, comptime T: type) T {
        b.mutex.lock();
        defer b.mutex.unlock();

        return b.bytes.pop(T);
    }
};

pub const Header = struct {
    kind: meta.PrimitiveKind,
    color: Color,
};
