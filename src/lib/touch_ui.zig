// Clean Touch UI - Minimal, elegant, functional
const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const ig = @import("cimgui");
const input = @import("input.zig");

pub const TouchUI = struct {
    show_controls: bool = false,
    fade_timer: f32 = 0,

    const cfg = struct {
        const fade_duration = 2.0; // Seconds to fade out
        const alpha_base = 0.15;
        const alpha_active = 0.4;
        const alpha_pressed = 0.6;

        // Colors
        const movement_color = [3]f32{ 0.2, 0.6, 1.0 };
        const jump_color = [3]f32{ 1.0, 0.4, 0.2 };
        const crouch_color = [3]f32{ 0.8, 0.8, 0.2 };
        const look_color = [3]f32{ 0.6, 0.6, 0.6 };
    };

    pub fn update(self: *TouchUI, input_system: *const input.Input, dt: f32) void {
        // Show controls if touch input is detected
        const has_touch_input = input_system.touch.movement_touch != null or
            input_system.touch.look_touch != null or
            input_system.touch.jump or
            input_system.touch.crouch;

        if (has_touch_input) {
            self.show_controls = true;
            self.fade_timer = cfg.fade_duration;
        } else if (self.fade_timer > 0) {
            self.fade_timer -= dt;
            if (self.fade_timer <= 0) {
                self.show_controls = false;
            }
        }
    }

    pub fn render(self: *const TouchUI, input_system: *const input.Input) void {
        if (!self.show_controls) return;

        const screen_w = sapp.widthf();
        const screen_h = sapp.heightf();
        const fade_alpha: f32 = if (self.fade_timer > 0) 1.0 else 0.0;

        ig.igSetNextWindowPos(.{ .x = 0, .y = 0 }, ig.ImGuiCond_Always);
        ig.igSetNextWindowSize(.{ .x = screen_w, .y = screen_h }, ig.ImGuiCond_Always);
        const flags = ig.ImGuiWindowFlags_NoTitleBar | ig.ImGuiWindowFlags_NoResize |
            ig.ImGuiWindowFlags_NoMove | ig.ImGuiWindowFlags_NoScrollbar |
            ig.ImGuiWindowFlags_NoBackground | ig.ImGuiWindowFlags_NoInputs;

        if (ig.igBegin("TouchControls", null, flags)) {
            const dl = ig.igGetWindowDrawList();

            self.drawMovementControl(dl, input_system, fade_alpha);
            self.drawJumpControl(dl, input_system, screen_w, screen_h, fade_alpha);
            self.drawCrouchControl(dl, input_system, screen_h, fade_alpha);
            self.drawLookArea(dl, input_system, screen_w, screen_h, fade_alpha);
        }
        ig.igEnd();
    }

    fn drawMovementControl(self: *const TouchUI, dl: *ig.ImDrawList, input_system: *const input.Input, fade_alpha: f32) void {
        _ = self;
        const radius = input.TouchInput.cfg.movement_radius;
        const center_x = radius + 20;
        const center_y = sapp.heightf() - radius - 20;

        const is_active = input_system.touch.movement_touch != null;
        const alpha: f32 = if (is_active) cfg.alpha_active else cfg.alpha_base;
        const final_alpha = alpha * fade_alpha;

        // Outer circle
        const outer_color = ig.igColorConvertFloat4ToU32(.{ .x = cfg.movement_color[0], .y = cfg.movement_color[1], .z = cfg.movement_color[2], .w = final_alpha });
        const border_color = ig.igColorConvertFloat4ToU32(.{ .x = cfg.movement_color[0], .y = cfg.movement_color[1], .z = cfg.movement_color[2], .w = final_alpha * 0.8 });

        ig.ImDrawList_AddCircleFilled(dl, .{ .x = center_x, .y = center_y }, radius, outer_color, 32);
        ig.ImDrawList_AddCircle(dl, .{ .x = center_x, .y = center_y }, radius, border_color);

        // Inner knob if active
        if (is_active and input_system.touch.movement_touch != null) {
            const touch = input_system.touch.movement_touch.?;
            const knob_radius = radius * 0.2;
            const knob_color = ig.igColorConvertFloat4ToU32(.{ .x = 1.0, .y = 1.0, .z = 1.0, .w = final_alpha * 1.5 });

            ig.ImDrawList_AddCircleFilled(dl, .{ .x = touch.current_x, .y = touch.current_y }, knob_radius, knob_color, 16);
        }

        // Center dot
        const center_color = ig.igColorConvertFloat4ToU32(.{ .x = 1.0, .y = 1.0, .z = 1.0, .w = final_alpha * 0.6 });
        ig.ImDrawList_AddCircleFilled(dl, .{ .x = center_x, .y = center_y }, 3.0, center_color, 8);
    }

    fn drawJumpControl(self: *const TouchUI, dl: *ig.ImDrawList, input_system: *const input.Input, screen_w: f32, screen_h: f32, fade_alpha: f32) void {
        _ = self;
        const radius = input.TouchInput.cfg.jump_radius;
        const center_x = screen_w - radius - 20;
        const center_y = screen_h - radius - 20;

        const is_pressed = input_system.touch.jump;
        const alpha: f32 = if (is_pressed) cfg.alpha_pressed else cfg.alpha_base;
        const final_alpha = alpha * fade_alpha;

        const color = ig.igColorConvertFloat4ToU32(.{ .x = cfg.jump_color[0], .y = cfg.jump_color[1], .z = cfg.jump_color[2], .w = final_alpha });
        const border_color = ig.igColorConvertFloat4ToU32(.{ .x = cfg.jump_color[0], .y = cfg.jump_color[1], .z = cfg.jump_color[2], .w = final_alpha * 0.8 });

        ig.ImDrawList_AddCircleFilled(dl, .{ .x = center_x, .y = center_y }, radius, color, 24);
        ig.ImDrawList_AddCircle(dl, .{ .x = center_x, .y = center_y }, radius, border_color);

        // Jump icon (simple up arrow)
        const icon_color = ig.igColorConvertFloat4ToU32(.{ .x = 1.0, .y = 1.0, .z = 1.0, .w = final_alpha * 1.2 });
        const arrow_size = radius * 0.4;
        ig.ImDrawList_AddTriangleFilled(dl, .{ .x = center_x, .y = center_y - arrow_size }, .{ .x = center_x - arrow_size * 0.6, .y = center_y + arrow_size * 0.3 }, .{ .x = center_x + arrow_size * 0.6, .y = center_y + arrow_size * 0.3 }, icon_color);
    }

    fn drawCrouchControl(self: *const TouchUI, dl: *ig.ImDrawList, input_system: *const input.Input, screen_h: f32, fade_alpha: f32) void {
        _ = self;
        const radius = input.TouchInput.cfg.crouch_radius;
        const center_x = radius + 20;
        const center_y = screen_h - input.TouchInput.cfg.movement_radius * 2 - radius - 30;

        const is_pressed = input_system.touch.crouch;
        const alpha: f32 = if (is_pressed) cfg.alpha_pressed else cfg.alpha_base;
        const final_alpha = alpha * fade_alpha;

        const color = ig.igColorConvertFloat4ToU32(.{ .x = cfg.crouch_color[0], .y = cfg.crouch_color[1], .z = cfg.crouch_color[2], .w = final_alpha });
        const border_color = ig.igColorConvertFloat4ToU32(.{ .x = cfg.crouch_color[0], .y = cfg.crouch_color[1], .z = cfg.crouch_color[2], .w = final_alpha * 0.8 });

        ig.ImDrawList_AddCircleFilled(dl, .{ .x = center_x, .y = center_y }, radius, color, 20);
        ig.ImDrawList_AddCircle(dl, .{ .x = center_x, .y = center_y }, radius, border_color);

        // Crouch icon (simple down arrow)
        const icon_color = ig.igColorConvertFloat4ToU32(.{ .x = 1.0, .y = 1.0, .z = 1.0, .w = final_alpha * 1.2 });
        const arrow_size = radius * 0.4;
        ig.ImDrawList_AddTriangleFilled(dl, .{ .x = center_x, .y = center_y + arrow_size }, .{ .x = center_x - arrow_size * 0.6, .y = center_y - arrow_size * 0.3 }, .{ .x = center_x + arrow_size * 0.6, .y = center_y - arrow_size * 0.3 }, icon_color);
    }

    fn drawLookArea(self: *const TouchUI, dl: *ig.ImDrawList, input_system: *const input.Input, screen_w: f32, screen_h: f32, fade_alpha: f32) void {
        _ = self;
        const is_active = input_system.touch.look_touch != null;
        if (!is_active) return; // Only show when actively looking

        const alpha = cfg.alpha_base * 0.5;
        const final_alpha = alpha * fade_alpha;

        // Draw subtle look area indicator
        const jump_area_left = screen_w - input.TouchInput.cfg.jump_radius * 2 - 40;
        const look_area_left = screen_w * 0.4;
        const look_area_bottom = screen_h - input.TouchInput.cfg.jump_radius * 2 - 40;

        const color = ig.igColorConvertFloat4ToU32(.{ .x = cfg.look_color[0], .y = cfg.look_color[1], .z = cfg.look_color[2], .w = final_alpha });

        ig.ImDrawList_AddRectFilled(dl, .{ .x = look_area_left, .y = 0 }, .{ .x = jump_area_left, .y = look_area_bottom }, color);

        // Draw crosshair at touch point if active
        if (input_system.touch.look_touch) |touch| {
            const crosshair_color = ig.igColorConvertFloat4ToU32(.{ .x = 1.0, .y = 1.0, .z = 1.0, .w = final_alpha * 2.0 });
            const size = 8.0;
            ig.ImDrawList_AddLine(dl, .{ .x = touch.current_x - size, .y = touch.current_y }, .{ .x = touch.current_x + size, .y = touch.current_y }, crosshair_color);
            ig.ImDrawList_AddLine(dl, .{ .x = touch.current_x, .y = touch.current_y - size }, .{ .x = touch.current_x, .y = touch.current_y + size }, crosshair_color);
        }
    }
};
