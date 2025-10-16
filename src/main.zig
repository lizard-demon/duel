const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;

// Input
const input = @import("lib/io/input.zig");
// World
const octree = @import("lib/world/octree.zig");
const mesh = @import("lib/world/mesh.zig");
const rend = @import("lib/world/render.zig");
// Math
const alg = @import("lib/math/algebra.zig");

const Vec3 = alg.Vec3;
const Mat4 = alg.Mat4;
const World = octree.Octree(6); // depth 6 = 64x64x64
const shade = @import("shaders/cube.glsl.zig");

fn blockColors(block: octree.Block) [3]f32 {
    return switch (block) {
        .grass => .{ 0.3, 0.7, 0.3 },
        .dirt => .{ 0.5, 0.35, 0.2 },
        .stone => .{ 0.5, 0.5, 0.5 },
        .air => unreachable,
    };
}

fn Physics(comptime cfg: struct {
    gravity: f32 = 20.0,
    jump: f32 = 8.0,
    accel_ground: f32 = 10.0,
    accel_air: f32 = 10.0,
    friction: f32 = 4.0,
    speed_max: f32 = 7.0,
    speed_stop: f32 = 0.1,
    air_cap: f32 = 0.7, // Air acceleration cap threshold
}) type {
    return struct {
        vel: Vec3 = Vec3.zero(),
        grounded: bool = false,

        pub fn jump(self: *@This()) void {
            self.vel.data[1] = cfg.jump;
            self.grounded = false;
        }

        pub fn move(self: *@This(), dir: Vec3, dt: f32) void {
            // Get horizontal direction length
            const len = @sqrt(dir.x() * dir.x() + dir.z() * dir.z());
            if (len < 0.0001) return if (self.grounded) self.applyFriction(dt);

            // Normalize wish direction
            const wish_dir = Vec3.new(dir.x() / len, 0, dir.z() / len);
            const wish_speed = cfg.speed_max * len;

            if (self.grounded) {
                self.applyFriction(dt);
                self.accelerate(wish_dir, wish_speed, cfg.accel_ground * dt);
            } else {
                // Air acceleration - key to strafing
                self.airAccelerate(wish_dir, wish_speed, cfg.accel_air * dt);
            }
        }

        fn accelerate(self: *@This(), wish_dir: Vec3, wish_speed: f32, accel: f32) void {
            // Current speed in wish direction
            const current_speed = self.vel.dot(wish_dir);
            // Speed to add
            const add_speed = wish_speed - current_speed;
            if (add_speed <= 0) return;

            // Clamp acceleration
            var accel_speed = accel * wish_speed;
            if (accel_speed > add_speed) accel_speed = add_speed;

            self.vel = self.vel.add(wish_dir.scale(accel_speed));
        }

        fn airAccelerate(self: *@This(), wish_dir: Vec3, wish_speed: f32, accel: f32) void {
            // Cap wish speed for air control
            const capped_speed = @min(wish_speed, cfg.air_cap);

            // Current speed in wish direction
            const current_speed = self.vel.dot(wish_dir);
            // Speed to add
            const add_speed = capped_speed - current_speed;
            if (add_speed <= 0) return;

            // How much to accelerate
            var accel_speed = accel * wish_speed;
            if (accel_speed > add_speed) accel_speed = add_speed;

            // Add the acceleration
            self.vel = self.vel.add(wish_dir.scale(accel_speed));
        }

        pub fn update(self: *@This(), pos: *Vec3, world: anytype, dt: f32) void {
            self.vel.data[1] -= cfg.gravity * dt;
            const result = world.sweep(pos.*, .{
                .min = Vec3.new(-0.4, -0.9, -0.4),
                .max = Vec3.new(0.4, 0.9, 0.4)
            }, self.vel.scale(dt), 3);
            pos.* = result.pos;
            self.vel = result.vel.scale(1.0 / dt);
            self.grounded = result.hit and @abs(result.vel.y()) < 0.01;
        }

        fn applyFriction(self: *@This(), dt: f32) void {
            const speed = @sqrt(self.vel.x() * self.vel.x() + self.vel.z() * self.vel.z());
            if (speed < 0.1) {
                self.vel.data[0] = 0;
                self.vel.data[2] = 0;
                return;
            }

            // Drop friction amount
            const drop = @max(speed, cfg.speed_stop) * cfg.friction * dt;
            const new_speed = @max(0, speed - drop);
            const scale = new_speed / speed;

            self.vel.data[0] *= scale;
            self.vel.data[2] *= scale;
        }
    };
}

