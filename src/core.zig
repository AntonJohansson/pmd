const std = @import("std");
const gs = @import("common");
const build_options = @import("build_options");
const disk = if (build_options.options.debug) @import("pack-disk") else struct {};
const net = @import("net");

const assert = std.debug.assert;

var futex_await_main = std.atomic.Value(u32).init(0);

//
// Globals
//

const ThreadLoopFn = fn (m: *const Module, std.Io) void;

var system = gs.SystemState{};
var global_memory = gs.Memory{};
var thread_loop_fn: *const ThreadLoopFn = undefined;
pub var module: Module = undefined;

var arena_pack_frame: gs.Arena = undefined;
var arena_pack_state: gs.Arena = undefined;

//
// Module
//

pub const Module = gs.code_module.CodeModule(struct {
    init: *fn (ss: *const gs.SystemState, thread: *gs.ThreadState, memory: *gs.Memory) callconv(.c) bool,
    deinit: *fn (thread: *gs.ThreadState, memory: *gs.Memory) callconv(.c) void,
    thread_rescale_main: *fn () callconv(.c) void,
    update: *fn (thread: *gs.ThreadState, vars: *const gs.config.Vars, memory: *gs.Memory, player: *gs.Player, input: *const gs.Input, dt: f32) callconv(.c) void,
    authorizedPlayerUpdate: *fn (thread: *gs.ThreadState, vars: *const gs.config.Vars, memory: *gs.Memory, player: *gs.Player, input: *const gs.Input, dt: f32) callconv(.c) void,
    authorizedUpdate: *fn (thread: *gs.ThreadState, vars: *const gs.config.Vars, memory: *gs.Memory, dt: f32) callconv(.c) void,
    client_update: *fn (thread: *gs.ThreadState, vars: *const gs.config.Vars, memory: *gs.Memory, dt: f32) callconv(.c) void,
    server_update: *fn (vars: *const gs.config.Vars, memory: *gs.Memory, dt: f32) callconv(.c) void,
    draw: *fn (thread: *gs.ThreadState, vars: *const gs.config.Vars, memory: *gs.Memory, b: *gs.draw_api.CommandBuffer, player_id: gs.EntityId, input: *const gs.Input) callconv(.c) void,
});

//
// Exposed functions
//

pub fn init(args: std.process.Args.Vector, io: std.Io, f: *const ThreadLoopFn) void {
    // save thread function so we can spawn more later
    thread_loop_fn = f;

    parse_cmdline(args);

    var arena = gs.Arena{ .memory = page_alloc(1 * MiB) };
    resolve_dirs(&arena);
    // Create log/config directories, the others should be created by the build system
    create_dir(io, system.dirs.log);
    create_dir(io, system.dirs.config);
    const conf = config_load_or_create(io, &arena, "conf.zon") catch |err| {
        std.log.err("Failed loading or creating config: {}", .{err});
        std.process.exit(1);
    };
    std.log.info("config\n{}", .{conf});

    // Setup stdout log function
    stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);

    // Subsystems
    var arena_res = gs.Arena{ .memory = page_alloc(1 * GiB) };
    gs.res.arena = &arena_res;
    defer page_free(arena_res.memory);

    arena_pack_frame = gs.Arena{ .memory = page_alloc(16 * MiB) };
    arena_pack_state = gs.Arena{ .memory = page_alloc(16 * MiB) };
    defer page_free(arena_pack_state.memory);
    var arena_freelist_pack_state = gs.ArenaFreelist{ .arena = &arena_pack_state };
    gs.goosepack.arena_persistent = &arena_freelist_pack_state;

    if (build_options.options.debug) {
        disk.arena_frame = &arena_pack_state;
        disk.arena_persistent = &arena_freelist_pack_state;
    }

    var arena_frame_net = gs.Arena{.memory = page_alloc(1*MiB)};
    defer page_free(arena_frame_net.memory);
    var arena_persistent_state_net = gs.Arena{.memory = page_alloc(1*MiB)};
    defer page_free(arena_persistent_state_net.memory);
    var arena_persistent_net = gs.ArenaFreelist{.arena = &arena_persistent_state_net};
    net.arena_frame = &arena_frame_net;
    net.arena_persistent = &arena_persistent_net;
    net.io = io;

    // Load asset pack
    const pack_in_memory = gs.res.read_file_to_memory(io, "res.gp") catch null;
    global_memory.pack = gs.goosepack.Pack{};
    if (pack_in_memory) |bytes| {
        gs.goosepack.load(&global_memory.pack, bytes) catch {
            std.log.err("Failed loading pack", .{});
            std.process.exit(1);
        };
    }
    global_memory.cache.pack = &global_memory.pack;
    global_memory.cache.eviction_list = .{
        .arena = &arena_pack_frame,
    };
    global_memory.font = gs.goosepack.resource_lookup(&global_memory.pack, "res/fonts/MononokiNerdFontMono-Regular").?.font;

    // Module
    const module_name = "game";
    module = Module.init(&arena_freelist_pack_state, system.dirs.modules, module_name) catch {
        std.log.err("Failed to init module: {} at {}", .{ module_name, system.dirs.modules });
        return;
    };
    module.open(io) catch |err| {
        std.log.err("Failed to open module {}", .{err});
        return;
    };
    defer module.close();

    // Spawn threads
    system.num_threads = 8;
    system.target_fps = 165;
    system.desired_frame_time = std.time.ns_per_s / system.target_fps;
    system.dt = 1.0 / @as(f32, @floatFromInt(system.target_fps));

    thread_spawn_range(io, 0, system.num_threads - 1);
    thread_main(io, 0);
    thread_join_range(0, system.num_threads - 1);
}

