const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const input = @import("lib/input.zig");
const rend = @import("lib/render.zig");
const alg = @import("lib/algebra.zig");
const voxel = @import("lib/voxel.zig");
const Vec3 = alg.Vec3;
const Mat4 = alg.Mat4;
const shade = @import("shaders/cube.glsl.zig");

const World = voxel.VoxelWorld(voxel.Chunk(16, 64));

fn blockColors(block: voxel.Block) [3]f32 {
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
    accel_air: f32 = 1.0,
    friction: f32 = 6.0,
    speed_max: f32 = 7.0,
    speed_air_cap: f32 = 1.0,
    speed_stop: f32 = 1.0,
}) type {
    return struct {
        vel: Vec3 = Vec3.zero(),
        grounded: bool = false,

        pub fn jump(self: *@This()) void {
            self.vel.data[1] = cfg.jump;
            self.grounded = false;
        }

        pub fn move(self: *@This(), dir: Vec3, dt: f32) void {
            const len = @sqrt(dir.x() * dir.x() + dir.z() * dir.z());
            if (len < 0.0001) return if (self.grounded) self.applyFriction(dt);

            const norm = Vec3.new(dir.x() / len, 0, dir.z() / len);
            const wish = @min(cfg.speed_max * len, if (self.grounded) cfg.speed_max else cfg.speed_air_cap);
            if (self.grounded) self.applyFriction(dt);

            const add = wish - self.vel.dot(norm);
            if (add > 0) self.vel = self.vel.add(norm.scale(@min((if (self.grounded) cfg.accel_ground else cfg.accel_air) * dt * wish, add)));
        }

        pub fn update(self: *@This(), pos: *Vec3, world: anytype, dt: f32) void {
            self.vel.data[1] -= cfg.gravity * dt;
            const result = world.sweep(pos.*, .{ .min = Vec3.new(-0.4, -0.9, -0.4), .max = Vec3.new(0.4, 0.9, 0.4) }, self.vel.scale(dt), 3);
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
            const scale = @max(0, speed - @max(speed, cfg.speed_stop) * cfg.friction * dt) / speed;
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

        self.cam = rend.Camera3D.init(Vec3.new(8, 40, 8), 0, 0, 60);
        self.world = World.init();

        var verts: [65536]rend.Vertex = undefined;
        var indices: [98304]u16 = undefined;
        const mesh = self.world.buildMesh(&verts, &indices, blockColors);

        self.voxel_pipeline = rend.Renderer.init(verts[0..mesh.vcount], indices[0..mesh.icount], .{ 0.5, 0.7, 0.9, 1 });
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
        .window_title = "Voxel Physics",
        .logger = .{ .func = sokol.log.func },
    });
}
