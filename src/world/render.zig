const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sglue = sokol.glue;
const alg = @import("../lib/algebra.zig");
const Vec3 = alg.Vec3;
const Mat4 = alg.Mat4;

pub const Vertex = extern struct { pos: [3]f32, col: [4]f32 };

pub const Renderer = struct {
    pip: sg.Pipeline = .{},
    bind: sg.Bindings = .{},
    pass: sg.PassAction,
    count: u32,
    pub fn init(v: []const Vertex, i: []const u16, c: [4]f32) Renderer {
        return .{
            .bind = .{ .vertex_buffers = .{ sg.makeBuffer(.{ .data = sg.asRange(v) }), .{}, .{}, .{}, .{}, .{}, .{}, .{} }, .index_buffer = sg.makeBuffer(.{ .usage = .{ .index_buffer = true }, .data = sg.asRange(i) }) },
            .pass = .{ .colors = .{ .{ .load_action = .CLEAR, .clear_value = .{ .r = c[0], .g = c[1], .b = c[2], .a = c[3] } }, .{}, .{}, .{}, .{}, .{}, .{}, .{} } },
            .count = @intCast(i.len),
        };
    }

    pub fn shader(s: *Renderer, desc: sg.ShaderDesc) void {
        var layout = sg.VertexLayoutState{};
        layout.attrs[0].format = .FLOAT3;
        layout.attrs[1].format = .FLOAT4;
        s.pip = sg.makePipeline(.{ .shader = sg.makeShader(desc), .layout = layout, .index_type = .UINT16, .depth = .{ .compare = .LESS_EQUAL, .write_enabled = true }, .cull_mode = .BACK });
    }
    pub fn draw(s: Renderer, mvp: Mat4) void {
        sg.applyPipeline(s.pip);
        sg.applyBindings(s.bind);
        sg.applyUniforms(0, sg.asRange(&mvp));
        sg.draw(0, s.count, 1);
    }
    pub fn deinit(s: Renderer) void {
        if (s.bind.vertex_buffers[0].id != 0) sg.destroyBuffer(s.bind.vertex_buffers[0]);
        if (s.bind.index_buffer.id != 0) sg.destroyBuffer(s.bind.index_buffer);
        if (s.pip.id != 0) sg.destroyPipeline(s.pip);
    }
};
