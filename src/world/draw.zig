const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sglue = sokol.glue;
const math = @import("../lib/math.zig");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

pub const Vertex = extern struct { pos: [3]f32, col: [4]f32 };

pub const Draw = struct {
    pipe: sg.Pipeline = .{},
    bind: sg.Bindings = .{},
    pass: sg.PassAction,
    count: u32,
    pub fn init(v: []const Vertex, i: []const u16, c: [4]f32) Draw {
        return .{
            .bind = .{ .vertex_buffers = .{ sg.makeBuffer(.{ .data = sg.asRange(v) }), .{}, .{}, .{}, .{}, .{}, .{}, .{} }, .index_buffer = sg.makeBuffer(.{ .usage = .{ .index_buffer = true }, .data = sg.asRange(i) }) },
            .pass = .{ .colors = .{ .{ .load_action = .CLEAR, .clear_value = .{ .r = c[0], .g = c[1], .b = c[2], .a = c[3] } }, .{}, .{}, .{}, .{}, .{}, .{}, .{} } },
            .count = @intCast(i.len),
        };
    }

    pub fn shader(d: *Draw, desc: sg.ShaderDesc) void {
        var layout = sg.VertexLayoutState{};
        layout.attrs[0].format = .FLOAT3;
        layout.attrs[1].format = .FLOAT4;
        d.pipe = sg.makePipeline(.{ .shader = sg.makeShader(desc), .layout = layout, .index_type = .UINT16, .depth = .{ .compare = .LESS_EQUAL, .write_enabled = true }, .cull_mode = .BACK });
    }
    pub fn draw(d: Draw, mvp: Mat4) void {
        sg.applyPipeline(d.pipe);
        sg.applyBindings(d.bind);
        sg.applyUniforms(0, sg.asRange(&mvp));
        sg.draw(0, d.count, 1);
    }
    pub fn deinit(d: Draw) void {
        if (d.bind.vertex_buffers[0].id != 0) sg.destroyBuffer(d.bind.vertex_buffers[0]);
        if (d.bind.index_buffer.id != 0) sg.destroyBuffer(d.bind.index_buffer);
        if (d.pipe.id != 0) sg.destroyPipeline(d.pipe);
    }
};
