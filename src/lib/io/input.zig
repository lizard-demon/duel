const std = @import("std");
const sokol = @import("sokol");
    const sapp = sokol.app;

pub const Key = enum(u16) {
    a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z,
    _0, _1, _2, _3, _4, _5, _6, _7, _8, _9,
    f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20, f21, f22, f23, f24, f25,
    up, down, left, right, page_up, page_down, home, end,
    left_shift, right_shift, left_ctrl, right_ctrl, left_alt, right_alt, left_super, right_super,
    space, enter, tab, backspace, escape, insert, delete, caps_lock, scroll_lock, num_lock, print_screen, pause, menu,
    apostrophe, comma, minus, period, slash, semicolon, equal, left_bracket, backslash, right_bracket, grave_accent,
    kp_0, kp_1, kp_2, kp_3, kp_4, kp_5, kp_6, kp_7, kp_8, kp_9, kp_decimal, kp_divide, kp_multiply, kp_subtract, kp_add, kp_enter, kp_equal,
    world_1, world_2, none,

    pub fn from(kc: sapp.Keycode) Key {
        return switch (kc) {
            .A => .a, .B => .b, .C => .c, .D => .d, .E => .e, .F => .f, .G => .g, .H => .h, .I => .i, .J => .j,
            .K => .k, .L => .l, .M => .m, .N => .n, .O => .o, .P => .p, .Q => .q, .R => .r, .S => .s, .T => .t,
            .U => .u, .V => .v, .W => .w, .X => .x, .Y => .y, .Z => .z,
            ._0 => ._0, ._1 => ._1, ._2 => ._2, ._3 => ._3, ._4 => ._4, ._5 => ._5, ._6 => ._6, ._7 => ._7, ._8 => ._8, ._9 => ._9,
            .F1 => .f1, .F2 => .f2, .F3 => .f3, .F4 => .f4, .F5 => .f5, .F6 => .f6, .F7 => .f7, .F8 => .f8, .F9 => .f9, .F10 => .f10,
            .F11 => .f11, .F12 => .f12, .F13 => .f13, .F14 => .f14, .F15 => .f15, .F16 => .f16, .F17 => .f17, .F18 => .f18, .F19 => .f19, .F20 => .f20,
            .F21 => .f21, .F22 => .f22, .F23 => .f23, .F24 => .f24, .F25 => .f25,
            .UP => .up, .DOWN => .down, .LEFT => .left, .RIGHT => .right, .PAGE_UP => .page_up, .PAGE_DOWN => .page_down, .HOME => .home, .END => .end,
            .LEFT_SHIFT => .left_shift, .RIGHT_SHIFT => .right_shift, .LEFT_CONTROL => .left_ctrl, .RIGHT_CONTROL => .right_ctrl,
            .LEFT_ALT => .left_alt, .RIGHT_ALT => .right_alt, .LEFT_SUPER => .left_super, .RIGHT_SUPER => .right_super,
            .SPACE => .space, .ENTER => .enter, .TAB => .tab, .BACKSPACE => .backspace, .ESCAPE => .escape, .INSERT => .insert, .DELETE => .delete,
            .CAPS_LOCK => .caps_lock, .SCROLL_LOCK => .scroll_lock, .NUM_LOCK => .num_lock, .PRINT_SCREEN => .print_screen, .PAUSE => .pause, .MENU => .menu,
            .APOSTROPHE => .apostrophe, .COMMA => .comma, .MINUS => .minus, .PERIOD => .period, .SLASH => .slash, .SEMICOLON => .semicolon,
            .EQUAL => .equal, .LEFT_BRACKET => .left_bracket, .BACKSLASH => .backslash, .RIGHT_BRACKET => .right_bracket, .GRAVE_ACCENT => .grave_accent,
            .KP_0 => .kp_0, .KP_1 => .kp_1, .KP_2 => .kp_2, .KP_3 => .kp_3, .KP_4 => .kp_4, .KP_5 => .kp_5, .KP_6 => .kp_6, .KP_7 => .kp_7,
            .KP_8 => .kp_8, .KP_9 => .kp_9, .KP_DECIMAL => .kp_decimal, .KP_DIVIDE => .kp_divide, .KP_MULTIPLY => .kp_multiply,
            .KP_SUBTRACT => .kp_subtract, .KP_ADD => .kp_add, .KP_ENTER => .kp_enter, .KP_EQUAL => .kp_equal,
            .WORLD_1 => .world_1, .WORLD_2 => .world_2,
            else => .none,
        };
    }
};

pub const Vec2 = struct { x: f32, y: f32 };
pub const Touch = struct { id: usize, x: f32, y: f32, changed: bool, tool_type: sapp.AndroidTooltype };

pub const Mouse = struct {
    x: f32 = 0, y: f32 = 0, dx: f32 = 0, dy: f32 = 0, scroll_x: f32 = 0, scroll_y: f32 = 0,
    left: bool = false, right: bool = false, middle: bool = false, cursor: sapp.MouseCursor = .DEFAULT,

    pub fn lock(_: *Mouse) void { sapp.lockMouse(true); }
    pub fn unlock(_: *Mouse) void { sapp.lockMouse(false); }
    pub fn isLocked(_: *const Mouse) bool { return sapp.mouseLocked(); }
    pub fn toggle(self: *Mouse) void { if (self.isLocked()) self.unlock() else self.lock(); }
    pub fn show(_: *Mouse) void { sapp.showMouse(true); }
    pub fn hide(_: *Mouse) void { sapp.showMouse(false); }
    pub fn isShown(_: *const Mouse) bool { return sapp.mouseShown(); }
    pub fn setCursor(self: *Mouse, cursor: sapp.MouseCursor) void { sapp.setMouseCursor(cursor); self.cursor = cursor; }
};

