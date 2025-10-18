const std = @import("std");
const alg = @import("../lib/algebra.zig");
const Vec3 = alg.Vec3;

pub const Block = enum(u8) { air, grass, dirt, stone };

pub const AABB = struct {
    min: Vec3,
    max: Vec3,
    pub fn at(s: AABB, p: Vec3) AABB {
        return .{ .min = p.add(s.min), .max = p.add(s.max) };
    }
    pub fn bounds(s: AABB, v: Vec3) struct { min: Vec3, max: Vec3 } {
        const sm = s.min.add(v);
        const sx = s.max.add(v);
        return .{ .min = Vec3.new(@min(sm.data[0], s.min.data[0]), @min(sm.data[1], s.min.data[1]), @min(sm.data[2], s.min.data[2])), .max = Vec3.new(@max(sx.data[0], s.max.data[0]), @max(sx.data[1], s.max.data[1]), @max(sx.data[2], s.max.data[2])) };
    }

    pub fn sweep(s: AABB, v: Vec3, o: AABB) ?struct { t: f32, n: Vec3 } {
        if (@sqrt(v.dot(v)) < 0.0001) return null;
        const inv = Vec3.new(if (v.data[0] != 0) 1 / v.data[0] else std.math.inf(f32), if (v.data[1] != 0) 1 / v.data[1] else std.math.inf(f32), if (v.data[2] != 0) 1 / v.data[2] else std.math.inf(f32));
        const tx = axis(s.min.data[0], s.max.data[0], o.min.data[0], o.max.data[0], inv.data[0]);
        const ty = axis(s.min.data[1], s.max.data[1], o.min.data[1], o.max.data[1], inv.data[1]);
        const tz = axis(s.min.data[2], s.max.data[2], o.min.data[2], o.max.data[2], inv.data[2]);
        const e = @max(@max(tx.enter, ty.enter), tz.enter);
        const x = @min(@min(tx.exit, ty.exit), tz.exit);
        if (e > x or e > 1 or x < 0 or e < 0) return null;
        const n = if (tx.enter > ty.enter and tx.enter > tz.enter) Vec3.new(if (v.data[0] > 0) -1 else 1, 0, 0) else if (ty.enter > tz.enter) Vec3.new(0, if (v.data[1] > 0) -1 else 1, 0) else Vec3.new(0, 0, if (v.data[2] > 0) -1 else 1);
        return .{ .t = e, .n = n };
    }
    fn axis(min1: f32, max1: f32, min2: f32, max2: f32, inv: f32) struct { enter: f32, exit: f32 } {
        const t1 = (min2 - max1) * inv;
        const t2 = (max2 - min1) * inv;
        return .{ .enter = @min(t1, t2), .exit = @max(t1, t2) };
    }
};

pub const World = struct {
    blocks: [64][64][64]Block,

    const COLORS = [_][3]f32{
        .{ 0, 0, 0 }, // air
        .{ 0.3, 0.7, 0.3 }, // grass
        .{ 0.5, 0.35, 0.2 }, // dirt
        .{ 0.5, 0.5, 0.5 }, // stone
    };

    pub fn blockColor(block: Block) [3]f32 {
        return COLORS[@intFromEnum(block)];
    }
    pub fn init() World {
        var w = World{ .blocks = std.mem.zeroes([64][64][64]Block) };
        for (0..64) |x| for (0..64) |y| for (0..64) |z| {
            const e = x == 0 or x == 63 or z == 0 or z == 63;
            w.blocks[x][y][z] = if (e) if (y < 63) .stone else .grass else if (y == 0) .grass else .air;
        };
        return w;
    }
    pub fn get(s: *const World, x: i32, y: i32, z: i32) Block {
        if (x < 0 or x >= 64 or y < 0 or y >= 64 or z < 0 or z >= 64) return .air;
        return s.blocks[@intCast(x)][@intCast(y)][@intCast(z)];
    }
    pub fn solid(s: *const World, x: i32, y: i32, z: i32) bool {
        return s.get(x, y, z) != .air;
    }

    pub fn sweep(s: *const World, pos: Vec3, box: AABB, vel: Vec3, comptime steps: comptime_int) struct { pos: Vec3, vel: Vec3, hit: bool } {
        var p = pos;
        var v = vel;
        var hit = false;
        const dt: f32 = 1 / @as(f32, @floatFromInt(steps));
        inline for (0..steps) |_| {
            const r = s.step(p, box, v.scale(dt));
            p = r.pos;
            v = r.vel.scale(1 / dt);
            if (r.hit) hit = true;
        }
        return .{ .pos = p, .vel = v, .hit = hit };
    }

    fn step(s: *const World, pos: Vec3, box: AABB, vel: Vec3) struct { pos: Vec3, vel: Vec3, hit: bool } {
        var p = pos;
        var v = vel;
        var hit = false;
        for (0..3) |_| {
            const pl = box.at(p);
            const rg = pl.bounds(v);
            var c: f32 = 1;
            var n = Vec3.zero();
            var f = false;
            var bx = @as(i32, @intFromFloat(@floor(rg.min.data[0])));
            while (bx <= @as(i32, @intFromFloat(@floor(rg.max.data[0])))) : (bx += 1) {
                var by = @as(i32, @intFromFloat(@floor(rg.min.data[1])));
                while (by <= @as(i32, @intFromFloat(@floor(rg.max.data[1])))) : (by += 1) {
                    var bz = @as(i32, @intFromFloat(@floor(rg.min.data[2])));
                    while (bz <= @as(i32, @intFromFloat(@floor(rg.max.data[2])))) : (bz += 1) {
                        if (!s.solid(bx, by, bz)) continue;
                        const b = Vec3.new(@floatFromInt(bx), @floatFromInt(by), @floatFromInt(bz));
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
            p = p.add(v.scale(@max(0, c - 0.001)));
            const d = n.dot(v);
            v.data[0] -= n.data[0] * d;
            v.data[1] -= n.data[1] * d;
            v.data[2] -= n.data[2] * d;
            if (@sqrt(v.dot(v)) < 0.0001) break;
        }
        return .{ .pos = p, .vel = v, .hit = hit };
    }
    pub fn deinit(_: *World) void {}
};
