const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const use_docking = @import("build_options").docking;
const ig = if (use_docking) @import("cimgui_docking") else @import("cimgui");
const simgui = sokol.imgui;

const alg = @import("lib/algebra.zig");
const input = @import("lib/input.zig");
const world = @import("world/map.zig");
const mesh = @import("world/mesh.zig");
const rend = @import("world/render.zig");
const shade = @import("shaders/cube.glsl.zig");

const Vec3 = alg.Vec3;
const Mat4 = alg.Mat4;
const World = world.World;

const Weapon = struct {
    charge: f32 = 0,
    cooldown: f32 = 0,

    const CHARGE_MAX: f32 = 1.0;
    const CHARGE_RATE: f32 = 2.0;
    const COOLDOWN: f32 = 0.3;
    const MIN_FIRE: f32 = 0.1;

    fn update(w: *Weapon, dt: f32, charging: bool) void {
        w.cooldown = @max(0, w.cooldown - dt);
        const rate = CHARGE_RATE * dt;
        w.charge = if (charging and w.cooldown == 0)
            @min(CHARGE_MAX, w.charge + rate)
        else
            @max(0, w.charge - rate * 2);
    }

    fn fire(w: *Weapon) ?f32 {
        if (w.cooldown > 0 or w.charge < MIN_FIRE) return null;
        defer {
            w.charge = 0;
            w.cooldown = COOLDOWN;
        }
        return w.charge;
    }
};

