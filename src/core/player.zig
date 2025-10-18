const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const use_docking = @import("build_options").docking;
const ig = if (use_docking) @import("cimgui_docking") else @import("cimgui");
const math = @import("../lib/math.zig");
const io = @import("../lib/io.zig");
const world = @import("world.zig");

const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const World = world.World;

pub const Player = struct {
    pos: Vec3,
    vel: Vec3,
    yaw: f32,
    pitch: f32,
    ground: bool,
    crouch: bool,

    io: io.IO,
    block: world.Block,
    cool: f32,

    const cfg = struct {
        const spawn = struct {
            const x = 32.0;
            const y = 40.0;
            const z = 32.0;
        };
        const ui = struct {
            const crosshair_size = 8.0;
            const hud_x = 10.0;
            const hud_y = 10.0;
            const hud_w = 150.0;
            const hud_h = 50.0;
        };
        const input = struct {
            const sens = 0.002;
            const pitch_limit = 1.57;
        };
        const size = struct {
            const stand = 1.8;
            const crouch = 0.9;
            const width = 0.4;
        };
        const move = struct {
            const speed = 7.0;
            const air_cap = 0.7;
            const accel = 70.0;
            const min_len = 0.001;
        };
        const phys = struct {
            const gravity = 20.0;
            const steps = 3;
            const ground_thresh = 0.01;
        };
        const friction = struct {
            const min_speed = 0.1;
            const factor = 4.0;
        };
        const jump = struct {
            const power = 8.0;
        };

        const reach = 5.0;
        const block_cool = 0.15;
    };

    pub fn drawUI(p: *const Player) void {
        const w, const h = .{ sapp.widthf(), sapp.heightf() };

        // Simple crosshair
        ig.igSetNextWindowPos(.{ .x = 0, .y = 0 }, ig.ImGuiCond_Always);
        ig.igSetNextWindowSize(.{ .x = w, .y = h }, ig.ImGuiCond_Always);
        const flags = ig.ImGuiWindowFlags_NoTitleBar | ig.ImGuiWindowFlags_NoResize | ig.ImGuiWindowFlags_NoMove | ig.ImGuiWindowFlags_NoScrollbar | ig.ImGuiWindowFlags_NoBackground | ig.ImGuiWindowFlags_NoInputs;
        if (ig.igBegin("Crosshair", null, flags)) {
            const dl = ig.igGetWindowDrawList();
            const cx, const cy = .{ w * 0.5, h * 0.5 };
            const size = cfg.ui.crosshair_size;
            const col = ig.igColorConvertFloat4ToU32(.{ .x = 1, .y = 1, .z = 1, .w = 0.8 });
            ig.ImDrawList_AddLine(dl, .{ .x = cx - size, .y = cy }, .{ .x = cx + size, .y = cy }, col);
            ig.ImDrawList_AddLine(dl, .{ .x = cx, .y = cy - size }, .{ .x = cx, .y = cy + size }, col);
        }
        ig.igEnd();

        // HUD
        ig.igSetNextWindowPos(.{ .x = cfg.ui.hud_x, .y = cfg.ui.hud_y }, ig.ImGuiCond_Once);
        ig.igSetNextWindowSize(.{ .x = cfg.ui.hud_w, .y = cfg.ui.hud_h }, ig.ImGuiCond_Once);
        var show = true;
        if (ig.igBegin("HUD", &show, ig.ImGuiWindowFlags_NoResize | ig.ImGuiWindowFlags_NoCollapse)) {
            const block_color = world.World.color(p.block);
            _ = ig.igColorButton("##color_preview", .{ .x = block_color[0], .y = block_color[1], .z = block_color[2], .w = 1.0 }, ig.ImGuiColorEditFlags_NoTooltip);
            ig.igSameLine();
            _ = ig.igText("Color %d (Q/E)", p.block);
        }
        ig.igEnd();
    }

    pub fn init() Player {
        return .{ .pos = Vec3.new(cfg.spawn.x, cfg.spawn.y, cfg.spawn.z), .vel = Vec3.zero(), .yaw = 0, .pitch = 0, .ground = false, .crouch = false, .io = .{}, .block = 0b11100011, .cool = 0 };
    }

    pub fn tick(p: *Player, w: *World, dt: f32) bool {
        p.cool = @max(0, p.cool - dt);
        const changed = p.input(w, dt);
        p.physics(w, dt);
        return changed;
    }

    fn input(p: *Player, w: *World, dt: f32) bool {
        var world_changed = false;
        const mv = p.io.vec2(.a, .d, .s, .w);
        var dir = Vec3.zero();
        if (mv.x != 0) dir = dir.add(Vec3.new(@cos(p.yaw), 0, @sin(p.yaw)).scale(mv.x));
        if (mv.y != 0) dir = dir.add(Vec3.new(@sin(p.yaw), 0, -@cos(p.yaw)).scale(mv.y));
        p.move(dir, dt);

        const wish = p.io.shift();
        if (p.crouch and !wish) {
            const diff: f32 = (cfg.size.stand - cfg.size.crouch) / 2.0;
            const pos = Vec3.new(p.pos.data[0], p.pos.data[1] + diff, p.pos.data[2]);
            const box = world.AABB{ .min = Vec3.new(-cfg.size.width, -cfg.size.stand / 2.0, -cfg.size.width), .max = Vec3.new(cfg.size.width, cfg.size.stand / 2.0, cfg.size.width) };
            const r = w.sweep(pos, box, Vec3.zero(), 1);
            if (!r.hit) p.pos.data[1] += diff;
            p.crouch = r.hit;
        } else p.crouch = wish;

        if (p.io.pressed(.space) and p.ground) {
            p.vel.data[1] = cfg.jump.power;
            p.ground = false;
        }

        if (p.io.mouse.locked()) {
            p.yaw += p.io.mouse.dx * cfg.input.sens;
            p.pitch = @max(-cfg.input.pitch_limit, @min(cfg.input.pitch_limit, p.pitch + p.io.mouse.dy * cfg.input.sens));

            // Block interactions
            if (p.cool == 0) {
                const look = Vec3.new(@sin(p.yaw) * @cos(p.pitch), -@sin(p.pitch), -@cos(p.yaw) * @cos(p.pitch));
                if (w.raycast(p.pos, look, cfg.reach)) |hit| {
                    const pos = [3]i32{ @intFromFloat(@floor(hit.data[0])), @intFromFloat(@floor(hit.data[1])), @intFromFloat(@floor(hit.data[2])) };

                    if (p.io.mouse.left and w.set(pos[0], pos[1], pos[2], 0)) {
                        world_changed = true;
                        p.cool = cfg.block_cool;
                    } else if (p.io.mouse.right) {
                        const prev = hit.sub(look.scale(0.1));
                        const place_pos = [3]i32{ @intFromFloat(@floor(prev.data[0])), @intFromFloat(@floor(prev.data[1])), @intFromFloat(@floor(prev.data[2])) };
                        if (w.set(place_pos[0], place_pos[1], place_pos[2], p.block)) {
                            world_changed = true;
                            p.cool = cfg.block_cool;
                        }
                    }
                }
            }

            // Color selection with Q and E keys
            if (p.io.justPressed(.q)) {
                p.block = if (p.block > 1) p.block - 1 else 255;
            }
            if (p.io.justPressed(.e)) {
                p.block = if (p.block < 255) p.block + 1 else 1;
            }
        }
        if (p.io.justPressed(.escape)) p.io.mouse.unlock();
        if (p.io.mouse.left and !p.io.mouse.locked()) p.io.mouse.lock();

        return world_changed;
    }

    fn move(p: *Player, dir: Vec3, dt: f32) void {
        const len = @sqrt(dir.data[0] * dir.data[0] + dir.data[2] * dir.data[2]);
        if (len < cfg.move.min_len) return if (p.ground) p.friction(dt);
        const wish = Vec3.new(dir.data[0] / len, 0, dir.data[2] / len);
        const max = if (p.ground) cfg.move.speed * len else @min(cfg.move.speed * len, cfg.move.air_cap);
        const add = @max(0, max - p.vel.dot(wish));
        if (add > 0) p.vel = p.vel.add(wish.scale(@min(cfg.move.accel * dt, add)));
        if (p.ground) p.friction(dt);
    }

    fn physics(p: *Player, w: *const World, dt: f32) void {
        p.vel.data[1] -= cfg.phys.gravity * dt;
        const h: f32 = if (p.crouch) cfg.size.crouch else cfg.size.stand;
        const box = world.AABB{ .min = Vec3.new(-cfg.size.width, -h / 2.0, -cfg.size.width), .max = Vec3.new(cfg.size.width, h / 2.0, cfg.size.width) };
        const r = w.sweep(p.pos, box, p.vel.scale(dt), cfg.phys.steps);
        p.pos = r.pos;
        p.vel = r.vel.scale(1 / dt);
        p.ground = r.hit and @abs(r.vel.data[1]) < cfg.phys.ground_thresh;
    }

    fn friction(p: *Player, dt: f32) void {
        const s = @sqrt(p.vel.data[0] * p.vel.data[0] + p.vel.data[2] * p.vel.data[2]);
        if (s < cfg.friction.min_speed) {
            p.vel.data[0] = 0;
            p.vel.data[2] = 0;
            return;
        }
        const f = @max(0, s - @max(s, cfg.friction.min_speed) * cfg.friction.factor * dt) / s;
        p.vel.data[0] *= f;
        p.vel.data[2] *= f;
    }

    pub fn view(p: *Player) Mat4 {
        const cy, const sy, const cp, const sp = .{ @cos(p.yaw), @sin(p.yaw), @cos(p.pitch), @sin(p.pitch) };
        const x, const y, const z = .{ p.pos.data[0], p.pos.data[1], p.pos.data[2] };
        return .{ .data = .{ cy, sy * sp, -sy * cp, 0, 0, cp, sp, 0, sy, -cy * sp, cy * cp, 0, -x * cy - z * sy, -x * sy * sp - y * cp + z * cy * sp, x * sy * cp - y * sp - z * cy * cp, 1 } };
    }
};
