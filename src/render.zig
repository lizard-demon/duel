const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sglue = sokol.glue;
const alg = @import("lib/algebra.zig");
const Vec3 = alg.Vec3;
const Mat4 = alg.Mat4;

pub const Camera3D = struct {
    position: Vec3,
    yaw: f32,
    pitch: f32,
    fov: f32,

    pub fn init(position: Vec3, yaw: f32, pitch: f32, fov: f32) Camera3D {
        return .{
            .position = position,
            .yaw = yaw,
            .pitch = pitch,
            .fov = fov,
        };
    }

    pub fn forward(self: Camera3D) Vec3 {
        const cy = @cos(self.yaw);
        const sy = @sin(self.yaw);
        const cp = @cos(self.pitch);
        const sp = @sin(self.pitch);
        return Vec3.new(cp * cy, sp, cp * sy);
    }

    pub fn right(self: Camera3D) Vec3 {
        return self.forward().cross(Vec3.up()).norm();
    }

    pub fn move(self: *Camera3D, offset: Vec3) void {
        self.position = self.position.add(offset);
    }

    pub fn look(self: *Camera3D, dyaw: f32, dpitch: f32) void {
        self.yaw += dyaw;
        self.pitch = std.math.clamp(
            self.pitch + dpitch,
            -std.math.pi / 2.0 + 0.01,
            std.math.pi / 2.0 - 0.01,
        );
    }

    pub fn viewMatrix(self: Camera3D) Mat4 {
        return alg.lookAt(self.position, self.position.add(self.forward()), Vec3.up());
    }

    pub fn projectionMatrix(self: Camera3D, aspect: f32, near: f32, far: f32) Mat4 {
        return alg.perspective(self.fov, aspect, near, far);
    }
};

pub const Vertex = extern struct {
    pos: [3]f32,
    col: [4]f32,
};

pub const Renderer = struct {
    pip: sg.Pipeline = .{},
    bind: sg.Bindings = .{},
    pass: sg.PassAction,
    count: u32,

    pub fn init(v: []const Vertex, i: []const u16, clear_color: [4]f32) Renderer {
        sg.setup(.{
            .environment = sglue.environment(),
            .logger = .{ .func = sokol.log.func },
        });

        return .{
            .bind = .{
                .vertex_buffers = .{
                    sg.makeBuffer(.{ .data = sg.asRange(v) }),
                    .{}, .{}, .{}, .{}, .{}, .{}, .{},
                },
                .index_buffer = sg.makeBuffer(.{
                    .usage = .{ .index_buffer = true },
                    .data = sg.asRange(i),
                }),
            },
            .pass = .{
                .colors = .{
                    .{
                        .load_action = .CLEAR,
                        .clear_value = .{
                            .r = clear_color[0],
                            .g = clear_color[1],
                            .b = clear_color[2],
                            .a = clear_color[3],
                        },
                    },
                    .{}, .{}, .{}, .{}, .{}, .{}, .{},
                },
            },
            .count = @intCast(i.len),
        };
    }

    pub fn shader(self: *Renderer, desc: sg.ShaderDesc) void {
        var layout = sg.VertexLayoutState{};
        layout.attrs[0].format = .FLOAT3;
        layout.attrs[1].format = .FLOAT4;

        self.pip = sg.makePipeline(.{
            .shader = sg.makeShader(desc),
            .layout = layout,
            .index_type = .UINT16,
            .depth = .{
                .compare = .LESS_EQUAL,
                .write_enabled = true,
            },
            .cull_mode = .BACK,
        });
    }

    pub fn draw(self: Renderer, mvp: Mat4) void {
        sg.beginPass(.{
            .action = self.pass,
            .swapchain = sglue.swapchain(),
        });
        sg.applyPipeline(self.pip);
        sg.applyBindings(self.bind);
        sg.applyUniforms(0, sg.asRange(&mvp));
        sg.draw(0, self.count, 1);
        sg.endPass();
        sg.commit();
    }

    pub fn deinit(self: Renderer) void {
        if (self.bind.vertex_buffers[0].id != 0) {
            sg.destroyBuffer(self.bind.vertex_buffers[0]);
        }
        if (self.bind.index_buffer.id != 0) {
            sg.destroyBuffer(self.bind.index_buffer);
        }
        if (self.pip.id != 0) {
            sg.destroyPipeline(self.pip);
        }
        sg.shutdown();
    }
};
