// Unified Input System - Clean, minimal, elegant
const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
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

    const cfg = struct {
        const mouse_sensitivity = 0.002;
        const touch_sensitivity = 0.003;
        const pitch_limit = std.math.pi / 2.0;
    };

    pub fn update(self: *Input, io_state: *const io.IO) void {
        // Clear previous frame state
        self.state = .{};

        // Update touch input first
        self.touch.update(io_state);

        // Desktop input (keyboard + mouse)
        self.updateDesktop(io_state);

        // Mobile input (touch)
        self.updateMobile();

        // Update just-pressed states
        self.updateJustPressed(io_state);
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

    fn updateJustPressed(self: *Input, io_state: *const io.IO) void {
        self.state.jump_pressed = io_state.justPressed(.space) or self.touch.jump_pressed;
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
        // Clear previous state
        self.movement = .{ .x = 0, .y = 0 };
        self.look = .{ .x = 0, .y = 0 };
        self.jump = false;
        self.crouch = false;
        self.break_block = false;
        self.place_block = false;

        // Update just-pressed states
        self.jump_pressed = self.jump and !self.prev_jump;
        self.break_pressed = self.break_block and !self.prev_break;
        self.place_pressed = self.place_block and !self.prev_place;

        self.prev_jump = self.jump;
        self.prev_break = self.break_block;
        self.prev_place = self.place_block;

        if (io_state.num_touches == 0) {
            self.movement_touch = null;
            self.look_touch = null;
            return;
        }

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
