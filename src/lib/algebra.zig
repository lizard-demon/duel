const std = @import("std");

pub const Vec3 = struct {
    data: @Vector(3, f32),
    pub fn new(x: f32, y: f32, z: f32) Vec3 {
        return .{ .data = .{ x, y, z } };
    }
    pub fn zero() Vec3 {
        return .{ .data = @splat(0) };
    }
    pub fn add(self: Vec3, o: Vec3) Vec3 {
        return .{ .data = self.data + o.data };
    }
    pub fn scale(self: Vec3, s: f32) Vec3 {
        return .{ .data = self.data * @as(@Vector(3, f32), @splat(s)) };
    }
    pub fn dot(self: Vec3, o: Vec3) f32 {
        return @reduce(.Add, self.data * o.data);
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

pub fn perspective(fov: f32, asp: f32, n: f32, f: f32) Mat4 {
    const t = @tan(fov * std.math.pi / 360) * n;
    const r = t * asp;
    return .{ .data = .{ n / r, 0, 0, 0, 0, n / t, 0, 0, 0, 0, -(f + n) / (f - n), -1, 0, 0, -(2 * f * n) / (f - n), 0 } };
}
