const V = @import("../math/algebra.zig").Vec3;

pub fn Physics(comptime g: f32, j: f32, a: f32, f: f32, s: f32, h: f32, c: f32) type {
    return struct {
        v: V = V.zero(),
        on: bool = false,
        cr: bool = false,

        pub fn crouch(p: *@This(), pos: *V, w: anytype, want: bool) void {
            if (p.cr and !want) {
                const test_pos = V.new(pos.x(), pos.y() + (h - c) / 2, pos.z());
                const r = w.sweep(test_pos, .{ .min = V.new(-0.4, -h / 2, -0.4), .max = V.new(0.4, h / 2, 0.4) }, V.zero(), 1);
                if (!r.hit) pos.data[1] += (h - c) / 2;
                p.cr = r.hit;
            } else p.cr = want;
        }

        pub fn jump(p: *@This()) void {
            p.v.data[1] = j;
            p.on = false;
        }

        pub fn move(p: *@This(), d: V, dt: f32) void {
            const l = @sqrt(d.x() * d.x() + d.z() * d.z());
            if (l < 0.001) return if (p.on) p.slow(dt);
            const w = V.new(d.x() / l, 0, d.z() / l);
            if (p.on) {
                p.slow(dt);
                p.push(w, s * l, a * dt);
            } else p.air(w, s * l, a * dt);
        }

        fn push(p: *@This(), w: V, ws: f32, ac: f32) void {
            const add = ws - p.v.dot(w);
            if (add <= 0) return;
            p.v = p.v.add(w.scale(@min(ac * ws, add)));
        }

        fn air(p: *@This(), w: V, ws: f32, ac: f32) void {
            const add = @min(ws, 0.7) - p.v.dot(w);
            if (add <= 0) return;
            p.v = p.v.add(w.scale(@min(ac * ws, add)));
        }

        pub fn update(p: *@This(), pos: *V, w: anytype, dt: f32) void {
            p.v.data[1] -= g * dt;
            const ht = if (p.cr) c else h;
            const r = w.sweep(pos.*, .{ .min = V.new(-0.4, -ht / 2, -0.4), .max = V.new(0.4, ht / 2, 0.4) }, p.v.scale(dt), 3);
            pos.* = r.pos;
            p.v = r.vel.scale(1 / dt);
            p.on = r.hit and @abs(r.vel.y()) < 0.01;
        }

        fn slow(p: *@This(), dt: f32) void {
            const sp = @sqrt(p.v.x() * p.v.x() + p.v.z() * p.v.z());
            if (sp < 0.1) {
                p.v.data[0] = 0;
                p.v.data[2] = 0;
                return;
            }
            const sc = @max(0, sp - @max(sp, 0.1) * f * dt) / sp;
            p.v.data[0] *= sc;
            p.v.data[2] *= sc;
        }
    };
}
