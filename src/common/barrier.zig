const std = @import("std");
const Futex = @import("futex.zig");
const atomic = std.atomic;

pub var num_threads: u32 = 0;
pub var count: atomic.Value(u32) = undefined;
var futex: atomic.Value(u32) = undefined;

pub fn init(n: u32) void {
    num_threads = n;
    count = atomic.Value(u32).init(num_threads);
    futex = atomic.Value(u32).init(0);
}

pub fn wait() void {
    while (futex.load(.acquire) == 1) {
        Futex.wait(&futex, 1);
    }
    // last thread to wait will wake up all others
    if (count.fetchSub(1, .acq_rel) == 1) {
        // reset barrier
        _ = count.fetchAdd(1, .acq_rel);

        futex.store(1, .release);
        Futex.wake(&futex, num_threads-1);

        // spinlock until everyone is awake
        while (count.load(.acquire) != num_threads) {
        }

        futex.store(0, .release);
        Futex.wake(&futex, num_threads-1);

        return;
    }

    while (futex.load(.acquire) == 0) {
        Futex.wait(&futex, 0);
    }
    _ = count.fetchAdd(1, .acq_rel);
}
