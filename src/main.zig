const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;

const alg = @import("lib/algebra.zig");
const input = @import("lib/input.zig");
const world = @import("world/map.zig");
const mesh = @import("world/mesh.zig");
const rend = @import("world/render.zig");
const shade = @import("shaders/cube.glsl.zig");

const V = alg.Vec3;
const M = alg.Mat4;
const W = world.World;

const Player = struct {
    pos: V,
    vel: V,
    yaw: f32,
    pitch: f32,
    on_ground: bool,
    crouching: bool,
    io: input.IO,

    const GRAVITY: f32 = 20;
    const JUMP_FORCE: f32 = 8;
    const ACCEL: f32 = 10;
    const FRICTION: f32 = 4;
    const SPEED: f32 = 7;
    const HEIGHT: f32 = 1.8;
    const CROUCH_HEIGHT: f32 = 0.9;

    fn init() Player {
        return .{
            .pos = V.new(32, 40, 32),
            .vel = V.zero(),
            .yaw = 0,
            .pitch = 0,
            .on_ground = false,
            .crouching = false,
            .io = .{},
        };
    }

    fn update(p: *Player, w: *const W, dt: f32) void {
        p.handleInput(w, dt);
        p.updatePhysics(w, dt);
    }

    fn handleInput(p: *Player, w: *const W, dt: f32) void {
        const mv = p.io.vec2(.a, .d, .s, .w);
        var d = V.zero();
        if (mv.x != 0) d = d.add(V.new(@cos(p.yaw), 0, @sin(p.yaw)).scale(mv.x));
        if (mv.y != 0) d = d.add(V.new(@sin(p.yaw), 0, -@cos(p.yaw)).scale(mv.y));
        p.move(d, dt);

        const want_crouch = p.io.shift();
        if (p.crouching and !want_crouch) {
            const test_pos = V.new(p.pos.data[0], p.pos.data[1] + (HEIGHT - CROUCH_HEIGHT) / 2, p.pos.data[2]);
            const r = w.sweep(test_pos, .{ .min = V.new(-0.4, -HEIGHT / 2, -0.4), .max = V.new(0.4, HEIGHT / 2, 0.4) }, V.zero(), 1);
            if (!r.hit) p.pos.data[1] += (HEIGHT - CROUCH_HEIGHT) / 2;
            p.crouching = r.hit;
        } else p.crouching = want_crouch;

        if (p.io.pressed(.space) and p.on_ground) {
            p.vel.data[1] = JUMP_FORCE;
            p.on_ground = false;
        }

        if (p.io.mouse.isLocked()) {
            p.yaw += p.io.mouse.dx * 0.002;
            p.pitch = @max(-1.57, @min(1.57, p.pitch + p.io.mouse.dy * 0.002));
        }
        if (p.io.justPressed(.escape)) p.io.mouse.unlock();
        if (p.io.mouse.left and !p.io.mouse.isLocked()) p.io.mouse.lock();
    }

    fn move(p: *Player, d: V, dt: f32) void {
        const l = @sqrt(d.data[0] * d.data[0] + d.data[2] * d.data[2]);
        if (l < 0.001) return if (p.on_ground) p.applyFriction(dt);
        const w = V.new(d.data[0] / l, 0, d.data[2] / l);
        const ws = SPEED * l;
        const ac = ACCEL * dt;
        const max_add = if (p.on_ground) ws else @min(ws, 0.7);
        const add = max_add - p.vel.dot(w);
        if (add > 0) p.vel = p.vel.add(w.scale(@min(ac * ws, add)));
        if (p.on_ground) p.applyFriction(dt);
    }

    fn updatePhysics(p: *Player, w: *const W, dt: f32) void {
        p.vel.data[1] -= GRAVITY * dt;
        const ht = if (p.crouching) CROUCH_HEIGHT else HEIGHT;
        const r = w.sweep(p.pos, .{ .min = V.new(-0.4, -ht / 2, -0.4), .max = V.new(0.4, ht / 2, 0.4) }, p.vel.scale(dt), 3);
        p.pos = r.pos;
        p.vel = r.vel.scale(1 / dt);
        p.on_ground = r.hit and @abs(r.vel.data[1]) < 0.01;
    }

    fn applyFriction(p: *Player, dt: f32) void {
        const sp = @sqrt(p.vel.data[0] * p.vel.data[0] + p.vel.data[2] * p.vel.data[2]);
        if (sp < 0.1) {
            p.vel.data[0] = 0;
            p.vel.data[2] = 0;
            return;
        }
        const sc = @max(0, sp - @max(sp, 0.1) * FRICTION * dt) / sp;
        p.vel.data[0] *= sc;
        p.vel.data[2] *= sc;
    }

    fn getViewMatrix(p: *Player) M {
        const cy = @cos(p.yaw);
        const sy = @sin(p.yaw);
        const cp = @cos(p.pitch);
        const sp = @sin(p.pitch);
        return .{ .data = .{
            cy,                                       sy * sp,                                                                 -sy * cp,                                                               0,
            0,                                        cp,                                                                      sp,                                                                     0,
            sy,                                       -cy * sp,                                                                cy * cp,                                                                0,
            -p.pos.data[0] * cy - p.pos.data[2] * sy, -p.pos.data[0] * sy * sp - p.pos.data[1] * cp + p.pos.data[2] * cy * sp, p.pos.data[0] * sy * cp - p.pos.data[1] * sp - p.pos.data[2] * cy * cp, 1,
        } };
    }
};

