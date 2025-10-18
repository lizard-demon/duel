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

const V = alg.Vec3;
const M = alg.Mat4;
const W = world.World;

const Weapon = struct {
    charge: f32,
    cooldown: f32,

    const MAX_CHARGE: f32 = 1.0;
    const CHARGE_RATE: f32 = 2.0;
    const COOLDOWN_TIME: f32 = 0.3;

    fn init() Weapon {
        return .{ .charge = 0, .cooldown = 0 };
    }

    fn update(w: *Weapon, dt: f32, charging: bool) void {
        w.cooldown = @max(0, w.cooldown - dt);
        if (charging and w.cooldown == 0) {
            w.charge = @min(MAX_CHARGE, w.charge + CHARGE_RATE * dt);
        } else {
            w.charge = @max(0, w.charge - CHARGE_RATE * 2 * dt);
        }
    }

    fn fire(w: *Weapon) ?f32 {
        if (w.cooldown > 0 or w.charge < 0.1) return null;
        const power = w.charge;
        w.charge = 0;
        w.cooldown = COOLDOWN_TIME;
        return power;
    }
};

const Player = struct {
    pos: V,
    vel: V,
    yaw: f32,
    pitch: f32,
    on_ground: bool,
    crouching: bool,
    weapon: Weapon,
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
            .weapon = Weapon.init(),
            .io = .{},
        };
    }

    fn update(p: *Player, w: *const W, dt: f32) void {
        p.handleInput(w, dt);
        p.updatePhysics(w, dt);
        p.weapon.update(dt, p.io.mouse.right and p.io.mouse.isLocked());
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

            if (!p.io.mouse.right and p.weapon.charge > 0.1) {
                if (p.weapon.fire()) |power| {
                    p.fireWeapon(power);
                }
            }
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

    fn fireWeapon(p: *Player, power: f32) void {
        const cy = @cos(p.yaw);
        const sy = @sin(p.yaw);
        const cp = @cos(p.pitch);
        const sp = @sin(p.pitch);

        const dir = V.new(sy * cp, -sp, -cy * cp);
        const force = 12.5 * power * power;
        p.vel = p.vel.add(dir.scale(-force));

        if (p.on_ground and power > 0.5) {
            p.vel.data[1] += 2.0 * power;
            p.on_ground = false;
        }
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

    fn drawHUD(p: *Player) void {
        ig.igSetNextWindowPos(.{ .x = 10, .y = 10 }, ig.ImGuiCond_Once);
        ig.igSetNextWindowSize(.{ .x = 200, .y = 140 }, ig.ImGuiCond_Once);
        var show_hud = true;
        if (ig.igBegin("Player HUD", &show_hud, ig.ImGuiWindowFlags_NoResize | ig.ImGuiWindowFlags_NoCollapse)) {
            _ = ig.igText("Pos: %.1f, %.1f, %.1f", p.pos.data[0], p.pos.data[1], p.pos.data[2]);
            _ = ig.igText("Vel: %.1f, %.1f, %.1f", p.vel.data[0], p.vel.data[1], p.vel.data[2]);
            _ = ig.igText("Yaw: %.2f", p.yaw);
            _ = ig.igText("Pitch: %.2f", p.pitch);
            _ = ig.igText("Ground: %s", if (p.on_ground) "Yes".ptr else "No".ptr);
            _ = ig.igText("Crouch: %s", if (p.crouching) "Yes".ptr else "No".ptr);
            _ = ig.igText("Charge: %.2f", p.weapon.charge);
        }
        ig.igEnd();

        p.drawCrosshair();
    }

    fn drawCrosshair(p: *Player) void {
        const w = sapp.widthf();
        const h = sapp.heightf();
        const cx = w * 0.5;
        const cy = h * 0.5;
        const size = 8.0 + p.weapon.charge * 12.0;
        const alpha = 0.7 + p.weapon.charge * 0.3;

        ig.igSetNextWindowPos(.{ .x = 0, .y = 0 }, ig.ImGuiCond_Always);
        ig.igSetNextWindowSize(.{ .x = w, .y = h }, ig.ImGuiCond_Always);
        if (ig.igBegin("Crosshair", null, ig.ImGuiWindowFlags_NoTitleBar | ig.ImGuiWindowFlags_NoResize | ig.ImGuiWindowFlags_NoMove | ig.ImGuiWindowFlags_NoScrollbar | ig.ImGuiWindowFlags_NoBackground | ig.ImGuiWindowFlags_NoInputs)) {
            const draw_list = ig.igGetWindowDrawList();
            const col = ig.igColorConvertFloat4ToU32(.{ .x = 1, .y = 1, .z = 1, .w = alpha });
            ig.ImDrawList_AddLine(draw_list, .{ .x = cx - size, .y = cy }, .{ .x = cx + size, .y = cy }, col);
            ig.ImDrawList_AddLine(draw_list, .{ .x = cx, .y = cy - size }, .{ .x = cx, .y = cy + size }, col);
        }
        ig.igEnd();
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

        simgui.setup(.{
            .logger = .{ .func = sokol.log.func },
        });

        if (use_docking) {
            ig.igGetIO().*.ConfigFlags |= ig.ImGuiConfigFlags_DockingEnable;
        }

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
        simgui.newFrame(.{
            .width = sapp.width(),
            .height = sapp.height(),
            .delta_time = sapp.frameDuration(),
            .dpi_scale = sapp.dpiScale(),
        });

        s.player.drawHUD();

        const proj = alg.perspective(90, sapp.widthf() / sapp.heightf(), 0.1, 1000);
        const view = s.player.getViewMatrix();
        const mvp = M.mul(proj, view);

        sokol.gfx.beginPass(.{
            .action = s.pipe.pass,
            .swapchain = sokol.glue.swapchain(),
        });
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
