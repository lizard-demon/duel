const std = @import("std");
const math = @import("../lib/math.zig");
const io = @import("../lib/io.zig");
const world = @import("world.zig");
const physics = @import("physics.zig");

const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const World = world.World;
const AABB = physics.AABB;

pub const Player = struct {
    pos: Vec3,
    vel: Vec3,
    yaw: f32,
    pitch: f32,
    ground: bool,
    crouch: bool,

    io: io.IO,
    block: world.Block,

    pub fn spawn(x: f32, y: f32, z: f32) Player {
        return .{ .pos = Vec3.new(x, y, z), .vel = Vec3.zero(), .yaw = 0, .pitch = 0, .ground = false, .crouch = false, .io = .{}, .block = 2 };
    }

    pub fn view(p: *Player) Mat4 {
        const cy, const sy, const cp, const sp = .{ @cos(p.yaw), @sin(p.yaw), @cos(p.pitch), @sin(p.pitch) };
        const x, const y, const z = .{ p.pos.data[0], p.pos.data[1], p.pos.data[2] };
        return .{ .data = .{ cy, sy * sp, -sy * cp, 0, 0, cp, sp, 0, sy, -cy * sp, cy * cp, 0, -x * cy - z * sy, -x * sy * sp - y * cp + z * cy * sp, x * sy * cp - y * sp - z * cy * cp, 1 } };
    }

    pub const update = struct {
        pub fn pos(p: *Player, cfg: anytype, dir: Vec3, dt: f32) void {
            const len = @sqrt(dir.data[0] * dir.data[0] + dir.data[2] * dir.data[2]);
            if (len < cfg.move.min_len) return if (p.ground) update.friction(p, cfg, dt);
            const wish = Vec3.new(dir.data[0] / len, 0, dir.data[2] / len);
            const base_speed: f32 = if (p.crouch) cfg.move.crouch_speed else cfg.move.speed;
            const max = if (p.ground) base_speed * len else @min(base_speed * len, cfg.move.air_cap);
            const add = @max(0, max - p.vel.dot(wish));
            if (add > 0) p.vel = p.vel.add(wish.scale(@min(cfg.move.accel * dt, add)));
            if (p.ground) update.friction(p, cfg, dt);
        }

        pub fn phys(p: *Player, cfg: anytype, w: *const World, dt: f32) void {
            p.vel.data[1] -= cfg.phys.gravity * dt;
            const h: f32 = if (p.crouch) cfg.size.crouch else cfg.size.stand;
            const box = AABB{ .min = Vec3.new(-cfg.size.width, -h / 2.0, -cfg.size.width), .max = Vec3.new(cfg.size.width, h / 2.0, cfg.size.width) };
            const r = physics.sweep(w, p.pos, box, p.vel.scale(dt), cfg.phys.steps);
            p.pos = r.pos;
            p.vel = r.vel.scale(1 / dt);
            p.ground = r.hit and @abs(r.vel.data[1]) < cfg.phys.ground_thresh;

            if (p.pos.data[1] < cfg.respawn_y) {
                const new_player = Player.spawn(cfg.spawn.x, cfg.spawn.y, cfg.spawn.z);
                p.pos = new_player.pos;
                p.vel = new_player.vel;
                p.yaw = new_player.yaw;
                p.pitch = new_player.pitch;
                p.ground = new_player.ground;
                p.crouch = new_player.crouch;
            }
        }

        pub fn friction(p: *Player, cfg: anytype, dt: f32) void {
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
    };
};