pub const IO = struct {
    keys: [512]bool = [_]bool{false} ** 512, keys_prev: [512]bool = [_]bool{false} ** 512,
    mouse: Mouse = .{}, touches: [sapp.max_touchpoints]?Touch = [_]?Touch{null} ** sapp.max_touchpoints,
    num_touches: usize = 0, char_code: u32 = 0, frame_count: u64 = 0,
    window_resized: bool = false, window_focused: bool = true, window_iconified: bool = false,

    pub fn pressed(self: *const IO, k: Key) bool { return self.keys[@intFromEnum(k)]; }
    pub fn released(self: *const IO, k: Key) bool { return !self.keys[@intFromEnum(k)]; }
    pub fn justPressed(self: *const IO, k: Key) bool {
        const idx = @intFromEnum(k);
        return self.keys[idx] and !self.keys_prev[idx];
    }
    pub fn justReleased(self: *const IO, k: Key) bool {
        const idx = @intFromEnum(k);
        return !self.keys[idx] and self.keys_prev[idx];
    }

    pub fn axis(self: *const IO, neg: Key, pos: Key) f32 {
        return @as(f32, if (self.pressed(pos)) 1 else 0) - @as(f32, if (self.pressed(neg)) 1 else 0);
    }
    pub fn vec2(self: *const IO, left: Key, right: Key, down: Key, up: Key) Vec2 {
        return .{ .x = self.axis(left, right), .y = self.axis(down, up) };
    }

    pub fn shift(self: *const IO) bool { return self.pressed(.left_shift) or self.pressed(.right_shift); }
    pub fn ctrl(self: *const IO) bool { return self.pressed(.left_ctrl) or self.pressed(.right_ctrl); }
    pub fn alt(self: *const IO) bool { return self.pressed(.left_alt) or self.pressed(.right_alt); }
    pub fn super(self: *const IO) bool { return self.pressed(.left_super) or self.pressed(.right_super); }

    pub fn getTouch(self: *const IO, idx: usize) ?Touch {
        if (idx >= sapp.max_touchpoints) return null;
        return self.touches[idx];
    }

    pub fn cleanInput(self: *IO) void {
        @memcpy(&self.keys_prev, &self.keys);
        self.mouse.dx = 0; self.mouse.dy = 0; self.mouse.scroll_x = 0; self.mouse.scroll_y = 0;
        self.char_code = 0; self.window_resized = false;
    }

    pub fn update(self: *IO, ev: [*c]const sapp.Event) void {
        const e = ev.*; self.frame_count = e.frame_count;
        switch (e.type) {
            .KEY_DOWN => { const k = Key.from(e.key_code); if (k != .none) self.keys[@intFromEnum(k)] = true; },
            .KEY_UP => { const k = Key.from(e.key_code); if (k != .none) self.keys[@intFromEnum(k)] = false; },
            .CHAR => self.char_code = e.char_code,
            .MOUSE_DOWN => switch (e.mouse_button) {
                .LEFT => self.mouse.left = true, .RIGHT => self.mouse.right = true, .MIDDLE => self.mouse.middle = true, else => {},
            },
            .MOUSE_UP => switch (e.mouse_button) {
                .LEFT => self.mouse.left = false, .RIGHT => self.mouse.right = false, .MIDDLE => self.mouse.middle = false, else => {},
            },
            .MOUSE_MOVE => {
                self.mouse.x = e.mouse_x; self.mouse.y = e.mouse_y;
                self.mouse.dx += e.mouse_dx; self.mouse.dy += e.mouse_dy;
            },
            .MOUSE_SCROLL => { self.mouse.scroll_x += e.scroll_x; self.mouse.scroll_y += e.scroll_y; },
            .MOUSE_ENTER, .MOUSE_LEAVE => {},
            .TOUCHES_BEGAN, .TOUCHES_MOVED => {
                self.num_touches = @intCast(@max(0, @min(e.num_touches, sapp.max_touchpoints)));
                for (0..self.num_touches) |i| {
                    const t = e.touches[i];
                    self.touches[i] = Touch{ .id = t.identifier, .x = t.pos_x, .y = t.pos_y, .changed = t.changed, .tool_type = t.android_tooltype };
                }
            },
            .TOUCHES_ENDED, .TOUCHES_CANCELLED => {
                self.touches = [_]?Touch{null} ** sapp.max_touchpoints;
                self.num_touches = 0;
            },
            .RESIZED => self.window_resized = true,
            .ICONIFIED => self.window_iconified = true,
            .RESTORED => self.window_iconified = false,
            .FOCUSED => self.window_focused = true,
            .UNFOCUSED => self.window_focused = false,
            .SUSPENDED, .RESUMED, .QUIT_REQUESTED, .CLIPBOARD_PASTED, .FILES_DROPPED => {},
            else => {},
        }
    }
};
