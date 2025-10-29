// Minimal input system
const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const ig = @import("cimgui");
const math = @import("math.zig");

pub const Vec2 = struct { x: f32, y: f32 };

pub const Key = enum(u16) {
    a,
    d,
    s,
    w,
    space,
    z,
    x,
    r,
    q,
    e,
    escape,
    left_shift,
    right_shift,
    none,
    pub fn from(kc: sapp.Keycode) Key {
        return switch (kc) {
            .A => .a,
            .D => .d,
            .S => .s,
            .W => .w,
            .SPACE => .space,
            .Z => .z,
            .X => .x,
            .R => .r,
            .Q => .q,
            .E => .e,
            .ESCAPE => .escape,
            .LEFT_SHIFT, .RIGHT_SHIFT => .left_shift,
            else => .none,
        };
    }
};

pub const Input = struct {
    keys: [16]bool = [_]bool{false} ** 16,
    keys_prev: [16]bool = [_]bool{false} ** 16,
    mouse: Mouse = .{},
    touches: [8]?TouchPoint = [_]?TouchPoint{null} ** 8,
    num_touches: usize = 0,

    // Game state
    move: Vec2 = .{ .x = 0, .y = 0 },
    look: Vec2 = .{ .x = 0, .y = 0 },
    jump: bool = false,
    crouch: bool = false,
    break_block: bool = false,
    place_block: bool = false,
    pick_block: bool = false,
    prev_block: bool = false,
    next_block: bool = false,
    escape: bool = false,
    restart: bool = false,

    jump_pressed: bool = false,
    break_pressed: bool = false,
    place_pressed: bool = false,
    pick_pressed: bool = false,
    prev_block_pressed: bool = false,
    next_block_pressed: bool = false,
    escape_pressed: bool = false,
    restart_pressed: bool = false,

    touch: Touch = .{},
    ui: UI = .{},
    ground_time: f32 = 0,
    pub fn update(self: *Input, dt: f32, on_ground: bool) void {
        if (on_ground) self.ground_time += dt else self.ground_time = 0;
        self.touch.update(self);
        self.ui.update(self, dt);

        const kb_move = self.vec2(.a, .d, .s, .w);
        const kb_look_x: f32 = if (self.mouse.locked() or self.mouse.left) self.mouse.dx * 0.008 else 0;
        const kb_look_y: f32 = if (self.mouse.locked() or self.mouse.left) self.mouse.dy * 0.008 else 0;

        self.move = Vec2{ .x = kb_move.x + self.touch.move.x, .y = kb_move.y + self.touch.move.y };
        self.look = Vec2{ .x = kb_look_x + self.touch.look.x, .y = kb_look_y + self.touch.look.y };

        self.jump = self.pressed(.space) or self.touch.jump;
        self.crouch = self.pressed(.left_shift) or self.touch.crouch;
        self.break_block = self.pressed(.z) or self.touch.break_block;
        self.place_block = self.pressed(.x) or self.touch.place_block;
        self.pick_block = self.pressed(.r);
        self.prev_block = self.pressed(.q);
        self.next_block = self.pressed(.e);
        self.escape = self.pressed(.escape);
        self.restart = self.pressed(.r);

        const kb_jump_pressed = self.justPressed(.space);
        const holding_jump = self.pressed(.space) or self.touch.jump;
        const auto_jump = holding_jump and on_ground and self.ground_time < 0.1;

        self.jump_pressed = kb_jump_pressed or self.touch.jump_pressed or auto_jump;
        self.break_pressed = self.justPressed(.z) or self.touch.break_pressed;
        self.place_pressed = self.justPressed(.x) or self.touch.place_pressed;
        self.pick_pressed = self.justPressed(.r);
        self.prev_block_pressed = self.justPressed(.q);
        self.next_block_pressed = self.justPressed(.e);
        self.escape_pressed = self.justPressed(.escape);
        self.restart_pressed = self.justPressed(.r);
    }

    pub fn tick(self: *Input, ev: [*c]const sapp.Event) void {
        const e = ev.*;
        switch (e.type) {
            .KEY_DOWN => {
                const k = Key.from(e.key_code);
                if (k != .none) self.keys[@intFromEnum(k)] = true;
            },
            .KEY_UP => {
                const k = Key.from(e.key_code);
                if (k != .none) self.keys[@intFromEnum(k)] = false;
            },
            .MOUSE_DOWN => switch (e.mouse_button) {
                .LEFT => self.mouse.left = true,
                .RIGHT => self.mouse.right = true,
                else => {},
            },
            .MOUSE_UP => switch (e.mouse_button) {
                .LEFT => self.mouse.left = false,
                .RIGHT => self.mouse.right = false,
                else => {},
            },
            .MOUSE_MOVE => {
                self.mouse.x = e.mouse_x;
                self.mouse.y = e.mouse_y;
                self.mouse.dx += e.mouse_dx;
                self.mouse.dy += e.mouse_dy;
            },
            .TOUCHES_BEGAN, .TOUCHES_MOVED => {
                self.num_touches = @intCast(@max(0, @min(e.num_touches, 8)));
                for (0..self.num_touches) |i| {
                    const t = e.touches[i];
                    self.touches[i] = TouchPoint{ .id = t.identifier, .x = t.pos_x, .y = t.pos_y };
                }
            },
            .TOUCHES_ENDED, .TOUCHES_CANCELLED => {
                self.touches = [_]?TouchPoint{null} ** 8;
                self.num_touches = 0;
            },
            else => {},
        }
    }

    pub fn clean(self: *Input) void {
        @memcpy(&self.keys_prev, &self.keys);
        self.mouse.left_prev = self.mouse.left;
        self.mouse.right_prev = self.mouse.right;
        self.mouse.dx = 0;
        self.mouse.dy = 0;
    }

    pub fn pressed(self: *const Input, k: Key) bool {
        return self.keys[@intFromEnum(k)];
    }

    pub fn justPressed(self: *const Input, k: Key) bool {
        const idx = @intFromEnum(k);
        return self.keys[idx] and !self.keys_prev[idx];
    }

    pub fn axis(self: *const Input, neg: Key, pos: Key) f32 {
        return @as(f32, if (self.pressed(pos)) 1 else 0) - @as(f32, if (self.pressed(neg)) 1 else 0);
    }

    pub fn vec2(self: *const Input, left: Key, right: Key, down: Key, up: Key) Vec2 {
        return .{ .x = self.axis(left, right), .y = self.axis(down, up) };
    }
};
pub const Mouse = struct {
    x: f32 = 0,
    y: f32 = 0,
    dx: f32 = 0,
    dy: f32 = 0,
    left: bool = false,
    right: bool = false,
    left_prev: bool = false,
    right_prev: bool = false,

    pub fn locked(_: *const Mouse) bool {
        return sapp.mouseLocked();
    }
    pub fn rightPressed(self: *const Mouse) bool {
        return self.right and !self.right_prev;
    }
    pub fn leftPressed(self: *const Mouse) bool {
        return self.left and !self.left_prev;
    }
};

