// Elegant unified input system - keyboard, mouse, and touch
const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const ig = @import("cimgui");
const math = @import("math.zig");

pub const Vec2 = struct { x: f32, y: f32 };
pub const Vec3 = math.Vec3;

// Minimal key enum - only what we need
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
    left_ctrl,
    right_ctrl,
    left_alt,
    right_alt,
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
            .LEFT_SHIFT => .left_shift,
            .RIGHT_SHIFT => .right_shift,
            .LEFT_CONTROL => .left_ctrl,
            .RIGHT_CONTROL => .right_ctrl,
            .LEFT_ALT => .left_alt,
            .RIGHT_ALT => .right_alt,
            else => .none,
        };
    }
};

// Core input state
pub const Input = struct {
    // Raw input state
    keys: [32]bool = [_]bool{false} ** 32,
    keys_prev: [32]bool = [_]bool{false} ** 32,
    mouse: Mouse = .{},
    touches: [sapp.max_touchpoints]?Touch = [_]?Touch{null} ** sapp.max_touchpoints,
    num_touches: usize = 0,

    // Game input state
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

    // Just pressed states
    jump_pressed: bool = false,
    break_pressed: bool = false,
    place_pressed: bool = false,
    pick_pressed: bool = false,
    prev_block_pressed: bool = false,
    next_block_pressed: bool = false,
    escape_pressed: bool = false,
    restart_pressed: bool = false,

    // Touch state
    touch: TouchState = .{},
    ui: TouchUI = .{},

    // Autohop
    ground_time: f32 = 0,

    const mouse_sens = 0.008;
    const autohop_window = 0.1;

    pub fn update(self: *Input, dt: f32, on_ground: bool) void {
        // Update timing
        if (on_ground) self.ground_time += dt else self.ground_time = 0;

        // Update touch
        self.touch.update(self);
        self.ui.update(self, dt);

        // Combine keyboard + touch input
        const kb_move = self.vec2(.a, .d, .s, .w);
        const kb_look_x: f32 = if (self.mouse.locked() or self.mouse.left) self.mouse.dx * mouse_sens else 0;
        const kb_look_y: f32 = if (self.mouse.locked() or self.mouse.left) self.mouse.dy * mouse_sens else 0;

        self.move = Vec2{ .x = kb_move.x + self.touch.move.x, .y = kb_move.y + self.touch.move.y };
        self.look = Vec2{ .x = kb_look_x + self.touch.look.x, .y = kb_look_y + self.touch.look.y };

        // Actions
        self.jump = self.pressed(.space) or self.touch.jump;
        self.crouch = self.shift() or self.touch.crouch;
        self.break_block = self.pressed(.z) or self.touch.break_block;
        self.place_block = self.pressed(.x) or self.touch.place_block;
        self.pick_block = self.pressed(.r);
        self.prev_block = self.pressed(.q);
        self.next_block = self.pressed(.e);
        self.escape = self.pressed(.escape);
        self.restart = self.pressed(.r);

        // Just pressed with autohop
        const kb_jump_pressed = self.justPressed(.space);
        const holding_jump = self.pressed(.space) or self.touch.jump;
        const auto_jump = holding_jump and on_ground and self.ground_time < autohop_window;

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
                .MIDDLE => self.mouse.middle = true,
                else => {},
            },
            .MOUSE_UP => switch (e.mouse_button) {
                .LEFT => self.mouse.left = false,
                .RIGHT => self.mouse.right = false,
                .MIDDLE => self.mouse.middle = false,
                else => {},
            },
            .MOUSE_MOVE => {
                self.mouse.x = e.mouse_x;
                self.mouse.y = e.mouse_y;
                self.mouse.dx += e.mouse_dx;
                self.mouse.dy += e.mouse_dy;
            },
            .MOUSE_SCROLL => {
                self.mouse.scroll_x += e.scroll_x;
                self.mouse.scroll_y += e.scroll_y;
            },
            .TOUCHES_BEGAN, .TOUCHES_MOVED => {
                self.num_touches = @intCast(@max(0, @min(e.num_touches, sapp.max_touchpoints)));
                for (0..self.num_touches) |i| {
                    const t = e.touches[i];
                    self.touches[i] = Touch{
                        .id = t.identifier,
                        .x = t.pos_x,
                        .y = t.pos_y,
                        .changed = t.changed,
                    };
                }
            },
            .TOUCHES_ENDED, .TOUCHES_CANCELLED => {
                self.touches = [_]?Touch{null} ** sapp.max_touchpoints;
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
        self.mouse.scroll_x = 0;
        self.mouse.scroll_y = 0;
    }

    // Key queries
    pub fn pressed(self: *const Input, k: Key) bool {
        return self.keys[@intFromEnum(k)];
    }

    pub fn justPressed(self: *const Input, k: Key) bool {
        const idx = @intFromEnum(k);
        return self.keys[idx] and !self.keys_prev[idx];
    }

    pub fn shift(self: *const Input) bool {
        return self.pressed(.left_shift) or self.pressed(.right_shift);
    }

    pub fn ctrl(self: *const Input) bool {
        return self.pressed(.left_ctrl) or self.pressed(.right_ctrl);
    }

    pub fn alt(self: *const Input) bool {
        return self.pressed(.left_alt) or self.pressed(.right_alt);
    }

    pub fn axis(self: *const Input, neg: Key, pos: Key) f32 {
        return @as(f32, if (self.pressed(pos)) 1 else 0) -
            @as(f32, if (self.pressed(neg)) 1 else 0);
    }

    pub fn vec2(self: *const Input, left: Key, right: Key, down: Key, up: Key) Vec2 {
        return .{ .x = self.axis(left, right), .y = self.axis(down, up) };
    }

    pub fn getTouch(self: *const Input, idx: usize) ?Touch {
        if (idx >= sapp.max_touchpoints) return null;
        return self.touches[idx];
    }
};

