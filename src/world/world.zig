const std = @import("std");
const math = @import("../lib/math.zig");
const gfx = @import("render.zig");
const Vec3 = math.Vec3;

pub const Block = enum(u8) { air, grass, dirt, stone };

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

    pub fn color(block: Block) [3]f32 {
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
    pub fn get(w: *const World, x: i32, y: i32, z: i32) Block {
        if (x < 0 or x >= 64 or y < 0 or y >= 64 or z < 0 or z >= 64) return .air;
        return w.blocks[@intCast(x)][@intCast(y)][@intCast(z)];
    }
    pub fn solid(w: *const World, x: i32, y: i32, z: i32) bool {
        return w.get(x, y, z) != .air;
    }

    pub fn sweep(w: *const World, pos: Vec3, box: AABB, vel: Vec3, comptime steps: comptime_int) struct { pos: Vec3, vel: Vec3, hit: bool } {
        var p = pos;
        var v = vel;
        var hit = false;
        const dt: f32 = 1 / @as(f32, @floatFromInt(steps));
        inline for (0..steps) |_| {
            const r = w.step(p, box, v.scale(dt));
            p = r.pos;
            v = r.vel.scale(1 / dt);
            if (r.hit) hit = true;
        }
        return .{ .pos = p, .vel = v, .hit = hit };
    }

    fn step(w: *const World, pos: Vec3, box: AABB, vel: Vec3) struct { pos: Vec3, vel: Vec3, hit: bool } {
        var p = pos;
        var v = vel;
        var hit = false;
        for (0..3) |_| {
            const pl = box.at(p);
            const rg = pl.bounds(v);
            var c: f32 = 1;
            var n = Vec3.zero();
            var f = false;
            var x = @as(i32, @intFromFloat(@floor(rg.min.data[0])));
            while (x <= @as(i32, @intFromFloat(@floor(rg.max.data[0])))) : (x += 1) {
                var y = @as(i32, @intFromFloat(@floor(rg.min.data[1])));
                while (y <= @as(i32, @intFromFloat(@floor(rg.max.data[1])))) : (y += 1) {
                    var z = @as(i32, @intFromFloat(@floor(rg.min.data[2])));
                    while (z <= @as(i32, @intFromFloat(@floor(rg.max.data[2])))) : (z += 1) {
                        if (!w.solid(x, y, z)) continue;
                        const b = Vec3.new(@floatFromInt(x), @floatFromInt(y), @floatFromInt(z));
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

    pub fn mesh(w: *const World, verts: []gfx.Vertex, indices: []u16, comptime colors: fn (Block) [3]f32) struct { verts: usize, indices: usize } {
        var mask: [4096]bool = std.mem.zeroes([4096]bool);
        var vi: usize = 0;
        var ii: usize = 0;
        const Axis = struct { d: u2, u: u2, v: u2 };
        const axes = [_]Axis{ .{ .d = 0, .u = 2, .v = 1 }, .{ .d = 0, .u = 1, .v = 2 }, .{ .d = 1, .u = 0, .v = 2 }, .{ .d = 1, .u = 2, .v = 0 }, .{ .d = 2, .u = 0, .v = 1 }, .{ .d = 2, .u = 1, .v = 0 } };
        const shades = [_]f32{ 0.8, 0.8, 1.0, 0.8, 0.8, 0.8 };
        for (axes, 0..) |ax, dir| {
            for (0..2) |back| {
                const stp: i32 = if (back == 0) 1 else -1;
                var d: i32 = if (back == 0) 0 else 63;
                while ((back == 0 and d < 64) or (back == 1 and d >= 0)) : (d += stp) {
                    var n: usize = 0;
                    for (0..64) |v| {
                        for (0..64) |u| {
                            var pos = [3]i32{ 0, 0, 0 };
                            pos[ax.d] = d;
                            pos[ax.u] = @intCast(u);
                            pos[ax.v] = @intCast(v);
                            const blk = w.get(pos[0], pos[1], pos[2]);
                            if (blk == .air) {
                                mask[n] = false;
                                n += 1;
                                continue;
                            }
                            pos[ax.d] += stp;
                            mask[n] = w.get(pos[0], pos[1], pos[2]) == .air;
                            n += 1;
                        }
                    }
                    n = 0;
                    for (0..64) |v| {
                        var u: usize = 0;
                        while (u < 64) {
                            if (!mask[n]) {
                                n += 1;
                                u += 1;
                                continue;
                            }
                            var pos = [3]i32{ 0, 0, 0 };
                            pos[ax.d] = d;
                            pos[ax.u] = @intCast(u);
                            pos[ax.v] = @intCast(v);
                            const blk = w.get(pos[0], pos[1], pos[2]);
                            var wid: usize = 1;
                            while (u + wid < 64 and mask[n + wid]) : (wid += 1) {
                                var p2 = pos;
                                p2[ax.u] = @intCast(u + wid);
                                if (w.get(p2[0], p2[1], p2[2]) != blk) break;
                            }
                            var h: usize = 1;
                            outer: while (v + h < 64) : (h += 1) {
                                for (0..wid) |k| {
                                    if (!mask[n + k + h * 64]) break :outer;
                                    var p2 = pos;
                                    p2[ax.u] = @intCast(u + k);
                                    p2[ax.v] = @intCast(v + h);
                                    if (w.get(p2[0], p2[1], p2[2]) != blk) break :outer;
                                }
                            }
                            const col = colors(blk);
                            const shade = shades[dir];
                            const fcol = [4]f32{ col[0] * shade, col[1] * shade, col[2] * shade, 1 };
                            var quad = [4][3]f32{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } };
                            var du = [3]f32{ 0, 0, 0 };
                            var dv = [3]f32{ 0, 0, 0 };
                            du[ax.u] = @floatFromInt(wid);
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
                            if (vi + 4 > verts.len or ii + 6 > indices.len) return .{ .verts = vi, .indices = ii };
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
                                for (0..wid) |i| mask[n + i + j * 64] = false;
                            }
                            n += wid;
                            u += wid;
                        }
                    }
                }
            }
        }
        return .{ .verts = vi, .indices = ii };
    }

    pub fn deinit(_: *World) void {}
};
