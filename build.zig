const std = @import("std");
//const sokol = @import("third_party/sokol-zig/build.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sokol_dep = b.dependency("sokol-zig", .{
        .target = target,
        .optimize = optimize,
    });

    //
    // common
    //

    const common = b.createModule(.{
        .root_source_file = b.path("src/common/common.zig"),
        //.dependencies = &.{.{ .name = "sokol", .module = sokol_module }},
    });

    //
    // net
    //

    const net = b.createModule(.{
        .root_source_file = b.path("src/net/net.zig"),
        .imports = &.{.{ .name = "common", .module = common }},
    });

    //
    // lib
    //

    const libgame = b.addSharedLibrary(.{
        .name = "game",
        .root_source_file = b.path("src/game/game.zig"),
        .target = target,
        .optimize = optimize,
    });
    // TODO: Remove when renderer is moved to separate library
    //libgame.addModule("sokol", sokol_module);
    libgame.root_module.addImport("common", common);
    libgame.root_module.addImport("net", net);
    //libgame.linkLibrary(sokol_build);
    _ = b.installArtifact(libgame);

    //
    // client
    //
    const client_dir = try std.fs.cwd().openDir("src/client", .{});
    try std.fs.cwd().copyFile("third_party/SDL_GameControllerDB/gamecontrollerdb.txt", client_dir, "gamecontrollerdb.txt", .{});

    const client = b.addExecutable(.{
        .name = "client",
        .root_source_file = b.path("src/client/client.zig"),
        .target = target,
        .optimize = optimize,
    });
    client.addCSourceFile(.{ .file = b.path("src/client/stb.c"), .flags = &.{
        "-Wall",
        "-Wextra",
        "-Werror",
    } });
    client.addIncludePath(b.path("src/client"));
    client.linkLibC();
    client.root_module.addImport("sokol", sokol_dep.module("sokol"));
    client.root_module.addImport("common", common);
    client.root_module.addImport("net", net);
    //client.linkLibrary(sokol_build);
    b.installArtifact(client);

    // Use mach-glfw
    const glfw_dep = b.dependency("mach-glfw", .{
        .target = target,
        .optimize = optimize,
    });
    client.root_module.addImport("mach-glfw", glfw_dep.module("mach-glfw"));
    //@import("mach_glfw").link(glfw_dep.builder, client);

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
    // pack
    //

    const pack_dir = try std.fs.cwd().openDir("src/tools", .{});
    try std.fs.cwd().copyFile("third_party/SDL_GameControllerDB/gamecontrollerdb.txt", pack_dir, "gamecontrollerdb.txt", .{});

    const pack = b.addExecutable(.{
        .name = "pack",
        .root_source_file = b.path("src/tools/pack.zig"),
        .target = target,
        .optimize = optimize,
    });
    pack.addCSourceFile(.{ .file = b.path("src/tools/stb.c"), .flags = &.{
        "-Wall",
        "-Wextra",
        "-Werror",
    } });
    pack.root_module.addImport("common", common);
    pack.root_module.addImport("sokol", sokol_dep.module("sokol"));
    pack.addIncludePath(b.path("src/tools"));
    pack.linkLibC();
    b.installArtifact(pack);

    const run_pack_cmd = b.addRunArtifact(pack);
    run_pack_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_pack_cmd.addArgs(args);
    }
    const run_pack_step = b.step("run-pack", "Run pack");
    run_pack_step.dependOn(&run_pack_cmd.step);
}
