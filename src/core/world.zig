const std = @import("std");
const math = @import("../lib/math.zig");
const gfx = @import("render.zig");
const Vec3 = math.Vec3;

pub const Block = u8;

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
};

pub const World = struct {
    blocks: [64][64][64]Block,

    fn hsvToRgb(h: f32, s: f32, v: f32) [3]f32 {
        const c = v * s;
        const x = c * (1.0 - @abs(@mod(h / 60.0, 2.0) - 1.0));
        const m = v - c;

        const rgb = if (h < 60.0) [3]f32{ c, x, 0 } else if (h < 120.0) [3]f32{ x, c, 0 } else if (h < 180.0) [3]f32{ 0, c, x } else if (h < 240.0) [3]f32{ 0, x, c } else if (h < 300.0) [3]f32{ x, 0, c } else [3]f32{ c, 0, x };

        return .{ rgb[0] + m, rgb[1] + m, rgb[2] + m };
    }

    pub fn color(block: Block) [3]f32 {
        if (block == 0) return .{ 0, 0, 0 }; // air

        const idx = block - 1; // 0-254 range

        // Single black + full HSV coverage
        if (idx == 0) return .{ 0, 0, 0 }; // Pure black for color 1

        const adjusted_idx = idx - 1; // 0-253 range for remaining colors
        const h_steps = 6;
        const s_steps = 6;
        const v_steps = 7;

        const h_idx = adjusted_idx % h_steps;
        const s_idx = (adjusted_idx / h_steps) % s_steps;
        const v_idx = adjusted_idx / (h_steps * s_steps);

        const hue = @as(f32, @floatFromInt(h_idx)) / @as(f32, h_steps) * 360.0;
        const sat = @as(f32, @floatFromInt(s_idx)) / @as(f32, s_steps - 1);
        const val = 0.2 + @as(f32, @floatFromInt(v_idx)) / @as(f32, v_steps - 1) * 0.8; // 0.2-1.0 (avoid more blacks)

        return hsvToRgb(hue, sat, val);
    }
    pub fn init() World {
        var w = World{ .blocks = std.mem.zeroes([64][64][64]Block) };
        for (0..64) |x| for (0..64) |y| for (0..64) |z| {
            const is_wall = x == 0 or x == 63 or z == 0 or z == 63;
            const is_floor = y == 0;
            w.blocks[x][y][z] = if (is_wall and y <= 2) 110 else if (is_floor) 100 else 0;
        };
        return w;
    }
    pub fn get(w: *const World, x: i32, y: i32, z: i32) Block {
        if (x < 0 or x >= 64 or y < 0 or y >= 64 or z < 0 or z >= 64) return 0;
        return w.blocks[@intCast(x)][@intCast(y)][@intCast(z)];
    }

    pub fn set(w: *World, x: i32, y: i32, z: i32, block: Block) bool {
        if (x < 0 or x >= 64 or y < 0 or y >= 64 or z < 0 or z >= 64) return false;
        const old_block = w.blocks[@intCast(x)][@intCast(y)][@intCast(z)];
        if (old_block == block) return false;
        w.blocks[@intCast(x)][@intCast(y)][@intCast(z)] = block;
        return true;
    }

    pub fn raycast(w: *const World, pos: Vec3, dir: Vec3, dist: f32) ?Vec3 {
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

    pub fn sweep(w: *const World, pos: Vec3, box: AABB, vel: Vec3, comptime steps: comptime_int) struct { pos: Vec3, vel: Vec3, hit: bool } {
        var p = pos;
        var v = vel;
        var hit = false;
        const dt: f32 = 1.0 / @as(f32, @floatFromInt(steps));
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
        var vi: usize = 0;
        var ii: usize = 0;
        const shades = [_]f32{ 0.8, 0.8, 1.0, 0.8, 0.8, 0.8 };

        // Use a struct to store face info instead of bit packing
        const FaceInfo = struct { block: Block, is_back: bool };
        var mask: [64 * 64]FaceInfo = undefined;

        // Greedy meshing - sweep each axis
        inline for (0..3) |axis| {
            const u = (axis + 1) % 3;
            const v = (axis + 2) % 3;

            var d: i32 = 0;
            while (d < 64) : (d += 1) {
                @memset(&mask, .{ .block = 0, .is_back = false });

                // Build face mask for this slice
                for (0..64) |j| {
                    for (0..64) |i| {
                        var pos1 = [3]i32{ 0, 0, 0 };
                        var pos2 = [3]i32{ 0, 0, 0 };
                        pos1[axis] = d - 1;
                        pos2[axis] = d;
                        pos1[u] = @intCast(i);
                        pos1[v] = @intCast(j);
                        pos2[u] = @intCast(i);
                        pos2[v] = @intCast(j);

                        const b1 = w.get(pos1[0], pos1[1], pos1[2]);
                        const b2 = w.get(pos2[0], pos2[1], pos2[2]);

                        // Face exists if blocks differ and one is solid
                        if (b1 != 0 and b2 == 0) {
                            mask[j * 64 + i] = .{ .block = b1, .is_back = false };
                        } else if (b1 == 0 and b2 != 0) {
                            mask[j * 64 + i] = .{ .block = b2, .is_back = true };
                        }
                    }
                }

                // Generate quads from mask
                var j: usize = 0;
                while (j < 64) : (j += 1) {
                    var i: usize = 0;
                    while (i < 64) {
                        const face_info = mask[j * 64 + i];
                        if (face_info.block == 0) {
                            i += 1;
                            continue;
                        }

                        // Find width - extend right while same face
                        var width: usize = 1;
                        while (i + width < 64) {
                            const next_face = mask[j * 64 + i + width];
                            if (next_face.block != face_info.block or next_face.is_back != face_info.is_back) break;
                            width += 1;
                        }

                        // Find height - extend up while entire row matches
                        var height: usize = 1;
                        while (j + height < 64) {
                            var row_matches = true;
                            for (0..width) |k| {
                                const check_face = mask[(j + height) * 64 + i + k];
                                if (check_face.block != face_info.block or check_face.is_back != face_info.is_back) {
                                    row_matches = false;
                                    break;
                                }
                            }
                            if (!row_matches) break;
                            height += 1;
                        }

                        // Clear processed area
                        for (0..height) |h| {
                            for (0..width) |w_idx| {
                                mask[(j + h) * 64 + i + w_idx] = .{ .block = 0, .is_back = false };
                            }
                        }

                        // Generate quad vertices
                        if (vi + 4 > verts.len or ii + 6 > indices.len) return .{ .verts = vi, .indices = ii };

                        const col = colors(face_info.block);
                        const shade_offset: usize = if (face_info.is_back) 0 else 1;
                        const shade_idx = axis * 2 + shade_offset;
                        const shade = shades[shade_idx];
                        const fcol = [4]f32{ col[0] * shade, col[1] * shade, col[2] * shade, 1 };

                        // Calculate face position correctly
                        const face_pos: f32 = @floatFromInt(d);

                        var quad = [4][3]f32{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } };

                        quad[0][axis] = face_pos;
                        quad[0][u] = @floatFromInt(i);
                        quad[0][v] = @floatFromInt(j);

                        quad[1][axis] = face_pos;
                        quad[1][u] = @floatFromInt(i);
                        quad[1][v] = @floatFromInt(j + height);

                        quad[2][axis] = face_pos;
                        quad[2][u] = @floatFromInt(i + width);
                        quad[2][v] = @floatFromInt(j + height);

                        quad[3][axis] = face_pos;
                        quad[3][u] = @floatFromInt(i + width);
                        quad[3][v] = @floatFromInt(j);

                        const base = @as(u16, @intCast(vi));

                        // Wind vertices correctly for face direction
                        if (face_info.is_back) {
                            verts[vi] = .{ .pos = quad[0], .col = fcol };
                            verts[vi + 1] = .{ .pos = quad[3], .col = fcol };
                            verts[vi + 2] = .{ .pos = quad[2], .col = fcol };
                            verts[vi + 3] = .{ .pos = quad[1], .col = fcol };
                        } else {
                            verts[vi] = .{ .pos = quad[0], .col = fcol };
                            verts[vi + 1] = .{ .pos = quad[1], .col = fcol };
                            verts[vi + 2] = .{ .pos = quad[2], .col = fcol };
                            verts[vi + 3] = .{ .pos = quad[3], .col = fcol };
                        }

                        vi += 4;

                        for ([_]u16{ 0, 1, 2, 0, 2, 3 }) |idx| {
                            indices[ii] = base + idx;
                            ii += 1;
                        }

                        i += width;
                    }
                }
            }
        }
        return .{ .verts = vi, .indices = ii };
    }
};
