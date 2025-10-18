const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const use_docking = @import("build_options").docking;
const ig = if (use_docking) @import("cimgui_docking") else @import("cimgui");
const simgui = sokol.imgui;

const math = @import("lib/math.zig");
const io = @import("lib/io.zig");
const world = @import("core/world.zig");
const gfx = @import("core/render.zig");
const player = @import("core/player.zig");
const shader = @import("shaders/cube.glsl.zig");

const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const World = world.World;
const Player = player.Player;
const Weapon = player.Weapon;

var verts: [65536]gfx.Vertex = undefined;
var indices: [98304]u16 = undefined;
var buf: [1024]u8 = undefined;

const Game = struct {
    pipe: gfx.Render,
    vox: gfx.Render,
    player: Player,
    world: World,
    alloc: std.heap.FixedBufferAllocator,

    fn init() Game {
        sokol.gfx.setup(.{ .environment = sokol.glue.environment(), .logger = .{ .func = sokol.log.func } });
        simgui.setup(.{ .logger = .{ .func = sokol.log.func } });
        if (use_docking) ig.igGetIO().*.ConfigFlags |= ig.ImGuiConfigFlags_DockingEnable;

        const gv = [_]gfx.Vertex{ .{ .pos = .{ -100, -1, -100 }, .col = .{ 0.1, 0.1, 0.12, 1 } }, .{ .pos = .{ 100, -1, -100 }, .col = .{ 0.12, 0.15, 0.18, 1 } }, .{ .pos = .{ 100, -1, 100 }, .col = .{ 0.15, 0.12, 0.15, 1 } }, .{ .pos = .{ -100, -1, 100 }, .col = .{ 0.12, 0.12, 0.15, 1 } } };
        const gi = [_]u16{ 0, 1, 2, 0, 2, 3 };
        const sky = [4]f32{ 0.5, 0.7, 0.9, 1 };

        var g = Game{ .pipe = gfx.Render.init(&gv, &gi, sky), .player = Player.init(), .world = World.init(), .vox = undefined, .alloc = std.heap.FixedBufferAllocator.init(&buf) };

        const r = g.world.mesh(&verts, &indices, World.color);
        g.vox = gfx.Render.init(verts[0..r.verts], indices[0..r.indices], sky);
        const sh = shader.cubeShaderDesc(sokol.gfx.queryBackend());
        g.pipe.shader(sh);
        g.vox.shader(sh);
        return g;
    }

    fn tick(g: *Game) void {
        g.player.tick(&g.world, @floatCast(sapp.frameDuration()));
    }

    fn draw(g: *Game) void {
        simgui.newFrame(.{ .width = sapp.width(), .height = sapp.height(), .delta_time = sapp.frameDuration(), .dpi_scale = sapp.dpiScale() });
        g.player.drawUI();
        const mvp = Mat4.mul(math.perspective(90, sapp.widthf() / sapp.heightf(), 0.1, 1000), g.player.view());
        sokol.gfx.beginPass(.{ .action = g.pipe.pass, .swapchain = sokol.glue.swapchain() });
        g.pipe.draw(mvp);
        g.vox.draw(mvp);
        simgui.render();
        sokol.gfx.endPass();
        sokol.gfx.commit();
    }

    fn deinit(g: *Game) void {
        g.pipe.deinit();
        g.vox.deinit();
        g.world.deinit();
        simgui.shutdown();
        sokol.gfx.shutdown();
    }
};

var game: Game = undefined;
export fn init() void {
    game = Game.init();
}
export fn frame() void {
    game.tick();
    game.draw();
    game.player.io.clean();
}
export fn cleanup() void {
    game.deinit();
}
export fn event(e: [*c]const sapp.Event) void {
    _ = simgui.handleEvent(e.*);
    game.player.io.tick(e);
}

pub fn main() void {
    sapp.run(.{ .init_cb = init, .frame_cb = frame, .cleanup_cb = cleanup, .event_cb = event, .width = 800, .height = 600, .sample_count = 4, .icon = .{ .sokol_default = true }, .window_title = "Voxels", .html5_canvas_selector = "canvas", .html5_ask_leave_site = false, .logger = .{ .func = sokol.log.func } });
}
