const std = @import("std");

pub const Vec3 = struct {
    data: @Vector(3, f32),

    pub fn new(vx: f32, vy: f32, vz: f32) Vec3 {
        return .{ .data = .{ vx, vy, vz } };
    }

    pub fn zero() Vec3 {
        return .{ .data = @splat(0) };
    }

    pub fn up() Vec3 {
        return new(0, 1, 0);
    }

    pub fn x(self: Vec3) f32 { return self.data[0]; }
    pub fn y(self: Vec3) f32 { return self.data[1]; }
    pub fn z(self: Vec3) f32 { return self.data[2]; }

    pub fn add(self: Vec3, other: Vec3) Vec3 {
        return .{ .data = self.data + other.data };
    }

    pub fn sub(self: Vec3, other: Vec3) Vec3 {
        return .{ .data = self.data - other.data };
    }

    pub fn scale(self: Vec3, s: f32) Vec3 {
        return .{ .data = self.data * @as(@Vector(3, f32), @splat(s)) };
    }

    pub fn dot(self: Vec3, other: Vec3) f32 {
        return @reduce(.Add, self.data * other.data);
    }

    pub fn cross(self: Vec3, other: Vec3) Vec3 {
        return new(
            self.y() * other.z() - self.z() * other.y(),
            self.z() * other.x() - self.x() * other.z(),
            self.x() * other.y() - self.y() * other.x(),
        );
    }

    pub fn length(self: Vec3) f32 {
        return @sqrt(self.dot(self));
    }

    pub fn norm(self: Vec3) Vec3 {
        const len = self.length();
        return if (len > 0) self.scale(1.0 / len) else self;
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

pub fn lookAt(eye: Vec3, target: Vec3, up: Vec3) Mat4 {
    const f = target.sub(eye).norm();
    const s = f.cross(up).norm();
    const u = s.cross(f);

    return .{ .data = .{
        s.x(), u.x(), -f.x(), 0,
        s.y(), u.y(), -f.y(), 0,
        s.z(), u.z(), -f.z(), 0,
        -s.dot(eye), -u.dot(eye), f.dot(eye), 1,
    } };
}

pub fn perspective(fov_deg: f32, aspect: f32, near: f32, far: f32) Mat4 {
    const t = @tan(fov_deg * std.math.pi / 360.0) * near;
    const r = t * aspect;
    const l = -r;
    const b = -t;

    return .{ .data = .{
        (2 * near) / (r - l), 0, 0, 0,
        0, (2 * near) / (t - b), 0, 0,
        (r + l) / (r - l), (t + b) / (t - b), -(far + near) / (far - near), -1,
        0, 0, -(2 * far * near) / (far - near), 0,
    } };
}
