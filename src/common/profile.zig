const std = @import("std");

const Self = @This();

pub const FrameBlock = struct {
    start_tsc: u64,
    start_pagefault_count: u64,
    start_cachemiss_count: u64,
    elapsed_tsc: u64 = 0,
    elapsed_pagefault_count: u64 = 0,
    elapsed_cachemiss_count: u64 = 0,
};

pub const Block = struct {
    label: []const u8,
    old_tsc_elapsed_inclusive: u64,
    old_pagefault_elapsed_inclusive: u64,
    old_cachemiss_elapsed_inclusive: u64,
    start_tsc: u64,
    start_pagefault_count: u64,
    start_cachemiss_count: u64,
    parent_id: usize,
    anchor_id: usize,
    thread_index: u8,
};

const Anchor = struct {
    label: []const u8 = undefined,
    tsc_elapsed_exclusive: i64 = 0,
    tsc_elapsed_inclusive: u64 = 0,
    tsc_last_elapsed_inclusive: i64 = 0,
    pagefault_elapsed_exclusive: i64 = 0,
    pagefault_elapsed_inclusive: u64 = 0,
    pagefault_last_elapsed_inclusive: u64 = 0,
    cachemiss_elapsed_exclusive: i64 = 0,
    cachemiss_elapsed_inclusive: u64 = 0,
    cachemiss_last_elapsed_inclusive: u64 = 0,
    hitcount: u64 = 0,
    processed_bytecount: u64 = 0,
    tsc_delta_from_root: u64 = 0,
    parent_id: usize = 0,
    active_last_frame: bool = false,
};

pub const TotalElapsed = struct {
    tsc_elapsed: u64 = 0,
    pagefault_elapsed: u64 = 0,
    cachemiss_elapsed: u64 = 0,
};

pub const AnchorMap = struct {
    const max_num_anchors = 128;

    // Runtime values
    // Assumptions on storage of Anchors:
    //   * Create once
    //   * Read/modify multiple times
    //   * return address will be used as a hash identifying a given Anchor, they
    //     are unique for each call to begin()
    //   * Anchors written/modified by one thread will no be accessed by other
    //     threads. Only exception is the printing of profiling data at the end
    //     of the frame, which occurs from the main thread. As such, data printed
    //     on other thread might be missing entries.
    //
    //  For the above reasons we should get away with a single unordered atomic
    //  addition for protection.
    ids: [max_num_anchors]usize = undefined,
    anchors: [max_num_anchors]Anchor = undefined,
    global_parent_id: usize = 0,
    index_current: u8 = 0,

    pub fn anchor_values(self: *AnchorMap) []Anchor {
        return self.anchors[0..self.index_current];
    }

    pub fn id_values(self: *AnchorMap) []usize {
        return self.ids[0..self.index_current];
    }

    pub fn get_index(self: *AnchorMap, id: usize) ?usize {
        for (self.id_values(), 0..) |_id, i| {
            if (_id == id) {
                return i;
            }
        }
        return null;
    }

    pub fn get_or_put_index(self: *AnchorMap, id: usize) usize {
        return self.get_index(id) orelse blk: {
            const i = self.index_current;
            self.ids[i] = id;
            self.anchors[i] = .{};
            self.index_current += 1;
            break :blk i;
        };
    }

    fn get_anchor(self: *AnchorMap, id: usize) *Anchor {
        return &self.anchors[self.get_or_put_index(id)];
    }
};

var allocator: std.mem.Allocator = undefined;

used_thread_indices: std.atomic.Value(u8) = undefined,
thread_indices: []usize = undefined,
anchor_maps: []AnchorMap = undefined,

// Values set during init
start_tsc: u64 = 0,
start_cachemiss: u64 = 0,
start_pagefault: u64 = 0,
timer_freq: u64 = 0,

cachemiss_fd: i32 = 0,

// Frame values
block_current_frame: FrameBlock = undefined,
block_last_frame: FrameBlock = undefined,

// Should be called from the main thread, not thread safe
pub fn begin_frame(self: *Self) void {
    self.block_last_frame = self.block_current_frame;
    self.block_current_frame = .{
        .start_tsc = read_tsc(),
        .start_pagefault_count = read_pagefault_count(),
        .start_cachemiss_count = self.read_cachemiss_count(),
    };
    for (self.anchor_maps_slice()) |*map| {
        for (map.anchor_values()) |*a| {
            a.active_last_frame = false;
        }
    }
}

