const std = @import("std");
//const sokol = @import("third_party/sokol-zig/build.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sokol_dep = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });

    const zphysics_dep = b.dependency("zphysics", .{
        .target = target,
        .optimize = optimize,
        .use_double_precision = false,
        .enable_cross_platform_determinism = true,
    });


    //
    // build_options
    //

    const options = b.addOptions();
    const production = b.option(bool, "production", "disables debug engine features (hot reloading, modules, pack recompilation)") orelse false;
    options.addOption(bool, "debug", !production);

    const build_options = b.createModule(.{
        .root_source_file = b.path("src/build_options.zig"),
    });
    build_options.addOptions("options", options);

    //
    // common
    //

    const common = b.createModule(.{
        .root_source_file = b.path("src/common/common.zig"),
    });
    common.addImport("build_options", build_options);

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
        .root_source_file = b.path("src/tools/pack.zig"),
        .target = target,
        .optimize = optimize,
    });
    pack.root_module.addImport("common", common);
    pack.root_module.addImport("pack-disk", pack_disk);
    b.installArtifact(pack);

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

    const libgame = b.addSharedLibrary(.{
        .name = "game",
        .root_source_file = b.path("src/game/game.zig"),
        .target = target,
        .optimize = optimize,
    });
    libgame.root_module.addImport("common", common);
    libgame.root_module.addImport("net", net);
    libgame.root_module.addImport("build_options", build_options);
    libgame.root_module.addImport("zphysics", zphysics_dep.module("root"));
    libgame.linkLibrary(zphysics_dep.artifact("joltc"));
    _ = b.installArtifact(libgame);

    //
    // mach glfw dependency
    //
    const glfw_dep = b.dependency("mach-glfw", .{
        .target = target,
        .optimize = optimize,
    });

    //
    // client
    //
    //const client_dir = try std.fs.cwd().openDir("src/client", .{});
    //try std.fs.cwd().copyFile("third_party/SDL_GameControllerDB/gamecontrollerdb.txt", client_dir, "gamecontrollerdb.txt", .{});

    const client = b.addExecutable(.{
        .name = "client",
        .root_source_file = b.path("src/client/client.zig"),
        .target = target,
        .optimize = optimize,
    });
    client.addIncludePath(b.path("src/client"));
    client.linkLibC();
    client.root_module.addImport("sokol", sokol_dep.module("sokol"));
    client.root_module.addImport("common", common);
    client.root_module.addImport("net", net);
    client.root_module.addImport("mach-glfw", glfw_dep.module("mach-glfw"));
    client.root_module.addImport("pack-disk", pack_disk);
    client.root_module.addImport("build_options", build_options);
    b.installArtifact(client);

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

    const server = b.addExecutable(.{
        .name = "server",
        .root_source_file = b.path("src/server/server.zig"),
        .target = target,
        .optimize = optimize,
    });
    server.root_module.addImport("common", common);
    server.root_module.addImport("net", net);
    client.root_module.addImport("pack-disk", pack_disk);
    server.root_module.addImport("build_options", build_options);
    server.linkLibC();
    b.installArtifact(server);

    const run_server_cmd = b.addRunArtifact(server);
    run_server_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_server_cmd.addArgs(args);
    }
    const run_server_step = b.step("run-server", "Run the server");
    run_server_step.dependOn(&run_server_cmd.step);

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
