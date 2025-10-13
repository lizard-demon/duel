const std = @import("std");
const Build = std.Build;
const sokol = @import("sokol");

const Options = struct {
    mod: *Build.Module,
    dep_sokol: *Build.Dependency,
    shader_step: *Build.Step,
};

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const sokol_dep = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });
    const shdc_dep = b.dependency("shdc", .{});

    // Compile shader
    const sokol_shdc = @import("shdc");
    const shader_step = try sokol_shdc.createSourceFile(b, .{
        .shdc_dep = shdc_dep,
        .input = "src/shaders/cube.glsl",
        .output = "src/shaders/cube.glsl.zig",
        .slang = .{
            .glsl410 = true,
            .glsl300es = true,
            .metal_macos = true,
            .hlsl5 = true,
            .wgsl = true,
        },
        .reflection = true,
    });

    // Create module with dependencies
    const mod_camera = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sokol", .module = sokol_dep.module("sokol") },
        },
    });

    // Special case handling for native vs web build
    const opts = Options{
        .mod = mod_camera,
        .dep_sokol = sokol_dep,
        .shader_step = shader_step,
    };
    if (target.result.cpu.arch.isWasm()) {
        try buildWeb(b, opts);
    } else {
        try buildNative(b, opts);
    }
}

// Regular build for all native platforms
fn buildNative(b: *Build, opts: Options) !void {
    const exe = b.addExecutable(.{
        .name = "camera_demo",
        .root_module = opts.mod,
    });
    exe.step.dependOn(opts.shader_step);
    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the camera demo");
    run_step.dependOn(&run_cmd.step);
}

// For web builds, build into a library and link with Emscripten
fn buildWeb(b: *Build, opts: Options) !void {
    const lib = b.addLibrary(.{
        .name = "camera_demo",
        .root_module = opts.mod,
    });
    lib.step.dependOn(opts.shader_step);

    // Create a build step which invokes the Emscripten linker
    const emsdk = opts.dep_sokol.builder.dependency("emsdk", .{});
    const link_step = try sokol.emLinkStep(b, .{
        .lib_main = lib,
        .target = opts.mod.resolved_target.?,
        .optimize = opts.mod.optimize.?,
        .emsdk = emsdk,
        .use_webgl2 = true,
        .use_emmalloc = true,
        .use_filesystem = false,
        .shell_file_path = opts.dep_sokol.path("src/sokol/web/shell.html"),
    });

    // Attach Emscripten linker output to default install step
    b.getInstallStep().dependOn(&link_step.step);

    // Rename camera_demo.html to index.html
    const rename_step = b.addSystemCommand(&.{
        "mv",
        b.pathJoin(&.{ b.install_path, "web", "camera_demo.html" }),
        b.pathJoin(&.{ b.install_path, "web", "index.html" }),
    });
    rename_step.step.dependOn(&link_step.step);
    b.getInstallStep().dependOn(&rename_step.step);

    // Create zip file of the web directory
    const zip_step = b.addSystemCommand(&.{
        "zip",
        "-r",
        b.pathJoin(&.{ b.install_path, "camera_demo_web.zip" }),
        "web",
    });
    zip_step.setCwd(.{ .cwd_relative = b.install_path });
    zip_step.step.dependOn(&rename_step.step);

    // Add a packaging step
    const package_step = b.step("package", "Package the web build into a zip file");
    package_step.dependOn(&zip_step.step);

    // Make install step also create the zip
    b.getInstallStep().dependOn(&zip_step.step);

    // Special run step to start the web build output via 'emrun'
    const run = sokol.emRunStep(b, .{ .name = "camera_demo", .emsdk = emsdk });
    run.step.dependOn(&link_step.step);
    b.step("run", "Run camera_demo").dependOn(&run.step);
}