// Should be called from the main thread, not thread safe
pub fn end_frame(self: *Self) void {
    self.block_current_frame.elapsed_tsc = read_tsc() - self.block_current_frame.start_tsc;
    self.block_current_frame.elapsed_pagefault_count = read_pagefault_count() - self.block_current_frame.start_pagefault_count;
    self.block_current_frame.elapsed_cachemiss_count = self.read_cachemiss_count() - self.block_current_frame.start_cachemiss_count;
}

pub fn begin(self: *Self, comptime name: []const u8, bytecount: u64) Block {
    const id = @intFromPtr(name.ptr);

    const thread_index = self.get_or_put_thread_index(std.Thread.getCurrentId());
    var map = &self.anchor_maps[thread_index];
    const anchor = map.get_anchor(id);

    const start_tsc = read_tsc();

    anchor.processed_bytecount += bytecount;
    anchor.tsc_delta_from_root = start_tsc - self.block_current_frame.start_tsc;
    anchor.active_last_frame = true;

    const b = Block{
        .label = name,
        .old_tsc_elapsed_inclusive = anchor.tsc_elapsed_inclusive,
        .old_pagefault_elapsed_inclusive = anchor.pagefault_elapsed_inclusive,
        .old_cachemiss_elapsed_inclusive = anchor.cachemiss_elapsed_inclusive,
        .start_pagefault_count = read_pagefault_count(),
        .start_cachemiss_count = self.read_cachemiss_count(),
        .start_tsc = start_tsc,
        .parent_id = map.global_parent_id,
        .anchor_id = id,
        .thread_index = thread_index,
    };

    map.global_parent_id = id;

    return b;
}

pub fn end(self: *Self, b: Block) void {
    const elapsed_tsc = read_tsc() - b.start_tsc;
    const elapsed_pagefault = read_pagefault_count() - b.start_pagefault_count;
    const elapsed_cachemiss = self.read_cachemiss_count() - b.start_cachemiss_count;

    var map = &self.anchor_maps[b.thread_index];
    const anchor = map.get_anchor(b.anchor_id);

    anchor.tsc_elapsed_exclusive += @intCast(elapsed_tsc);
    anchor.tsc_elapsed_inclusive = b.old_tsc_elapsed_inclusive + elapsed_tsc;
    anchor.tsc_last_elapsed_inclusive = @intCast(elapsed_tsc);

    anchor.pagefault_elapsed_exclusive += @intCast(elapsed_pagefault);
    anchor.pagefault_elapsed_inclusive = b.old_pagefault_elapsed_inclusive + elapsed_pagefault;
    anchor.pagefault_last_elapsed_inclusive = @intCast(elapsed_pagefault);

    anchor.cachemiss_elapsed_exclusive += @intCast(elapsed_cachemiss);
    anchor.cachemiss_elapsed_inclusive = b.old_cachemiss_elapsed_inclusive + elapsed_cachemiss;
    anchor.cachemiss_last_elapsed_inclusive = @intCast(elapsed_cachemiss);

    anchor.hitcount += 1;
    anchor.label = b.label;
    anchor.parent_id = b.parent_id;

    if (b.parent_id > 0) {
        const parent = map.get_anchor(b.parent_id);
        parent.tsc_elapsed_exclusive -= @intCast(elapsed_tsc);
        parent.pagefault_elapsed_exclusive -= @intCast(elapsed_pagefault);
        parent.cachemiss_elapsed_exclusive -= @intCast(elapsed_cachemiss);
    }

    map.global_parent_id = b.parent_id;
}

pub fn init(self: *Self, _allocator: std.mem.Allocator) void {
    allocator = _allocator;

    self.used_thread_indices = std.atomic.Value(u8).init(0);
    self.cachemiss_fd = init_cachemiss_fd();
    self.start_tsc = read_tsc();
    self.start_cachemiss = self.read_cachemiss_count();
    self.start_pagefault = read_pagefault_count();
    self.timer_freq = estimate_cpu_timer_freq();

    const thread_count = std.Thread.getCpuCount() catch 1;
    self.thread_indices = allocator.alloc(usize, thread_count) catch unreachable;
    self.anchor_maps = allocator.alloc(AnchorMap, thread_count) catch unreachable;
}

pub fn free_indices(self: *Self) void {
    allocator.free(self.thread_indices);
}

pub fn free_anchors(self: *Self) void {
    allocator.free(self.anchor_maps);
}

pub fn deinit(self: *Self) void {
    _ = std.os.linux.ioctl(self.cachemiss_fd, std.os.linux.PERF.EVENT_IOC.RESET, 0);
    _ = std.os.linux.close(self.cachemiss_fd);
    self.free_indices();
    self.free_anchors();
}

