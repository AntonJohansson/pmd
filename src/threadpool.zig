const std = @import("std");
const bb = @import("bytebuffer.zig");

pub const Work = struct {
    func: *const fn(*anyopaque)void,
    i: *anyopaque,
};

var should_run = std.atomic.Atomic(bool).init(true);
var should_wait = std.atomic.Atomic(u32).init(0);

var threads: []std.Thread = undefined;

var work_data_mutex = std.Thread.Mutex{};
var work_data: bb.CircularArray(Work, 64) = .{};

var allocator: std.mem.Allocator = undefined;

fn worker() void {
    std.log.info("thread start", .{});
    while (true) {
        std.Thread.Futex.wait(&should_wait, 0);

        if (!should_run.load(.Acquire))
            break;

        work_data_mutex.lock();
        const maybe_work: ?Work = if (work_data.size > 0) work_data.pop() else null;
        work_data_mutex.unlock();

        if (maybe_work) |work| {
            work.func(work.i);
        }
    }
    std.log.info("thread stop", .{});
}

pub fn start(alloc: std.mem.Allocator) !void {
    allocator = alloc;

    threads = try allocator.alloc(std.Thread, try std.Thread.getCpuCount());
    for (threads) |*t| {
        t.* = try std.Thread.spawn(.{}, worker, .{});
    }
}

pub fn join() void {
    should_run.store(false, .Release);
    std.Thread.Futex.wake(&should_wait, @intCast(threads.len));

    for (threads) |*t| {
        t.join();
    }

    allocator.free(threads);
}

pub fn enqueue(work: []const Work) void {
    work_data_mutex.lock();
    for (work) |w| {
        work_data.push(w);
    }
    work_data_mutex.unlock();

    const wake_count = std.math.min(threads.len, work.len);
    std.Thread.Futex.wake(&should_wait, @intCast(wake_count));
}