pub const Mouse = struct {
    x: f32 = 0,
    y: f32 = 0,
    dx: f32 = 0,
    dy: f32 = 0,
    scroll_x: f32 = 0,
    scroll_y: f32 = 0,
    left: bool = false,
    right: bool = false,
    middle: bool = false,
    left_prev: bool = false,
    right_prev: bool = false,

    pub fn lock(_: *Mouse) void {
        sapp.lockMouse(true);
    }
    pub fn unlock(_: *Mouse) void {
        sapp.lockMouse(false);
    }
    pub fn locked(_: *const Mouse) bool {
        return sapp.mouseLocked();
    }
    pub fn toggle(self: *Mouse) void {
        if (self.locked()) self.unlock() else self.lock();
    }
    pub fn rightPressed(self: *const Mouse) bool {
        return self.right and !self.right_prev;
    }
    pub fn leftPressed(self: *const Mouse) bool {
        return self.left and !self.left_prev;
    }
};

pub const Touch = struct {
    id: usize,
    x: f32,
    y: f32,
    changed: bool,
};

// Touch input handling
pub const TouchState = struct {
    move: Vec2 = .{ .x = 0, .y = 0 },
    look: Vec2 = .{ .x = 0, .y = 0 },
    jump: bool = false,
    crouch: bool = false,
    break_block: bool = false,
    place_block: bool = false,
    jump_pressed: bool = false,
    break_pressed: bool = false,
    place_pressed: bool = false,

    // Internal state
    move_touch: ?TouchData = null,
    look_touch: ?TouchData = null,
    jump_touch: ?TouchData = null,
    crouch_touch: ?TouchData = null,
    jump_toggled: bool = false,
    prev_jump_id: ?usize = null,

    const TouchData = struct { id: usize, start_x: f32, start_y: f32, x: f32, y: f32 };
    const move_radius = 75.0;
    const jump_radius = 50.0;
    const crouch_radius = 44.0;
    const look_sens = 0.012;
    const deadzone = 0.1;

    pub fn update(self: *TouchState, input: *const Input) void {
        const prev_jump = self.jump;
        const prev_break = self.break_block;
        const prev_place = self.place_block;

        // Clear state
        self.move = .{ .x = 0, .y = 0 };
        self.look = .{ .x = 0, .y = 0 };
        self.jump = false;
        self.crouch = false;
        self.break_block = false;
        self.place_block = false;

        if (input.num_touches == 0) {
            self.clearTouches();
            return;
        }

        const w = sapp.widthf();
        const h = sapp.heightf();

        // Process touches
        for (0..input.num_touches) |i| {
            if (input.getTouch(i)) |touch| {
                self.processTouch(touch, w, h);
            }
        }

        self.cleanupTouches(input);

        // Handle jump toggle
        if (self.jump_touch) |jt| {
            if (self.prev_jump_id == null or self.prev_jump_id.? != jt.id) {
                self.jump_toggled = !self.jump_toggled;
                self.prev_jump_id = jt.id;
            }
        } else {
            self.prev_jump_id = null;
        }

        self.jump = self.jump_toggled;
        if (self.crouch_touch != null) self.crouch = true;

        // Update pressed states
        self.jump_pressed = self.jump and !prev_jump;
        self.break_pressed = self.break_block and !prev_break;
        self.place_pressed = self.place_block and !prev_place;
    }

    fn processTouch(self: *TouchState, touch: Touch, w: f32, h: f32) void {
        // Update existing touches
        if (self.move_touch) |*mt| {
            if (mt.id == touch.id) {
                mt.x = touch.x;
                mt.y = touch.y;
                self.updateMove(mt.*);
                return;
            }
        }

        if (self.look_touch) |*lt| {
            if (lt.id == touch.id) {
                const dx = touch.x - lt.x;
                const dy = touch.y - lt.y;
                self.look.x = dx * look_sens;
                self.look.y = dy * look_sens;
                lt.x = touch.x;
                lt.y = touch.y;
                return;
            }
        }

        if (self.jump_touch) |*jt| {
            if (jt.id == touch.id) {
                jt.x = touch.x;
                jt.y = touch.y;
                return;
            }
        }

        if (self.crouch_touch) |*ct| {
            if (ct.id == touch.id) {
                ct.x = touch.x;
                ct.y = touch.y;
                return;
            }
        }

        // New touch
        if (self.inMoveArea(touch.x, touch.y, w, h) and self.move_touch == null) {
            self.move_touch = TouchData{ .id = touch.id, .start_x = touch.x, .start_y = touch.y, .x = touch.x, .y = touch.y };
        } else if (self.inJumpArea(touch.x, touch.y, w, h) and self.jump_touch == null) {
            self.jump_touch = TouchData{ .id = touch.id, .start_x = touch.x, .start_y = touch.y, .x = touch.x, .y = touch.y };
        } else if (self.inCrouchArea(touch.x, touch.y, w, h) and self.crouch_touch == null) {
            self.crouch_touch = TouchData{ .id = touch.id, .start_x = touch.x, .start_y = touch.y, .x = touch.x, .y = touch.y };
        } else if (self.inLookArea(touch.x, touch.y, w, h) and self.look_touch == null) {
            self.look_touch = TouchData{ .id = touch.id, .start_x = touch.x, .start_y = touch.y, .x = touch.x, .y = touch.y };
        }
    }

    fn updateMove(self: *TouchState, td: TouchData) void {
        const dx = td.x - td.start_x;
        const dy = td.y - td.start_y;
        const dist = @sqrt(dx * dx + dy * dy);
        if (dist > deadzone) {
            const norm_dist = @min(dist, move_radius) / move_radius;
            self.move.x = (dx / dist) * norm_dist;
            self.move.y = -(dy / dist) * norm_dist;
        }
    }

    fn clearTouches(self: *TouchState) void {
        self.move_touch = null;
        self.look_touch = null;
        self.jump_touch = null;
        self.crouch_touch = null;
        self.prev_jump_id = null;
    }

    fn cleanupTouches(self: *TouchState, input: *const Input) void {
        if (input.num_touches == 0) {
            self.clearTouches();
            return;
        }

        // Remove touches not found in current touch list
        if (self.move_touch) |mt| {
            if (!self.findTouch(input, mt.id)) self.move_touch = null;
        }
        if (self.look_touch) |lt| {
            if (!self.findTouch(input, lt.id)) self.look_touch = null;
        }
        if (self.jump_touch) |jt| {
            if (!self.findTouch(input, jt.id)) self.jump_touch = null;
        }
        if (self.crouch_touch) |ct| {
            if (!self.findTouch(input, ct.id)) self.crouch_touch = null;
        }
    }

    fn findTouch(self: *TouchState, input: *const Input, id: usize) bool {
        _ = self;
        for (0..input.num_touches) |i| {
            if (input.getTouch(i)) |touch| {
                if (touch.id == id) return true;
            }
        }
        return false;
    }

    fn inMoveArea(_: *TouchState, x: f32, y: f32, _: f32, h: f32) bool {
        const cx = move_radius + 20;
        const cy = h - move_radius - 20;
        const dx = x - cx;
        const dy = y - cy;
        return (dx * dx + dy * dy) <= (move_radius * move_radius);
    }

    fn inJumpArea(_: *TouchState, x: f32, y: f32, w: f32, h: f32) bool {
        const cx = w - jump_radius - 20;
        const cy = h - jump_radius - 20;
        const dx = x - cx;
        const dy = y - cy;
        return (dx * dx + dy * dy) <= (jump_radius * jump_radius);
    }

    fn inCrouchArea(_: *TouchState, x: f32, y: f32, _: f32, h: f32) bool {
        const cx = crouch_radius + 20;
        const cy = h - move_radius * 2 - crouch_radius - 30;
        const dx = x - cx;
        const dy = y - cy;
        return (dx * dx + dy * dy) <= (crouch_radius * crouch_radius);
    }

    fn inLookArea(_: *TouchState, x: f32, y: f32, w: f32, h: f32) bool {
        const jump_left = w - jump_radius * 2 - 40;
        const look_left = w * 0.4;
        return x >= look_left and x < jump_left and y < h - jump_radius * 2 - 40;
    }
};

