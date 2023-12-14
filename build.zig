const std = @import("std");
const sokol = @import("third_party/sokol-zig/build.zig");

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sokol_build = sokol.buildSokol(b, target, optimize, .{.backend=.gl}, "third_party/sokol-zig/");
    const sokol_module = b.addModule("sokol", .{
        .source_file = .{.path = "third_party/sokol-zig/src/sokol/sokol.zig"},
    });

    //
    // common
    //

    const common = b.createModule(.{
        .source_file = .{.path = "src/common/common.zig"},
        .dependencies = &.{.{.name="sokol",.module=sokol_module}},
    });

    //
    // net
    //

    const net = b.createModule(.{
        .source_file = .{.path = "src/net/net.zig"},
        .dependencies = &.{.{.name="common",.module=common}},
    });

    //
    // lib
    //

    const libgame = b.addSharedLibrary(.{
        .name = "game",
        .root_source_file = .{ .path = "src/game/game.zig" },
        .target = target,
        .optimize = optimize,
    });
    // TODO: Remove when renderer is moved to separate library
    libgame.addModule("sokol", sokol_module);
    libgame.addModule("common", common);
    libgame.addModule("net", net);
    libgame.linkLibrary(sokol_build);
    _ = b.installArtifact(libgame);

    //
    // client
    //
    const client_dir = try std.fs.cwd().openDir("src/client", .{});
    try std.fs.cwd().copyFile("third_party/SDL_GameControllerDB/gamecontrollerdb.txt", client_dir, "gamecontrollerdb.txt", .{});

    const client = b.addExecutable(.{
        .name = "client",
        .root_source_file = .{ .path = "src/client/client.zig" },
        .target = target,
        .optimize = optimize,
    });
    client.addCSourceFile(.{
        .file = .{
            .path = "src/client/stb_vorbis.c"
        },
        .flags = &.{
            "-Wall",
            "-Wextra",
            "-Werror",
        }});
    client.addIncludePath(std.build.LazyPath.relative("src/client"));
    client.linkLibC();
    client.addModule("sokol", sokol_module);
    client.addModule("common", common);
    client.addModule("net", net);
    client.linkLibrary(sokol_build);
    b.installArtifact(client);

    // Use mach-glfw
    const glfw_dep = b.dependency("mach_glfw", .{
        .target = client.target,
        .optimize = client.optimize,
    });
    client.addModule("mach-glfw", glfw_dep.module("mach-glfw"));
    @import("mach_glfw").link(glfw_dep.builder, client);

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
        .root_source_file = .{ .path = "src/server/server.zig" },
        .target = target,
        .optimize = optimize,
    });
    server.addModule("common", common);
    server.addModule("net", net);
    server.linkLibC();
    b.installArtifact(server);

    const run_server_cmd = b.addRunArtifact(server);
    run_server_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_server_cmd.addArgs(args);
    }
    const run_server_step = b.step("run-server", "Run the server");
    run_server_step.dependOn(&run_server_cmd.step);
}
