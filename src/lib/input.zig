// Unified Input System - Clean, minimal, elegant
const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const ig = @import("cimgui");
const io = @import("io.zig");
const math = @import("math.zig");

const Vec2 = io.Vec2;
const Vec3 = math.Vec3;

pub const InputState = struct {
    // Movement
    move: Vec2 = .{ .x = 0, .y = 0 },

    // Look/Camera
    look: Vec2 = .{ .x = 0, .y = 0 },

    // Actions
    jump: bool = false,
    crouch: bool = false,

    // Block actions
    break_block: bool = false,
    place_block: bool = false,
    pick_block: bool = false,

    // Block selection
    prev_block: bool = false,
    next_block: bool = false,

    // System
    escape: bool = false,

    // Just pressed states for single-frame actions
    jump_pressed: bool = false,
    break_pressed: bool = false,
    place_pressed: bool = false,
    pick_pressed: bool = false,
    prev_block_pressed: bool = false,
    next_block_pressed: bool = false,
    escape_pressed: bool = false,
};

pub const Input = struct {
    state: InputState = .{},
    touch: TouchInput = .{},
    ui: TouchUI = .{},

    // Autohop state
    last_jump_time: f32 = 0,
    ground_time: f32 = 0,

    const cfg = struct {
        const mouse_sensitivity = 0.002;
        const autohop_window = 0.1; // 100ms window for autohop
    };

    pub fn update(self: *Input, io_state: *const io.IO, dt: f32, on_ground: bool) void {
        // Clear previous frame state
        self.state = .{};

        // Update autohop timing
        if (on_ground) {
            self.ground_time += dt;
        } else {
            self.ground_time = 0;
        }

        // Update touch input first
        self.touch.update(io_state);
        self.ui.update(self, dt);

        // Desktop input (keyboard + mouse)
        self.updateDesktop(io_state);

        // Mobile input (touch)
        self.updateMobile();

        // Update just-pressed states with autohop
        self.updateJustPressed(io_state, dt, on_ground);
    }

    fn updateDesktop(self: *Input, io_state: *const io.IO) void {
        // Movement (WASD)
        self.state.move = io_state.vec2(.a, .d, .s, .w);

        // Mouse look (when mouse is locked or dragging)
        if (io_state.mouse.locked() or io_state.mouse.left) {
            self.state.look.x = io_state.mouse.dx * cfg.mouse_sensitivity;
            self.state.look.y = io_state.mouse.dy * cfg.mouse_sensitivity;
        }

        // Actions
        self.state.jump = io_state.pressed(.space);
        self.state.crouch = io_state.shift();

        // Block actions
        self.state.break_block = io_state.pressed(.z);
        self.state.place_block = io_state.pressed(.x);
        self.state.pick_block = io_state.pressed(.r);

        // Block selection
        self.state.prev_block = io_state.pressed(.q);
        self.state.next_block = io_state.pressed(.e);

        // System
        self.state.escape = io_state.pressed(.escape);
    }

    fn updateMobile(self: *Input) void {
        // Add touch input to existing desktop input (allows hybrid usage)
        self.state.move.x += self.touch.movement.x;
        self.state.move.y += self.touch.movement.y;

        self.state.look.x += self.touch.look.x;
        self.state.look.y += self.touch.look.y;

        self.state.jump = self.state.jump or self.touch.jump;
        self.state.crouch = self.state.crouch or self.touch.crouch;

        // Touch block actions
        self.state.break_block = self.state.break_block or self.touch.break_block;
        self.state.place_block = self.state.place_block or self.touch.place_block;
    }

    fn updateJustPressed(self: *Input, io_state: *const io.IO, dt: f32, on_ground: bool) void {
        const jump_input = io_state.justPressed(.space) or self.touch.jump_pressed;

        // Autohop: if holding jump and recently landed, auto-jump
        const holding_jump = self.state.jump;
        const auto_jump = holding_jump and on_ground and self.ground_time < cfg.autohop_window;

        self.state.jump_pressed = jump_input or auto_jump;

        if (self.state.jump_pressed) {
            self.last_jump_time = 0;
        } else {
            self.last_jump_time += dt;
        }

        self.state.break_pressed = io_state.justPressed(.z) or self.touch.break_pressed;
        self.state.place_pressed = io_state.justPressed(.x) or self.touch.place_pressed;
        self.state.pick_pressed = io_state.justPressed(.r);
        self.state.prev_block_pressed = io_state.justPressed(.q);
        self.state.next_block_pressed = io_state.justPressed(.e);
        self.state.escape_pressed = io_state.justPressed(.escape);
    }
};

