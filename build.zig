const std = @import("std");
const sokol = @import("sokol");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sokol_dep = b.dependency("sokol", .{ .target = target, .optimize = optimize });
    const shdc = b.dependency("shdc", .{});

    const shader = try @import("shdc").createSourceFile(b, .{
        .shdc_dep = shdc,
        .input = "src/shaders/cube.glsl",
        .output = "src/shaders/cube.glsl.zig",
        .slang = .{ .glsl410 = true, .metal_macos = true, .wgsl = true },
    });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "sokol", .module = sokol_dep.module("sokol") }},
    });

    if (target.result.cpu.arch.isWasm()) {
        const lib = b.addLibrary(.{ .name = "voxels", .root_module = mod });
        lib.step.dependOn(shader);

        const emsdk = sokol_dep.builder.dependency("emsdk", .{});
        const link = try sokol.emLinkStep(b, .{
            .lib_main = lib,
            .target = target,
            .optimize = optimize,
            .emsdk = emsdk,
            .use_webgl2 = true,
            .use_emmalloc = true,
            .use_filesystem = false,
            .shell_file_path = sokol_dep.path("src/sokol/web/shell.html"),
        });
        b.getInstallStep().dependOn(&link.step);

        const run = sokol.emRunStep(b, .{ .name = "voxels", .emsdk = emsdk });
        run.step.dependOn(&link.step);
        b.step("run", "Run voxels").dependOn(&run.step);
    } else {
        const exe = b.addExecutable(.{ .name = "voxels", .root_module = mod });
        exe.step.dependOn(shader);
        b.installArtifact(exe);

        const run = b.addRunArtifact(exe);
        run.step.dependOn(b.getInstallStep());
        b.step("run", "Run voxels").dependOn(&run.step);
    }
}
