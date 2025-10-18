const std = @import("std");
const gfx = @import("draw.zig");
const world = @import("world.zig");
const Block = world.Block;

pub fn mesh(w: anytype, verts: []gfx.Vertex, indices: []u16, comptime colors: fn (Block) [3]f32) struct { verts: usize, indices: usize } {
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