pub const TouchInput = struct {
    // Output state
    movement: Vec2 = .{ .x = 0, .y = 0 },
    look: Vec2 = .{ .x = 0, .y = 0 },
    jump: bool = false,
    crouch: bool = false,
    break_block: bool = false,
    place_block: bool = false,

    // Just pressed states
    jump_pressed: bool = false,
    break_pressed: bool = false,
    place_pressed: bool = false,

    // Internal state
    movement_touch: ?TouchState = null,
    look_touch: ?TouchState = null,
    prev_jump: bool = false,
    prev_break: bool = false,
    prev_place: bool = false,

    pub const cfg = struct {
        pub const movement_radius = 60.0;
        pub const jump_radius = 40.0;
        pub const crouch_radius = 35.0;
        pub const look_sensitivity = 0.003;
        pub const movement_deadzone = 0.1;
    };

    const TouchState = struct {
        id: usize,
        start_x: f32,
        start_y: f32,
        current_x: f32,
        current_y: f32,
    };

    pub fn update(self: *TouchInput, io_state: *const io.IO) void {
        // Update just-pressed states BEFORE clearing current state
        const prev_jump = self.jump;
        const prev_break = self.break_block;
        const prev_place = self.place_block;

        // Clear current state
        self.movement = .{ .x = 0, .y = 0 };
        self.look = .{ .x = 0, .y = 0 };
        self.jump = false;
        self.crouch = false;
        self.break_block = false;
        self.place_block = false;

        if (io_state.num_touches == 0) {
            self.movement_touch = null;
            self.look_touch = null;
        } else {
            const screen_w = sapp.widthf();
            const screen_h = sapp.heightf();

            // Process all touches
            for (0..io_state.num_touches) |i| {
                if (io_state.getTouch(i)) |touch| {
                    self.processTouch(touch, screen_w, screen_h);
                }
            }

            // Clean up ended touches
            self.cleanupTouches(io_state);
        }

        // Update just-pressed states after processing touches
        self.jump_pressed = self.jump and !prev_jump;
        self.break_pressed = self.break_block and !prev_break;
        self.place_pressed = self.place_block and !prev_place;
    }

    fn processTouch(self: *TouchInput, touch: io.Touch, screen_w: f32, screen_h: f32) void {
        const x = touch.x;
        const y = touch.y;

        // Check if this is an existing touch
        if (self.movement_touch) |*mt| {
            if (mt.id == touch.id) {
                mt.current_x = x;
                mt.current_y = y;
                self.updateMovement(mt.*);
                return;
            }
        }

        if (self.look_touch) |*lt| {
            if (lt.id == touch.id) {
                const dx = x - lt.current_x;
                const dy = y - lt.current_y;
                self.look.x = dx * cfg.look_sensitivity;
                self.look.y = dy * cfg.look_sensitivity;
                lt.current_x = x;
                lt.current_y = y;
                return;
            }
        }

        // New touch - determine what it controls
        if (self.isInMovementArea(x, y, screen_w, screen_h)) {
            if (self.movement_touch == null) {
                self.movement_touch = TouchState{
                    .id = touch.id,
                    .start_x = x,
                    .start_y = y,
                    .current_x = x,
                    .current_y = y,
                };
            }
        } else if (self.isInJumpArea(x, y, screen_w, screen_h)) {
            self.jump = true;
        } else if (self.isInCrouchArea(x, y, screen_w, screen_h)) {
            self.crouch = true;
        } else if (self.isInLookArea(x, y, screen_w, screen_h)) {
            if (self.look_touch == null) {
                self.look_touch = TouchState{
                    .id = touch.id,
                    .start_x = x,
                    .start_y = y,
                    .current_x = x,
                    .current_y = y,
                };
            }
        }
    }

    fn updateMovement(self: *TouchInput, touch_state: TouchState) void {
        const dx = touch_state.current_x - touch_state.start_x;
        const dy = touch_state.current_y - touch_state.start_y;
        const distance = @sqrt(dx * dx + dy * dy);

        if (distance > cfg.movement_deadzone) {
            const max_distance = cfg.movement_radius;
            const clamped_distance = @min(distance, max_distance);
            const normalized_distance = clamped_distance / max_distance;

            self.movement.x = (dx / distance) * normalized_distance;
            self.movement.y = -(dy / distance) * normalized_distance; // Invert Y for game coordinates
        }
    }

    fn cleanupTouches(self: *TouchInput, io_state: *const io.IO) void {
        // Check if movement touch still exists
        if (self.movement_touch) |mt| {
            var found = false;
            for (0..io_state.num_touches) |i| {
                if (io_state.getTouch(i)) |touch| {
                    if (touch.id == mt.id) {
                        found = true;
                        break;
                    }
                }
            }
            if (!found) self.movement_touch = null;
        }

        // Check if look touch still exists
        if (self.look_touch) |lt| {
            var found = false;
            for (0..io_state.num_touches) |i| {
                if (io_state.getTouch(i)) |touch| {
                    if (touch.id == lt.id) {
                        found = true;
                        break;
                    }
                }
            }
            if (!found) self.look_touch = null;
        }
    }

    // Touch area detection
    fn isInMovementArea(_: *TouchInput, x: f32, y: f32, _: f32, screen_h: f32) bool {
        const center_x = cfg.movement_radius + 20;
        const center_y = screen_h - cfg.movement_radius - 20;
        const dx = x - center_x;
        const dy = y - center_y;
        return (dx * dx + dy * dy) <= (cfg.movement_radius * cfg.movement_radius);
    }

    fn isInJumpArea(_: *TouchInput, x: f32, y: f32, screen_w: f32, screen_h: f32) bool {
        const center_x = screen_w - cfg.jump_radius - 20;
        const center_y = screen_h - cfg.jump_radius - 20;
        const dx = x - center_x;
        const dy = y - center_y;
        return (dx * dx + dy * dy) <= (cfg.jump_radius * cfg.jump_radius);
    }

    fn isInCrouchArea(_: *TouchInput, x: f32, y: f32, _: f32, screen_h: f32) bool {
        const center_x = cfg.crouch_radius + 20;
        const center_y = screen_h - cfg.movement_radius * 2 - cfg.crouch_radius - 30;
        const dx = x - center_x;
        const dy = y - center_y;
        return (dx * dx + dy * dy) <= (cfg.crouch_radius * cfg.crouch_radius);
    }

    fn isInLookArea(_: *TouchInput, x: f32, y: f32, screen_w: f32, screen_h: f32) bool {
        // Right side of screen, excluding jump button area
        const jump_area_left = screen_w - cfg.jump_radius * 2 - 40;
        const look_area_left = screen_w * 0.4;

        return x >= look_area_left and x < jump_area_left and y < screen_h - cfg.jump_radius * 2 - 40;
    }
};