pub fn frame_begin(thread: *gs.ThreadState, memory: *gs.Memory, io: std.Io) void {
    if (system.stopped_threads > 0 and thread.is_main()) {
        // If threads were stopped last tick, join them now as they have
        // exited the main loop, and update thread count.
        thread_join_range(system.num_threads - 1 - system.stopped_threads, system.num_threads - 1);
        _ = gs.barrier.count.fetchSub(system.stopped_threads, .acq_rel);
        system.num_threads -= system.stopped_threads;
        gs.barrier.num_threads = system.num_threads;
        module.function_table.thread_rescale_main();
        system.stopped_threads = 0;
    }

    if (memory.tick == 10) {
        if (thread.is_main()) {
            thread_rescale(io, 4);
        }
    }
    if (memory.tick == 20) {
        if (thread.is_main()) {
            thread_rescale(io, 12);
        }
    }

    gs.barrier.wait();

    thread.profile.begin_frame();

    if (thread.is_main()) {
        system.frame_start_time = std.Io.Timestamp.now(io, .real);
        const reloaded = module.reload_if_changed(io) catch false;
        if (reloaded) {
            //_ = module.function_table.fofo();
        }
    }
}

pub fn frame_end(thread: *gs.ThreadState, memory: *gs.Memory, io: std.Io) void {
    // Debug profiling and data collection
    {
        thread.profile.end_frame();
        if (!memory.debug_data_collection_paused) {
            // TODO(anjo): ??
            const next = thread.debug_frame_data.peekRelative(1);
            if (next.used) {
                const s: []gs.Profile = @ptrCast(next.profile);
                thread.arena_persistent.free(s);
            }

            thread.debug_frame_data.push(.{
                .profile = thread.profile.duplicate(&thread.arena_persistent) catch unreachable,
                .used = true,
            });
        }
    }

    if (thread.is_main() and build_options.options.debug) {
        //config.vars.pack_update_check_interval_ns;
        if (memory.tick % 165 == 0) {
            var log = thread.log_memory.group_log(.general);
            const block = thread.profile.begin("pack update", 0);
            thread.profile.end(block);

            const entries = disk.collect_and_update_entries(io, &memory.pack, &thread.arena_frame) catch |err| {
                log.err("Unable to collect changed pack entries: {}", .{err});
                // TODO(anjo):
                return;
            };
            for (entries) |e| {
                std.log.info("- {s}", .{e.name});
            }
            if (entries.len > 0) {
                // builder will be .deinit() from thread which writes to the pack file
                var builder = gs.goosepack.save_to_memory(&memory.pack, &thread.arena_frame);
                const buffer = thread.arena_frame.alloc(u8, builder.get_size());
                builder.dump_to_buffer(buffer);
                memory.pack = .{};
                gs.goosepack.load(&memory.pack, buffer) catch |err| {
                    log.err("Failed to reload pack {}", .{err});
                };
                // Swawn thread which writes to disk
                // TODO(anjo): when threading
                //try memory.threadpool.spawn(write_pack_to_file.run, .{ &builder, "res.gp" });

                // Force recompilation of shaders and etc.
                //draw.resources_update(entries);
            }
        }
    }

    if (thread.is_main()) {
        memory.tick += 1;

        const frame_end_time = std.Io.Timestamp.now(io, .real);
        const frame_time = system.frame_start_time.durationTo(frame_end_time).nanoseconds;

        // Here we shoehorn in some sleeping to not consume all the cpu resources
        {
            const start_sleep = std.Io.Timestamp.now(io, .real);
            const time_left = @as(i64, @intCast(system.desired_frame_time)) - @as(i64, @intCast(frame_time));
            if (time_left > std.time.us_per_s) {
                // if we have at least 1us left, sleep
                std.Io.sleep(io, std.Io.Duration{ .nanoseconds = time_left }, .real) catch {};
            }

            // spin for the remaining time
            while (start_sleep.durationTo(std.Io.Timestamp.now(io, .real)).nanoseconds < time_left) {}
        }
    }

    if (thread.is_main()) {
        gs.cache.free_evictions(&memory.cache);
        arena_pack_frame.top = 0;
    }

    // clear allocator
    thread.arena_frame.top = 0;
}

