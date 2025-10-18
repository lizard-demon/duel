const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const use_docking = @import("build_options").docking;
const ig = if (use_docking) @import("cimgui_docking") else @import("cimgui");
const simgui = sokol.imgui;

const math = @import("lib/math.zig");
const io = @import("lib/io.zig");
const world = @import("world/world.zig");
const mesh = @import("world/mesh.zig");
const gfx = @import("world/draw.zig");
const shader = @import("shaders/cube.glsl.zig");

const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const World = world.World;

const Weapon = struct {
    charge: f32 = 0,
    cool: f32 = 0,
    fn tick(w: *Weapon, dt: f32, wish: bool) void {
        w.cool = @max(0, w.cool - dt);
        const r = 2.0 * dt;
        w.charge = if (wish and w.cool == 0) @min(1.0, w.charge + r) else @max(0, w.charge - r * 2);
    }
    fn fire(w: *Weapon) ?f32 {
        if (w.cool > 0 or w.charge < 0.1) return null;
        defer {
            w.charge = 0;
            w.cool = 0.3;
        }
        return w.charge;
    }
};

pub const Player = struct {
    pos: Vec3,
    vel: Vec3,
    yaw: f32,
    pitch: f32,
    ground: bool,
    crouch: bool,
    weapon: Weapon,
    io: io.IO,

    fn drawUI(p: *const Player) void {
        const w, const h = .{ sapp.widthf(), sapp.heightf() };
        const cx, const cy = .{ w * 0.5, h * 0.5 };
        const size = 8.0 + p.weapon.charge * 12.0;
        const alpha = 0.7 + p.weapon.charge * 0.3;

        ig.igSetNextWindowPos(.{ .x = 0, .y = 0 }, ig.ImGuiCond_Always);
        ig.igSetNextWindowSize(.{ .x = w, .y = h }, ig.ImGuiCond_Always);
        const flags = ig.ImGuiWindowFlags_NoTitleBar | ig.ImGuiWindowFlags_NoResize | ig.ImGuiWindowFlags_NoMove | ig.ImGuiWindowFlags_NoScrollbar | ig.ImGuiWindowFlags_NoBackground | ig.ImGuiWindowFlags_NoInputs;
        if (ig.igBegin("Cross", null, flags)) {
            const dl = ig.igGetWindowDrawList();
            const col = ig.igColorConvertFloat4ToU32(.{ .x = 1, .y = 1, .z = 1, .w = alpha });
            ig.ImDrawList_AddLine(dl, .{ .x = cx - size, .y = cy }, .{ .x = cx + size, .y = cy }, col);
            ig.ImDrawList_AddLine(dl, .{ .x = cx, .y = cy - size }, .{ .x = cx, .y = cy + size }, col);
        }
        ig.igEnd();

        ig.igSetNextWindowPos(.{ .x = 10, .y = 10 }, ig.ImGuiCond_Once);
        ig.igSetNextWindowSize(.{ .x = 200, .y = 140 }, ig.ImGuiCond_Once);
        var show = true;
        if (ig.igBegin("HUD", &show, ig.ImGuiWindowFlags_NoResize | ig.ImGuiWindowFlags_NoCollapse)) {
            _ = ig.igText("Pos: %.1f, %.1f, %.1f", p.pos.data[0], p.pos.data[1], p.pos.data[2]);
            _ = ig.igText("Vel: %.1f, %.1f, %.1f", p.vel.data[0], p.vel.data[1], p.vel.data[2]);
            _ = ig.igText("Yaw: %.2f", p.yaw);
            _ = ig.igText("Pitch: %.2f", p.pitch);
            _ = ig.igText("Ground: %s", if (p.ground) "Yes".ptr else "No".ptr);
            _ = ig.igText("Crouch: %s", if (p.crouch) "Yes".ptr else "No".ptr);
            _ = ig.igText("Charge: %.2f", p.weapon.charge);
        }
        ig.igEnd();
    }

    fn init() Player {
        return .{ .pos = Vec3.new(32, 40, 32), .vel = Vec3.zero(), .yaw = 0, .pitch = 0, .ground = false, .crouch = false, .weapon = .{}, .io = .{} };
    }

    fn tick(p: *Player, w: *const World, dt: f32) void {
        p.input(w, dt);
        p.physics(w, dt);
        p.weapon.tick(dt, p.io.mouse.right and p.io.mouse.locked());
    }

    fn input(p: *Player, w: *const World, dt: f32) void {
        const mv = p.io.vec2(.a, .d, .s, .w);
        var dir = Vec3.zero();
        if (mv.x != 0) dir = dir.add(Vec3.new(@cos(p.yaw), 0, @sin(p.yaw)).scale(mv.x));
        if (mv.y != 0) dir = dir.add(Vec3.new(@sin(p.yaw), 0, -@cos(p.yaw)).scale(mv.y));
        p.move(dir, dt);

        const wish = p.io.shift();
        if (p.crouch and !wish) {
            const diff: f32 = (1.8 - 0.9) / 2.0;
            const pos = Vec3.new(p.pos.data[0], p.pos.data[1] + diff, p.pos.data[2]);
            const box = world.AABB{ .min = Vec3.new(-0.4, -1.8 / 2.0, -0.4), .max = Vec3.new(0.4, 1.8 / 2.0, 0.4) };
            const r = w.sweep(pos, box, Vec3.zero(), 1);
            if (!r.hit) p.pos.data[1] += diff;
            p.crouch = r.hit;
        } else p.crouch = wish;

        if (p.io.pressed(.space) and p.ground) {
            p.vel.data[1] = 8;
            p.ground = false;
        }

        if (p.io.mouse.locked()) {
            p.yaw += p.io.mouse.dx * 0.002;
            p.pitch = @max(-1.57, @min(1.57, p.pitch + p.io.mouse.dy * 0.002));
            if (p.io.mouse.left and p.weapon.charge > 0.1) if (p.weapon.fire()) |power| p.shoot(power);
        }
        if (p.io.justPressed(.escape)) p.io.mouse.unlock();
        if (p.io.mouse.left and !p.io.mouse.locked()) p.io.mouse.lock();
    }

    fn move(p: *Player, dir: Vec3, dt: f32) void {
        const len = @sqrt(dir.data[0] * dir.data[0] + dir.data[2] * dir.data[2]);
        if (len < 0.001) return if (p.ground) p.friction(dt);
        const wish = Vec3.new(dir.data[0] / len, 0, dir.data[2] / len);
        const max = if (p.ground) 7 * len else @min(7 * len, 0.7);
        const add = @max(0, max - p.vel.dot(wish));
        if (add > 0) p.vel = p.vel.add(wish.scale(@min(70 * dt, add)));
        if (p.ground) p.friction(dt);
    }

    fn physics(p: *Player, w: *const World, dt: f32) void {
        p.vel.data[1] -= 20 * dt;
        const h: f32 = if (p.crouch) 0.9 else 1.8;
        const box = world.AABB{ .min = Vec3.new(-0.4, -h / 2, -0.4), .max = Vec3.new(0.4, h / 2, 0.4) };
        const r = w.sweep(p.pos, box, p.vel.scale(dt), 3);
        p.pos = r.pos;
        p.vel = r.vel.scale(1 / dt);
        p.ground = r.hit and @abs(r.vel.data[1]) < 0.01;
    }

    fn friction(p: *Player, dt: f32) void {
        const s = @sqrt(p.vel.data[0] * p.vel.data[0] + p.vel.data[2] * p.vel.data[2]);
        if (s < 0.1) {
            p.vel.data[0] = 0;
            p.vel.data[2] = 0;
            return;
        }
        const f = @max(0, s - @max(s, 0.1) * 4 * dt) / s;
        p.vel.data[0] *= f;
        p.vel.data[2] *= f;
    }

    fn shoot(p: *Player, power: f32) void {
        const cy, const sy, const cp, const sp = .{ @cos(p.yaw), @sin(p.yaw), @cos(p.pitch), @sin(p.pitch) };
        const dir = Vec3.new(sy * cp, -sp, -cy * cp);
        p.vel = p.vel.add(dir.scale(-12.5 * power * power));
        if (p.ground and power > 0.5) {
            p.vel.data[1] += 2.0 * power;
            p.ground = false;
        }
    }

    fn view(p: *Player) Mat4 {
        const cy, const sy, const cp, const sp = .{ @cos(p.yaw), @sin(p.yaw), @cos(p.pitch), @sin(p.pitch) };
        const x, const y, const z = .{ p.pos.data[0], p.pos.data[1], p.pos.data[2] };
        return .{ .data = .{ cy, sy * sp, -sy * cp, 0, 0, cp, sp, 0, sy, -cy * sp, cy * cp, 0, -x * cy - z * sy, -x * sy * sp - y * cp + z * cy * sp, x * sy * cp - y * sp - z * cy * cp, 1 } };
    }
};

var verts: [65536]gfx.Vertex = undefined;
var indices: [98304]u16 = undefined;
var buf: [1024]u8 = undefined;

const Game = struct {
    pipe: gfx.Draw,
    vox: gfx.Draw,
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

        var g = Game{ .pipe = gfx.Draw.init(&gv, &gi, sky), .player = Player.init(), .world = World.init(), .vox = undefined, .alloc = std.heap.FixedBufferAllocator.init(&buf) };

        const r = mesh.mesh(&g.world, &verts, &indices, World.color);
        g.vox = gfx.Draw.init(verts[0..r.verts], indices[0..r.indices], sky);
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