const BLOCK_COLORS = [_][3]f32{
    .{ 0, 0, 0 },
    .{ 0.3, 0.7, 0.3 },
    .{ 0.5, 0.35, 0.2 },
    .{ 0.5, 0.5, 0.5 },
};

fn cols(b: world.Block) [3]f32 {
    return BLOCK_COLORS[@intFromEnum(b)];
}

var static_verts: [65536]rend.Vertex = undefined;
var static_indices: [98304]u16 = undefined;
var static_buffer: [1024]u8 = undefined;

const Game = struct {
    pipe: rend.Renderer,
    vox: rend.Renderer,
    player: Player,
    w: W,
    fba: std.heap.FixedBufferAllocator,

    fn init() Game {
        sokol.gfx.setup(.{
            .environment = sokol.glue.environment(),
            .logger = .{ .func = sokol.log.func },
        });

        var s: Game = undefined;
        s.fba = std.heap.FixedBufferAllocator.init(&static_buffer);

        const ground_verts = [_]rend.Vertex{
            .{ .pos = .{ -100, -1, -100 }, .col = .{ 0.1, 0.1, 0.12, 1 } },
            .{ .pos = .{ 100, -1, -100 }, .col = .{ 0.12, 0.15, 0.18, 1 } },
            .{ .pos = .{ 100, -1, 100 }, .col = .{ 0.15, 0.12, 0.15, 1 } },
            .{ .pos = .{ -100, -1, 100 }, .col = .{ 0.12, 0.12, 0.15, 1 } },
        };
        const ground_indices = [_]u16{ 0, 1, 2, 0, 2, 3 };

        s.pipe = rend.Renderer.init(&ground_verts, &ground_indices, .{ 0.5, 0.7, 0.9, 1 });
        s.player = Player.init();
        s.w = W.init();

        const r = mesh.buildMesh(&s.w, &static_verts, &static_indices, cols);
        s.vox = rend.Renderer.init(static_verts[0..r.vcount], static_indices[0..r.icount], .{ 0.5, 0.7, 0.9, 1 });

        const sh = shade.cubeShaderDesc(sokol.gfx.queryBackend());
        s.pipe.shader(sh);
        s.vox.shader(sh);
        return s;
    }

    fn update(s: *Game) void {
        const dt: f32 = @floatCast(sapp.frameDuration());
        s.player.update(&s.w, dt);
    }

    fn render(s: *Game) void {
        const proj = alg.perspective(60, sapp.widthf() / sapp.heightf(), 0.1, 1000);
        const view = s.player.getViewMatrix();
        const mvp = M.mul(proj, view);

        sokol.gfx.beginPass(.{
            .action = s.pipe.pass,
            .swapchain = sokol.glue.swapchain(),
        });
        s.pipe.draw(mvp);
        s.vox.draw(mvp);
        sokol.gfx.endPass();
        sokol.gfx.commit();
    }

    fn deinit(s: *Game) void {
        s.pipe.deinit();
        s.vox.deinit();
        s.w.deinit();
        sokol.gfx.shutdown();
    }
};

var app: Game = undefined;

export fn init() void {
    app = Game.init();
}
export fn frame() void {
    app.update();
    app.render();
    app.player.io.cleanInput();
}
export fn cleanup() void {
    app.deinit();
}
export fn event(e: [*c]const sapp.Event) void {
    app.player.io.update(e);
}

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
        .window_title = "Voxels",
        .html5_canvas_selector = "canvas",
        .html5_ask_leave_site = false,
        .logger = .{ .func = sokol.log.func },
    });
}
