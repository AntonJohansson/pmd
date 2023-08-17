const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //
    // lib
    //

    const libgame = b.addSharedLibrary(.{
        .name = "game",
        .root_source_file = .{ .path = "src/game.zig" },
        .target = target,
        .optimize = optimize,
    });
    libgame.linkLibC();
    _ = b.installArtifact(libgame);

    //
    // client
    //

    const client = b.addExecutable(.{
        .name = "client",
        .root_source_file = .{ .path = "src/client.zig" },
        .target = target,
        .optimize = optimize,
    });
    client.linkLibC();
    client.linkSystemLibrary("raylib");
    b.installArtifact(client);

    // Use mach-glfw
    //const glfw_dep = b.dependency("mach_glfw", .{
    //    .target = client.target,
    //    .optimize = client.optimize,
    //});
    //client.addModule("mach-glfw", glfw_dep.module("mach-glfw"));
    //try @import("mach_glfw").link(b, client);

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
        .root_source_file = .{ .path = "src/server.zig" },
        .target = target,
        .optimize = optimize,
    });
    server.linkLibC();
    server.linkSystemLibrary("raylib");
    b.installArtifact(server);

    const run_server_cmd = b.addRunArtifact(server);
    run_server_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_server_cmd.addArgs(args);
    }
    const run_server_step = b.step("run-server", "Run the server");
    run_server_step.dependOn(&run_server_cmd.step);
}