// Combined Touch UI - Integrated with input system
pub const TouchUI = struct {
    show_controls: bool = false,
    fade_timer: f32 = 0,

    const cfg = struct {
        const fade_duration = 2.0;
        const alpha_base = 0.15;
        const alpha_active = 0.4;
        const alpha_pressed = 0.6;

        // Colors
        const movement_color = [3]f32{ 0.2, 0.6, 1.0 };
        const jump_color = [3]f32{ 1.0, 0.4, 0.2 };
        const crouch_color = [3]f32{ 0.8, 0.8, 0.2 };
        const look_color = [3]f32{ 0.6, 0.6, 0.6 };
    };

    pub fn update(self: *TouchUI, input_system: *const Input, dt: f32) void {
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

    pub fn render(self: *const TouchUI, input_system: *const Input) void {
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

    fn drawMovementControl(self: *const TouchUI, dl: *ig.ImDrawList, input_system: *const Input, fade_alpha: f32) void {
        _ = self;
        const radius = TouchInput.cfg.movement_radius;
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

    fn drawJumpControl(self: *const TouchUI, dl: *ig.ImDrawList, input_system: *const Input, screen_w: f32, screen_h: f32, fade_alpha: f32) void {
        _ = self;
        const radius = TouchInput.cfg.jump_radius;
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

    fn drawCrouchControl(self: *const TouchUI, dl: *ig.ImDrawList, input_system: *const Input, screen_h: f32, fade_alpha: f32) void {
        _ = self;
        const radius = TouchInput.cfg.crouch_radius;
        const center_x = radius + 20;
        const center_y = screen_h - TouchInput.cfg.movement_radius * 2 - radius - 30;

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

    fn drawLookArea(self: *const TouchUI, dl: *ig.ImDrawList, input_system: *const Input, screen_w: f32, screen_h: f32, fade_alpha: f32) void {
        _ = self;
        const is_active = input_system.touch.look_touch != null;
        if (!is_active) return;

        const alpha = cfg.alpha_base * 0.5;
        const final_alpha = alpha * fade_alpha;

        // Draw subtle look area indicator
        const jump_area_left = screen_w - TouchInput.cfg.jump_radius * 2 - 40;
        const look_area_left = screen_w * 0.4;
        const look_area_bottom = screen_h - TouchInput.cfg.jump_radius * 2 - 40;

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
