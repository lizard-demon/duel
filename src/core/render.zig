// Entire Render Pipeline
const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sglue = sokol.glue;
const math = @import("../lib/math.zig");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

pub const Vertex = extern struct { pos: [3]f32, col: [4]f32 };

pub const Render = struct {
    pipe: sg.Pipeline = .{},
    bind: sg.Bindings = .{},
    pass: sg.PassAction,
    count: u32,
    pub fn init(v: []const Vertex, i: []const u16, c: [4]f32) Render {
        return .{
            .bind = .{ .vertex_buffers = .{ sg.makeBuffer(.{ .data = sg.asRange(v) }), .{}, .{}, .{}, .{}, .{}, .{}, .{} }, .index_buffer = sg.makeBuffer(.{ .usage = .{ .index_buffer = true }, .data = sg.asRange(i) }) },
            .pass = .{ .colors = .{ .{ .load_action = .CLEAR, .clear_value = .{ .r = c[0], .g = c[1], .b = c[2], .a = c[3] } }, .{}, .{}, .{}, .{}, .{}, .{}, .{} } },
            .count = @intCast(i.len),
        };
    }

    pub fn shader(r: *Render, desc: sg.ShaderDesc) void {
        var layout = sg.VertexLayoutState{};
        layout.attrs[0].format = .FLOAT3;
        layout.attrs[1].format = .FLOAT4;
        r.pipe = sg.makePipeline(.{ .shader = sg.makeShader(desc), .layout = layout, .index_type = .UINT16, .depth = .{ .compare = .LESS_EQUAL, .write_enabled = true }, .cull_mode = .BACK });
    }
    pub fn draw(r: Render, mvp: Mat4) void {
        sg.applyPipeline(r.pipe);
        sg.applyBindings(r.bind);
        sg.applyUniforms(0, sg.asRange(&mvp));
        sg.draw(0, r.count, 1);
    }
    pub fn deinit(r: Render) void {
        if (r.bind.vertex_buffers[0].id != 0) sg.destroyBuffer(r.bind.vertex_buffers[0]);
        if (r.bind.index_buffer.id != 0) sg.destroyBuffer(r.bind.index_buffer);
        if (r.pipe.id != 0) sg.destroyPipeline(r.pipe);
    }
};