pub fn get_thread_index(self: *Self, _id: usize) ?u8 {
    for (self.thread_indices[0..self.used_thread_indices.load(.monotonic)], 0..) |id, i| {
        if (_id == id) {
            return @intCast(i);
        }
    }
    return null;
}

pub fn get_or_put_thread_index(self: *Self, id: usize) u8 {
    return self.get_thread_index(id) orelse blk: {
        const i = self.used_thread_indices.fetchAdd(1, .monotonic);
        self.thread_indices[i] = id;
        self.anchor_maps[i] = .{};
        break :blk i;
    };
}

pub fn get_anchor_map(self: *Self, id: usize) *AnchorMap {
    return &self.anchor_maps[self.get_or_put_thread_index(id)];
}

pub fn anchor_maps_slice(self: *Self) []AnchorMap {
    return self.anchor_maps[0..self.used_thread_indices.load(.monotonic)];
}

pub fn total_elapsed(self: *Self) TotalElapsed {
    return .{
        .tsc_elapsed = read_tsc() - self.start_tsc,
        .pagefault_elapsed = read_pagefault_count() - self.start_pagefault,
        .cachemiss_elapsed = self.read_cachemiss_count(),// - self.start_cachemiss,
    };
}

pub fn print(self: *Self) void {
    const total = self.total_elapsed();
    print_anchors(self, total.tsc_elapsed, total.pagefault_elapsed, total.cachemiss_elapsed);
}

pub fn duplicate(self: *Self) !*Self {
    const dup: *Self = @ptrCast((try allocator.alloc(Self, 1)).ptr);
    dup.* = self.*;
    // NOTE: We don't need to copy thread_indices, as these don't change across
    // frames, and the array only grows monotonically :)
    dup.anchor_maps = try allocator.alloc(AnchorMap, self.anchor_maps.len);
    for (self.anchor_maps_slice(), 0..) |map, i| {
        dup.anchor_maps[i] = map;
    }
    return dup;
}

fn print_anchors(self: *Self, tsc_elapsed: u64, pagefault_elapsed: u64, cachemiss_elapsed: u64) void {
    std.log.info("{s:16} {s:10} {s:16} {s:5} {s:10} {s:6} {s:5} {s:10} {s:9} {s:5} {s:10} {s:10} {s:10}\n",
                 .{"name", "samples", "tsc", "%", "% w/chld", "faults", "%", "% w/chld", "l1 misses", "%", "% w/chld", "mib", "gib/s"});
    for (self.anchor_maps_slice()) |*map| {
        for (map.anchor_values()) |*a| {
            if (a.tsc_elapsed_inclusive > 0) {
                print_elapsed_time(self.timer_freq, tsc_elapsed, pagefault_elapsed, cachemiss_elapsed, a);
            }
        }
    }
}

fn print_elapsed_time(timer_freq: u64, tsc_elapsed: u64, pagefault_elapsed: u64, cachemiss_elapsed: u64, anchor: *const Anchor) void {
    const float_tsc_elapsed: f32 = @floatFromInt(tsc_elapsed);
    const float_pagefault_elapsed: f32 = @floatFromInt(pagefault_elapsed);
    const float_cachemiss_elapsed: f32 = @floatFromInt(cachemiss_elapsed);

    const tsc_percent = 100.0 * @as(f32, @floatFromInt(anchor.tsc_elapsed_exclusive)) / float_tsc_elapsed;
    var tsc_percent_w_child: f32 = 0.0;
    if (anchor.tsc_elapsed_inclusive != anchor.tsc_elapsed_exclusive) {
        tsc_percent_w_child = 100.0 * @as(f32, @floatFromInt(anchor.tsc_elapsed_inclusive)) / float_tsc_elapsed;
    }

    const pagefault_percent = 100.0 * @as(f32, @floatFromInt(anchor.pagefault_elapsed_exclusive)) / float_pagefault_elapsed;
    var pagefault_percent_w_child: f32 = 0;
    if (anchor.pagefault_elapsed_inclusive != anchor.pagefault_elapsed_exclusive) {
        pagefault_percent_w_child = 100.0 * @as(f32, @floatFromInt(anchor.pagefault_elapsed_inclusive)) / float_pagefault_elapsed;
    }

    const cachemiss_percent = 100.0 * @as(f32, @floatFromInt(anchor.cachemiss_elapsed_exclusive)) / float_cachemiss_elapsed;
    var cachemiss_percent_w_child: f32 = 0;
    if (anchor.cachemiss_elapsed_inclusive != anchor.cachemiss_elapsed_exclusive) {
        cachemiss_percent_w_child = 100.0 * @as(f32, @floatFromInt(anchor.cachemiss_elapsed_inclusive)) / float_pagefault_elapsed;
    }

    var bytecount_mib: f32 = 0;
    var bytecount_gibps: f32 = 0;
    if (anchor.processed_bytecount > 0) {
        const mib = 1024.0*1024.0;
        const gib = mib*1024.0;

        const float_bytecount: f32 = @floatFromInt(anchor.processed_bytecount);
        const seconds = @as(f32, @floatFromInt(anchor.tsc_elapsed_inclusive)) / @as(f32, @floatFromInt(timer_freq));
        const bytes_per_sec = float_bytecount / seconds;
        bytecount_mib = float_bytecount / mib;
        bytecount_gibps = bytes_per_sec / gib;
    }

    std.log.info("{s:16} {:10} {:16} {d:5.2} {d:10.2} {:6} {d:5.2} {d:10.2} {:9} {d:5.2} {d:10.2} {d:10.2} {d:10.2}",
    .{
        anchor.label,
        anchor.hitcount,
        anchor.tsc_elapsed_exclusive,
        tsc_percent,
        tsc_percent_w_child,
        anchor.pagefault_elapsed_exclusive,
        pagefault_percent,
        pagefault_percent_w_child,
        anchor.cachemiss_elapsed_exclusive,
        cachemiss_percent,
        cachemiss_percent_w_child,
        bytecount_mib,
        bytecount_gibps,
    });
}