// Touch UI rendering
pub const TouchUI = struct {
    show: bool = false,
    fade: f32 = 0,

    const fade_time = 2.0;
    const alpha_base: f32 = 0.15;
    const alpha_active: f32 = 0.4;
    const alpha_pressed: f32 = 0.6;

    pub fn update(self: *TouchUI, input: *const Input, dt: f32) void {
        const has_touch = input.touch.move_touch != null or input.touch.look_touch != null or
            input.touch.jump or input.touch.crouch;

        if (has_touch) {
            self.show = true;
            self.fade = fade_time;
        } else if (self.fade > 0) {
            self.fade -= dt;
            if (self.fade <= 0) self.show = false;
        }
    }

    pub fn render(self: *const TouchUI, input: *const Input) void {
        if (!self.show) return;

        const w = sapp.widthf();
        const h = sapp.heightf();
        const alpha: f32 = if (self.fade > 0) 1.0 else 0.0;

        ig.igSetNextWindowPos(.{ .x = 0, .y = 0 }, ig.ImGuiCond_Always);
        ig.igSetNextWindowSize(.{ .x = w, .y = h }, ig.ImGuiCond_Always);
        const flags = ig.ImGuiWindowFlags_NoTitleBar | ig.ImGuiWindowFlags_NoResize |
            ig.ImGuiWindowFlags_NoMove | ig.ImGuiWindowFlags_NoScrollbar |
            ig.ImGuiWindowFlags_NoBackground | ig.ImGuiWindowFlags_NoInputs;

        if (ig.igBegin("TouchControls", null, flags)) {
            const dl = ig.igGetWindowDrawList();
            self.drawMove(dl, input, alpha);
            self.drawJump(dl, input, w, h, alpha);
            self.drawCrouch(dl, input, h, alpha);
            self.drawLook(dl, input, w, h, alpha);
        }
        ig.igEnd();
    }

    fn drawMove(self: *const TouchUI, dl: *ig.ImDrawList, input: *const Input, fade: f32) void {
        _ = self;
        const r = TouchState.move_radius;
        const cx = r + 20;
        const cy = sapp.heightf() - r - 20;
        const active = input.touch.move_touch != null;
        const a = (if (active) alpha_active else alpha_base) * fade;

        const color = ig.igColorConvertFloat4ToU32(.{ .x = 0.2, .y = 0.6, .z = 1.0, .w = a });
        const border = ig.igColorConvertFloat4ToU32(.{ .x = 0.2, .y = 0.6, .z = 1.0, .w = a * 0.8 });

        ig.ImDrawList_AddCircleFilled(dl, .{ .x = cx, .y = cy }, r, color, 32);
        ig.ImDrawList_AddCircle(dl, .{ .x = cx, .y = cy }, r, border);

        if (active and input.touch.move_touch != null) {
            const t = input.touch.move_touch.?;
            const knob = ig.igColorConvertFloat4ToU32(.{ .x = 1.0, .y = 1.0, .z = 1.0, .w = a * 1.5 });
            ig.ImDrawList_AddCircleFilled(dl, .{ .x = t.x, .y = t.y }, r * 0.2, knob, 16);
        }
    }

    fn drawJump(self: *const TouchUI, dl: *ig.ImDrawList, input: *const Input, w: f32, h: f32, fade: f32) void {
        _ = self;
        const r = TouchState.jump_radius;
        const cx = w - r - 20;
        const cy = h - r - 20;
        const pressed = input.touch.jump;
        const a = (if (pressed) alpha_pressed else alpha_base) * fade;

        const color = ig.igColorConvertFloat4ToU32(.{ .x = 1.0, .y = 0.4, .z = 0.2, .w = a });
        const border = ig.igColorConvertFloat4ToU32(.{ .x = 1.0, .y = 0.4, .z = 0.2, .w = a * 0.8 });

        ig.ImDrawList_AddCircleFilled(dl, .{ .x = cx, .y = cy }, r, color, 24);
        ig.ImDrawList_AddCircle(dl, .{ .x = cx, .y = cy }, r, border);

        // Up arrow
        const icon = ig.igColorConvertFloat4ToU32(.{ .x = 1.0, .y = 1.0, .z = 1.0, .w = a * 1.2 });
        const s = r * 0.4;
        ig.ImDrawList_AddTriangleFilled(dl, .{ .x = cx, .y = cy - s }, .{ .x = cx - s * 0.6, .y = cy + s * 0.3 }, .{ .x = cx + s * 0.6, .y = cy + s * 0.3 }, icon);
    }

    fn drawCrouch(self: *const TouchUI, dl: *ig.ImDrawList, input: *const Input, h: f32, fade: f32) void {
        _ = self;
        const r = TouchState.crouch_radius;
        const cx = r + 20;
        const cy = h - TouchState.move_radius * 2 - r - 30;
        const pressed = input.touch.crouch;
        const a = (if (pressed) alpha_pressed else alpha_base) * fade;

        const color = ig.igColorConvertFloat4ToU32(.{ .x = 0.8, .y = 0.8, .z = 0.2, .w = a });
        const border = ig.igColorConvertFloat4ToU32(.{ .x = 0.8, .y = 0.8, .z = 0.2, .w = a * 0.8 });

        ig.ImDrawList_AddCircleFilled(dl, .{ .x = cx, .y = cy }, r, color, 20);
        ig.ImDrawList_AddCircle(dl, .{ .x = cx, .y = cy }, r, border);

        // Down arrow
        const icon = ig.igColorConvertFloat4ToU32(.{ .x = 1.0, .y = 1.0, .z = 1.0, .w = a * 1.2 });
        const s = r * 0.4;
        ig.ImDrawList_AddTriangleFilled(dl, .{ .x = cx, .y = cy + s }, .{ .x = cx - s * 0.6, .y = cy - s * 0.3 }, .{ .x = cx + s * 0.6, .y = cy - s * 0.3 }, icon);
    }

    fn drawLook(self: *const TouchUI, dl: *ig.ImDrawList, input: *const Input, w: f32, h: f32, fade: f32) void {
        _ = self;
        const active = input.touch.look_touch != null;
        if (!active) return;

        const a = alpha_base * 0.5 * fade;
        const jump_left = w - TouchState.jump_radius * 2 - 40;
        const look_left = w * 0.4;
        const look_bottom = h - TouchState.jump_radius * 2 - 40;

        const color = ig.igColorConvertFloat4ToU32(.{ .x = 0.6, .y = 0.6, .z = 0.6, .w = a });
        ig.ImDrawList_AddRectFilled(dl, .{ .x = look_left, .y = 0 }, .{ .x = jump_left, .y = look_bottom }, color);

        if (input.touch.look_touch) |t| {
            const cross = ig.igColorConvertFloat4ToU32(.{ .x = 1.0, .y = 1.0, .z = 1.0, .w = a * 2.0 });
            const s = 8.0;
            ig.ImDrawList_AddLine(dl, .{ .x = t.x - s, .y = t.y }, .{ .x = t.x + s, .y = t.y }, cross);
            ig.ImDrawList_AddLine(dl, .{ .x = t.x, .y = t.y - s }, .{ .x = t.x, .y = t.y + s }, cross);
        }
    }
};
