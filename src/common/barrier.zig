const std = @import("std");
const Futex = std.Thread.Futex;
const atomic = std.atomic;

num_threads: u32 = 0,
count: atomic.Value(u32) = undefined,
futex: atomic.Value(u32) = undefined,

pub fn init(b: *@This(), n: u32) void {
    b.num_threads = n;
    b.count = atomic.Value(u32).init(b.num_threads);
    b.futex = atomic.Value(u32).init(0);
}

pub fn wait(b: *@This()) void {
    while (b.futex.load(.acquire) == 1) {
        Futex.wait(&b.futex, 1);
    }
    // last thread to wait will wake up all others
    if (b.count.fetchSub(1, .acq_rel) == 1) {
        // reset barrier
        _ = b.count.fetchAdd(1, .acq_rel);

        b.futex.store(1, .release);
        Futex.wake(&b.futex, b.num_threads-1);

        // spinlock until everyone is awake
        while (b.count.load(.acquire) != b.num_threads) {
        }

        b.futex.store(0, .release);
        Futex.wake(&b.futex, b.num_threads-1);

        return;
    }

    while (b.futex.load(.acquire) == 0) {
        Futex.wait(&b.futex, 0);
    }
    _ = b.count.fetchAdd(1, .acq_rel);
}
