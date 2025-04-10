const std = @import("std");
const bb = @import("bytebuffer.zig");
const BoundedArray = @import("common.zig").BoundedArray;

fn rdtsc() u32 {
    return asm volatile ("rdtsc "
        : [out] "={eax}" (-> u32),
    );
}

pub const StatData = struct {
    enabled: bool = true,
    entries: BoundedArray(StatEntry, 128) = .{},
    ids_being_tracked: BoundedArray(u16, 128) = .{},

    const Self = @This();

    pub fn start(self: *Self, name: []const u8) void {
        if (!self.enabled)
            return;
        const id = self.findId(name) orelse blk: {
            _ = self.entries.addOneAssumeCapacity();
            const new_id = self.entries.len - 1;
            if (self.ids_being_tracked.len > 0) {
                const parent_id = self.ids_being_tracked.get(self.ids_being_tracked.len - 1);
                var parent = &self.entries.slice()[parent_id];
                parent.children.appendAssumeCapacity(new_id);
            }
            break :blk new_id;
        };

        var stat = &self.entries.slice()[id];
        stat.name = name;

        if (self.ids_being_tracked.len == 0) {
            stat.is_root = true;
        }

        _ = stat.startTime();
        self.ids_being_tracked.appendAssumeCapacity(id);
    }

    pub fn end(self: *Self) void {
        if (!self.enabled)
            return;
        std.debug.assert(self.ids_being_tracked.len != 0);
        const id = self.ids_being_tracked.pop();
        var stat = &self.entries.slice()[id];
        _ = stat.endTime();
    }

    pub fn findId(self: *Self, name: []const u8) ?u16 {
        for (self.entries.constSlice(), 0..self.entries.len) |stat, i| {
            if (std.mem.eql(u8, stat.name, name))
                return @intCast(i);
        }
        return null;
    }
};

const StatResult = struct {
    avg: u64,
    std: u64,
    min: u64,
    max: u64,
};

pub const StatEntry = struct {
    name: []const u8 = undefined,
    samples: bb.CircularBuffer(u64, 256) = .{},
    start_time: std.time.Instant = undefined,
    is_root: bool = false,

    children: BoundedArray(u16, 16) = .{},

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

        var min: u64 = std.math.maxInt(u64);
        var max: u64 = std.math.minInt(u64);
        for (self.samples.data) |s| {
            const d = @as(i64, @intCast(s)) - @as(i64, @intCast(avg));
            const mul = @mulWithOverflow(d, d);
            // Skip on overflow
            if (mul[1] == 1)
                continue;
            variance = @addWithOverflow(variance, @as(@TypeOf(variance), @intCast(mul[0])))[0];

            if (s < min)
                min = s;
            if (s > max)
                max = s;
        }
        variance /= self.samples.data.len - 1;

        const std_float = std.math.sqrt(@as(f64, @floatFromInt(variance)));

        return StatResult{
            .avg = avg,
            .std = @intFromFloat(std_float),
            .min = min,
            .max = max,
        };
    }
};
