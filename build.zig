const std = @import("std");
const Build = std.Build;
const sokol = @import("sokol");

const Opts = struct { mod: *Build.Module, dep_sokol: *Build.Dependency, shader: *Build.Step };

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dep_sokol = b.dependency("sokol", .{ .target = target, .optimize = optimize });
    const shdc = b.dependency("shdc", .{});
    const shader = try @import("shdc").createSourceFile(b, .{ .shdc_dep = shdc, .input = "src/shaders/cube.glsl", .output = "src/shaders/cube.glsl.zig", .slang = .{ .glsl410 = true, .glsl300es = true, .metal_macos = true, .wgsl = true } });
    const mod = b.createModule(.{ .root_source_file = b.path("src/main.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "sokol", .module = dep_sokol.module("sokol") }} });
    const opts = Opts{ .mod = mod, .dep_sokol = dep_sokol, .shader = shader };
    if (target.result.cpu.arch.isWasm()) try buildWeb(b, opts) else try buildNative(b, opts);
}

fn buildNative(b: *Build, opts: Opts) !void {
    const exe = b.addExecutable(.{ .name = "voxels", .root_module = opts.mod });
    exe.step.dependOn(opts.shader);
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    b.step("run", "Run voxels").dependOn(&run.step);
}

fn buildWeb(b: *Build, opts: Opts) !void {
    const lib = b.addLibrary(.{ .name = "voxels", .root_module = opts.mod });
    lib.step.dependOn(opts.shader);
    const emsdk = opts.dep_sokol.builder.dependency("emsdk", .{});
    const link_step = try sokol.emLinkStep(b, .{ .lib_main = lib, .target = opts.mod.resolved_target.?, .optimize = opts.mod.optimize.?, .emsdk = emsdk, .use_webgl2 = true, .use_emmalloc = true, .use_filesystem = false, .shell_file_path = opts.dep_sokol.path("src/sokol/web/shell.html") });
    b.getInstallStep().dependOn(&link_step.step);
    const run = sokol.emRunStep(b, .{ .name = "voxels", .emsdk = emsdk });
    run.step.dependOn(&link_step.step);
    b.step("run", "Run voxels").dependOn(&run.step);
}