pub const Player = struct {
    pos: Vec3,
    vel: Vec3,
    yaw: f32,
    pitch: f32,
    on_ground: bool,
    crouching: bool,
    weapon: Weapon,
    io: input.IO,

    const GRAVITY: f32 = 20;
    const JUMP: f32 = 8;
    const SPEED: f32 = 7;
    const ACCEL: f32 = 10;
    const FRICTION: f32 = 4;
    const HEIGHT: f32 = 1.8;
    const CROUCH: f32 = 0.9;

    const UI = struct {
        fn drawCrosshair(charge: f32) void {
            const screen_w = sapp.widthf();
            const screen_h = sapp.heightf();
            const cx = screen_w * 0.5;
            const cy = screen_h * 0.5;
            const size = 8.0 + charge * 12.0;
            const alpha = 0.7 + charge * 0.3;

            ig.igSetNextWindowPos(.{ .x = 0, .y = 0 }, ig.ImGuiCond_Always);
            ig.igSetNextWindowSize(.{ .x = screen_w, .y = screen_h }, ig.ImGuiCond_Always);

            const flags = ig.ImGuiWindowFlags_NoTitleBar | ig.ImGuiWindowFlags_NoResize |
                ig.ImGuiWindowFlags_NoMove | ig.ImGuiWindowFlags_NoScrollbar |
                ig.ImGuiWindowFlags_NoBackground | ig.ImGuiWindowFlags_NoInputs;

            if (ig.igBegin("Crosshair", null, flags)) {
                const draw_list = ig.igGetWindowDrawList();
                const col = ig.igColorConvertFloat4ToU32(.{ .x = 1, .y = 1, .z = 1, .w = alpha });
                ig.ImDrawList_AddLine(draw_list, .{ .x = cx - size, .y = cy }, .{ .x = cx + size, .y = cy }, col);
                ig.ImDrawList_AddLine(draw_list, .{ .x = cx, .y = cy - size }, .{ .x = cx, .y = cy + size }, col);
            }
            ig.igEnd();
        }

        fn drawHUD(p: *const Player) void {
            ig.igSetNextWindowPos(.{ .x = 10, .y = 10 }, ig.ImGuiCond_Once);
            ig.igSetNextWindowSize(.{ .x = 200, .y = 140 }, ig.ImGuiCond_Once);
            var show_hud = true;

            const flags = ig.ImGuiWindowFlags_NoResize | ig.ImGuiWindowFlags_NoCollapse;
            if (ig.igBegin("Player HUD", &show_hud, flags)) {
                _ = ig.igText("Pos: %.1f, %.1f, %.1f", p.pos.data[0], p.pos.data[1], p.pos.data[2]);
                _ = ig.igText("Vel: %.1f, %.1f, %.1f", p.vel.data[0], p.vel.data[1], p.vel.data[2]);
                _ = ig.igText("Yaw: %.2f", p.yaw);
                _ = ig.igText("Pitch: %.2f", p.pitch);
                _ = ig.igText("Ground: %s", if (p.on_ground) "Yes".ptr else "No".ptr);
                _ = ig.igText("Crouch: %s", if (p.crouching) "Yes".ptr else "No".ptr);
                _ = ig.igText("Charge: %.2f", p.weapon.charge);
            }
            ig.igEnd();

            UI.drawCrosshair(p.weapon.charge);
        }
    };

    fn init() Player {
        return .{
            .pos = Vec3.new(32, 40, 32),
            .vel = Vec3.zero(),
            .yaw = 0,
            .pitch = 0,
            .on_ground = false,
            .crouching = false,
            .weapon = .{},
            .io = .{},
        };
    }

    fn update(p: *Player, w: *const World, dt: f32) void {
        p.handleInput(w, dt);
        p.updatePhysics(w, dt);
        p.weapon.update(dt, p.io.mouse.right and p.io.mouse.isLocked());
    }

    fn handleInput(p: *Player, w: *const World, dt: f32) void {
        const mv = p.io.vec2(.a, .d, .s, .w);
        var d = Vec3.zero();
        if (mv.x != 0) d = d.add(Vec3.new(@cos(p.yaw), 0, @sin(p.yaw)).scale(mv.x));
        if (mv.y != 0) d = d.add(Vec3.new(@sin(p.yaw), 0, -@cos(p.yaw)).scale(mv.y));
        p.move(d, dt);

        const want_crouch = p.io.shift();
        if (p.crouching and !want_crouch) {
            const height_diff = (HEIGHT - CROUCH) / 2;
            const test_pos = Vec3.new(p.pos.data[0], p.pos.data[1] + height_diff, p.pos.data[2]);
            const bbox = world.AABB{ .min = Vec3.new(-0.4, -HEIGHT / 2, -0.4), .max = Vec3.new(0.4, HEIGHT / 2, 0.4) };
            const r = w.sweep(test_pos, bbox, Vec3.zero(), 1);
            if (!r.hit) p.pos.data[1] += height_diff;
            p.crouching = r.hit;
        } else p.crouching = want_crouch;

        if (p.io.pressed(.space) and p.on_ground) {
            p.vel.data[1] = JUMP;
            p.on_ground = false;
        }

        if (p.io.mouse.isLocked()) {
            p.yaw += p.io.mouse.dx * 0.002;
            p.pitch = @max(-1.57, @min(1.57, p.pitch + p.io.mouse.dy * 0.002));

            if (!p.io.mouse.right and p.weapon.charge > Weapon.MIN_FIRE) {
                if (p.weapon.fire()) |power| p.fireWeapon(power);
            }
        }
        if (p.io.justPressed(.escape)) p.io.mouse.unlock();
        if (p.io.mouse.left and !p.io.mouse.isLocked()) p.io.mouse.lock();
    }

    fn move(p: *Player, d: Vec3, dt: f32) void {
        const l = @sqrt(d.data[0] * d.data[0] + d.data[2] * d.data[2]);
        if (l < 0.001) return if (p.on_ground) p.applyFriction(dt);

        const w = Vec3.new(d.data[0] / l, 0, d.data[2] / l);
        const max_add = if (p.on_ground) SPEED * l else @min(SPEED * l, 0.7);
        const add = @max(0, max_add - p.vel.dot(w));

        if (add > 0) p.vel = p.vel.add(w.scale(@min(ACCEL * dt * SPEED, add)));
        if (p.on_ground) p.applyFriction(dt);
    }

    fn updatePhysics(p: *Player, w: *const World, dt: f32) void {
        p.vel.data[1] -= GRAVITY * dt;
        const ht = if (p.crouching) CROUCH else HEIGHT;
        const bbox = world.AABB{ .min = Vec3.new(-0.4, -ht / 2, -0.4), .max = Vec3.new(0.4, ht / 2, 0.4) };
        const r = w.sweep(p.pos, bbox, p.vel.scale(dt), 3);
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

    fn fireWeapon(p: *Player, power: f32) void {
        const cy = @cos(p.yaw);
        const sy = @sin(p.yaw);
        const cp = @cos(p.pitch);
        const sp = @sin(p.pitch);

        const dir = Vec3.new(sy * cp, -sp, -cy * cp);
        const force = 12.5 * power * power;
        p.vel = p.vel.add(dir.scale(-force));

        if (p.on_ground and power > 0.5) {
            p.vel.data[1] += 2.0 * power;
            p.on_ground = false;
        }
    }

    fn getViewMatrix(p: *Player) Mat4 {
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

var static_verts: [65536]rend.Vertex = undefined;
var static_indices: [98304]u16 = undefined;
var static_buffer: [1024]u8 = undefined;

const Game = struct {
    pipe: rend.Renderer,
    vox: rend.Renderer,
    player: Player,
    w: World,
    fba: std.heap.FixedBufferAllocator,

    fn init() Game {
        sokol.gfx.setup(.{ .environment = sokol.glue.environment(), .logger = .{ .func = sokol.log.func } });
        simgui.setup(.{ .logger = .{ .func = sokol.log.func } });

        if (use_docking) ig.igGetIO().*.ConfigFlags |= ig.ImGuiConfigFlags_DockingEnable;

        const ground_verts = [_]rend.Vertex{
            .{ .pos = .{ -100, -1, -100 }, .col = .{ 0.1, 0.1, 0.12, 1 } },
            .{ .pos = .{ 100, -1, -100 }, .col = .{ 0.12, 0.15, 0.18, 1 } },
            .{ .pos = .{ 100, -1, 100 }, .col = .{ 0.15, 0.12, 0.15, 1 } },
            .{ .pos = .{ -100, -1, 100 }, .col = .{ 0.12, 0.12, 0.15, 1 } },
        };
        const ground_indices = [_]u16{ 0, 1, 2, 0, 2, 3 };
        const sky_color = [4]f32{ 0.5, 0.7, 0.9, 1 };

        var s = Game{
            .pipe = rend.Renderer.init(&ground_verts, &ground_indices, sky_color),
            .player = Player.init(),
            .w = World.init(),
            .vox = undefined,
            .fba = std.heap.FixedBufferAllocator.init(&static_buffer),
        };

        const r = mesh.buildMesh(&s.w, &static_verts, &static_indices, World.blockColor);
        s.vox = rend.Renderer.init(static_verts[0..r.vcount], static_indices[0..r.icount], sky_color);

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
        simgui.newFrame(.{
            .width = sapp.width(),
            .height = sapp.height(),
            .delta_time = sapp.frameDuration(),
            .dpi_scale = sapp.dpiScale(),
        });

        Player.UI.drawHUD(&s.player);

        const mvp = Mat4.mul(alg.perspective(90, sapp.widthf() / sapp.heightf(), 0.1, 1000), s.player.getViewMatrix());

        sokol.gfx.beginPass(.{ .action = s.pipe.pass, .swapchain = sokol.glue.swapchain() });
        s.pipe.draw(mvp);
        s.vox.draw(mvp);
        simgui.render();
        sokol.gfx.endPass();
        sokol.gfx.commit();
    }

    fn deinit(s: *Game) void {
        s.pipe.deinit();
        s.vox.deinit();
        s.w.deinit();
        simgui.shutdown();
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
    _ = simgui.handleEvent(e.*);
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
