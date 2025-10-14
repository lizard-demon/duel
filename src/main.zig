// Main.zig
const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;

const input = @import("lib/input.zig");
const rend = @import("lib/render.zig");
const alg = @import("lib/algebra.zig");
const bsp = @import("lib/bsp.zig");
const Vec3 = alg.Vec3;
const Mat4 = alg.Mat4;

const shade = @import("shaders/cube.glsl.zig");

const Physics = struct {
    vel: Vec3 = Vec3.zero(),
    gravity: f32 = 9.8,
    grounded: bool = false,

    pub fn jump(self: *Physics, force: f32) void {
        self.vel.data[1] = force;
        self.grounded = false;
    }

    pub fn accel(self: *Physics, wishdir: Vec3, speed: f32, dt: f32) void {
        self.vel = self.vel.add(wishdir.norm().scale(speed * dt));
    }

    fn grav(self: *Physics, dt: f32) void {
        self.vel.data[1] -= self.gravity * dt;
    }

    fn friction(self: *Physics, amount: f32, dt: f32) void {
        if (self.grounded) {
            const xz = Vec3.new(self.vel.x(), 0, self.vel.z());
            const damped = xz.scale(1.0 - amount * dt);
            self.vel.data[0] = damped.x();
            self.vel.data[2] = damped.z();
        }
    }

    pub fn update(self: *Physics, pos: *Vec3, world: *bsp.BSP, dt: f32) void {
        self.grav(dt);
        self.friction(8.0, dt);

        const box = bsp.AABB.new(Vec3.new(-0.4, -0.9, -0.4), Vec3.new(0.4, 0.9, 0.4));
        const result = world.trace(pos.*, box, self.vel.scale(dt));

        if (result.hit) {
            pos.* = result.pos;
            self.vel = result.vel.scale(1.0 / dt);
            self.grounded = @abs(result.vel.y()) < 0.01;
        } else {
            pos.* = pos.add(self.vel.scale(dt));
            self.grounded = false;
        }
    }
};

const App = struct {
    pipeline: rend.Renderer,
    cam: rend.Camera3D,
    io: input.IO = .{},
    phys: Physics = .{},
    world: bsp.BSP,

    fn init() !App {
        const v = [_]rend.Vertex{
            .{ .pos = .{ -20, -1, -20 }, .col = .{ 0.2, 0.2, 0.25, 1 } },
            .{ .pos = .{  20, -1, -20 }, .col = .{ 0.25, 0.3, 0.35, 1 } },
            .{ .pos = .{  20, -1,  20 }, .col = .{ 0.3, 0.25, 0.3, 1 } },
            .{ .pos = .{ -20, -1,  20 }, .col = .{ 0.25, 0.25, 0.3, 1 } },
        };
        const i = [_]u16{ 0, 1, 2, 0, 2, 3 };

        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();

        var self = App{
            .pipeline = rend.Renderer.init(&v, &i, .{ 0.1, 0.1, 0.15, 1 }),
            .cam = rend.Camera3D.init(Vec3.new(0, 2, 0), 0, 0, 60),
            .world = try bsp.BSP.init(
                allocator,
                bsp.AABB.new(Vec3.new(-50, -10, -50), Vec3.new(50, 0, 50)),
                3
            ),
        };
        self.pipeline.shader(shade.cubeShaderDesc(sokol.gfx.queryBackend()));
        return self;
    }

    fn update(self: *App) void {
        const dt: f32 = @floatCast(sapp.frameDuration());
        const mv = self.io.vec2(.a, .d, .s, .w);
        var dir = Vec3.zero();

        if (mv.x != 0) {
            const right = self.cam.right();
            dir = dir.add(Vec3.new(right.x(), 0, right.z()).norm().scale(mv.x));
        }
        if (mv.y != 0) {
            const fwd = self.cam.forward();
            dir = dir.add(Vec3.new(fwd.x(), 0, fwd.z()).norm().scale(mv.y));
        }

        if (dir.length() > 0) self.phys.accel(dir, 5, dt);
        if (self.io.pressed(.space) and self.phys.grounded) self.phys.jump(5);
        self.phys.update(&self.cam.position, &self.world, dt);

        if (self.io.mouse.isLocked())
            self.cam.look(self.io.mouse.dx * 0.002, -self.io.mouse.dy * 0.002);
        if (self.io.justPressed(.escape)) self.io.mouse.unlock();
        if (self.io.mouse.left and !self.io.mouse.isLocked()) self.io.mouse.lock();
    }

    fn render(self: *App) void {
        const mvp = Mat4.mul(
            Mat4.mul(
                self.cam.projectionMatrix(sapp.widthf() / sapp.heightf(), 0.1, 1000),
                self.cam.viewMatrix()
            ),
            Mat4.identity()
        );
        self.pipeline.draw(mvp);
    }

    fn deinit(self: *App) void {
        self.pipeline.deinit();
        self.world.deinit();
    }
};

var app: App = undefined;
export fn init() void                           { app = App.init() catch unreachable; }
export fn frame() void                          { app.update(); app.render(); app.io.cleanInput(); }
export fn cleanup() void                        { app.deinit(); }
export fn event(e: [*c]const sapp.Event) void   { app.io.update(e); }

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .width = 800, .height = 600,
        .sample_count = 4,
        .icon = .{ .sokol_default = true },
        .window_title = "BSP Physics",
        .logger = .{ .func = sokol.log.func },
    });
}
