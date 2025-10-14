// main.zig
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
    grounded: bool = false,

    const gravity: f32 = 20.0;
    const jump_force: f32 = 8.0;
    const stop_speed: f32 = 1.0;

    // Ground movement
    const ground_accel: f32 = 10.0;
    const ground_friction: f32 = 6.0;
    const max_speed: f32 = 7.0;

    // Air movement (uses same accelerate function, different wishspeed cap)
    const air_accel: f32 = 1.0;
    const air_speed_cap: f32 = 0.4;  // CPM caps wishspeed in air to 30 (scaled to our units)

    pub fn jump(self: *Physics) void {
        self.vel.data[1] = jump_force;
        self.grounded = false;
    }

    fn applyFriction(self: *Physics, dt: f32) void {
        if (!self.grounded) return;

        const speed = @sqrt(self.vel.x() * self.vel.x() + self.vel.z() * self.vel.z());
        if (speed < 0.1) {
            self.vel.data[0] = 0;
            self.vel.data[2] = 0;
            return;
        }

        // Use stop_speed as control threshold
        const control = if (speed < stop_speed) stop_speed else speed;
        const drop = control * ground_friction * dt;
        const newspeed = @max(0, speed - drop);

        if (newspeed != speed) {
            const scale = newspeed / speed;
            self.vel.data[0] *= scale;
            self.vel.data[2] *= scale;
        }
    }

    fn accelerate(self: *Physics, wishdir: Vec3, wishspeed: f32, accel: f32, dt: f32) void {
        // PM_Accelerate from the paper
        const currentspeed = self.vel.dot(wishdir);
        const addspeed = wishspeed - currentspeed;
        if (addspeed <= 0) return;

        const accelspeed = @min(accel * dt * wishspeed, addspeed);
        self.vel = self.vel.add(wishdir.scale(accelspeed));
    }

    pub fn move(self: *Physics, wishdir: Vec3, dt: f32) void {
        const len = @sqrt(wishdir.x() * wishdir.x() + wishdir.z() * wishdir.z());
        if (len < 0.0001) {
            if (self.grounded) self.applyFriction(dt);
            return;
        }

        // Normalize direction
        const dir = Vec3.new(wishdir.x() / len, 0, wishdir.z() / len);
        var wishspeed = max_speed * len;

        if (self.grounded) {
            // Ground movement
            self.applyFriction(dt);
            // Clamp to max speed
            if (wishspeed > max_speed) {
                wishspeed = max_speed;
            }
            self.accelerate(dir, wishspeed, ground_accel, dt);
        } else {
            // Air movement - CPM style caps wishspeed instead of using different function
            // From paper: "wishspeed is restricted to being within the bounds of 0 to 30"
            const capped_wishspeed = @min(wishspeed, air_speed_cap);
            self.accelerate(dir, capped_wishspeed, air_accel, dt);
        }
    }

    pub fn update(self: *Physics, pos: *Vec3, world: *bsp.BSP, dt: f32) void {
        self.vel.data[1] -= gravity * dt;

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
    buffer: [64 * 1024]u8 = undefined,
    fba: std.heap.FixedBufferAllocator = undefined,

    fn init() !App {
        const v = [_]rend.Vertex{
            .{ .pos = .{ -20, -1, -20 }, .col = .{ 0.2, 0.2, 0.25, 1 } },
            .{ .pos = .{ 20, -1, -20 }, .col = .{ 0.25, 0.3, 0.35, 1 } },
            .{ .pos = .{ 20, -1, 20 }, .col = .{ 0.3, 0.25, 0.3, 1 } },
            .{ .pos = .{ -20, -1, 20 }, .col = .{ 0.25, 0.25, 0.3, 1 } },
        };
        const i = [_]u16{ 0, 1, 2, 0, 2, 3 };

        var self: App = undefined;
        self.buffer = undefined;
        self.fba = std.heap.FixedBufferAllocator.init(&self.buffer);
        const allocator = self.fba.allocator();

        self.pipeline = rend.Renderer.init(&v, &i, .{ 0.1, 0.1, 0.15, 1 });
        self.cam = rend.Camera3D.init(Vec3.new(0, 2, 0), 0, 0, 60);
        self.world = try bsp.BSP.init(
            allocator,
            bsp.AABB.new(Vec3.new(-50, -10, -50), Vec3.new(50, 0, 50)),
            3,
        );
        self.io = .{};
        self.phys = .{};

        self.pipeline.shader(shade.cubeShaderDesc(sokol.gfx.queryBackend()));
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
        const mvp = Mat4.mul(Mat4.mul(
            self.cam.projectionMatrix(sapp.widthf() / sapp.heightf(), 0.1, 1000),
            self.cam.viewMatrix(),
        ), Mat4.identity());
        self.pipeline.draw(mvp);
    }

    fn deinit(self: *App) void {
        self.pipeline.deinit();
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
        .window_title = "BSP Physics",
        .logger = .{ .func = sokol.log.func },
    });
}
