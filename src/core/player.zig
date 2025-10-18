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

pub const Weapon = struct {
    charge: f32 = 0,
    cool: f32 = 0,

    const cfg = struct {
        const rate = 2.0;
        const min_charge = 0.1;
        const cooldown = 0.3;
    };

    pub fn tick(w: *Weapon, dt: f32, wish: bool) void {
        w.cool = @max(0, w.cool - dt);
        const r = cfg.rate * dt;
        w.charge = if (wish and w.cool == 0) @min(1.0, w.charge + r) else @max(0, w.charge - r * 2);
    }
    pub fn fire(w: *Weapon) ?f32 {
        if (w.cool > 0 or w.charge < cfg.min_charge) return null;
        defer {
            w.charge = 0;
            w.cool = cfg.cooldown;
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
    selected_block: world.Block,
    interact_cooldown: f32,

    const cfg = struct {
        const spawn = struct {
            const x = 32.0;
            const y = 40.0;
            const z = 32.0;
        };
        const ui = struct {
            const cross_base = 8.0;
            const cross_scale = 12.0;
            const alpha_base = 0.7;
            const alpha_scale = 0.3;
            const hud_x = 10.0;
            const hud_y = 10.0;
            const hud_w = 200.0;
            const hud_h = 140.0;
        };
        const input = struct {
            const sens = 0.002;
            const pitch_limit = 1.57;
            const fire_min = 0.1;
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
        const shoot = struct {
            const force = 12.5;
            const jump_min = 0.5;
            const jump_boost = 2.0;
        };
        const reach = struct {
            const distance = 5.0;
        };
        const interact = struct {
            const cooldown = 0.15;
        };
    };

    pub fn drawUI(p: *const Player) void {
        const w, const h = .{ sapp.widthf(), sapp.heightf() };
        const cx, const cy = .{ w * 0.5, h * 0.5 };
        const size = cfg.ui.cross_base + p.weapon.charge * cfg.ui.cross_scale;
        const alpha = cfg.ui.alpha_base + p.weapon.charge * cfg.ui.alpha_scale;

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

        ig.igSetNextWindowPos(.{ .x = cfg.ui.hud_x, .y = cfg.ui.hud_y }, ig.ImGuiCond_Once);
        ig.igSetNextWindowSize(.{ .x = cfg.ui.hud_w, .y = cfg.ui.hud_h }, ig.ImGuiCond_Once);
        var show = true;
        if (ig.igBegin("HUD", &show, ig.ImGuiWindowFlags_NoResize | ig.ImGuiWindowFlags_NoCollapse)) {
            _ = ig.igText("Pos: %.1f, %.1f, %.1f", p.pos.data[0], p.pos.data[1], p.pos.data[2]);
            _ = ig.igText("Vel: %.1f, %.1f, %.1f", p.vel.data[0], p.vel.data[1], p.vel.data[2]);
            _ = ig.igText("Yaw: %.2f", p.yaw);
            _ = ig.igText("Pitch: %.2f", p.pitch);
            _ = ig.igText("Ground: %s", if (p.ground) "Yes".ptr else "No".ptr);
            _ = ig.igText("Crouch: %s", if (p.crouch) "Yes".ptr else "No".ptr);
            _ = ig.igText("Charge: %.2f", p.weapon.charge);
            const block_name = switch (p.selected_block) {
                .air => "Air",
                .grass => "Grass",
                .dirt => "Dirt",
                .stone => "Stone",
            };
            _ = ig.igText("Selected: %s", block_name.ptr);
        }
        ig.igEnd();
    }

    pub fn init() Player {
        return .{ .pos = Vec3.new(cfg.spawn.x, cfg.spawn.y, cfg.spawn.z), .vel = Vec3.zero(), .yaw = 0, .pitch = 0, .ground = false, .crouch = false, .weapon = .{}, .io = .{}, .selected_block = .stone, .interact_cooldown = 0 };
    }

    pub fn tick(p: *Player, w: *World, dt: f32) bool {
        p.interact_cooldown = @max(0, p.interact_cooldown - dt);
        const world_changed = p.input(w, dt);
        p.physics(w, dt);
        p.weapon.tick(dt, p.io.mouse.right and p.io.mouse.locked());
        return world_changed;
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
            if (p.io.mouse.left and p.weapon.charge > cfg.input.fire_min) if (p.weapon.fire()) |power| p.shoot(power);

            // Block interactions
            if (p.interact_cooldown == 0) {
                const look_dir = p.getLookDirection();
                const ray_result = w.raycast(p.pos, look_dir, cfg.reach.distance);

                if (ray_result.hit) {
                    // Break block with left click (when not shooting)
                    if (p.io.mouse.left and p.weapon.charge <= cfg.input.fire_min) {
                        const bx = @as(i32, @intFromFloat(ray_result.block_pos.data[0]));
                        const by = @as(i32, @intFromFloat(ray_result.block_pos.data[1]));
                        const bz = @as(i32, @intFromFloat(ray_result.block_pos.data[2]));
                        if (w.set(bx, by, bz, .air)) {
                            world_changed = true;
                            p.interact_cooldown = cfg.interact.cooldown;
                        }
                    }
                    // Place block with right click (when not charging weapon)
                    else if (p.io.mouse.right and p.weapon.charge == 0) {
                        const place_pos = ray_result.block_pos.add(ray_result.normal);
                        const px = @as(i32, @intFromFloat(place_pos.data[0]));
                        const py = @as(i32, @intFromFloat(place_pos.data[1]));
                        const pz = @as(i32, @intFromFloat(place_pos.data[2]));

                        // Don't place blocks inside the player
                        const player_box = world.AABB{ .min = Vec3.new(-cfg.size.width, -cfg.size.stand / 2.0, -cfg.size.width), .max = Vec3.new(cfg.size.width, cfg.size.stand / 2.0, cfg.size.width) };
                        const block_box = world.AABB{ .min = place_pos, .max = place_pos.add(Vec3.new(1, 1, 1)) };

                        if (!p.intersectsAABB(player_box.at(p.pos), block_box)) {
                            if (w.set(px, py, pz, p.selected_block)) {
                                world_changed = true;
                                p.interact_cooldown = cfg.interact.cooldown;
                            }
                        }
                    }
                }
            }

            // Block selection with number keys
            if (p.io.justPressed(._1)) p.selected_block = .grass;
            if (p.io.justPressed(._2)) p.selected_block = .dirt;
            if (p.io.justPressed(._3)) p.selected_block = .stone;
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

    fn shoot(p: *Player, power: f32) void {
        const cy, const sy, const cp, const sp = .{ @cos(p.yaw), @sin(p.yaw), @cos(p.pitch), @sin(p.pitch) };
        const dir = Vec3.new(sy * cp, -sp, -cy * cp);
        p.vel = p.vel.add(dir.scale(-cfg.shoot.force * power * power));
        if (p.ground and power > cfg.shoot.jump_min) {
            p.vel.data[1] += cfg.shoot.jump_boost * power;
            p.ground = false;
        }
    }

    fn getLookDirection(p: *const Player) Vec3 {
        const cy, const sy, const cp, const sp = .{ @cos(p.yaw), @sin(p.yaw), @cos(p.pitch), @sin(p.pitch) };
        return Vec3.new(sy * cp, -sp, -cy * cp);
    }

    fn intersectsAABB(p: *const Player, a: world.AABB, b: world.AABB) bool {
        _ = p;
        return a.min.data[0] < b.max.data[0] and a.max.data[0] > b.min.data[0] and
            a.min.data[1] < b.max.data[1] and a.max.data[1] > b.min.data[1] and
            a.min.data[2] < b.max.data[2] and a.max.data[2] > b.min.data[2];
    }

    pub fn view(p: *Player) Mat4 {
        const cy, const sy, const cp, const sp = .{ @cos(p.yaw), @sin(p.yaw), @cos(p.pitch), @sin(p.pitch) };
        const x, const y, const z = .{ p.pos.data[0], p.pos.data[1], p.pos.data[2] };
        return .{ .data = .{ cy, sy * sp, -sy * cp, 0, 0, cp, sp, 0, sy, -cy * sp, cy * cp, 0, -x * cy - z * sy, -x * sy * sp - y * cp + z * cy * sp, x * sy * cp - y * sp - z * cy * cp, 1 } };
    }
};
