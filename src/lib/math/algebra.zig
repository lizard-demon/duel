const std = @import("std");

pub const Vec3 = struct {
    data: @Vector(3, f32),

    pub fn new(vx: f32, vy: f32, vz: f32) Vec3 {
        return .{ .data = .{ vx, vy, vz } };
    }

    pub fn zero() Vec3 {
        return .{ .data = @splat(0) };
    }

    pub fn add(self: Vec3, other: Vec3) Vec3 {
        return .{ .data = self.data + other.data };
    }

    pub fn scale(self: Vec3, s: f32) Vec3 {
        return .{ .data = self.data * @as(@Vector(3, f32), @splat(s)) };
    }

    pub fn dot(self: Vec3, other: Vec3) f32 {
        return @reduce(.Add, self.data * other.data);
    }
};

pub const Mat4 = struct {
    data: [16]f32,

    pub fn identity() Mat4 {
        return .{ .data = .{
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        } };
    }

    pub fn mul(a: Mat4, b: Mat4) Mat4 {
        var r: Mat4 = undefined;
        inline for (0..4) |col| {
            inline for (0..4) |row| {
                var sum: f32 = 0;
                inline for (0..4) |k| {
                    sum += a.data[k * 4 + row] * b.data[col * 4 + k];
                }
                r.data[col * 4 + row] = sum;
            }
        }
        return r;
    }
};

pub fn perspective(fov_deg: f32, aspect: f32, near: f32, far: f32) Mat4 {
    const t = @tan(fov_deg * std.math.pi / 360.0) * near;
    const r = t * aspect;
    return .{ .data = .{
        near / r, 0,        0,                                0,
        0,        near / t, 0,                                0,
        0,        0,        -(far + near) / (far - near),     -1,
        0,        0,        -(2 * far * near) / (far - near), 0,
    } };
}
