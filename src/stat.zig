const std = @import("std");
const bb = @import("bytebuffer.zig");

const StatResult = struct {
    avg: u64,
    std: u64,
};

const StatData = struct {
    samples: bb.CircularBuffer(u64, 256) = .{},
    start_time: std.time.Instant = undefined,

    const Self = @This();

    pub fn startTime(self: *Self) *Self {
        self.start_time = std.time.Instant.now() catch unreachable;
        return self;
    }

    pub fn endTime(self: *Self) void {
        const end_time = std.time.Instant.now() catch unreachable;
        self.samples.push(end_time.since(self.start_time));
    }

    pub fn mean_std(self: *Self) StatResult {
        var avg: u64 = 0;
        for (self.samples.data) |s| {
            avg += s;
        }
        avg /= self.samples.data.len;

        var variance: u64 = 0;
        for (self.samples.data) |s| {
            const d = @as(i64, @intCast(s)) - @as(i64, @intCast(avg));
            variance += @intCast(d*d);
        }
        variance /= self.samples.data.len-1;

        const std_float = std.math.sqrt(@as(f64, @floatFromInt(variance)));

        return StatResult {
            .avg = avg,
            .std = @intFromFloat(std_float),
        };
    }
};

pub fn AllStatData(comptime T: type) type {
    return struct {
        stat_data: [@typeInfo(T).Enum.fields.len]StatData = undefined,

        comptime enum_type: type = T,

        pub fn get(self: *@This(), label: T) *StatData {
            return &self.stat_data[@intFromEnum(label)];
        }
    };
}