pub fn thread_await_main(thread: *gs.ThreadState) void {
    if (thread.is_main()) {
        futex_await_main.store(1, .release);
        gs.Futex.wake(&futex_await_main, @intCast(system.num_threads - 1));
    } else {
        while (futex_await_main.load(.acquire) == 0) {
            gs.Futex.wait(&futex_await_main, 0);
        }
    }
}

pub fn thread_exit_all() void {
    for (&system.thread_states) |*ts| {
        ts.should_run.store(false, .release);
    }
}

//
// Commandline arguments
//

fn parse_cmdline(args: std.process.Args.Vector) void {
    system.dirs.run = std.fs.path.dirname(std.mem.span(args[0])) orelse {
        std.log.err("Failed getting runtime path", .{});
        return;
    };
}

//
// Config files
//

fn resolve_dirs(arena: *gs.Arena) void {
    system.dirs.log = gs.path_concat(arena, &[_][]const u8{ system.dirs.run, "log" });
    system.dirs.config = gs.path_concat(arena, &[_][]const u8{ system.dirs.run, "config" });
    system.dirs.data = gs.path_concat(arena, &[_][]const u8{ system.dirs.run, "data" });
    system.dirs.modules = gs.path_concat(arena, &[_][]const u8{ system.dirs.run, "modules" });
}

fn create_dir(io: std.Io, dir: []const u8) void {
    std.Io.Dir.cwd().createDir(io, dir, .default_dir) catch |dir_err| switch (dir_err) {
        error.PathAlreadyExists => {},
        else => {
            std.log.err("Failed creating directory {s}: {}", .{ dir, dir_err });
            std.process.exit(1);
        },
    };
}

fn config_load_or_create(io: std.Io, arena: *gs.Arena, filename: []const u8) !gs.ConfigSystem {
    const allocator = arena_allocator(arena);

    var buffer: [1024]u8 = undefined;
    const dir = try std.Io.Dir.cwd().openDir(io, system.dirs.config, .{});
    const stat = dir.statFile(io, filename, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            const num_cpus = std.Thread.getCpuCount() catch 1;
            const conf = gs.ConfigSystem{
                .num_threads = @intCast(num_cpus),
            };
            const file = try dir.createFile(io, filename, .{});
            var file_writer = file.writer(io, &buffer);
            const writer = &file_writer.interface;
            try std.zon.stringify.serialize(conf, .{}, writer);
            try writer.flush();
            return conf;
        },
        else => return err,
    };

    const size = stat.size + 1;
    const source = try allocator.alloc(u8, size);
    source[size - 1] = 0;

    const file = try dir.openFile(io, filename, .{});
    var file_reader = file.reader(io, &buffer);
    const reader = &file_reader.interface;
    try reader.readSliceAll(source[0 .. size - 1]);
    const input = source[0 .. size - 1 :0];

    return try std.zon.parse.fromSlice(gs.ConfigSystem, allocator, input, null, .{});
}

//
// Memory
//

const KiB = 1024;
const MiB = 1024 * KiB;
const GiB = 1024 * MiB;
const page_size = std.heap.page_size_min;

fn page_alloc(size: usize) []u8 {
    const aligned_size = page_size * @divTrunc(size + page_size, page_size);
    return std.heap.page_allocator.alignedAlloc(u8, null, aligned_size) catch unreachable;
}

fn page_free(bytes: []const u8) void {
    std.heap.page_allocator.free(bytes);
}

//
// Thread spawning and despawning
//

