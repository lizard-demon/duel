const std = @import("std");
const math = @import("../lib/math.zig");
const io = @import("../lib/io.zig");
const world = @import("world.zig");
const sokol = @import("sokol");
const stime = sokol.time;

const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Map = world.Map;

pub const Player = struct {
    pos: Vec3,
    vel: Vec3,
    yaw: f32,
    pitch: f32,
    ground: bool,
    crouch: bool,
    io: io.IO,
    block: world.Block,
    spawn_time: u64,

    const cfg = struct {
        const spawn = struct {
            const x = 2.0;
            const y = 2.0;
            const z = 2.0;
            const yaw = std.math.pi;
            const pitch = 0.0;
        };
        const size = struct {
            const stand = 1.8;
            const crouch = 0.9;
            const width = 0.49;
        };
        const move = struct {
            const speed = 4.0;
            const crouch_speed = speed / 2.0;
            const air_cap = 0.7;
            const accel = 70.0;
            const min_len = 0.001;
        };
        const phys = struct {
            const gravity = 12.0;
            const steps = 3;
            const ground_thresh = 0.01;
        };
        const friction = struct {
            const min_speed = 0.1;
            const factor = 5.0;
        };
        const respawn_y = 0.0;
        const succeed_y = 64.0;
    };

    pub inline fn spawn(x: f32, y: f32, z: f32) Player {
        return .{ .pos = Vec3.new(x, y, z), .vel = Vec3.zero(), .yaw = cfg.spawn.yaw, .pitch = cfg.spawn.pitch, .ground = false, .crouch = false, .io = .{}, .block = 2, .spawn_time = stime.now() };
    }

    pub inline fn init() Player {
        return spawn(cfg.spawn.x, cfg.spawn.y, cfg.spawn.z);
    }

    pub inline fn lookdir(yaw: f32, pitch: f32) Vec3 {
        return Vec3.new(@sin(yaw) * @cos(pitch), -@sin(pitch), -@cos(yaw) * @cos(pitch));
    }

    pub fn view(p: *Player) Mat4 {
        const cy, const sy, const cp, const sp = .{ @cos(p.yaw), @sin(p.yaw), @cos(p.pitch), @sin(p.pitch) };
        const x, const y, const z = .{ p.pos.data[0], p.pos.data[1], p.pos.data[2] };
        return .{ .data = .{ cy, sy * sp, -sy * cp, 0, 0, cp, sp, 0, sy, -cy * sp, cy * cp, 0, -x * cy - z * sy, -x * sy * sp - y * cp + z * cy * sp, x * sy * cp - y * sp - z * cy * cp, 1 } };
    }

    pub const bounds = struct {
        pub inline fn bbox(pos: Vec3, crouch: bool, crouch_height: f32, stand_height: f32, width: f32) Collision.bbox {
            const h: f32 = if (crouch) crouch_height else stand_height;
            const w: f32 = width;
            return Collision.bbox{
                .min = pos.add(Vec3.new(-w, -h / 2.0, -w)),
                .max = pos.add(Vec3.new(w, h / 2.0, w)),
            };
        }

        pub inline fn standbox(pos: Vec3, width: f32, height: f32) Collision.bbox {
            const box = Collision.bbox{
                .min = Vec3.new(-width, -height / 2.0, -width),
                .max = Vec3.new(width, height / 2.0, width),
            };
            return box.at(pos);
        }

        pub inline fn blockbox(pos: Vec3) Collision.bbox {
            return Collision.bbox{
                .min = pos,
                .max = pos.add(Vec3.new(1, 1, 1)),
            };
        }
    };

    pub const update = struct {
        pub fn pos(p: *Player, dir: Vec3, dt: f32) void {
            const len = @sqrt(dir.data[0] * dir.data[0] + dir.data[2] * dir.data[2]);
            if (len < cfg.move.min_len) return if (p.ground) update.friction(p, dt);
            const wish = Vec3.new(dir.data[0] / len, 0, dir.data[2] / len);
            const base_speed: f32 = if (p.crouch) cfg.move.crouch_speed else cfg.move.speed;
            const max = if (p.ground) base_speed * len else @min(base_speed * len, cfg.move.air_cap);
            const add = @max(0, max - p.vel.dot(wish));
            if (add > 0) p.vel = p.vel.add(wish.scale(@min(cfg.move.accel * dt, add)));
            if (p.ground) update.friction(p, dt);
        }

        pub fn phys(p: *Player, w: *const Map, dt: f32) void {
            p.vel.data[1] -= cfg.phys.gravity * dt;
            const h: f32 = if (p.crouch) cfg.size.crouch else cfg.size.stand;
            const box = Collision.bbox{ .min = Vec3.new(-cfg.size.width, -h / 2.0, -cfg.size.width), .max = Vec3.new(cfg.size.width, h / 2.0, cfg.size.width) };
            const r = Collision.sweep(w, p.pos, box, p.vel.scale(dt), cfg.phys.steps);
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
                p.spawn_time = new_player.spawn_time;
            }

            if (p.pos.data[1] > cfg.succeed_y) {
                // Player wins! Calculate time taken
                const win_time = stime.now();
                const elapsed_ticks = stime.diff(win_time, p.spawn_time);
                const elapsed_seconds = stime.sec(elapsed_ticks);

                std.debug.print("🎉 Victory! Time to reach y={d}: {d:.3} seconds\n", .{ cfg.succeed_y, elapsed_seconds });

                // Reset to spawn for another attempt
                const new_player = Player.spawn(cfg.spawn.x, cfg.spawn.y, cfg.spawn.z);
                p.pos = new_player.pos;
                p.vel = new_player.vel;
                p.yaw = new_player.yaw;
                p.pitch = new_player.pitch;
                p.ground = new_player.ground;
                p.crouch = new_player.crouch;
                p.spawn_time = new_player.spawn_time;
            }
        }

        pub fn friction(p: *Player, dt: f32) void {
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

pub const Input = struct {
    const cfg = struct {
        const sensitivity = 0.002;
        const pitch_limit = std.math.pi / 2.0;
        const jump_power = 4.0;
        const reach = 10.0;
    };

    const handle = struct {
        pub fn movement(p: *Player, yaw: f32, dt: f32) void {
            const mv = p.io.vec2(.a, .d, .s, .w);
            var dir = Vec3.zero();
            if (mv.x != 0) dir = dir.add(Vec3.new(@cos(yaw), 0, @sin(yaw)).scale(mv.x));
            if (mv.y != 0) dir = dir.add(Vec3.new(@sin(yaw), 0, -@cos(yaw)).scale(mv.y));
            Player.update.pos(p, dir, dt);
        }

        pub fn crouch(p: *Player, world_map: *Map) void {
            const wish = p.io.shift();

            if (p.crouch and !wish) {
                const diff = (Player.cfg.size.stand - Player.cfg.size.crouch) / 2.0;
                const test_pos = Vec3.new(p.pos.data[0], p.pos.data[1] + diff, p.pos.data[2]);
                const standing = Player.bounds.standbox(test_pos, Player.cfg.size.width, Player.cfg.size.stand);

                if (!Collision.checkStatic(world_map, standing)) {
                    p.pos.data[1] += diff;
                    p.crouch = false;
                }
            } else {
                p.crouch = wish;
            }
        }

        pub inline fn jump(p: *Player) void {
            if (p.io.pressed(.space) and p.ground) {
                p.vel.data[1] = cfg.jump_power;
                p.ground = false;
            }
        }

        pub inline fn camera(p: *Player) void {
            if (!p.io.mouse.locked()) return;

            p.yaw += p.io.mouse.dx * cfg.sensitivity;
            p.pitch = @max(-cfg.pitch_limit, @min(cfg.pitch_limit, p.pitch + p.io.mouse.dy * cfg.sensitivity));
        }

        pub fn blocks(p: *Player, world_map: *Map) bool {
            if (!p.io.mouse.locked()) return false;

            const look = Player.lookdir(p.yaw, p.pitch);
            const hit = Collision.raycast(world_map, p.pos, look, cfg.reach) orelse return false;
            const pos = [3]i32{
                @intFromFloat(@floor(hit.data[0])),
                @intFromFloat(@floor(hit.data[1])),
                @intFromFloat(@floor(hit.data[2])),
            };

            // Break block
            if (p.io.mouse.leftPressed()) {
                return world_map.set(pos[0], pos[1], pos[2], 0);
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

                const player_box = Player.bounds.bbox(p.pos, p.crouch, Player.cfg.size.crouch, Player.cfg.size.stand, Player.cfg.size.width);
                const block_box = Player.bounds.blockbox(block_pos);

                if (!Collision.bbox.overlaps(player_box, block_box)) {
                    return world_map.set(place_pos[0], place_pos[1], place_pos[2], p.block);
                }
            }

            // Pick block color
            if (p.io.justPressed(.r)) {
                const target = world_map.get(pos[0], pos[1], pos[2]);
                if (target != 0) p.block = target;
            }

            return false;
        }

        pub inline fn color(p: *Player) void {
            if (!p.io.mouse.locked()) return;

            if (p.io.justPressed(.q)) p.block -%= 1;
            if (p.io.justPressed(.e)) p.block +%= 1;
        }

        pub inline fn mouse(p: *Player) void {
            if (p.io.justPressed(.escape)) p.io.mouse.unlock();
            if (p.io.mouse.left and !p.io.mouse.locked()) p.io.mouse.lock();
        }
    };

    pub fn tick(player_ptr: *Player, world_map: *Map, dt: f32) bool {
        handle.movement(player_ptr, player_ptr.yaw, dt);
        handle.crouch(player_ptr, world_map);
        handle.jump(player_ptr);
        handle.camera(player_ptr);
        const world_changed = handle.blocks(player_ptr, world_map);
        handle.color(player_ptr);
        handle.mouse(player_ptr);
        return world_changed;
    }
};

pub const Collision = struct {
    pub const bbox = struct {
        min: Vec3,
        max: Vec3,

        pub inline fn at(b: bbox, p: Vec3) bbox {
            return .{ .min = p.add(b.min), .max = p.add(b.max) };
        }

        pub fn bounds(b: bbox, v: Vec3) struct { min: Vec3, max: Vec3 } {
            const sm = b.min.add(v);
            const sx = b.max.add(v);
            return .{ .min = Vec3.new(@min(sm.data[0], b.min.data[0]), @min(sm.data[1], b.min.data[1]), @min(sm.data[2], b.min.data[2])), .max = Vec3.new(@max(sx.data[0], b.max.data[0]), @max(sx.data[1], b.max.data[1]), @max(sx.data[2], b.max.data[2])) };
        }

        pub fn sweep(b: bbox, v: Vec3, o: bbox) ?struct { t: f32, n: Vec3 } {
            if (@sqrt(v.dot(v)) < 0.0001) return null;
            const inv = Vec3.new(if (v.data[0] != 0) 1 / v.data[0] else std.math.inf(f32), if (v.data[1] != 0) 1 / v.data[1] else std.math.inf(f32), if (v.data[2] != 0) 1 / v.data[2] else std.math.inf(f32));
            const tx = axis(b.min.data[0], b.max.data[0], o.min.data[0], o.max.data[0], inv.data[0]);
            const ty = axis(b.min.data[1], b.max.data[1], o.min.data[1], o.max.data[1], inv.data[1]);
            const tz = axis(b.min.data[2], b.max.data[2], o.min.data[2], o.max.data[2], inv.data[2]);
            const enter = @max(@max(tx.enter, ty.enter), tz.enter);
            const exit = @min(@min(tx.exit, ty.exit), tz.exit);
            if (enter > exit or enter > 1 or exit < 0 or enter < 0) return null;
            const n = if (tx.enter > ty.enter and tx.enter > tz.enter)
                Vec3.new(if (v.data[0] > 0) -1 else 1, 0, 0)
            else if (ty.enter > tz.enter)
                Vec3.new(0, if (v.data[1] > 0) -1 else 1, 0)
            else
                Vec3.new(0, 0, if (v.data[2] > 0) -1 else 1);
            return .{ .t = enter, .n = n };
        }

        inline fn axis(min1: f32, max1: f32, min2: f32, max2: f32, inv: f32) struct { enter: f32, exit: f32 } {
            const t1 = (min2 - max1) * inv;
            const t2 = (max2 - min1) * inv;
            return .{ .enter = @min(t1, t2), .exit = @max(t1, t2) };
        }

        pub inline fn overlaps(a: bbox, b: bbox) bool {
            return a.min.data[0] < b.max.data[0] and a.max.data[0] > b.min.data[0] and
                a.min.data[1] < b.max.data[1] and a.max.data[1] > b.min.data[1] and
                a.min.data[2] < b.max.data[2] and a.max.data[2] > b.min.data[2];
        }
    };

    pub fn raycast(w: anytype, pos: Vec3, dir: Vec3, dist: f32) ?Vec3 {
        var p = pos;
        const step_size = 0.1;
        const steps = @as(u32, @intFromFloat(dist / step_size));
        for (0..steps) |_| {
            p = p.add(dir.scale(step_size));
            const x = @as(i32, @intFromFloat(@floor(p.data[0])));
            const y = @as(i32, @intFromFloat(@floor(p.data[1])));
            const z = @as(i32, @intFromFloat(@floor(p.data[2])));
            if (w.get(x, y, z) != 0) return p;
        }
        return null;
    }

    pub fn sweep(w: anytype, pos: Vec3, box: bbox, vel: Vec3, comptime steps: comptime_int) struct { pos: Vec3, vel: Vec3, hit: bool } {
        var p = pos;
        var v = vel;
        var hit = false;
        const dt: f32 = 1.0 / @as(f32, @floatFromInt(steps));
        inline for (0..steps) |_| {
            const r = step(w, p, box, v.scale(dt));
            p = r.pos;
            v = r.vel.scale(1 / dt);
            if (r.hit) hit = true;
        }
        return .{ .pos = p, .vel = v, .hit = hit };
    }

    fn step(w: anytype, pos: Vec3, box: bbox, vel: Vec3) struct { pos: Vec3, vel: Vec3, hit: bool } {
        var p = pos;
        var v = vel;
        var hit = false;
        for (0..3) |_| {
            const pl = box.at(p);
            const rg = pl.bounds(v);
            var c: f32 = 1;
            var n = Vec3.zero();
            var f = false;
            const min_x = @as(i32, @intFromFloat(@floor(rg.min.data[0])));
            const max_x = @as(i32, @intFromFloat(@floor(rg.max.data[0])));
            const min_y = @as(i32, @intFromFloat(@floor(rg.min.data[1])));
            const max_y = @as(i32, @intFromFloat(@floor(rg.max.data[1])));
            const min_z = @as(i32, @intFromFloat(@floor(rg.min.data[2])));
            const max_z = @as(i32, @intFromFloat(@floor(rg.max.data[2])));

            var x = min_x;
            while (x <= max_x) : (x += 1) {
                var y = min_y;
                while (y <= max_y) : (y += 1) {
                    var z = min_z;
                    while (z <= max_z) : (z += 1) {
                        if (w.get(x, y, z) == 0) continue;
                        const b = Vec3.new(@as(f32, @floatFromInt(x)), @as(f32, @floatFromInt(y)), @as(f32, @floatFromInt(z)));
                        if (pl.sweep(v, .{ .min = b, .max = b.add(Vec3.new(1, 1, 1)) })) |col| if (col.t < c) {
                            c = col.t;
                            n = col.n;
                            f = true;
                        };
                    }
                }
            }
            if (!f) {
                p = p.add(v);
                break;
            }
            hit = true;
            p = p.add(v.scale(@max(0, c - 0.01)));
            const d = n.dot(v);
            v = v.sub(n.scale(d));
            if (@sqrt(v.dot(v)) < 0.0001) break;
        }
        return .{ .pos = p, .vel = v, .hit = hit };
    }

    pub fn checkStatic(w: anytype, aabb: bbox) bool {
        const min_x = @as(i32, @intFromFloat(@floor(aabb.min.data[0])));
        const max_x = @as(i32, @intFromFloat(@floor(aabb.max.data[0])));
        const min_y = @as(i32, @intFromFloat(@floor(aabb.min.data[1])));
        const max_y = @as(i32, @intFromFloat(@floor(aabb.max.data[1])));
        const min_z = @as(i32, @intFromFloat(@floor(aabb.min.data[2])));
        const max_z = @as(i32, @intFromFloat(@floor(aabb.max.data[2])));

        var x = min_x;
        while (x <= max_x) : (x += 1) {
            var y = min_y;
            while (y <= max_y) : (y += 1) {
                var z = min_z;
                while (z <= max_z) : (z += 1) {
                    if (w.get(x, y, z) != 0) return true;
                }
            }
        }
        return false;
    }
};
