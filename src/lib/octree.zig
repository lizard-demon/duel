const std = @import("std");
const alg = @import("algebra.zig");
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
            .min = Vec3.new(@min(swept_min.x(), self.min.x()), @min(swept_min.y(), self.min.y()), @min(swept_min.z(), self.min.z())),
            .max = Vec3.new(@max(swept_max.x(), self.max.x()), @max(swept_max.y(), self.max.y()), @max(swept_max.z(), self.max.z())),
        };
    }

    pub fn sweep(self: AABB, vel: Vec3, other: AABB) ?struct { t: f32, n: Vec3 } {
        if (vel.length() < 0.0001) return null;
        const inv = Vec3.new(
            if (vel.x() != 0) 1.0 / vel.x() else std.math.inf(f32),
            if (vel.y() != 0) 1.0 / vel.y() else std.math.inf(f32),
            if (vel.z() != 0) 1.0 / vel.z() else std.math.inf(f32),
        );
        const tx = axis(self.min.x(), self.max.x(), other.min.x(), other.max.x(), inv.x());
        const ty = axis(self.min.y(), self.max.y(), other.min.y(), other.max.y(), inv.y());
        const tz = axis(self.min.z(), self.max.z(), other.min.z(), other.max.z(), inv.z());
        const enter = @max(@max(tx.enter, ty.enter), tz.enter);
        const exit = @min(@min(tx.exit, ty.exit), tz.exit);
        if (enter > exit or enter > 1.0 or exit < 0.0 or enter < 0.0) return null;
        const n = if (tx.enter > ty.enter and tx.enter > tz.enter)
            Vec3.new(if (vel.x() > 0) -1 else 1, 0, 0)
        else if (ty.enter > tz.enter)
            Vec3.new(0, if (vel.y() > 0) -1 else 1, 0)
        else
            Vec3.new(0, 0, if (vel.z() > 0) -1 else 1);
        return .{ .t = enter, .n = n };
    }

    fn axis(min1: f32, max1: f32, min2: f32, max2: f32, inv: f32) struct { enter: f32, exit: f32 } {
        const t1 = (min2 - max1) * inv;
        const t2 = (max2 - min1) * inv;
        return .{ .enter = @min(t1, t2), .exit = @max(t1, t2) };
    }
};

pub fn Octree(comptime depth: comptime_int) type {
    return struct {
        root: Node,
        size: i32,

        const Node = union(enum) {
            leaf: Block,
            branch: *[8]Node,
        };

        pub fn init() @This() {
            const size = std.math.shl(i32, 1, depth);
            var world: @This() = .{ .root = undefined, .size = size };
            world.root = world.generate(0, 0, 0, size);
            return world;
        }

        fn generate(self: *@This(), x: i32, y: i32, z: i32, s: i32) Node {
            if (s == 1) {
                const edge = x == 0 or x == self.size - 1 or z == 0 or z == self.size - 1;
                return .{ .leaf = if (edge)
                    if (y < self.size - 1) .stone else .grass
                else if (y == 0) .grass else .air };
            }
            const h = @divExact(s, 2);
            var uniform: ?Block = null;
            var children = std.heap.page_allocator.create([8]Node) catch unreachable;
            for (0..8) |i| {
                const cx = x + if (i & 1 != 0) h else 0;
                const cy = y + if (i & 2 != 0) h else 0;
                const cz = z + if (i & 4 != 0) h else 0;
                children[i] = self.generate(cx, cy, cz, h);
                const b = switch (children[i]) {
                    .leaf => |blk| blk,
                    else => null,
                };
                if (i == 0) {
                    uniform = b;
                } else if (uniform != b) {
                    uniform = null;
                }
            }
            if (uniform) |blk| {
                std.heap.page_allocator.destroy(children);
                return .{ .leaf = blk };
            }
            return .{ .branch = children };
        }

        pub fn get(self: *const @This(), px: i32, py: i32, pz: i32) Block {
            if (px < 0 or px >= self.size or py < 0 or py >= self.size or pz < 0 or pz >= self.size) return .air;
            var node = &self.root;
            var x: i32 = 0;
            var y: i32 = 0;
            var z: i32 = 0;
            var s = self.size;
            while (true) {
                switch (node.*) {
                    .leaf => |blk| return blk,
                    .branch => |children| {
                        s = @divExact(s, 2);
                        const i: usize = (if (px >= x + s) @as(usize, 1) else 0) |
                            (if (py >= y + s) @as(usize, 2) else 0) |
                            (if (pz >= z + s) @as(usize, 4) else 0);
                        if (px >= x + s) x += s;
                        if (py >= y + s) y += s;
                        if (pz >= z + s) z += s;
                        node = &children[i];
                    },
                }
            }
        }

        pub fn solid(self: *const @This(), x: i32, y: i32, z: i32) bool {
            return self.get(x, y, z) != .air;
        }

        pub fn sweep(self: *const @This(), pos: Vec3, box: AABB, vel: Vec3, comptime steps: comptime_int) struct { pos: Vec3, vel: Vec3, hit: bool } {
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

        fn step(self: *const @This(), pos: Vec3, box: AABB, vel: Vec3) struct { pos: Vec3, vel: Vec3, hit: bool } {
            var p = pos;
            var v = vel;
            var hit = false;
            for (0..3) |_| {
                const player = box.at(p);
                const region = player.bounds(v);
                var closest: f32 = 1.0;
                var n = Vec3.zero();
                var found = false;
                var bx = @as(i32, @intFromFloat(@floor(region.min.x())));
                while (bx <= @as(i32, @intFromFloat(@floor(region.max.x())))) : (bx += 1) {
                    var by = @as(i32, @intFromFloat(@floor(region.min.y())));
                    while (by <= @as(i32, @intFromFloat(@floor(region.max.y())))) : (by += 1) {
                        var bz = @as(i32, @intFromFloat(@floor(region.min.z())));
                        while (bz <= @as(i32, @intFromFloat(@floor(region.max.z())))) : (bz += 1) {
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
                v = v.sub(n.scale(n.dot(v)));
                if (v.length() < 0.0001) break;
            }
            return .{ .pos = p, .vel = v, .hit = hit };
        }

        pub fn deinit(self: *@This()) void {
            self.freeNode(&self.root);
        }

        fn freeNode(_: *@This(), node: *Node) void {
            switch (node.*) {
                .leaf => {},
                .branch => |children| {
                    for (children) |*child| {
                        _ = child;
                    }
                    std.heap.page_allocator.destroy(children);
                },
            }
        }
    };
}
