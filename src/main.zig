const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const ig = @import("cimgui");
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

var verts: [65536]gfx.Vertex = undefined;
var indices: [98304]u16 = undefined;
const sky = [4]f32{ 0.5, 0.7, 0.9, 1 };

const Game = struct {
    vox: gfx.Render,
    player: Player,
    world: World,
    mesh_dirty: bool,
    cube_shader: sokol.gfx.Shader,

    fn init() Game {
        sokol.gfx.setup(.{ .environment = sokol.glue.environment(), .logger = .{ .func = sokol.log.func } });
        simgui.setup(.{ .logger = .{ .func = sokol.log.func } });

        const sh_desc = shader.cubeShaderDesc(sokol.gfx.queryBackend());
        const sh = sokol.gfx.makeShader(sh_desc);
        var g = Game{ .player = Player.init(), .world = World.load(), .vox = undefined, .mesh_dirty = false, .cube_shader = sh };

        const r = g.world.mesh(&verts, &indices, World.color);
        g.vox = gfx.Render.init(verts[0..r.verts], indices[0..r.indices], sky);
        g.vox.shaderFromHandle(sh);
        return g;
    }

    fn tick(g: *Game) void {
        const world_changed = g.player.tick(&g.world, @floatCast(sapp.frameDuration()));
        if (world_changed) {
            g.mesh_dirty = true;
        }

        if (g.mesh_dirty) {
            g.regenerateMesh();
            g.mesh_dirty = false;
        }
    }

    fn draw(g: *Game) void {
        simgui.newFrame(.{ .width = sapp.width(), .height = sapp.height(), .delta_time = sapp.frameDuration(), .dpi_scale = sapp.dpiScale() });
        g.player.drawUI();
        const mvp = Mat4.mul(math.perspective(90, sapp.widthf() / sapp.heightf(), 0.1, 1000), g.player.view());
        sokol.gfx.beginPass(.{ .action = g.vox.pass, .swapchain = sokol.glue.swapchain() });
        g.vox.draw(mvp);
        simgui.render();
        sokol.gfx.endPass();
        sokol.gfx.commit();
    }

    fn regenerateMesh(g: *Game) void {
        g.vox.deinit();
        const r = g.world.mesh(&verts, &indices, World.color);
        g.vox = gfx.Render.init(verts[0..r.verts], indices[0..r.indices], sky);
        g.vox.shaderFromHandle(g.cube_shader);
    }

    fn deinit(g: *Game) void {
        g.world.save();
        g.vox.deinit();
        if (g.cube_shader.id != 0) sokol.gfx.destroyShader(g.cube_shader);
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