pub const TouchPoint = struct { id: usize, x: f32, y: f32 };

pub const Touch = struct {
    move: Vec2 = .{ .x = 0, .y = 0 },
    look: Vec2 = .{ .x = 0, .y = 0 },
    jump: bool = false,
    crouch: bool = false,
    break_block: bool = false,
    place_block: bool = false,
    jump_pressed: bool = false,
    break_pressed: bool = false,
    place_pressed: bool = false,

    move_touch: ?TouchData = null,
    look_touch: ?TouchData = null,
    jump_touch: ?TouchData = null,
    crouch_touch: ?TouchData = null,
    jump_toggled: bool = false,

    const TouchData = struct { id: usize, start_x: f32, start_y: f32, x: f32, y: f32 };

    pub fn update(self: *Touch, input: *const Input) void {
        const prev_jump = self.jump;
        self.move = .{ .x = 0, .y = 0 };
        self.look = .{ .x = 0, .y = 0 };
        self.jump = false;
        self.crouch = false;

        if (input.num_touches == 0) {
            self.move_touch = null;
            self.look_touch = null;
            self.jump_touch = null;
            self.crouch_touch = null;
            return;
        }

        const w = sapp.widthf();
        const h = sapp.heightf();

        for (0..input.num_touches) |i| {
            if (input.touches[i]) |touch| {
                self.processTouch(.{ .id = touch.id, .x = touch.x, .y = touch.y }, w, h);
            }
        }

        if (self.jump_touch != null) self.jump_toggled = !self.jump_toggled;
        self.jump = self.jump_toggled;
        if (self.crouch_touch != null) self.crouch = true;
        self.jump_pressed = self.jump and !prev_jump;
    }
    fn processTouch(self: *Touch, touch: struct { id: usize, x: f32, y: f32 }, w: f32, h: f32) void {
        const x, const y = .{ touch.x, touch.y };

        // Movement area (bottom left)
        if (self.inCircle(x, y, 75 + 20, h - 75 - 20, 75)) {
            if (self.move_touch == null) {
                self.move_touch = TouchData{ .id = touch.id, .start_x = x, .start_y = y, .x = x, .y = y };
            } else if (self.move_touch.?.id == touch.id) {
                self.move_touch.?.x = x;
                self.move_touch.?.y = y;
                const dx = x - self.move_touch.?.start_x;
                const dy = y - self.move_touch.?.start_y;
                const dist = @sqrt(dx * dx + dy * dy);
                if (dist > 0.1) {
                    const norm = @min(dist, 75) / 75;
                    self.move.x = (dx / dist) * norm;
                    self.move.y = -(dy / dist) * norm;
                }
            }
        }
        // Jump area (bottom right)
        else if (self.inCircle(x, y, w - 50 - 20, h - 50 - 20, 50)) {
            if (self.jump_touch == null) {
                self.jump_touch = TouchData{ .id = touch.id, .start_x = x, .start_y = y, .x = x, .y = y };
            }
        }
        // Crouch area (left side, above movement)
        else if (self.inCircle(x, y, 44 + 20, h - 150 - 44 - 30, 44)) {
            if (self.crouch_touch == null) {
                self.crouch_touch = TouchData{ .id = touch.id, .start_x = x, .start_y = y, .x = x, .y = y };
            }
        }
        // Look area (right side, excluding jump)
        else if (x >= w * 0.4 and x < w - 100 and y < h - 100) {
            if (self.look_touch == null) {
                self.look_touch = TouchData{ .id = touch.id, .start_x = x, .start_y = y, .x = x, .y = y };
            } else if (self.look_touch.?.id == touch.id) {
                const dx = x - self.look_touch.?.x;
                const dy = y - self.look_touch.?.y;
                self.look.x = dx * 0.012;
                self.look.y = dy * 0.012;
                self.look_touch.?.x = x;
                self.look_touch.?.y = y;
            }
        }
    }

    fn inCircle(_: *Touch, x: f32, y: f32, cx: f32, cy: f32, r: f32) bool {
        const dx = x - cx;
        const dy = y - cy;
        return (dx * dx + dy * dy) <= (r * r);
    }
};
pub const UI = struct {
    show: bool = false,
    fade: f32 = 0,

    pub fn update(self: *UI, input: *const Input, dt: f32) void {
        const has_touch = input.touch.move_touch != null or input.touch.look_touch != null or input.touch.jump or input.touch.crouch;
        if (has_touch) {
            self.show = true;
            self.fade = 2.0;
        } else if (self.fade > 0) {
            self.fade -= dt;
            if (self.fade <= 0) self.show = false;
        }
    }

    pub fn render(self: *const UI, input: *const Input) void {
        if (!self.show) return;
        const w, const h = .{ sapp.widthf(), sapp.heightf() };
        const alpha: f32 = if (self.fade > 0) 1.0 else 0.0;

        ig.igSetNextWindowPos(.{ .x = 0, .y = 0 }, ig.ImGuiCond_Always);
        ig.igSetNextWindowSize(.{ .x = w, .y = h }, ig.ImGuiCond_Always);
        const flags = ig.ImGuiWindowFlags_NoTitleBar | ig.ImGuiWindowFlags_NoResize |
            ig.ImGuiWindowFlags_NoMove | ig.ImGuiWindowFlags_NoScrollbar |
            ig.ImGuiWindowFlags_NoBackground | ig.ImGuiWindowFlags_NoInputs;

        if (ig.igBegin("TouchControls", null, flags)) {
            const dl = ig.igGetWindowDrawList();
            self.drawCircle(dl, 75 + 20, h - 75 - 20, 75, input.touch.move_touch != null, alpha, .{ 0.2, 0.6, 1.0 });
            self.drawCircle(dl, w - 50 - 20, h - 50 - 20, 50, input.touch.jump, alpha, .{ 1.0, 0.4, 0.2 });
            self.drawCircle(dl, 44 + 20, h - 150 - 44 - 30, 44, input.touch.crouch, alpha, .{ 0.8, 0.8, 0.2 });
        }
        ig.igEnd();
    }

    fn drawCircle(self: *const UI, dl: *ig.ImDrawList, cx: f32, cy: f32, r: f32, active: bool, fade: f32, rgb: struct { f32, f32, f32 }) void {
        _ = self;
        const base: f32 = if (active) 0.6 else 0.15;
        const a = base * fade;
        const color = ig.igColorConvertFloat4ToU32(.{ .x = rgb[0], .y = rgb[1], .z = rgb[2], .w = a });
        ig.ImDrawList_AddCircleFilled(dl, .{ .x = cx, .y = cy }, r, color, 24);
        ig.ImDrawList_AddCircle(dl, .{ .x = cx, .y = cy }, r, color);
    }
};
