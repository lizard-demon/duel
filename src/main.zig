const sokol = @import("sokol");
const sapp = sokol.app;
const input = @import("lib/io/input.zig");
const octree = @import("lib/world/octree.zig");
const mesh = @import("lib/world/mesh.zig");
const rend = @import("lib/world/render.zig");
const alg = @import("lib/math/algebra.zig");
const physics = @import("lib/player/physics.zig");

const V = alg.Vec3;
const M = alg.Mat4;
const W = octree.Octree(6);
const shade = @import("shaders/cube.glsl.zig");

fn cols(b: octree.Block) [3]f32 {
    return switch (b) {
        .grass => .{ 0.3, 0.7, 0.3 },
        .dirt => .{ 0.5, 0.35, 0.2 },
        .stone => .{ 0.5, 0.5, 0.5 },
        .air => unreachable,
    };
}

const App = struct {
    pipe: rend.Renderer,
    vox: rend.Renderer,
    cam: rend.Camera3D,
    io: input.IO = .{},
    p: physics.Physics(20, 8, 10, 4, 7, 1.8, 0.9) = .{},
    w: W,

    fn init() !App {
        var s: App = undefined;
        s.pipe = rend.Renderer.init(&[_]rend.Vertex{
            .{ .pos = .{ -100, -1, -100 }, .col = .{ 0.1, 0.1, 0.12, 1 } },
            .{ .pos = .{ 100, -1, -100 }, .col = .{ 0.12, 0.15, 0.18, 1 } },
            .{ .pos = .{ 100, -1, 100 }, .col = .{ 0.15, 0.12, 0.15, 1 } },
            .{ .pos = .{ -100, -1, 100 }, .col = .{ 0.12, 0.12, 0.15, 1 } },
        }, &[_]u16{ 0, 1, 2, 0, 2, 3 }, .{ 0.5, 0.7, 0.9, 1 });
        s.cam = rend.Camera3D.init(V.new(32, 40, 32), 0, 0, 90);
        s.w = W.init();

        var verts: [65536]rend.Vertex = undefined;
        var indices: [98304]u16 = undefined;
        const r = mesh.buildMesh(&s.w, &verts, &indices, cols);
        s.vox = rend.Renderer.init(verts[0..r.vcount], indices[0..r.icount], .{ 0.5, 0.7, 0.9, 1 });

        const sh = shade.cubeShaderDesc(sokol.gfx.queryBackend());
        s.pipe.shader(sh);
        s.vox.shader(sh);
        return s;
    }

    fn update(s: *App) void {
        const dt: f32 = @floatCast(sapp.frameDuration());
        const mv = s.io.vec2(.a, .d, .s, .w);
        var d = V.zero();
        if (mv.x != 0) d = d.add(V.new(s.cam.right().x(), 0, s.cam.right().z()).scale(mv.x));
        if (mv.y != 0) d = d.add(V.new(s.cam.forward().x(), 0, s.cam.forward().z()).scale(mv.y));
        s.p.move(d, dt);
        s.p.crouch(&s.cam.position, &s.w, s.io.shift());
        if (s.io.pressed(.space) and s.p.on) s.p.jump();
        s.p.update(&s.cam.position, &s.w, dt);
        if (s.io.mouse.isLocked()) s.cam.look(s.io.mouse.dx * 0.002, -s.io.mouse.dy * 0.002);
        if (s.io.justPressed(.escape)) s.io.mouse.unlock();
        if (s.io.mouse.left and !s.io.mouse.isLocked()) s.io.mouse.lock();
    }

    fn render(s: *App) void {
        const mvp = M.mul(M.mul(s.cam.projectionMatrix(sapp.widthf() / sapp.heightf(), 0.1, 1000), s.cam.viewMatrix()), M.identity());
        s.pipe.draw(mvp);
        s.vox.draw(mvp);
    }

    fn deinit(s: *App) void {
        s.pipe.deinit();
        s.vox.deinit();
        s.w.deinit();
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
