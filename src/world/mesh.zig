const std = @import("std");
const rend = @import("render.zig");
const octree = @import("map.zig");
const Block = octree.Block;

pub fn buildMesh(
    world: anytype,
    verts: []rend.Vertex,
    indices: []u16,
    comptime colors: fn (Block) [3]f32,
) struct { vcount: usize, icount: usize } {
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
        const dim = [3]usize{ @intCast(world.size), @intCast(world.size), @intCast(world.size) };
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
                        const blk = world.get(pos[0], pos[1], pos[2]);
                        if (blk == .air) {
                            mask[n] = false;
                            n += 1;
                            continue;
                        }
                        pos[ax.d] += stp;
                        mask[n] = world.get(pos[0], pos[1], pos[2]) == .air;
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
                        const blk = world.get(pos[0], pos[1], pos[2]);
                        var w: usize = 1;
                        while (u + w < dim[ax.u] and mask[n + w]) : (w += 1) {
                            var p2 = pos;
                            p2[ax.u] = @intCast(u + w);
                            if (world.get(p2[0], p2[1], p2[2]) != blk) break;
                        }
                        var h: usize = 1;
                        outer: while (v + h < dim[ax.v]) : (h += 1) {
                            for (0..w) |k| {
                                if (!mask[n + k + h * dim[ax.u]]) break :outer;
                                var p2 = pos;
                                p2[ax.u] = @intCast(u + k);
                                p2[ax.v] = @intCast(v + h);
                                if (world.get(p2[0], p2[1], p2[2]) != blk) break :outer;
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
