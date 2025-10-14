// bsp.zig
const std = @import("std");
const alg = @import("algebra.zig");
const Vec3 = alg.Vec3;

pub const AABB = struct {
    min: Vec3, max: Vec3,

    pub fn new(min: Vec3, max: Vec3) AABB {
        return .{ .min = min, .max = max };
    }

    pub fn center(self: AABB) Vec3 {
        return Vec3.new(
            (self.min.x() + self.max.x()) * 0.5,
            (self.min.y() + self.max.y()) * 0.5,
            (self.min.z() + self.max.z()) * 0.5,
        );
    }

    pub fn contains(self: AABB, p: Vec3) bool {
        return p.x() >= self.min.x() and p.x() <= self.max.x() and
               p.y() >= self.min.y() and p.y() <= self.max.y() and
               p.z() >= self.min.z() and p.z() <= self.max.z();
    }

    pub fn intersects(self: AABB, other: AABB) bool {
        return self.min.x() <= other.max.x() and self.max.x() >= other.min.x() and
               self.min.y() <= other.max.y() and self.max.y() >= other.min.y() and
               self.min.z() <= other.max.z() and self.max.z() >= other.min.z();
    }

    pub fn sweep(self: AABB, vel: Vec3, other: AABB) ?struct { t: f32, n: Vec3 } {
        if (vel.length() < 0.0001) return null;

        const inv = Vec3.new(
            if (vel.x() != 0) 1.0 / vel.x() else std.math.inf(f32),
            if (vel.y() != 0) 1.0 / vel.y() else std.math.inf(f32),
            if (vel.z() != 0) 1.0 / vel.z() else std.math.inf(f32),
        );

        const tx1 = (other.min.x() - self.max.x()) * inv.x();
        const tx2 = (other.max.x() - self.min.x()) * inv.x();
        const ty1 = (other.min.y() - self.max.y()) * inv.y();
        const ty2 = (other.max.y() - self.min.y()) * inv.y();
        const tz1 = (other.min.z() - self.max.z()) * inv.z();
        const tz2 = (other.max.z() - self.min.z()) * inv.z();

        const txmin = @min(tx1, tx2);
        const txmax = @max(tx1, tx2);
        const tymin = @min(ty1, ty2);
        const tymax = @max(ty1, ty2);
        const tzmin = @min(tz1, tz2);
        const tzmax = @max(tz1, tz2);

        const tenter = @max(@max(txmin, tymin), tzmin);
        const texit = @min(@min(txmax, tymax), tzmax);

        if (tenter > texit or tenter > 1.0 or texit < 0.0) return null;
        if (tenter < 0.0) return null;

        const n = if (txmin > tymin and txmin > tzmin)
            Vec3.new(if (vel.x() > 0) -1 else 1, 0, 0)
        else if (tymin > tzmin)
            Vec3.new(0, if (vel.y() > 0) -1 else 1, 0)
        else
            Vec3.new(0, 0, if (vel.z() > 0) -1 else 1);

        return .{ .t = tenter, .n = n };
    }
};

pub const BSP = struct {
    pub const Node = struct {
        bounds: AABB,
        axis: u2,
        split: f32,
        left: ?*Node = null,
        right: ?*Node = null,

        fn side(self: Node, p: Vec3) bool {
            const v = switch (self.axis) {
                0 => p.x(),
                1 => p.y(),
                2 => p.z(),
                3 => unreachable,
            };
            return v < self.split;
        }
    };

    root: ?*Node,
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator, bounds: AABB, depth: u32) !BSP {
        return .{ .root = try build(alloc, bounds, 0, depth), .alloc = alloc };
    }

    fn build(alloc: std.mem.Allocator, b: AABB, d: u32, max: u32) !*Node {
        const axis: u2 = @intCast(d % 3);
        const c = b.center();
        const split = switch (axis) {
            0 => c.x(),
            1 => c.y(),
            2 => c.z(),
            3 => unreachable,
        };

        var node = try alloc.create(Node);
        node.* = .{ .bounds = b, .axis = axis, .split = split };

        if (d < max) {
            const lb = switch (axis) {
                0 => AABB.new(b.min, Vec3.new(split, b.max.y(), b.max.z())),
                1 => AABB.new(b.min, Vec3.new(b.max.x(), split, b.max.z())),
                2 => AABB.new(b.min, Vec3.new(b.max.x(), b.max.y(), split)),
                3 => unreachable,
            };

            const rb = switch (axis) {
                0 => AABB.new(Vec3.new(split, b.min.y(), b.min.z()), b.max),
                1 => AABB.new(Vec3.new(b.min.x(), split, b.min.z()), b.max),
                2 => AABB.new(Vec3.new(b.min.x(), b.min.y(), split), b.max),
                3 => unreachable,
            };

            node.left = try build(alloc, lb, d + 1, max);
            node.right = try build(alloc, rb, d + 1, max);
        }

        return node;
    }

    pub fn trace(self: BSP, pos: Vec3, box: AABB, vel: Vec3) struct { pos: Vec3, vel: Vec3, hit: bool } {
        if (self.root == null) return .{ .pos = pos.add(vel), .vel = vel, .hit = false };

        var p = pos;
        var v = vel;
        var hit = false;

        self.traceNode(self.root.?, &p, box, &v, &hit);
        return .{ .pos = p, .vel = v, .hit = hit };
    }

    fn traceNode(self: BSP, node: *Node, pos: *Vec3, box: AABB, vel: *Vec3, hit: *bool) void {
        if (node.left == null) {
            const playerBox = AABB.new(
                box.min.add(pos.*),
                box.max.add(pos.*)
            );

            if (playerBox.sweep(vel.*, node.bounds)) |collision| {
                const slideVel = vel.sub(collision.n.scale(collision.n.dot(vel.*)));
                pos.* = pos.add(vel.scale(collision.t)).add(slideVel.scale(1.0 - collision.t));
                vel.* = slideVel;
                hit.* = true;
            }
            return;
        }

        const onLeft = node.side(pos.*);
        const first = if (onLeft) node.left.? else node.right.?;
        const second = if (onLeft) node.right.? else node.left.?;

        self.traceNode(first, pos, box, vel, hit);
        self.traceNode(second, pos, box, vel, hit);
    }

    pub fn deinit(self: BSP) void {
        if (self.root) |root| self.freeNode(root);
    }

    fn freeNode(self: BSP, node: *Node) void {
        if (node.left) |l| self.freeNode(l);
        if (node.right) |r| self.freeNode(r);
        self.alloc.destroy(node);
    }
};
