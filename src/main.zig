const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const ig = @import("cimgui");
const simgui = sokol.imgui;

const math = @import("lib/math.zig");
const io = @import("lib/io.zig");
const audio = @import("lib/audio.zig");

const world = @import("core/world.zig");
const gfx = @import("core/render.zig");
const player = @import("core/player.zig");
const state = @import("core/state.zig");
const shader = @import("shaders/cube.glsl.zig");

const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Vertex = math.Vertex;
const Map = world.Map;
const Player = player.Player;

var verts: [65536]Vertex = undefined;
var indices: [98304]u16 = undefined;
const sky = [4]f32{ 0, 0, 0, 1 };

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

// Global writer buffer for JSON operations
var writer_buffer: [4096]u8 = undefined;

pub const Game = struct {
    vox: gfx.pipeline,
    player: Player,
    world: Map,
    cube_shader: sokol.gfx.Shader,
    audio_system: audio.Audio,
    state: state.State,

    fn init() Game {
        sokol.time.setup();
        sokol.gfx.setup(.{ .environment = sokol.glue.environment(), .logger = .{ .func = sokol.log.func } });
        simgui.setup(.{ .logger = .{ .func = sokol.log.func } });

        const audio_system = audio.Audio.init();

        const sh_desc = shader.cubeShaderDesc(sokol.gfx.queryBackend());
        const sh = sokol.gfx.makeShader(sh_desc);

        const allocator = gpa.allocator();

        var g = Game{
            .player = Player.init(),
            .world = Map.init(), // Start with empty world
            .vox = undefined,
            .cube_shader = sh,
            .audio_system = audio_system,
            .state = state.State.init(allocator),
        };

        // Load state and world data
        g.state.load() catch {};
        g.state.loadWorldData(&g.world) catch {
            // If no state data, try loading from old world.dat
            g.world = Map.load();
        };

        const r = world.Mesh.build(&g.world, &verts, &indices, world.color);
        g.vox = gfx.pipeline.init(verts[0..r.verts], indices[0..r.indices], sky);
        g.vox.shader(sh);
        return g;
    }

    fn run(g: *Game) void {
        const dt = @as(f32, @floatCast(sapp.frameDuration()));

        // State machine tick based on current mode
        const world_changed = switch (g.state.config.local.state) {
            .build => blk: {
                // Build mode: allow block editing
                const changed = player.Input.tick(&g.player, &g.world, dt);
                Player.update.phys(&g.player, &g.world, dt);
                break :blk changed;
            },
            .speedrun => blk: {
                // Speedrun mode: no block editing, just movement
                Player.update.phys(&g.player, &g.world, dt);
                break :blk false;
            },
        };

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
                gfx.UI.render(g.player.block, &g.player.input);
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
        // Save world data to state system
        g.state.saveWorldData(&g.world) catch {};
        g.state.deinit(&writer_buffer);
        g.vox.deinit();
        if (g.cube_shader.id != 0) sokol.gfx.destroyShader(g.cube_shader);
        simgui.shutdown();
        sokol.gfx.shutdown();
        audio.Audio.deinit(); // Deinit audio last
        _ = gpa.deinit();
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

// JS API
export fn map() usize {
    return @intFromPtr(&game.world.blocks);
}
