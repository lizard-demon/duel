const std = @import("std");
const math = @import("../lib/math.zig");

const Vec3 = math.Vec3;

pub const AABB = struct {
    min: Vec3,
    max: Vec3,

    pub fn at(b: AABB, p: Vec3) AABB {
        return .{ .min = p.add(b.min), .max = p.add(b.max) };
    }

    pub fn bounds(b: AABB, v: Vec3) struct { min: Vec3, max: Vec3 } {
        const sm = b.min.add(v);
        const sx = b.max.add(v);
        return .{ .min = Vec3.new(@min(sm.data[0], b.min.data[0]), @min(sm.data[1], b.min.data[1]), @min(sm.data[2], b.min.data[2])), .max = Vec3.new(@max(sx.data[0], b.max.data[0]), @max(sx.data[1], b.max.data[1]), @max(sx.data[2], b.max.data[2])) };
    }

    pub fn sweep(b: AABB, v: Vec3, o: AABB) ?struct { t: f32, n: Vec3 } {
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

    fn axis(min1: f32, max1: f32, min2: f32, max2: f32, inv: f32) struct { enter: f32, exit: f32 } {
        const t1 = (min2 - max1) * inv;
        const t2 = (max2 - min1) * inv;
        return .{ .enter = @min(t1, t2), .exit = @max(t1, t2) };
    }

    pub fn overlaps(a: AABB, b: AABB) bool {
        return a.min.data[0] < b.max.data[0] and a.max.data[0] > b.min.data[0] and
            a.min.data[1] < b.max.data[1] and a.max.data[1] > b.min.data[1] and
            a.min.data[2] < b.max.data[2] and a.max.data[2] > b.min.data[2];
    }
};

pub fn raycast(world: anytype, pos: Vec3, dir: Vec3, dist: f32) ?Vec3 {
    var p = pos;
    const step_size = 0.1;
    const steps = @as(u32, @intFromFloat(dist / step_size));
    for (0..steps) |_| {
        p = p.add(dir.scale(step_size));
        const x = @as(i32, @intFromFloat(@floor(p.data[0])));
        const y = @as(i32, @intFromFloat(@floor(p.data[1])));
        const z = @as(i32, @intFromFloat(@floor(p.data[2])));
        if (world.get(x, y, z) != 0) return p;
    }
    return null;
}

pub fn sweep(world: anytype, pos: Vec3, box: AABB, vel: Vec3, comptime steps: comptime_int) struct { pos: Vec3, vel: Vec3, hit: bool } {
    var p = pos;
    var v = vel;
    var hit = false;
    const dt: f32 = 1.0 / @as(f32, @floatFromInt(steps));
    inline for (0..steps) |_| {
        const r = step(world, p, box, v.scale(dt));
        p = r.pos;
        v = r.vel.scale(1 / dt);
        if (r.hit) hit = true;
    }
    return .{ .pos = p, .vel = v, .hit = hit };
}

fn step(world: anytype, pos: Vec3, box: AABB, vel: Vec3) struct { pos: Vec3, vel: Vec3, hit: bool } {
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
                    if (world.get(x, y, z) == 0) continue;
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

pub fn checkStaticCollision(world: anytype, aabb: AABB) bool {
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
                if (world.get(x, y, z) != 0) {
                    return true;
                }
            }
        }
    }
    return false;
}
