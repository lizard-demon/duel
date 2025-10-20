// All the math we need
const std = @import("std");

pub const Vec3 = struct {
    data: @Vector(3, f32),
    pub inline fn new(x: f32, y: f32, z: f32) Vec3 {
        return .{ .data = .{ x, y, z } };
    }
    pub inline fn zero() Vec3 {
        return .{ .data = @splat(0) };
    }
    pub inline fn add(v: Vec3, o: Vec3) Vec3 {
        return .{ .data = v.data + o.data };
    }
    pub inline fn scale(v: Vec3, s: f32) Vec3 {
        return .{ .data = v.data * @as(@Vector(3, f32), @splat(s)) };
    }
    pub inline fn sub(v: Vec3, o: Vec3) Vec3 {
        return .{ .data = v.data - o.data };
    }
    pub inline fn dot(v: Vec3, o: Vec3) f32 {
        return @reduce(.Add, v.data * o.data);
    }
    pub inline fn length(v: Vec3) f32 {
        return @sqrt(v.dot(v));
    }
};

pub const Mat4 = struct {
    data: [16]f32,
    pub fn mul(a: Mat4, b: Mat4) Mat4 {
        var r: Mat4 = undefined;
        inline for (0..4) |c| {
            inline for (0..4) |row| {
                var s: f32 = 0;
                inline for (0..4) |k| s += a.data[k * 4 + row] * b.data[c * 4 + k];
                r.data[c * 4 + row] = s;
            }
        }
        return r;
    }
};

pub const Vertex = extern struct { pos: [3]f32, col: [4]f32 };

pub inline fn perspective(fov: f32, asp: f32, n: f32, f: f32) Mat4 {
    const t = @tan(fov * std.math.pi / 360) * n;
    const r = t * asp;
    return .{ .data = .{ n / r, 0, 0, 0, 0, n / t, 0, 0, 0, 0, -(f + n) / (f - n), -1, 0, 0, -(2 * f * n) / (f - n), 0 } };
}
