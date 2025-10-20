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
const input = @import("input.zig");

const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Vertex = math.Vertex;
const Map = world.Map;
const Player = player.Player;
const AABB = player.AABB;

var verts: [65536]Vertex = undefined;
var indices: [98304]u16 = undefined;
const sky = [4]f32{ 0.5, 0.7, 0.9, 1 };

pub const Game = struct {
    vox: gfx.pipeline,
    player: Player,
    world: Map,
    cube_shader: sokol.gfx.Shader,

    pub const cfg = struct {
        pub const spawn = struct {
            pub const x = 58.0;
            pub const y = 3.0;
            pub const z = 58.0;
        };
        pub const input = struct {
            pub const sens = 0.002;
            pub const pitch_limit = 1.57;
        };
        pub const size = struct {
            pub const stand = 1.8;
            pub const crouch = 0.9;
            pub const width = 0.4;
        };
        pub const move = struct {
            pub const speed = 6.0;
            pub const crouch_speed = speed / 2.0;
            pub const air_cap = 0.7;
            pub const accel = 70.0;
            pub const min_len = 0.001;
        };
        pub const phys = struct {
            pub const gravity = 20.0;
            pub const steps = 3;
            pub const ground_thresh = 0.01;
        };
        pub const friction = struct {
            pub const min_speed = 0.1;
            pub const factor = 4.0;
        };
        pub const jump = struct {
            pub const power = 8.0;
        };

        pub const reach = 10.0;
        pub const respawn_y = -1.0;
    };

    fn init() Game {
        sokol.gfx.setup(.{ .environment = sokol.glue.environment(), .logger = .{ .func = sokol.log.func } });
        simgui.setup(.{ .logger = .{ .func = sokol.log.func } });

        const sh_desc = shader.cubeShaderDesc(sokol.gfx.queryBackend());
        const sh = sokol.gfx.makeShader(sh_desc);
        var g = Game{ .player = Player.spawn(Game.cfg.spawn.x, Game.cfg.spawn.y, Game.cfg.spawn.z), .world = Map.load(), .vox = undefined, .cube_shader = sh };

        const r = world.Mesh.build(&g.world, &verts, &indices, world.color);
        g.vox = gfx.pipeline.init(verts[0..r.verts], indices[0..r.indices], sky);
        g.vox.shader(sh);
        return g;
    }

    fn run(g: *Game) void {
        const dt = @as(f32, @floatCast(sapp.frameDuration()));
        const input_cfg = input.Config{
            .sensitivity = Game.cfg.input.sens,
            .pitch_limit = Game.cfg.input.pitch_limit,
            .stand_height = Game.cfg.size.stand,
            .crouch_height = Game.cfg.size.crouch,
            .width = Game.cfg.size.width,
            .jump_power = Game.cfg.jump.power,
            .reach = Game.cfg.reach,
        };
        const world_changed = input.tick(&g.player, &g.world, dt, input_cfg, Game.cfg);
        Player.update.phys(&g.player, Game.cfg, &g.world, dt);

        frame: switch (world_changed) {
            true => {
                // Rebuild mesh and draw
                g.vox.deinit();
                const r = world.Mesh.build(&g.world, &verts, &indices, world.color);
                g.vox = gfx.pipeline.init(verts[0..r.verts], indices[0..r.indices], sky);
                g.vox.shader(g.cube_shader);
                continue :frame false;
            },
            false => {
                // Just draw
                simgui.newFrame(.{ .width = sapp.width(), .height = sapp.height(), .delta_time = sapp.frameDuration(), .dpi_scale = sapp.dpiScale() });
                gfx.UI.render(g.player.block);
                const mvp = Mat4.mul(math.perspective(90, sapp.widthf() / sapp.heightf(), 0.1, 1000), g.player.view());
                sokol.gfx.beginPass(.{ .action = g.vox.pass, .swapchain = sokol.glue.swapchain() });
                g.vox.draw(mvp);
                simgui.render();
                sokol.gfx.endPass();
                sokol.gfx.commit();
            },
        }
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
    game.run();
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
