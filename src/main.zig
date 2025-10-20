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

        pub const reach = 10.0;
        pub const respawn_y = -1.0;
    };

    pub const input = struct {
        pub const lib = struct {
            pub fn lookdir(p: *const Player) Vec3 {
                return Vec3.new(@sin(p.yaw) * @cos(p.pitch), -@sin(p.pitch), -@cos(p.yaw) * @cos(p.pitch));
            }

            pub fn bbox(p: *const Player) AABB {
                const h: f32 = if (p.crouch) Game.cfg.size.crouch else Game.cfg.size.stand;
                const w: f32 = Game.cfg.size.width;
                return AABB{
                    .min = p.pos.add(Vec3.new(-w, -h / 2.0, -w)),
                    .max = p.pos.add(Vec3.new(w, h / 2.0, w)),
                };
            }

            pub fn standbox(pos: Vec3) AABB {
                const w = Game.cfg.size.width;
                const h = Game.cfg.size.stand;
                const box = AABB{
                    .min = Vec3.new(-w, -h / 2.0, -w),
                    .max = Vec3.new(w, h / 2.0, w),
                };
                return box.at(pos);
            }

            pub fn blockbox(pos: Vec3) AABB {
                return AABB{
                    .min = pos,
                    .max = pos.add(Vec3.new(1, 1, 1)),
                };
            }
        };

        pub const handle = struct {
            pub fn movement(g: *Game, dt: f32) void {
                const p = &g.player;
                const mv = p.io.vec2(.a, .d, .s, .w);
                var dir = Vec3.zero();
                if (mv.x != 0) dir = dir.add(Vec3.new(@cos(p.yaw), 0, @sin(p.yaw)).scale(mv.x));
                if (mv.y != 0) dir = dir.add(Vec3.new(@sin(p.yaw), 0, -@cos(p.yaw)).scale(mv.y));
                Player.update.pos(p, Game.cfg, dir, dt);
            }

            pub fn crouch(g: *Game) void {
                const p = &g.player;
                const wish = p.io.shift();

                if (p.crouch and !wish) {
                    const diff = (Game.cfg.size.stand - Game.cfg.size.crouch) / 2.0;
                    const test_pos = Vec3.new(p.pos.data[0], p.pos.data[1] + diff, p.pos.data[2]);
                    const standing = Game.input.lib.standbox(test_pos);

                    if (!player.checkStaticCollision(&g.world, standing)) {
                        p.pos.data[1] += diff;
                        p.crouch = false;
                    }
                } else {
                    p.crouch = wish;
                }
            }

            pub fn jump(g: *Game) void {
                const p = &g.player;
                if (p.io.pressed(.space) and p.ground) {
                    p.vel.data[1] = Game.cfg.jump.power;
                    p.ground = false;
                }
            }

            pub fn camera(g: *Game) void {
                const p = &g.player;
                if (!p.io.mouse.locked()) return;

                p.yaw += p.io.mouse.dx * Game.cfg.input.sens;
                p.pitch = @max(-Game.cfg.input.pitch_limit, @min(Game.cfg.input.pitch_limit, p.pitch + p.io.mouse.dy * Game.cfg.input.sens));
            }

            pub fn blocks(g: *Game) bool {
                const p = &g.player;
                if (!p.io.mouse.locked()) return false;

                const look = Game.input.lib.lookdir(p);
                const hit = player.raycast(&g.world, p.pos, look, Game.cfg.reach) orelse return false;
                const pos = [3]i32{
                    @intFromFloat(@floor(hit.data[0])),
                    @intFromFloat(@floor(hit.data[1])),
                    @intFromFloat(@floor(hit.data[2])),
                };

                // Break block
                if (p.io.mouse.leftPressed()) {
                    return g.world.set(pos[0], pos[1], pos[2], 0);
                }

                // Place block
                if (p.io.mouse.rightPressed()) {
                    const prev = hit.sub(look.scale(0.1));
                    const place_pos = [3]i32{
                        @intFromFloat(@floor(prev.data[0])),
                        @intFromFloat(@floor(prev.data[1])),
                        @intFromFloat(@floor(prev.data[2])),
                    };
                    const block_pos = Vec3.new(@floatFromInt(place_pos[0]), @floatFromInt(place_pos[1]), @floatFromInt(place_pos[2]));

                    const player_box = Game.input.lib.bbox(p);
                    const block_box = Game.input.lib.blockbox(block_pos);

                    if (!AABB.overlaps(player_box, block_box)) {
                        return g.world.set(place_pos[0], place_pos[1], place_pos[2], p.block);
                    }
                }

                // Pick block color
                if (p.io.justPressed(.r)) {
                    const target = g.world.get(pos[0], pos[1], pos[2]);
                    if (target != 0) p.block = target;
                }

                return false;
            }

            pub fn color(g: *Game) void {
                const p = &g.player;
                if (!p.io.mouse.locked()) return;

                if (p.io.justPressed(.q)) p.block -%= 1;
                if (p.io.justPressed(.e)) p.block +%= 1;
            }

            pub fn mouse(g: *Game) void {
                const p = &g.player;
                if (p.io.justPressed(.escape)) p.io.mouse.unlock();
                if (p.io.mouse.left and !p.io.mouse.locked()) p.io.mouse.lock();
            }
        };

        pub fn tick(g: *Game, dt: f32) bool {
            Game.input.handle.movement(g, dt);
            Game.input.handle.crouch(g);
            Game.input.handle.jump(g);
            Game.input.handle.camera(g);
            const world_changed = Game.input.handle.blocks(g);
            Game.input.handle.color(g);
            Game.input.handle.mouse(g);
            return world_changed;
        }
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
        const world_changed = Game.input.tick(g, dt);
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
