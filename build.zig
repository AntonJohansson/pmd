const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sokol_dep = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
        .x11 = true,
        .wayland = true,
    });

    //
    // build_options
    //

    const options = b.addOptions();
    const production = b.option(bool, "production", "disables debug engine features (hot reloading, modules, pack recompilation)") orelse false;
    options.addOption(bool, "debug", !production);

    const should_build_glfw = b.option(bool, "build-glfw", "build glfw submodule") orelse false;
    if (should_build_glfw) {
        try build_glfw(b);
    }

    const build_options = b.createModule(.{
        .root_source_file = b.path("src/build_options.zig"),
    });
    build_options.addOptions("options", options);

    //
    // mach glfw dependency
    //
    //
    // common
    //

    const common = b.createModule(.{
        .root_source_file = b.path("src/common/common.zig"),
    });
    common.addImport("build_options", build_options);
    common.addIncludePath(b.path("third_party/glfw/include/GLFW"));
    //common.addImport("mach-glfw", glfw_dep.module("mach-glfw"));

    //
    // pack
    //

    const pack_disk = b.createModule(.{
        .root_source_file = b.path("src/tools/pack-disk.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    pack_disk.addImport("common", common);
    pack_disk.addImport("sokol", sokol_dep.module("sokol"));
    pack_disk.addIncludePath(b.path("src/tools"));
    pack_disk.addCSourceFile(.{ .file = b.path("src/tools/stb.c"), .flags = &.{
        "-Wall",
        "-Wextra",
        "-Werror",
    } });

    const pack = b.addExecutable(.{
        .name = "pack",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools/pack.zig"),
            .target = target,
            .optimize = optimize,
        }),
        // TODO(anjo): temp
        .use_lld = false,
    });
    pack.root_module.addImport("common", common);
    pack.root_module.addImport("pack-disk", pack_disk);
    const pack_install = b.addInstallArtifact(pack, .{
        .dest_dir = .{ .override = .{ .custom = "tools" } },
    });
    b.getInstallStep().dependOn(&pack_install.step);

    //
    // net
    //

    const net = b.createModule(.{
        .root_source_file = b.path("src/net/net.zig"),
        .imports = &.{.{ .name = "common", .module = common }},
    });
    net.addImport("build_options", build_options);

    //
    // lib
    //

    const libgame = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "game",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/game/game.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    libgame.root_module.addImport("common", common);
    libgame.root_module.addImport("net", net);
    libgame.root_module.addImport("build_options", build_options);
    const libgame_install = b.addInstallArtifact(libgame, .{
        .dest_dir = .{ .override = .{ .custom = "modules" } },
    });
    b.getInstallStep().dependOn(&libgame_install.step);

    //
    // res.gp
    //

    const data_path = try std.Io.Dir.path.join(b.allocator, &[_][]const u8{ b.install_prefix, "data" });
    const res_path = try std.Io.Dir.path.join(b.allocator, &[_][]const u8{ data_path, "res.gp" });
    _ = try std.Io.Dir.cwd().createDirPath(b.graph.io, data_path);
    if (!exists(b.graph.io, res_path)) {
        const run_res = b.addRunArtifact(pack);
        run_res.step.dependOn(&pack_install.step);
        run_res.addArgs(&[_][]const u8{ res_path, "add", "directory", "res" });
        b.getInstallStep().dependOn(&run_res.step);
    }

    //
    // client
    //
    //const client_dir = try std.fs.cwd().openDir("src/client", .{});
    //try std.fs.cwd().copyFile("third_party/SDL_GameControllerDB/gamecontrollerdb.txt", client_dir, "gamecontrollerdb.txt", .{});

    //const client = b.addExecutable(.{
    //    .name = "client",
    //    .root_module = b.createModule(.{
    //        .root_source_file = b.path("src/client/client.zig"),
    //        .target = target,
    //        .optimize = optimize,
    //    }),
    //    // TODO(anjo): temp
    //    .use_lld = false,
    //    .use_llvm = true,
    //});
    //client.root_module.addObjectFile(b.path("third_party/glfw/build/src/libglfw3.a"));
    //client.root_module.addIncludePath(b.path("third_party/glfw/include/GLFW"));
    //client.root_module.addImport("sokol", sokol_dep.module("sokol"));
    //client.root_module.addImport("common", common);
    //client.root_module.addImport("net", net);
    //client.root_module.addImport("pack-disk", pack_disk);
    //client.root_module.addImport("build_options", build_options);
    //b.installArtifact(client);

    //const run_client_cmd = b.addRunArtifact(client);
    //run_client_cmd.step.dependOn(b.getInstallStep());
    //if (b.args) |args| {
    //    run_client_cmd.addArgs(args);
    //}
    //const run_client_step = b.step("run-client", "Run the client");
    //run_client_step.dependOn(&run_client_cmd.step);

    const client = b.addExecutable(.{
        .name = "client",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/client-main.zig"),
            .target = target,
            .optimize = optimize,
        }),
        // TODO(anjo): temp
        .use_lld = false,
        .use_llvm = true,
    });
    client.root_module.addObjectFile(b.path("third_party/glfw/build/src/libglfw3.a"));
    client.root_module.addIncludePath(b.path("third_party/glfw/include/GLFW"));
    client.root_module.addImport("sokol", sokol_dep.module("sokol"));
    client.root_module.addImport("common", common);
    client.root_module.addImport("net", net);
    client.root_module.addImport("pack-disk", pack_disk);
    client.root_module.addImport("build_options", build_options);
    const client_install = b.addInstallArtifact(client, .{
        .dest_dir = .{ .override = .{ .custom = "." } },
    });
    b.getInstallStep().dependOn(&client_install.step);

    const run_client_cmd = b.addRunArtifact(client);
    run_client_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_client_cmd.addArgs(args);
    }
    const run_client_step = b.step("run-client", "Run the client");
    run_client_step.dependOn(&run_client_cmd.step);

    //
    // server
    //

    //const server = b.addExecutable(.{
    //    .name = "server",
    //    .root_module = b.createModule(.{
    //        .root_source_file = b.path("src/server/server.zig"),
    //        .target = target,
    //        .optimize = optimize,
    //    }),
    //    // TODO(anjo): temp
    //    .use_lld = false,
    //});
    //server.root_module.addImport("common", common);
    //server.root_module.addImport("net", net);
    //server.root_module.addImport("pack-disk", pack_disk);
    //server.root_module.addImport("build_options", build_options);
    //server.linkLibC();
    //b.installArtifact(server);

    //const run_server_cmd = b.addRunArtifact(server);
    //run_server_cmd.step.dependOn(b.getInstallStep());
    //if (b.args) |args| {
    //    run_server_cmd.addArgs(args);
    //}
    //const run_server_step = b.step("run-server", "Run the server");
    //run_server_step.dependOn(&run_server_cmd.step);

    //
    // Run step
    //

    const run_pack_cmd = b.addRunArtifact(pack);
    run_pack_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_pack_cmd.addArgs(args);
    }
    const run_pack_step = b.step("run-pack", "Run pack");
    run_pack_step.dependOn(&run_pack_cmd.step);
}

fn build_glfw(b: *std.Build) !void {
    std.log.info("Building GLFW", .{});

    const build_path = "third_party/glfw/build";

    _ = try std.Io.Dir.cwd().createDirPath(b.graph.io, build_path);

    const res_cmake = try std.process.run(
        b.allocator,
        b.graph.io,
        .{ .argv = &[_][]const u8{ "cmake", "-B", build_path, "-S", "third_party/glfw", "-D", "GLFW_BUILD_X11=1", "-D", "GLFW_BUILD_WAYLAND=1" } },
    );
    if (res_cmake.stderr.len > 0) {
        std.log.info("{s}", .{res_cmake.stderr});
        return error.BuildFailed;
    }
    std.log.info("{s}", .{res_cmake.stdout});

    const res_make = try std.process.run(
        b.allocator,
        b.graph.io,
        .{ .argv = &[_][]const u8{ "make", "-C", build_path } },
    );
    std.log.info("{s}", .{res_make.stdout});
}

fn exists(io: std.Io, path: []const u8) bool {
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return true;
}
