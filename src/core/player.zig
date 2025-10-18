const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const ig = @import("cimgui");
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
            const x = 58.0;
            const y = 3.0;
            const z = 58.0;
        };
        const ui = struct {
            const crosshair_size = 8.0;
            const crosshair_color = [3]f32{ 1.0, 1.0, 1.0 };
            const crosshair_alpha = 0.8;
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
        const respawn_y = -1.0;
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
            const col = ig.igColorConvertFloat4ToU32(.{ .x = cfg.ui.crosshair_color[0], .y = cfg.ui.crosshair_color[1], .z = cfg.ui.crosshair_color[2], .w = cfg.ui.crosshair_alpha });
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
            // Calculate the height difference between crouching and standing
            const diff: f32 = (cfg.size.stand - cfg.size.crouch) / 2.0;

            // Calculate where the player would be positioned when standing
            const test_pos = Vec3.new(p.pos.data[0], p.pos.data[1] + diff, p.pos.data[2]);

            // Create the standing hitbox at the test position
            const standing_box = world.AABB{ .min = Vec3.new(-cfg.size.width, -cfg.size.stand / 2.0, -cfg.size.width), .max = Vec3.new(cfg.size.width, cfg.size.stand / 2.0, cfg.size.width) };

            // Check for static collision by testing the bounding box against world blocks
            const player_aabb = standing_box.at(test_pos);
            const min_x = @as(i32, @intFromFloat(@floor(player_aabb.min.data[0])));
            const max_x = @as(i32, @intFromFloat(@floor(player_aabb.max.data[0])));
            const min_y = @as(i32, @intFromFloat(@floor(player_aabb.min.data[1])));
            const max_y = @as(i32, @intFromFloat(@floor(player_aabb.max.data[1])));
            const min_z = @as(i32, @intFromFloat(@floor(player_aabb.min.data[2])));
            const max_z = @as(i32, @intFromFloat(@floor(player_aabb.max.data[2])));

            var collision = false;
            var x = min_x;
            while (x <= max_x and !collision) : (x += 1) {
                var y = min_y;
                while (y <= max_y and !collision) : (y += 1) {
                    var z = min_z;
                    while (z <= max_z and !collision) : (z += 1) {
                        if (w.get(x, y, z) != 0) {
                            collision = true;
                        }
                    }
                }
            }

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

                    if (p.io.mouse.leftPressed() and w.set(pos[0], pos[1], pos[2], 0)) {
                        world_changed = true;
                        p.cool = cfg.block_cool;
                    } else if (p.io.mouse.rightPressed()) {
                        const prev = hit.sub(look.scale(0.1));
                        const place_pos = [3]i32{ @intFromFloat(@floor(prev.data[0])), @intFromFloat(@floor(prev.data[1])), @intFromFloat(@floor(prev.data[2])) };
                        const block_pos = Vec3.new(@floatFromInt(place_pos[0]), @floatFromInt(place_pos[1]), @floatFromInt(place_pos[2]));
                        const h: f32 = if (p.crouch) cfg.size.crouch else cfg.size.stand;
                        const player_box = world.AABB{ .min = p.pos.add(Vec3.new(-cfg.size.width, -h / 2.0, -cfg.size.width)), .max = p.pos.add(Vec3.new(cfg.size.width, h / 2.0, cfg.size.width)) };
                        const block_box = world.AABB{ .min = block_pos, .max = block_pos.add(Vec3.new(1, 1, 1)) };
                        const overlaps = player_box.min.data[0] < block_box.max.data[0] and player_box.max.data[0] > block_box.min.data[0] and
                            player_box.min.data[1] < block_box.max.data[1] and player_box.max.data[1] > block_box.min.data[1] and
                            player_box.min.data[2] < block_box.max.data[2] and player_box.max.data[2] > block_box.min.data[2];
                        if (!overlaps and w.set(place_pos[0], place_pos[1], place_pos[2], p.block)) {
                            world_changed = true;
                            p.cool = cfg.block_cool;
                        }
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
                const look = Vec3.new(@sin(p.yaw) * @cos(p.pitch), -@sin(p.pitch), -@cos(p.yaw) * @cos(p.pitch));
                if (w.raycast(p.pos, look, cfg.reach)) |hit| {
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

        if (p.pos.data[1] < cfg.respawn_y) p.respawn();
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

    fn respawn(p: *Player) void {
        p.* = .{ .pos = Vec3.new(cfg.spawn.x, cfg.spawn.y, cfg.spawn.z), .vel = Vec3.zero(), .yaw = 0, .pitch = 0, .ground = false, .crouch = false, .io = p.io, .block = p.block, .cool = 0 };
    }

    pub fn view(p: *Player) Mat4 {
        const cy, const sy, const cp, const sp = .{ @cos(p.yaw), @sin(p.yaw), @cos(p.pitch), @sin(p.pitch) };
        const x, const y, const z = .{ p.pos.data[0], p.pos.data[1], p.pos.data[2] };
        return .{ .data = .{ cy, sy * sp, -sy * cp, 0, 0, cp, sp, 0, sy, -cy * sp, cy * cp, 0, -x * cy - z * sy, -x * sy * sp - y * cp + z * cy * sp, x * sy * cp - y * sp - z * cy * cp, 1 } };
    }
};
