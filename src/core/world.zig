const std = @import("std");
const math = @import("../lib/math.zig");
const Vec3 = math.Vec3;
const Vertex = math.Vertex;

pub const Block = u8;

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
        if (block == 1) return .{ 0, 0, 0 }; // reserved black
        if (block == 2) return .{ 1, 1, 1 }; // reserved white

        // Bit-packed HSV mapping: 32 hues, 4 saturations, 2 values
        const hue = @as(f32, @floatFromInt(block & 0x1F)) * 360.0 / 32.0; // 5 bits for hue (32 hues)
        const sat = 0.25 + @as(f32, @floatFromInt((block >> 5) & 0x03)) * 0.25; // 2 bits for saturation (0.25, 0.5, 0.75, 1.0)
        const val = 0.4 + @as(f32, @floatFromInt((block >> 7) & 0x01)) * 0.6; // 1 bit for value (0.4 or 1.0)

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

    pub fn save(w: *const World) void {
        const file = std.fs.cwd().createFile("world.dat", .{}) catch return;
        defer file.close();
        _ = file.writeAll(std.mem.asBytes(&w.blocks)) catch {};
    }

    pub fn load() World {
        const file = std.fs.cwd().openFile("world.dat", .{}) catch return World.init();
        defer file.close();
        var w = World{ .blocks = undefined };
        _ = file.readAll(std.mem.asBytes(&w.blocks)) catch return World.init();
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

    pub fn mesh(w: *const World, verts: []Vertex, indices: []u16, comptime colors: fn (Block) [3]f32) struct { verts: usize, indices: usize } {
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