const App = struct {
    pipeline: rend.Renderer,
    cam: rend.Camera3D,
    io: input.IO = .{},
    phys: Physics(.{}) = .{},
    world: World,
    voxel_pipeline: rend.Renderer,

    fn init() !App {
        var self: App = undefined;
        self.pipeline = rend.Renderer.init(&[_]rend.Vertex{
            .{ .pos = .{ -100, -1, -100 }, .col = .{ 0.1, 0.1, 0.12, 1 } },
            .{ .pos = .{ 100, -1, -100 }, .col = .{ 0.12, 0.15, 0.18, 1 } },
            .{ .pos = .{ 100, -1, 100 }, .col = .{ 0.15, 0.12, 0.15, 1 } },
            .{ .pos = .{ -100, -1, 100 }, .col = .{ 0.12, 0.12, 0.15, 1 } },
        }, &[_]u16{ 0, 1, 2, 0, 2, 3 }, .{ 0.5, 0.7, 0.9, 1 });
        self.cam = rend.Camera3D.init(Vec3.new(32, 40, 32), 0, 0, 60);
        self.world = World.init();

        var verts: [65536]rend.Vertex = undefined;
        var indices: [98304]u16 = undefined;
        const result = mesh.buildMesh(&self.world, &verts, &indices, blockColors);
        self.voxel_pipeline = rend.Renderer.init(verts[0..result.vcount], indices[0..result.icount], .{ 0.5, 0.7, 0.9, 1 });

        const shader_desc = shade.cubeShaderDesc(sokol.gfx.queryBackend());
        self.pipeline.shader(shader_desc);
        self.voxel_pipeline.shader(shader_desc);
        return self;
    }

    fn update(self: *App) void {
        const dt: f32 = @floatCast(sapp.frameDuration());
        const mv = self.io.vec2(.a, .d, .s, .w);
        var dir = Vec3.zero();
        if (mv.x != 0) dir = dir.add(Vec3.new(self.cam.right().x(), 0, self.cam.right().z()).scale(mv.x));
        if (mv.y != 0) dir = dir.add(Vec3.new(self.cam.forward().x(), 0, self.cam.forward().z()).scale(mv.y));
        self.phys.move(dir, dt);
        if (self.io.pressed(.space) and self.phys.grounded) self.phys.jump();
        self.phys.update(&self.cam.position, &self.world, dt);
        if (self.io.mouse.isLocked()) self.cam.look(self.io.mouse.dx * 0.002, -self.io.mouse.dy * 0.002);
        if (self.io.justPressed(.escape)) self.io.mouse.unlock();
        if (self.io.mouse.left and !self.io.mouse.isLocked()) self.io.mouse.lock();
    }

    fn render(self: *App) void {
        const mvp = Mat4.mul(Mat4.mul(self.cam.projectionMatrix(sapp.widthf() / sapp.heightf(), 0.1, 1000), self.cam.viewMatrix()), Mat4.identity());
        self.pipeline.draw(mvp);
        self.voxel_pipeline.draw(mvp);
    }

    fn deinit(self: *App) void {
        self.pipeline.deinit();
        self.voxel_pipeline.deinit();
        self.world.deinit();
    }
};

var app: App = undefined;
export fn init() void { app = App.init() catch unreachable; }
export fn frame() void { app.update(); app.render(); app.io.cleanInput(); }
export fn cleanup() void { app.deinit(); }
export fn event(e: [*c]const sapp.Event) void { app.io.update(e); }

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .width = 800,
        .height = 600,
        .sample_count = 4,
        .icon = .{ .sokol_default = true },
        .window_title = "Octree Voxels",
        .logger = .{ .func = sokol.log.func },
    });
}