fn read_pagefault_count() u64 {
    var usage: std.os.linux.rusage = undefined;
    _ = std.os.linux.getrusage(std.os.linux.rusage.SELF, &usage);
    return @intCast(usage.minflt + usage.majflt);
}

fn init_cachemiss_fd() i32 {
    var attr = std.os.linux.perf_event_attr{
        .type = std.os.linux.PERF.TYPE.HW_CACHE,
        .size = @sizeOf(std.os.linux.perf_event_attr),
        .config = @intFromEnum(std.os.linux.PERF.COUNT.HW.CACHE.L1D) |
            (@intFromEnum(std.os.linux.PERF.COUNT.HW.CACHE.OP.READ) << 8) |
            (@intFromEnum(std.os.linux.PERF.COUNT.HW.CACHE.RESULT.MISS) << 16),
        .flags = .{
            .disabled = true,
            .exclude_kernel = true,
            .exclude_hv = true,
        },
    };
    const fd = std.posix.perf_event_open(&attr, 0, -1, -1, 0) catch unreachable;
    std.debug.assert(fd != -1);

    _ = std.os.linux.ioctl(fd, std.os.linux.PERF.EVENT_IOC.RESET, 0);
    _ = std.os.linux.ioctl(fd, std.os.linux.PERF.EVENT_IOC.ENABLE, 0);

    return fd;
}

fn read_tsc() u64 {
    var tsc_lo: u32 = 0;
    var tsc_hi: u32 = 0;
    asm ("rdtscp"
        : [tsc_lo] "={eax}" (tsc_lo),
          [tsc_hi] "={edx}" (tsc_hi),
    );
    const tsc_wide_lo: u64 = @intCast(tsc_lo);
    const tsc_wide_hi: u64 = @intCast(tsc_hi);
    return (tsc_wide_hi << 32) | tsc_wide_lo;
}

fn read_os_timer_ns() std.time.Instant {
    return std.time.Instant.now() catch unreachable;
}

fn read_cachemiss_count(self: *Self) u64 {
    var count: usize = 0;
    _ = std.os.linux.read(self.cachemiss_fd, @ptrCast(&count), @sizeOf(usize));
    return count;
}

fn estimate_cpu_timer_freq() u64 {
    const ms_to_wait = 100;
    const os_freq = 1000000000;

    const cpu_start = read_tsc();
    const os_start = read_os_timer_ns();
    const os_wait_time = os_freq * ms_to_wait / 1000;
    var os_end: std.time.Instant = undefined;
    var os_elapsed: u64 = 0;
    while (os_elapsed < os_wait_time) {
        os_end = read_os_timer_ns();
        os_elapsed = os_end.since(os_start);
    }

    const cpu_end = read_tsc();
    const cpu_elapsed = cpu_end - cpu_start;

    var cpu_freq: u64 = 0;
    if (os_elapsed > 0) {
        cpu_freq = os_freq * cpu_elapsed / os_elapsed;
    }

    return cpu_freq;
}
