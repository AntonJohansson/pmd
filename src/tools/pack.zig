const std = @import("std");
const disk = @import("pack-disk");
const common = @import("common");
const goosepack = common.goosepack;

var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_state.allocator();
var arena_state = std.heap.ArenaAllocator.init(gpa);
var arena = arena_state.allocator();

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var stdout_buffered_writer = std.io.bufferedWriter(stdout_file);
    const stdout = stdout_buffered_writer.writer();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    if (args.len < 3) {
        printUsage();
        return;
    }

    const gp_str = args[1];

    goosepack.setAllocators(arena, arena);
    var p = goosepack.init();

    disk.persistent = gpa;
    disk.frame = gpa;
    const pack_in_memory: ?[]u8 = disk.read_file_to_memory(gp_str, gpa) catch null;
    if (pack_in_memory != null) {
        try goosepack.load(&p, pack_in_memory.?);
    }

    {
        if (args.len < 3) {
            printUsage();
            return;
        }
        const action_str = args[2];
        const action = std.meta.stringToEnum(Action, action_str) orelse {
            std.log.err("Invalid action \"{s}\"\n", .{action_str});
            printUsage();
            return;
        };

        switch (action) {
            .list => {
                switch (args.len) {
                    3 => {
                        try stdout.print("gosepack version: {}\n", .{p.header.format_version});
                        try stdout.print("file iteration: {}\n", .{p.header.file_iteration});
                        try stdout.print("size: {} MiB\n\n", .{pack_in_memory.?.len / 1024 / 1024});

                        try stdout.print("{s:4} {s:32} {s:16} {s:16} {s:16}\n", .{ "id", "name", "type", "offset", "size" });
                        for (p.entries.?.items, 0..) |e, i| {
                            try stdout.print("{:3}: {s:32} {s:16} {:16} {:16}\n", .{ i, e.name, @tagName(e.type), e.offset, e.size });
                        }
                    },
                    4 => {
                        const id = try std.fmt.parseInt(usize, args[3], 10);
                        if (id >= p.entries.?.items.len) {
                            printUsage();
                            return;
                        }
                        // TODO(anjo): this double switch on entry
                        const entry = p.entries.?.items[id];
                        const resource = goosepack.getResource(&p, id);
                        switch (entry.type) {
                            .text => {
                                try stdout.writeAll(resource.text.bytes);
                            },
                            .shader => {
                                try stdout.print("== vertex shader ==\n", .{});
                                try stdout.writeAll(resource.shader.vs_bytes);
                                try stdout.print("== fragment shader ==\n", .{});
                                try stdout.writeAll(resource.shader.fs_bytes);
                                try stdout.print("f {}\n", .{resource.shader.fs_bytes[resource.shader.fs_bytes.len - 1]});
                                try stdout.print("v {}\n", .{resource.shader.vs_bytes[resource.shader.vs_bytes.len - 1]});
                            },
                            .texture => {
                                try stdout.print("size: {}x{}\n", .{ resource.image.width, resource.image.height });
                                try stdout.print("channels: {}\n", .{resource.image.channels});
                            },
                            .cubemap => {
                                try stdout.print("size: {}x{}\n", .{ resource.cubemap.width, resource.cubemap.height });
                                try stdout.print("channels: {}\n", .{resource.cubemap.channels});
                            },
                            .audio => {
                                try stdout.print("num samples: {}\n", .{resource.audio.samples.len});
                            },
                            .model => {
                                for (resource.model.meshes, 0..) |m, i| {
                                    try stdout.print("mesh {}\n", .{i});
                                    for (m.primitives, 0..) |prim, j| {
                                        try stdout.print("  primitive {} - {}\n", .{ j, prim.buffer_types });
                                    }
                                }
                            },
                            .model_node => {
                                //const model = goosepack.lookup(&p, resource.model_node.model_name).model;
                                //math.m4.print(resource.model_node.transform);
                            },
                            else => unreachable,
                        }
                    },
                    else => {
                        printUsage();
                        return;
                    },
                }
            },
            .add => {
                if (args.len < 4) {
                    printUsage();
                    return;
                }
                const resource_str = args[3];

                const res_type = std.meta.stringToEnum(goosepack.ResourceType, resource_str) orelse {
                    std.log.err("Invalid action \"{s}\"\n", .{resource_str});
                    printUsage();
                    return;
                };

                if (args.len < 5) {
                    std.log.err("Expected texture path", .{});
                    return;
                }
                const path = args[4];

                if (res_type == .directory) {
                    var map = std.StringHashMap(struct {
                        type: goosepack.ResourceType,
                        name: []const u8,
                        srcs: []goosepack.EntrySrc,
                    }).init(arena);
                    var worklist = std.ArrayList([]const u8).init(arena);
                    try worklist.append(path);

                    while (worklist.popOrNull()) |workitem| {
                        const dir = try std.fs.cwd().openDir(workitem, .{ .iterate = true });
                        var it = dir.iterate();
                        while (try it.next()) |e| {
                            const item_path = try std.fs.path.join(arena, &[_][]const u8{ workitem, e.name });
                            switch (e.kind) {
                                .file => {
                                    const basename = std.fs.path.stem(e.name);
                                    const extension = std.fs.path.extension(e.name);
                                    const name = try std.fs.path.join(arena, &[_][]const u8{ workitem, basename });

                                    if (std.mem.eql(u8, extension, ".vert") or
                                        std.mem.eql(u8, extension, ".frag"))
                                    {
                                        // Shaders
                                        if (!map.contains(name)) {
                                            const srcs = try gpa.alloc(goosepack.EntrySrc, 2);
                                            const exts = [2][]const u8{
                                                ".vert",
                                                ".frag",
                                            };
                                            for (srcs, 0..) |*s, i| {
                                                s.* = .{
                                                    .path = try std.mem.concat(gpa, u8, &[_][]const u8{
                                                        name,
                                                        exts[i],
                                                    }),
                                                };
                                            }

                                            try map.put(name, .{
                                                .type = .shader,
                                                .name = name,
                                                .srcs = srcs,
                                            });
                                        }
                                    } else if (std.mem.eql(u8, extension, ".png")) {
                                        if (std.mem.eql(u8, basename, "px") or
                                            std.mem.eql(u8, basename, "nx") or
                                            std.mem.eql(u8, basename, "py") or
                                            std.mem.eql(u8, basename, "ny") or
                                            std.mem.eql(u8, basename, "pz") or
                                            std.mem.eql(u8, basename, "nz"))
                                        {
                                            // Cubemap
                                            if (!map.contains(workitem)) {
                                                const srcs = try gpa.alloc(goosepack.EntrySrc, 6);
                                                const filenames = [6][]const u8{
                                                    "px.png",
                                                    "nx.png",
                                                    "py.png",
                                                    "ny.png",
                                                    "pz.png",
                                                    "nz.png",
                                                };
                                                for (srcs, 0..) |*s, i| {
                                                    s.* = .{
                                                        .path = try std.fs.path.join(arena, &[_][]const u8{
                                                            workitem,
                                                            filenames[i],
                                                        }),
                                                    };
                                                }

                                                try map.put(workitem, .{
                                                    .type = .cubemap,
                                                    .name = workitem,
                                                    .srcs = srcs,
                                                });
                                            }
                                        } else {
                                            // Texture
                                            const srcs = try gpa.alloc(goosepack.EntrySrc, 1);
                                            srcs[0] = .{
                                                .path = item_path,
                                            };
                                            try map.put(item_path, .{
                                                .type = .texture,
                                                .name = name,
                                                .srcs = srcs,
                                            });
                                        }
                                    } else if (std.mem.eql(u8, extension, ".ttf")) {
                                        const srcs = try gpa.alloc(goosepack.EntrySrc, 1);
                                        srcs[0] = .{
                                            .path = item_path,
                                        };
                                        try map.put(item_path, .{
                                            .type = .font,
                                            .name = name,
                                            .srcs = srcs,
                                        });
                                    } else if (std.mem.eql(u8, extension, ".ogg")) {
                                        // Audio
                                        const srcs = try gpa.alloc(goosepack.EntrySrc, 1);
                                        srcs[0] = .{
                                            .path = item_path,
                                        };
                                        try map.put(item_path, .{
                                            .type = .audio,
                                            .name = name,
                                            .srcs = srcs,
                                        });
                                    } else if (std.mem.eql(u8, extension, ".glb")) {
                                        // Model
                                        const srcs = try gpa.alloc(goosepack.EntrySrc, 1);
                                        srcs[0] = .{
                                            .path = item_path,
                                        };
                                        try map.put(item_path, .{
                                            .type = .model,
                                            .name = name,
                                            .srcs = srcs,
                                        });
                                    }
                                },
                                .directory => {
                                    try worklist.append(item_path);
                                },
                                else => unreachable,
                            }
                        }
                    }

                    var it = map.iterator();
                    while (it.next()) |e| {
                        try stdout.print("adding {s:32}: {s:16}\n", .{ e.key_ptr.*, @tagName(e.value_ptr.type) });
                        _ = try disk.load_resource(&p, e.value_ptr.srcs, e.value_ptr.name, e.value_ptr.type);
                    }
                } else {
                    const ext = std.fs.path.extension(path);
                    const name = path[0 .. path.len - ext.len];
                    std.log.info("name {s}", .{name});
                    if (goosepack.entry_lookup(&p, name)) |ei| {
                        const entry = p.entries.?.items[ei.index];
                        std.log.info("always found \n{s}\n", .{entry.name});
                        if (goosepack.has_entry_been_modified(entry)) {
                            std.log.info("modified", .{});
                            goosepack.entry_delete(&p, entry);
                            const srcs = try gpa.alloc(goosepack.EntrySrc, 1);
                            srcs[0] = .{
                                .path = path,
                            };
                            _ = try disk.load_resource(&p, srcs, name, res_type);
                        } else {
                            std.log.info("not modified", .{});
                        }
                    } else {
                        const srcs = try gpa.alloc(goosepack.EntrySrc, 1);
                        srcs[0] = .{
                            .path = path,
                        };
                        _ = try disk.load_resource(&p, srcs, name, res_type);
                    }
                }
            },
            .del => {
                if (args.len < 4) {
                    printUsage();
                    return;
                }
                const id = try std.fmt.parseInt(usize, args[3], 10);
                if (id >= p.entries.?.items.len) {
                    std.log.err("{} not a valid entry id", .{id});
                    try stdout.print("{s:4} {s:32} {s:16} {s:16} {s:16}\n", .{ "id", "name", "type", "offset", "size" });
                    for (p.entries.?.items, 0..) |e, i| {
                        try stdout.print("{:3}: {s:32} {s:16} {:16} {:16}\n", .{ i, e.name, @tagName(e.type), e.offset, e.size });
                    }
                    try stdout_buffered_writer.flush();
                    return;
                }

                try goosepack.entry_delete_child_tree(&p, id);
            },
            .update => {
                if (pack_in_memory == null) {
                    std.log.err("{s} does not exist\n", .{gp_str});
                    return;
                }

                _ = try disk.collect_and_update_entries(&p);
            },
        }
    }

    try goosepack.saveToFile(&p, gp_str);

    arena_state.deinit();

    try stdout_buffered_writer.flush();
}

fn printUsage() void {
    std.log.err("Usage: pack [file] [resource] [option]...", .{});
}

const Action = enum(u8) {
    list,
    add,
    del,
    update,
};

