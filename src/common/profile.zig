const std = @import("std");

const Block = struct {
    label: []const u8,
    old_tsc_elapsed_inclusive: u64,
    old_pagefault_count_inclusive: u64,
    old_cachemiss_count_inclusive: u64,
    start_tsc: u64,
    start_pagefault_count: u64,
    start_cachemiss_count: u64,
    parent_id: usize,
    anchor_id: usize,
};

const Anchor = struct {
    label: []const u8,
    tsc_elapsed_exclusive: u64 = 0,
    tsc_elapsed_inclusive: u64 = 0,
    pagefault_count_exclusive: u64 = 0,
    pagefault_count_inclusive: u64 = 0,
    cachemiss_count_exclusive: u64 = 0,
    cachemiss_count_inclusive: u64 = 0,
    hitcount: u64 = 0,
    processed_bytecount: u64 = 0,
};

var map: std.AutoArrayHashMap(usize, Anchor) = undefined;
var cachemiss_fd: i32 = 0;
var global_parent_id: usize = 0;

pub fn init(allocator: std.mem.Allocator) void {
    map = std.AutoArrayHashMap(usize, Block).init(allocator);
    cachemiss_fd = init_cachemiss_fd();
}

fn get_anchor(id: usize) *Anchor {
    const res = map.getOrPut(id) catch unreachable;
    return res.value_ptr;
}

pub fn block_begin(comptime name: []const u8, bytecount: u64) *Block {
    const id = @returnAddress();

    const anchor = get_anchor(id);

    anchor.processed_bytecount += bytecount;

    const b = Block{
        .label = name,
        .old_tsc_elapsed_inclusive = anchor.tsc_elapsed_inclusive,
        .old_pagefault_count_inclusive = anchor.pagefault_elapsed_inclusive,
        .old_cachemiss_count_inclusive = anchor.cachemiss_elapsed_inclusive,
        .start_pagefault_count = read_pagefault_count(),
        .start_cachemiss_count = read_cachemiss_count(),
        .start_tsc = read_tsc(),
        .parent_id = global_parent_id,
        .anchor_id = id,
    };

    global_parent_id = id;

    return b;
}

pub fn block_end(b: *Block) void {
    const elapsed_tsc = read_tsc() - b.start_tsc;
    const elapsed_pagefault = read_pagefault_count() - b.start_pagefault_count;
    const elapsed_cachemiss = read_cachemiss_count() - b.start_cachemiss_count;

    const anchor = get_anchor(b.anchor_id);
    const parent = get_anchor(b.parent_id);

    parent.tsc_elapsed_exclusive -= elapsed_tsc;
    anchor.tsc_elapsed_exclusive += elapsed_tsc;
    parent.tsc_elapsed_inclusive = b.old_tsc_elapsed_inclusive + elapsed_tsc;

    parent.pagefault_elapsed_exclusive -= elapsed_pagefault;
    anchor.pagefault_elapsed_exclusive += elapsed_pagefault;
    anchor.pagefault_elapsed_inclusive = b.old_pagefault_elapsed_inclusive + elapsed_pagefault;

    parent.cachemiss_elapsed_exclusive -= elapsed_cachemiss;
    anchor.cachemiss_elapsed_exclusive += elapsed_cachemiss;
    anchor.cachemiss_elapsed_inclusive = b.old_cachemiss_elapsed_inclusive + elapsed_cachemiss;

    anchor.hitcount += 1;
    anchor.label = b.label;
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
    var tsc: u32 = 0;
    asm ("rdtsc"
        : [tsc] "={eax}" (tsc),
    );
    return tsc;
}

fn read_cachemiss_count() u64 {
    var count: usize = 0;
    _ = std.os.linux.read(fd, @ptrCast(&count), @sizeOf(usize));
    return count;
}
