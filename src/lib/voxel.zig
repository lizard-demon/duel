const std = @import("std");
const alg = @import("algebra.zig");
const Vec3 = alg.Vec3;
const rend = @import("render.zig");

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

pub fn OctreeWorld(comptime depth: comptime_int) type {
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

        pub fn buildMesh(self: *const @This(), verts: []rend.Vertex, indices: []u16, comptime colors: fn (Block) [3]f32) struct { vcount: usize, icount: usize } {
            var mask: [4096]bool = undefined;
            var vi: usize = 0;
            var ii: usize = 0;
            const Axis = struct { d: u2, u: u2, v: u2 };
            const axes = [_]Axis{
                .{ .d = 0, .u = 2, .v = 1 }, .{ .d = 0, .u = 1, .v = 2 },
                .{ .d = 1, .u = 0, .v = 2 }, .{ .d = 1, .u = 2, .v = 0 },
                .{ .d = 2, .u = 0, .v = 1 }, .{ .d = 2, .u = 1, .v = 0 },
            };
            const shades = [_]f32{ 0.8, 0.8, 1.0, 0.8, 0.8, 0.8 };
            for (axes, 0..) |ax, dir| {
                const dim = [3]usize{ @intCast(self.size), @intCast(self.size), @intCast(self.size) };
                for (0..2) |back| {
                    const stp: i32 = if (back == 0) 1 else -1;
                    var d: i32 = if (back == 0) 0 else @as(i32, @intCast(dim[ax.d])) - 1;
                    while ((back == 0 and d < @as(i32, @intCast(dim[ax.d]))) or (back == 1 and d >= 0)) : (d += stp) {
                        var n: usize = 0;
                        for (0..dim[ax.v]) |v| {
                            for (0..dim[ax.u]) |u| {
                                var pos = [3]i32{ 0, 0, 0 };
                                pos[ax.d] = d;
                                pos[ax.u] = @intCast(u);
                                pos[ax.v] = @intCast(v);
                                const blk = self.get(pos[0], pos[1], pos[2]);
                                if (blk == .air) {
                                    mask[n] = false;
                                    n += 1;
                                    continue;
                                }
                                pos[ax.d] += stp;
                                mask[n] = self.get(pos[0], pos[1], pos[2]) == .air;
                                n += 1;
                            }
                        }
                        n = 0;
                        for (0..dim[ax.v]) |v| {
                            var u: usize = 0;
                            while (u < dim[ax.u]) {
                                if (!mask[n]) {
                                    n += 1;
                                    u += 1;
                                    continue;
                                }
                                var pos = [3]i32{ 0, 0, 0 };
                                pos[ax.d] = d;
                                pos[ax.u] = @intCast(u);
                                pos[ax.v] = @intCast(v);
                                const blk = self.get(pos[0], pos[1], pos[2]);
                                var w: usize = 1;
                                while (u + w < dim[ax.u] and mask[n + w]) : (w += 1) {
                                    var p2 = pos;
                                    p2[ax.u] = @intCast(u + w);
                                    if (self.get(p2[0], p2[1], p2[2]) != blk) break;
                                }
                                var h: usize = 1;
                                outer: while (v + h < dim[ax.v]) : (h += 1) {
                                    for (0..w) |k| {
                                        if (!mask[n + k + h * dim[ax.u]]) break :outer;
                                        var p2 = pos;
                                        p2[ax.u] = @intCast(u + k);
                                        p2[ax.v] = @intCast(v + h);
                                        if (self.get(p2[0], p2[1], p2[2]) != blk) break :outer;
                                    }
                                }
                                const col = colors(blk);
                                const shade = shades[dir];
                                const fcol = [4]f32{ col[0] * shade, col[1] * shade, col[2] * shade, 1 };
                                var quad = [4][3]f32{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } };
                                var du = [3]f32{ 0, 0, 0 };
                                var dv = [3]f32{ 0, 0, 0 };
                                du[ax.u] = @floatFromInt(w);
                                dv[ax.v] = @floatFromInt(h);
                                const x: f32 = @floatFromInt(pos[0]);
                                const y: f32 = @floatFromInt(pos[1]);
                                const z: f32 = @floatFromInt(pos[2]);
                                quad[0] = .{ x, y, z };
                                if (back == 1) {
                                    quad[0][ax.d] += 1;
                                    quad[1] = .{ quad[0][0] + dv[0], quad[0][1] + dv[1], quad[0][2] + dv[2] };
                                    quad[2] = .{ quad[0][0] + du[0] + dv[0], quad[0][1] + du[1] + dv[1], quad[0][2] + du[2] + dv[2] };
                                    quad[3] = .{ quad[0][0] + du[0], quad[0][1] + du[1], quad[0][2] + du[2] };
                                } else {
                                    quad[1] = .{ quad[0][0] + du[0], quad[0][1] + du[1], quad[0][2] + du[2] };
                                    quad[2] = .{ quad[0][0] + du[0] + dv[0], quad[0][1] + du[1] + dv[1], quad[0][2] + du[2] + dv[2] };
                                    quad[3] = .{ quad[0][0] + dv[0], quad[0][1] + dv[1], quad[0][2] + dv[2] };
                                }
                                if (vi + 4 > verts.len or ii + 6 > indices.len) return .{ .vcount = vi, .icount = ii };
                                const base = @as(u16, @intCast(vi));
                                for (quad) |p| {
                                    verts[vi] = .{ .pos = p, .col = fcol };
                                    vi += 1;
                                }
                                for ([_]u16{ 0, 1, 2, 0, 2, 3 }) |idx| {
                                    indices[ii] = base + idx;
                                    ii += 1;
                                }
                                for (0..h) |j| {
                                    for (0..w) |i| mask[n + i + j * dim[ax.u]] = false;
                                }
                                n += w;
                                u += w;
                            }
                        }
                    }
                }
            }
            return .{ .vcount = vi, .icount = ii };
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
