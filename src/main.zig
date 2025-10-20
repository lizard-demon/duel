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
const Vertex = math.Vertex;
const Map = world.Map;
const Player = player.Player;
const AABB = player.AABB;

var verts: [65536]Vertex = undefined;
var indices: [98304]u16 = undefined;
const sky = [4]f32{ 0.5, 0.7, 0.9, 1 };

const Game = struct {
    vox: gfx.pipeline,
    player: Player,
    world: Map,
    mesh_dirty: bool,
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

        pub const reach = 5.0;
        pub const respawn_y = -1.0;
    };

    fn init() Game {
        sokol.gfx.setup(.{ .environment = sokol.glue.environment(), .logger = .{ .func = sokol.log.func } });
        simgui.setup(.{ .logger = .{ .func = sokol.log.func } });

        const sh_desc = shader.cubeShaderDesc(sokol.gfx.queryBackend());
        const sh = sokol.gfx.makeShader(sh_desc);
        var g = Game{ .player = Player.spawn(Game.cfg.spawn.x, Game.cfg.spawn.y, Game.cfg.spawn.z), .world = Map.load(), .vox = undefined, .mesh_dirty = false, .cube_shader = sh };

        const r = world.Mesh.build(&g.world, &verts, &indices, world.color);
        g.vox = gfx.pipeline.init(verts[0..r.verts], indices[0..r.indices], sky);
        g.vox.shader(sh);
        return g;
    }

    fn tick(g: *Game) void {
        const dt = @as(f32, @floatCast(sapp.frameDuration()));
        const world_changed = g.input(dt);
        Player.update.phys(&g.player, Game.cfg, &g.world, dt);

        if (world_changed) {
            g.mesh_dirty = true;
        }

        if (g.mesh_dirty) {
            g.mesh();
            g.mesh_dirty = false;
        }
    }

    fn draw(g: *Game) void {
        simgui.newFrame(.{ .width = sapp.width(), .height = sapp.height(), .delta_time = sapp.frameDuration(), .dpi_scale = sapp.dpiScale() });
        gfx.UI.render(g.player.block);
        const mvp = Mat4.mul(math.perspective(90, sapp.widthf() / sapp.heightf(), 0.1, 1000), g.player.view());
        sokol.gfx.beginPass(.{ .action = g.vox.pass, .swapchain = sokol.glue.swapchain() });
        g.vox.draw(mvp);
        simgui.render();
        sokol.gfx.endPass();
        sokol.gfx.commit();
    }

    fn mesh(g: *Game) void {
        g.vox.deinit();
        const r = world.Mesh.build(&g.world, &verts, &indices, world.color);
        g.vox = gfx.pipeline.init(verts[0..r.verts], indices[0..r.indices], sky);
        g.vox.shader(g.cube_shader);
    }

    fn input(g: *Game, dt: f32) bool {
        var world_changed = false;
        const p = &g.player;
        const w = &g.world;

        const mv = p.io.vec2(.a, .d, .s, .w);
        var dir = Vec3.zero();
        if (mv.x != 0) dir = dir.add(Vec3.new(@cos(p.yaw), 0, @sin(p.yaw)).scale(mv.x));
        if (mv.y != 0) dir = dir.add(Vec3.new(@sin(p.yaw), 0, -@cos(p.yaw)).scale(mv.y));
        Player.update.pos(p, Game.cfg, dir, dt);

        const wish = p.io.shift();
        if (p.crouch and !wish) {
            // Calculate the height difference between crouching and standing
            const diff: f32 = (Game.cfg.size.stand - Game.cfg.size.crouch) / 2.0;

            // Calculate where the player would be positioned when standing
            const test_pos = Vec3.new(p.pos.data[0], p.pos.data[1] + diff, p.pos.data[2]);

            // Create the standing hitbox at the test position
            const standing_box = AABB{ .min = Vec3.new(-Game.cfg.size.width, -Game.cfg.size.stand / 2.0, -Game.cfg.size.width), .max = Vec3.new(Game.cfg.size.width, Game.cfg.size.stand / 2.0, Game.cfg.size.width) };

            // Check for static collision by testing the bounding box against world blocks
            const player_aabb = standing_box.at(test_pos);
            const collision = player.checkStaticCollision(w, player_aabb);

            // Only uncrouch if there's no collision
            if (!collision) {
                p.pos.data[1] += diff;
                p.crouch = false;
            }
            // If collision detected, remain crouched
        } else {
            p.crouch = wish;
        }

        if (p.io.pressed(.space) and p.ground) {
            p.vel.data[1] = Game.cfg.jump.power;
            p.ground = false;
        }

        if (p.io.mouse.locked()) {
            p.yaw += p.io.mouse.dx * Game.cfg.input.sens;
            p.pitch = @max(-Game.cfg.input.pitch_limit, @min(Game.cfg.input.pitch_limit, p.pitch + p.io.mouse.dy * Game.cfg.input.sens));

            // Block interactions
            const look = Vec3.new(@sin(p.yaw) * @cos(p.pitch), -@sin(p.pitch), -@cos(p.yaw) * @cos(p.pitch));
            if (player.raycast(w, p.pos, look, Game.cfg.reach)) |hit| {
                const pos = [3]i32{ @intFromFloat(@floor(hit.data[0])), @intFromFloat(@floor(hit.data[1])), @intFromFloat(@floor(hit.data[2])) };

                if (p.io.mouse.leftPressed() and w.set(pos[0], pos[1], pos[2], 0)) {
                    world_changed = true;
                } else if (p.io.mouse.rightPressed()) {
                    const prev = hit.sub(look.scale(0.1));
                    const place_pos = [3]i32{ @intFromFloat(@floor(prev.data[0])), @intFromFloat(@floor(prev.data[1])), @intFromFloat(@floor(prev.data[2])) };
                    const block_pos = Vec3.new(@floatFromInt(place_pos[0]), @floatFromInt(place_pos[1]), @floatFromInt(place_pos[2]));
                    const h: f32 = if (p.crouch) Game.cfg.size.crouch else Game.cfg.size.stand;
                    const player_box = AABB{ .min = p.pos.add(Vec3.new(-Game.cfg.size.width, -h / 2.0, -Game.cfg.size.width)), .max = p.pos.add(Vec3.new(Game.cfg.size.width, h / 2.0, Game.cfg.size.width)) };
                    const block_box = AABB{ .min = block_pos, .max = block_pos.add(Vec3.new(1, 1, 1)) };
                    const overlaps = AABB.overlaps(player_box, block_box);
                    if (!overlaps and w.set(place_pos[0], place_pos[1], place_pos[2], p.block)) {
                        world_changed = true;
                    }
                }
            }

            // Color selection with Q and E keys
            if (p.io.justPressed(.q)) {
                p.block = p.block -% 1;
            }
            if (p.io.justPressed(.e)) {
                p.block = p.block +% 1;
            }

            // Grab block color with R key
            if (p.io.justPressed(.r)) {
                if (player.raycast(w, p.pos, look, Game.cfg.reach)) |hit| {
                    const pos = [3]i32{ @intFromFloat(@floor(hit.data[0])), @intFromFloat(@floor(hit.data[1])), @intFromFloat(@floor(hit.data[2])) };
                    const target_block = w.get(pos[0], pos[1], pos[2]);
                    if (target_block != 0) p.block = target_block;
                }
            }
        }
        if (p.io.justPressed(.escape)) p.io.mouse.unlock();
        if (p.io.mouse.left and !p.io.mouse.locked()) p.io.mouse.lock();

        return world_changed;
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
