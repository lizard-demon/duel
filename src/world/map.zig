const std = @import("std");
const alg = @import("../lib/algebra.zig");
const Vec3 = alg.Vec3;

pub const Block = enum(u8) { air, grass, dirt, stone };

pub const AABB = struct {
    min: Vec3,
    max: Vec3,

    pub fn at(self: AABB, pos: Vec3) AABB {
        return .{ .min = pos.add(self.min), .max = pos.add(self.max) };
    }

    pub fn bounds(self: AABB, vel: Vec3) struct { min: Vec3, max: Vec3 } {
        const swept_min = self.min.add(vel);
        const swept_max = self.max.add(vel);
        return .{
            .min = Vec3.new(@min(swept_min.data[0], self.min.data[0]), @min(swept_min.data[1], self.min.data[1]), @min(swept_min.data[2], self.min.data[2])),
            .max = Vec3.new(@max(swept_max.data[0], self.max.data[0]), @max(swept_max.data[1], self.max.data[1]), @max(swept_max.data[2], self.max.data[2])),
        };
    }

    pub fn sweep(self: AABB, vel: Vec3, other: AABB) ?struct { t: f32, n: Vec3 } {
        const len = @sqrt(vel.dot(vel));
        if (len < 0.0001) return null;
        const inv = Vec3.new(
            if (vel.data[0] != 0) 1.0 / vel.data[0] else std.math.inf(f32),
            if (vel.data[1] != 0) 1.0 / vel.data[1] else std.math.inf(f32),
            if (vel.data[2] != 0) 1.0 / vel.data[2] else std.math.inf(f32),
        );
        const tx = axis(self.min.data[0], self.max.data[0], other.min.data[0], other.max.data[0], inv.data[0]);
        const ty = axis(self.min.data[1], self.max.data[1], other.min.data[1], other.max.data[1], inv.data[1]);
        const tz = axis(self.min.data[2], self.max.data[2], other.min.data[2], other.max.data[2], inv.data[2]);
        const enter = @max(@max(tx.enter, ty.enter), tz.enter);
        const exit = @min(@min(tx.exit, ty.exit), tz.exit);
        if (enter > exit or enter > 1.0 or exit < 0.0 or enter < 0.0) return null;
        const n = if (tx.enter > ty.enter and tx.enter > tz.enter)
            Vec3.new(if (vel.data[0] > 0) -1 else 1, 0, 0)
        else if (ty.enter > tz.enter)
            Vec3.new(0, if (vel.data[1] > 0) -1 else 1, 0)
        else
            Vec3.new(0, 0, if (vel.data[2] > 0) -1 else 1);
        return .{ .t = enter, .n = n };
    }

    fn axis(min1: f32, max1: f32, min2: f32, max2: f32, inv: f32) struct { enter: f32, exit: f32 } {
        const t1 = (min2 - max1) * inv;
        const t2 = (max2 - min1) * inv;
        return .{ .enter = @min(t1, t2), .exit = @max(t1, t2) };
    }
};

pub const World = struct {
    blocks: [64][64][64]Block,
    size: i32 = 64,

    pub fn init() World {
        var world = World{ .blocks = undefined };
        for (0..64) |x| {
            for (0..64) |y| {
                for (0..64) |z| {
                    const edge = x == 0 or x == 63 or z == 0 or z == 63;
                    world.blocks[x][y][z] = if (edge)
                        if (y < 63) .stone else .grass
                    else if (y == 0) .grass else .air;
                }
            }
        }
        return world;
    }

    pub fn get(self: *const World, x: i32, y: i32, z: i32) Block {
        if (x < 0 or x >= 64 or y < 0 or y >= 64 or z < 0 or z >= 64) return .air;
        return self.blocks[@intCast(x)][@intCast(y)][@intCast(z)];
    }

    pub fn solid(self: *const World, x: i32, y: i32, z: i32) bool {
        return self.get(x, y, z) != .air;
    }

    pub fn sweep(self: *const World, pos: Vec3, box: AABB, vel: Vec3, comptime steps: comptime_int) struct { pos: Vec3, vel: Vec3, hit: bool } {
        var p = pos;
        var v = vel;
        var hit = false;
        const dt: f32 = 1.0 / @as(f32, @floatFromInt(steps));
        inline for (0..steps) |_| {
            const r = self.step(p, box, v.scale(dt));
            p = r.pos;
            v = r.vel.scale(1.0 / dt);
            if (r.hit) hit = true;
        }
        return .{ .pos = p, .vel = v, .hit = hit };
    }

    fn step(self: *const World, pos: Vec3, box: AABB, vel: Vec3) struct { pos: Vec3, vel: Vec3, hit: bool } {
        var p = pos;
        var v = vel;
        var hit = false;
        for (0..3) |_| {
            const player = box.at(p);
            const region = player.bounds(v);
            var closest: f32 = 1.0;
            var n = Vec3.zero();
            var found = false;
            var bx = @as(i32, @intFromFloat(@floor(region.min.data[0])));
            while (bx <= @as(i32, @intFromFloat(@floor(region.max.data[0])))) : (bx += 1) {
                var by = @as(i32, @intFromFloat(@floor(region.min.data[1])));
                while (by <= @as(i32, @intFromFloat(@floor(region.max.data[1])))) : (by += 1) {
                    var bz = @as(i32, @intFromFloat(@floor(region.min.data[2])));
                    while (bz <= @as(i32, @intFromFloat(@floor(region.max.data[2])))) : (bz += 1) {
                        if (!self.solid(bx, by, bz)) continue;
                        const b = Vec3.new(@floatFromInt(bx), @floatFromInt(by), @floatFromInt(bz));
                        if (player.sweep(v, .{ .min = b, .max = b.add(Vec3.new(1, 1, 1)) })) |col| {
                            if (col.t < closest) {
                                closest = col.t;
                                n = col.n;
                                found = true;
                            }
                        }
                    }
                }
            }
            if (!found) {
                p = p.add(v);
                break;
            }
            hit = true;
            p = p.add(v.scale(@max(0, closest - 0.001)));
            const dot = n.dot(v);
            v.data[0] -= n.data[0] * dot;
            v.data[1] -= n.data[1] * dot;
            v.data[2] -= n.data[2] * dot;
            if (@sqrt(v.dot(v)) < 0.0001) break;
        }
        return .{ .pos = p, .vel = v, .hit = hit };
    }

    pub fn deinit(_: *World) void {}
};
