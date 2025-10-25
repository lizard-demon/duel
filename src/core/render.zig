// Entire Render Pipeline
const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sglue = sokol.glue;
const sapp = sokol.app;
const ig = @import("cimgui");
const math = @import("../lib/math.zig");
const world = @import("world.zig");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Vertex = math.Vertex;

pub const pipeline = struct {
    pipe: sg.Pipeline = .{},
    bind: sg.Bindings = .{},
    pass: sg.PassAction,
    count: u32,
    pub fn init(v: []const Vertex, i: []const u16, c: [4]f32) pipeline {
        return .{
            .bind = .{ .vertex_buffers = .{ sg.makeBuffer(.{ .data = sg.asRange(v) }), .{}, .{}, .{}, .{}, .{}, .{}, .{} }, .index_buffer = sg.makeBuffer(.{ .usage = .{ .index_buffer = true }, .data = sg.asRange(i) }) },
            .pass = .{ .colors = .{ .{ .load_action = .CLEAR, .clear_value = .{ .r = c[0], .g = c[1], .b = c[2], .a = c[3] } }, .{}, .{}, .{}, .{}, .{}, .{}, .{} } },
            .count = @intCast(i.len),
        };
    }

    pub fn shader(r: *pipeline, sh: sg.Shader) void {
        var layout = sg.VertexLayoutState{};
        layout.attrs[0].format = .FLOAT3;
        layout.attrs[1].format = .FLOAT4;
        r.pipe = sg.makePipeline(.{ .shader = sh, .layout = layout, .index_type = .UINT16, .depth = .{ .compare = .LESS_EQUAL, .write_enabled = true }, .cull_mode = .BACK });
    }
    pub inline fn draw(r: pipeline, mvp: Mat4) void {
        sg.applyPipeline(r.pipe);
        sg.applyBindings(r.bind);
        sg.applyUniforms(0, sg.asRange(&mvp));
        sg.draw(0, r.count, 1);
    }
    pub fn deinit(r: pipeline) void {
        if (r.bind.vertex_buffers[0].id != 0) sg.destroyBuffer(r.bind.vertex_buffers[0]);
        if (r.bind.index_buffer.id != 0) sg.destroyBuffer(r.bind.index_buffer);
        if (r.pipe.id != 0) sg.destroyPipeline(r.pipe);
    }
};

pub const ButtonResult = struct {
    break_pressed: bool,
    place_pressed: bool,
};