fn thread_main(io: std.Io, id: u8) void {
    var arena_persisent_state = gs.Arena{ .memory = page_alloc(256 * MiB) };
    var arena_log_persistent = gs.Arena{ .memory = page_alloc(1 * KiB) };
    const arena_frame = gs.Arena{ .memory = page_alloc(256 * MiB) };
    const arena_persistent = gs.ArenaFreelist{ .arena = &arena_persisent_state };
    defer page_free(arena_persisent_state.memory);
    defer page_free(arena_log_persistent.memory);
    defer page_free(arena_frame.memory);

    const thread = &system.thread_states[id];
    thread.* = .{
        .id = @intCast(id),
        .num_threads = @intCast(system.num_threads),
        .arena_frame = arena_frame,
        .arena_persistent = arena_persistent,
    };

    const mirror_to_stdio = true;
    thread.log_memory = gs.log.LogMemory.init(stdout_log, &thread.arena_frame, &arena_log_persistent, mirror_to_stdio) catch {
        return;
    };

    thread.profile.init(io);
    defer thread.profile.deinit();

    gs.thread_init_globals(&system, thread, &global_memory);

    thread_loop_fn(&module, io);
}

fn thread_rescale(io: std.Io, new_threads: u8) void {
    assert(new_threads < gs.max_num_threads);
    if (new_threads == system.num_threads) {
        return;
    }
    if (new_threads >= system.num_threads) {
        _ = gs.barrier.count.fetchAdd(new_threads - system.num_threads, .acq_rel);
        thread_spawn_range(io, system.num_threads - 1, new_threads - 1);
        system.num_threads = new_threads;
        gs.barrier.num_threads = system.num_threads;
        module.function_table.thread_rescale_main();
    } else {
        // Only stop thread here to give them time to exit the main loop, join them
        // and update expected threads in the next loop iteration.
        thread_stop_range(new_threads - 1, system.num_threads - 1);
        system.stopped_threads = system.num_threads - new_threads;
    }
}

fn thread_spawn_range(io: std.Io, start_index: usize, end_index: usize) void {
    assert(start_index <= end_index);
    assert(end_index < gs.max_num_threads - 1);
    for (system.threads[start_index..end_index], 0..) |*t, i| {
        const id: u8 = @intCast(start_index + i + 1);
        t.* = std.Thread.spawn(.{}, thread_main, .{ io, id }) catch {
            std.log.err("Failed spawning thread {}", .{i});
            std.process.exit(1);
        };
    }
}

fn thread_stop_range(start_index: usize, end_index: usize) void {
    assert(start_index <= end_index);
    assert(end_index < gs.max_num_threads - 1);
    for (system.threads[start_index..end_index], 0..) |_, i| {
        const index = start_index + i + 1;
        system.thread_states[index].should_run.store(false, .release);
    }
}

fn thread_join_range(start_index: usize, end_index: usize) void {
    assert(start_index <= end_index);
    assert(end_index < gs.max_num_threads - 1);
    for (system.threads[start_index..end_index]) |*t| {
        t.join();
    }
}

//
// Interface exposed to modules
//

var stdout_buffer: [1024]u8 = undefined;
var stdout_writer: std.Io.File.Writer = undefined;
var stdout_mutex = gs.Mutex{};

fn stdout_log(str: [*]const u8, len: usize) callconv(.c) void {
    stdout_mutex.lock();
    defer stdout_mutex.unlock();

    const writer = &stdout_writer.interface;
    _ = writer.writeAll(str[0..len]) catch return;
    writer.flush() catch return;
}

//
// Hacky wrappers to use our arena allocators for loading Zon
//

fn arena_allocator(arena: *gs.Arena) std.mem.Allocator {
    return std.mem.Allocator{
        .ptr = arena,
        .vtable = &std.mem.Allocator.VTable{
            .alloc = arena_alloc_wrapper,
            .resize = arena_resize_wrapper,
            .remap = arena_remap_wrapper,
            .free = arena_free_wrapper,
        },
    };
}

fn arena_alloc_wrapper(context: *anyopaque, n: usize, al: std.mem.Alignment, ra: usize) ?[*]u8 {
    _ = ra;
    _ = al;
    assert(n > 0);
    var arena: *gs.Arena = @ptrCast(@alignCast(context));
    return @ptrCast(arena.alloc_aligned(u8, n, 8));
}

fn arena_resize_wrapper(context: *anyopaque, mem: []u8, al: std.mem.Alignment, new_len: usize, ra: usize) bool {
    _ = context;
    _ = mem;
    _ = al;
    _ = new_len;
    _ = ra;
    return false;
}

fn arena_remap_wrapper(context: *anyopaque, mem: []u8, al: std.mem.Alignment, new_len: usize, ra: usize) ?[*]u8 {
    _ = context;
    _ = mem;
    _ = al;
    _ = new_len;
    _ = ra;
    return null;
}

fn arena_free_wrapper(context: *anyopaque, mem: []u8, al: std.mem.Alignment, ra: usize) void {
    _ = context;
    _ = mem;
    _ = al;
    _ = ra;
}
