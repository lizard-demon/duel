const std = @import("std");
const math = @import("../lib/math.zig");
const Vec3 = math.Vec3;
const Vertex = math.Vertex;

pub const Block = u8;

inline fn hsvToRgb(h: f32, s: f32, v: f32) [3]f32 {
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

pub const Map = struct {
    blocks: [64][64][64]Block,

    pub fn init() Map {
        var w = Map{ .blocks = std.mem.zeroes([64][64][64]Block) };
        for (0..64) |x| for (0..64) |y| for (0..64) |z| {
            const is_wall = x == 0 or x == 63 or z == 0 or z == 63;
            const is_floor = y == 0;
            w.blocks[x][y][z] = if ((is_wall and y <= 2) or is_floor) 2 else 0;
        };
        return w;
    }

    pub fn save(w: *const Map) void {
        const file = std.fs.cwd().createFile("/world.dat", .{}) catch return;
        defer file.close();

        // RLE compress the blocks
        var compressed: [64 * 64 * 64 * 2]u8 = undefined; // worst case: alternating blocks
        var write_pos: usize = 0;

        var current_block = w.blocks[0][0][0];
        var run_length: u8 = 1;

        for (0..64) |x| {
            for (0..64) |y| {
                for (0..64) |z| {
                    if (x == 0 and y == 0 and z == 0) continue; // skip first block

                    const block = w.blocks[x][y][z];
                    if (block == current_block and run_length < 255) {
                        run_length += 1;
                    } else {
                        // Write current run
                        compressed[write_pos] = run_length;
                        compressed[write_pos + 1] = current_block;
                        write_pos += 2;

                        current_block = block;
                        run_length = 1;
                    }
                }
            }
        }

        // Write final run
        compressed[write_pos] = run_length;
        compressed[write_pos + 1] = current_block;
        write_pos += 2;

        _ = file.writeAll(compressed[0..write_pos]) catch {};
    }

    pub fn load() Map {
        const file = std.fs.cwd().openFile("/world.dat", .{}) catch return Map.init();
        defer file.close();

        // Read compressed data
        var compressed: [64 * 64 * 64 * 2]u8 = undefined;
        const bytes_read = file.readAll(&compressed) catch return Map.init();

        var w = Map{ .blocks = std.mem.zeroes([64][64][64]Block) };
        var read_pos: usize = 0;
        var block_pos: usize = 0;

        // RLE decompress
        while (read_pos < bytes_read and block_pos < 64 * 64 * 64) {
            const run_length = compressed[read_pos];
            const block_value = compressed[read_pos + 1];
            read_pos += 2;

            for (0..run_length) |_| {
                if (block_pos >= 64 * 64 * 64) break;

                const x = block_pos / (64 * 64);
                const y = (block_pos % (64 * 64)) / 64;
                const z = block_pos % 64;

                w.blocks[x][y][z] = block_value;
                block_pos += 1;
            }
        }

        return w;
    }

    pub inline fn get(w: *const Map, x: i32, y: i32, z: i32) Block {
        if (x < 0 or x >= 64 or y < 0 or y >= 64 or z < 0 or z >= 64) return 0;
        return w.blocks[@intCast(x)][@intCast(y)][@intCast(z)];
    }

    pub inline fn set(w: *Map, x: i32, y: i32, z: i32, block: Block) bool {
        if (x < 0 or x >= 64 or y < 0 or y >= 64 or z < 0 or z >= 64) return false;
        const old_block = w.blocks[@intCast(x)][@intCast(y)][@intCast(z)];
        if (old_block == block) return false;
        w.blocks[@intCast(x)][@intCast(y)][@intCast(z)] = block;
        return true;
    }
};

pub const Mesh = struct {
    const FaceInfo = struct { block: Block, is_back: bool };
    const shades = [_]f32{ 0.8, 0.8, 0.6, 0.8, 1.0, 1.0 };

    pub fn build(w: *const Map, verts: []Vertex, indices: []u16, comptime colors: fn (Block) [3]f32) struct { verts: usize, indices: usize } {
        var vi: usize = 0;
        var ii: usize = 0;
        var mask: [64 * 64]FaceInfo = undefined;

        // Greedy meshing - sweep each axis
        inline for (0..3) |axis| {
            const u = (axis + 1) % 3;
            const v = (axis + 2) % 3;

            var d: i32 = 0;
            while (d < 64) : (d += 1) {
                buildFaceMask(w, &mask, axis, u, v, d);
                generateQuadsFromMask(&mask, &vi, &ii, verts, indices, axis, u, v, d, colors);
            }
        }
        return .{ .verts = vi, .indices = ii };
    }

    fn buildFaceMask(w: *const Map, mask: *[64 * 64]FaceInfo, axis: usize, u: usize, v: usize, d: i32) void {
        @memset(mask, .{ .block = 0, .is_back = false });

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
    }

    fn generateQuadsFromMask(
        mask: *[64 * 64]FaceInfo,
        vi: *usize,
        ii: *usize,
        verts: []Vertex,
        indices: []u16,
        axis: usize,
        u: usize,
        v: usize,
        d: i32,
        comptime colors: fn (Block) [3]f32,
    ) void {
        var j: usize = 0;
        while (j < 64) : (j += 1) {
            var i: usize = 0;
            while (i < 64) {
                const face_info = mask[j * 64 + i];
                if (face_info.block == 0) {
                    i += 1;
                    continue;
                }

                const quad_size = findQuadSize(mask, face_info, i, j);
                clearMaskArea(mask, i, j, quad_size.width, quad_size.height);

                if (vi.* + 4 > verts.len or ii.* + 6 > indices.len) return;

                buildQuad(verts, indices, vi, ii, face_info, axis, u, v, d, i, j, quad_size.width, quad_size.height, colors);
                i += quad_size.width;
            }
        }
    }

    fn findQuadSize(mask: *[64 * 64]FaceInfo, face_info: FaceInfo, start_i: usize, start_j: usize) struct { width: usize, height: usize } {
        // Find width - extend right while same face
        var width: usize = 1;
        while (start_i + width < 64) {
            const next_face = mask[start_j * 64 + start_i + width];
            if (next_face.block != face_info.block or next_face.is_back != face_info.is_back) break;
            width += 1;
        }

        // Find height - extend up while entire row matches
        var height: usize = 1;
        while (start_j + height < 64) {
            var row_matches = true;
            for (0..width) |k| {
                const check_face = mask[(start_j + height) * 64 + start_i + k];
                if (check_face.block != face_info.block or check_face.is_back != face_info.is_back) {
                    row_matches = false;
                    break;
                }
            }
            if (!row_matches) break;
            height += 1;
        }

        return .{ .width = width, .height = height };
    }

    inline fn clearMaskArea(mask: *[64 * 64]FaceInfo, start_i: usize, start_j: usize, width: usize, height: usize) void {
        for (0..height) |h| {
            for (0..width) |w_idx| {
                mask[(start_j + h) * 64 + start_i + w_idx] = .{ .block = 0, .is_back = false };
            }
        }
    }

    fn buildQuad(
        verts: []Vertex,
        indices: []u16,
        vi: *usize,
        ii: *usize,
        face_info: FaceInfo,
        axis: usize,
        u: usize,
        v: usize,
        d: i32,
        start_i: usize,
        start_j: usize,
        width: usize,
        height: usize,
        comptime colors: fn (Block) [3]f32,
    ) void {
        const col = colors(face_info.block);
        const shade_offset: usize = if (face_info.is_back) 0 else 1;
        const shade_idx = axis * 2 + shade_offset;
        const shade = shades[shade_idx];
        const fcol = [4]f32{ col[0] * shade, col[1] * shade, col[2] * shade, 1 };

        const face_pos: f32 = @floatFromInt(d);
        const quad = buildQuadVertices(axis, u, v, face_pos, start_i, start_j, width, height);

        const base = @as(u16, @intCast(vi.*));
        addQuadVertices(verts, vi, quad, fcol, face_info.is_back);
        addQuadIndices(indices, ii, base);
    }

    fn buildQuadVertices(axis: usize, u: usize, v: usize, face_pos: f32, start_i: usize, start_j: usize, width: usize, height: usize) [4][3]f32 {
        var quad = [4][3]f32{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } };

        quad[0][axis] = face_pos;
        quad[0][u] = @floatFromInt(start_i);
        quad[0][v] = @floatFromInt(start_j);

        quad[1][axis] = face_pos;
        quad[1][u] = @floatFromInt(start_i);
        quad[1][v] = @floatFromInt(start_j + height);

        quad[2][axis] = face_pos;
        quad[2][u] = @floatFromInt(start_i + width);
        quad[2][v] = @floatFromInt(start_j + height);

        quad[3][axis] = face_pos;
        quad[3][u] = @floatFromInt(start_i + width);
        quad[3][v] = @floatFromInt(start_j);

        return quad;
    }

    inline fn addQuadVertices(verts: []Vertex, vi: *usize, quad: [4][3]f32, fcol: [4]f32, is_back: bool) void {
        if (is_back) {
            verts[vi.*] = .{ .pos = quad[0], .col = fcol };
            verts[vi.* + 1] = .{ .pos = quad[3], .col = fcol };
            verts[vi.* + 2] = .{ .pos = quad[2], .col = fcol };
            verts[vi.* + 3] = .{ .pos = quad[1], .col = fcol };
        } else {
            verts[vi.*] = .{ .pos = quad[0], .col = fcol };
            verts[vi.* + 1] = .{ .pos = quad[1], .col = fcol };
            verts[vi.* + 2] = .{ .pos = quad[2], .col = fcol };
            verts[vi.* + 3] = .{ .pos = quad[3], .col = fcol };
        }
        vi.* += 4;
    }

    inline fn addQuadIndices(indices: []u16, ii: *usize, base: u16) void {
        for ([_]u16{ 0, 1, 2, 0, 2, 3 }) |idx| {
            indices[ii.*] = base + idx;
            ii.* += 1;
        }
    }
};