pub const UI = struct {
    const cfg = struct {
        const crosshair_size = 8.0;
        const crosshair_color = [3]f32{ 1.0, 1.0, 1.0 };
        const crosshair_alpha = 0.8;
        const hud_x = 16.0;
        const hud_y = 16.0;
        const hud_w = 120.0;
        const hud_h = 70.0;
        const joystick_alpha = 0.3;
        const joystick_active_alpha = 0.6;
        const joystick_border_alpha = 0.4;
        const button_size = 60.0;
        const button_margin = 20.0;
        const button_alpha = 0.7;
        const button_text_alpha = 0.9;
    };

    pub const draw = struct {
        pub fn crosshair() void {
            const w, const h = .{ sapp.widthf(), sapp.heightf() };

            ig.igSetNextWindowPos(.{ .x = 0, .y = 0 }, ig.ImGuiCond_Always);
            ig.igSetNextWindowSize(.{ .x = w, .y = h }, ig.ImGuiCond_Always);
            const flags = ig.ImGuiWindowFlags_NoTitleBar | ig.ImGuiWindowFlags_NoResize | ig.ImGuiWindowFlags_NoMove | ig.ImGuiWindowFlags_NoScrollbar | ig.ImGuiWindowFlags_NoBackground | ig.ImGuiWindowFlags_NoInputs;
            if (ig.igBegin("Crosshair", null, flags)) {
                const dl = ig.igGetWindowDrawList();
                const cx, const cy = .{ w * 0.5, h * 0.5 };
                const size = cfg.crosshair_size;
                const col = ig.igColorConvertFloat4ToU32(.{ .x = cfg.crosshair_color[0], .y = cfg.crosshair_color[1], .z = cfg.crosshair_color[2], .w = cfg.crosshair_alpha });
                ig.ImDrawList_AddLine(dl, .{ .x = cx - size, .y = cy }, .{ .x = cx + size, .y = cy }, col);
                ig.ImDrawList_AddLine(dl, .{ .x = cx, .y = cy - size }, .{ .x = cx, .y = cy + size }, col);
            }
            ig.igEnd();
        }

        pub fn hud(block: world.Block) void {
            ig.igSetNextWindowPos(.{ .x = cfg.hud_x, .y = cfg.hud_y }, ig.ImGuiCond_Always);
            ig.igSetNextWindowSize(.{ .x = cfg.hud_w, .y = cfg.hud_h }, ig.ImGuiCond_Always);
            const hud_flags = ig.ImGuiWindowFlags_NoTitleBar | ig.ImGuiWindowFlags_NoResize | ig.ImGuiWindowFlags_NoMove | ig.ImGuiWindowFlags_NoScrollbar | ig.ImGuiWindowFlags_NoBackground | ig.ImGuiWindowFlags_NoInputs;
            if (ig.igBegin("GameHUD", null, hud_flags)) {
                const dl = ig.igGetWindowDrawList();
                const block_color = world.color(block);

                // Draw elegant color swatch with subtle border
                const swatch_size = 24.0;
                const swatch_x = cfg.hud_x + 8;
                const swatch_y = cfg.hud_y + 8;
                const color_u32 = ig.igColorConvertFloat4ToU32(.{ .x = block_color[0], .y = block_color[1], .z = block_color[2], .w = 1.0 });
                const border_color = ig.igColorConvertFloat4ToU32(.{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 0.3 });

                // Color swatch
                ig.ImDrawList_AddRectFilled(dl, .{ .x = swatch_x, .y = swatch_y }, .{ .x = swatch_x + swatch_size, .y = swatch_y + swatch_size }, color_u32);
                ig.ImDrawList_AddRect(dl, .{ .x = swatch_x, .y = swatch_y }, .{ .x = swatch_x + swatch_size, .y = swatch_y + swatch_size }, border_color);

                // Block ID text below the color swatch
                const text_x = swatch_x;
                const text_y = swatch_y + swatch_size + 6;
                const text_color = ig.igColorConvertFloat4ToU32(.{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 0.9 });
                ig.ImDrawList_AddText(dl, .{ .x = text_x, .y = text_y }, text_color, "Block");

                const id_color = ig.igColorConvertFloat4ToU32(.{ .x = 0.8, .y = 0.8, .z = 0.8, .w = 0.7 });
                var buf: [16]u8 = undefined;
                const id_str = std.fmt.bufPrintZ(&buf, "#{d}", .{block}) catch "###";
                ig.ImDrawList_AddText(dl, .{ .x = text_x, .y = text_y + 12 }, id_color, id_str.ptr);
            }
            ig.igEnd();
        }

        pub fn virtualJoystick(joystick: anytype) void {
            const w, const h = .{ sapp.widthf(), sapp.heightf() };

            ig.igSetNextWindowPos(.{ .x = 0, .y = 0 }, ig.ImGuiCond_Always);
            ig.igSetNextWindowSize(.{ .x = w, .y = h }, ig.ImGuiCond_Always);
            const flags = ig.ImGuiWindowFlags_NoTitleBar | ig.ImGuiWindowFlags_NoResize | ig.ImGuiWindowFlags_NoMove | ig.ImGuiWindowFlags_NoScrollbar | ig.ImGuiWindowFlags_NoBackground | ig.ImGuiWindowFlags_NoInputs;
            if (ig.igBegin("VirtualJoystick", null, flags)) {
                const dl = ig.igGetWindowDrawList();

                // Show direct control area for PC platforms
                {
                    const center_x = joystick.center_x;
                    const center_y = joystick.center_y;
                    const radius = joystick.radius;

                    // Draw direct control circle
                    const outer_alpha: f32 = if (joystick.active) cfg.joystick_active_alpha else cfg.joystick_alpha;
                    const direct_color = ig.igColorConvertFloat4ToU32(.{ .x = 0.8, .y = 0.8, .z = 1.0, .w = outer_alpha });
                    const border_color = ig.igColorConvertFloat4ToU32(.{ .x = 0.8, .y = 0.8, .z = 1.0, .w = cfg.joystick_border_alpha });

                    ig.ImDrawList_AddCircleFilled(dl, .{ .x = center_x, .y = center_y }, radius, direct_color, 32);
                    ig.ImDrawList_AddCircle(dl, .{ .x = center_x, .y = center_y }, radius, border_color);

                    // Draw center dot for reference
                    const center_dot_color = ig.igColorConvertFloat4ToU32(.{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 0.6 });
                    ig.ImDrawList_AddCircleFilled(dl, .{ .x = center_x, .y = center_y }, 3.0, center_dot_color, 8);

                    // Draw inner knob if active
                    if (joystick.active) {
                        const knob_radius = radius * 0.15;
                        const knob_color = ig.igColorConvertFloat4ToU32(.{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 0.9 });
                        ig.ImDrawList_AddCircleFilled(dl, .{ .x = joystick.current_x, .y = joystick.current_y }, knob_radius, knob_color, 16);
                        ig.ImDrawList_AddCircle(dl, .{ .x = joystick.current_x, .y = joystick.current_y }, knob_radius, border_color);
                    }

                    // Draw label for direct control
                    const label_color = ig.igColorConvertFloat4ToU32(.{ .x = 0.8, .y = 0.8, .z = 1.0, .w = 0.8 });
                    ig.ImDrawList_AddText(dl, .{ .x = center_x - 20, .y = center_y + radius + 10 }, label_color, "DIRECT");
                }
            }
            ig.igEnd();
        }

        pub fn actionButtons() ButtonResult {
            const w, const h = .{ sapp.widthf(), sapp.heightf() };
            var result = ButtonResult{ .break_pressed = false, .place_pressed = false };

            // Position buttons on the right side of the screen
            const button_x = w - cfg.button_size - cfg.button_margin;
            const break_button_y = h - (cfg.button_size * 2) - (cfg.button_margin * 2);

            // Set up button window
            ig.igSetNextWindowPos(.{ .x = button_x - 10, .y = break_button_y - 10 }, ig.ImGuiCond_Always);
            ig.igSetNextWindowSize(.{ .x = cfg.button_size + 20, .y = (cfg.button_size * 2) + cfg.button_margin + 20 }, ig.ImGuiCond_Always);
            const flags = ig.ImGuiWindowFlags_NoTitleBar | ig.ImGuiWindowFlags_NoResize | ig.ImGuiWindowFlags_NoMove | ig.ImGuiWindowFlags_NoScrollbar | ig.ImGuiWindowFlags_NoBackground;

            if (ig.igBegin("ActionButtons", null, flags)) {
                // Break button (Z key)
                ig.igSetCursorPos(.{ .x = 10, .y = 10 });
                if (ig.igButton("Z")) {
                    result.break_pressed = true;
                }

                // Place button (X key)
                ig.igSetCursorPos(.{ .x = 10, .y = 10 + cfg.button_size + cfg.button_margin });
                if (ig.igButton("X")) {
                    result.place_pressed = true;
                }
            }
            ig.igEnd();

            return result;
        }
    };

    pub inline fn render(block: world.Block, joystick: anytype) ButtonResult {
        draw.crosshair();
        draw.hud(block);
        draw.virtualJoystick(joystick);
        return draw.actionButtons();
    }
};
