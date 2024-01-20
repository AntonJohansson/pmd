const std = @import("std");
const bb = @import("bytebuffer.zig");

pub const Work = struct {
    func: *const fn(*anyopaque)void,
    user_ptr: *anyopaque,
    m: *std.Thread.Mutex = undefined,
    c: *std.Thread.Condition = undefined,
    n: *usize = undefined,
};

pub const Future = struct {
    pub fn wait() void {
    }
};

var should_run = std.atomic.Atomic(bool).init(true);
var should_wait = std.atomic.Atomic(u32).init(0);

var threads: []std.Thread = undefined;

var work_data_mutex = std.Thread.Mutex{};
var work_data: bb.CircularArray(Work, 64) = .{};

var allocator: std.mem.Allocator = undefined;

fn worker() void {
    const id = std.Thread.getCurrentId();
    _ = id;
    //std.log.info("thread {}: start", .{id});
    while (true) {
        //std.log.info("thread {}: sleep", .{id});
        std.Thread.Futex.wait(&should_wait, 0);
        //std.log.info("thread {}: wake", .{id});

        if (!should_run.load(.Acquire))
            break;

        //std.log.info("thread {}: checking for work", .{id});
        work_data_mutex.lock();
        const maybe_work: ?Work = if (work_data.size > 0) work_data.pop() else null;
        work_data_mutex.unlock();

        if (maybe_work) |work| {
            //std.log.info("thread {}: doing work", .{id});
            work.func(work.user_ptr);

            work.m.lock();
            //std.log.info("thread {}: signaling", .{id});
            work.n.* -= 1;
            work.c.signal();
            work.m.unlock();
        } else {
            //std.log.info("thread {}: no work", .{id});
        }
    }
    //std.log.info("thread {}: stop", .{id});
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

pub fn enqueue(work: []Work) void {
    var m = std.Thread.Mutex{};
    var c = std.Thread.Condition{};
    var n: usize = work.len;

    work_data_mutex.lock();
    for (work) |*w| {
        w.m = &m;
        w.c = &c;
        w.n = &n;
        work_data.push().* = w.*;
    }
    work_data_mutex.unlock();

    const wake_count = @min(threads.len, work.len);
    std.Thread.Futex.wake(&should_wait, @intCast(wake_count));

    m.lock();
    defer m.unlock();
    while (n > 0) {
        c.wait(&m);
        //std.log.info("finished", .{});
    }

    //std.log.info("All work done", .{});
}

pub fn sync() void {
}
