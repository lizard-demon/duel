// Entire Render Pipeline
const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sglue = sokol.glue;
const sapp = sokol.app;
const ig = @import("cimgui");
const math = @import("../lib/math.zig");
const world = @import("world.zig");
const input = @import("../lib/input.zig");
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

pub const UI = struct {
    const cfg = struct {
        const crosshair_size = 8.0;
        const crosshair_color = [3]f32{ 1.0, 1.0, 1.0 };
        const crosshair_alpha = 0.8;
        const hud_x = 16.0;
        const hud_y = 16.0;
        const hud_w = 120.0;
        const hud_h = 70.0;
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

        pub fn hud(block: world.Block, speedrun_time: ?f32) void {
            ig.igSetNextWindowPos(.{ .x = cfg.hud_x, .y = cfg.hud_y }, ig.ImGuiCond_Always);
            ig.igSetNextWindowSize(.{ .x = cfg.hud_w, .y = cfg.hud_h }, ig.ImGuiCond_Always);
            const hud_flags = ig.ImGuiWindowFlags_NoTitleBar | ig.ImGuiWindowFlags_NoResize | ig.ImGuiWindowFlags_NoMove | ig.ImGuiWindowFlags_NoScrollbar | ig.ImGuiWindowFlags_NoBackground | ig.ImGuiWindowFlags_NoInputs;
            if (ig.igBegin("GameHUD", null, hud_flags)) {
                const dl = ig.igGetWindowDrawList();

                if (speedrun_time) |time| {
                    // Speedrun mode - show timer
                    const timer_x = cfg.hud_x + 8;
                    const timer_y = cfg.hud_y + 8;

                    // Timer text (no background)
                    const timer_color = ig.igColorConvertFloat4ToU32(.{ .x = 1.0, .y = 1.0, .z = 0.2, .w = 1.0 });
                    var time_buf: [32]u8 = undefined;
                    const time_str = std.fmt.bufPrintZ(&time_buf, "{d:.2}s", .{time}) catch "0.00s";
                    ig.ImDrawList_AddText(dl, .{ .x = timer_x, .y = timer_y }, timer_color, time_str.ptr);

                    // Instructions
                    const inst_color = ig.igColorConvertFloat4ToU32(.{ .x = 0.8, .y = 0.8, .z = 0.8, .w = 0.8 });
                    ig.ImDrawList_AddText(dl, .{ .x = timer_x, .y = timer_y + 16 }, inst_color, "R to restart");
                } else {
                    // Build mode - show block selector
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
            }
            ig.igEnd();
        }

        pub fn touchControls(input_system: *const input.Input) void {
            input_system.ui.render(input_system);
        }

        pub fn leaderboard(state_ptr: *@import("state.zig").State) bool {
            const window_width = 400.0;
            const window_height = 500.0;
            const center_x = @as(f32, @floatFromInt(sapp.width())) / 2.0 - window_width / 2.0;
            const center_y = @as(f32, @floatFromInt(sapp.height())) / 2.0 - window_height / 2.0;

            ig.igSetNextWindowPos(.{ .x = center_x, .y = center_y }, ig.ImGuiCond_Always);
            ig.igSetNextWindowSize(.{ .x = window_width, .y = window_height }, ig.ImGuiCond_Always);

            const window_flags = ig.ImGuiWindowFlags_NoResize | ig.ImGuiWindowFlags_NoMove | ig.ImGuiWindowFlags_NoCollapse;
            if (ig.igBegin("Speedrun Leaderboard", null, window_flags)) {
                // Show last run time
                if (state_ptr.last_run_time > 0) {
                    var time_buf: [64]u8 = undefined;
                    const time_str = std.fmt.bufPrintZ(&time_buf, "Your time: {d:.2}s", .{state_ptr.last_run_time}) catch "Your time: 0.00s";
                    ig.igText(time_str.ptr);
                    ig.igSeparator();
                }

                // Show user's rank and best time
                if (state_ptr.config.local.player.username.len > 0) {
                    const rank = state_ptr.getUserRank(state_ptr.config.local.player.username);
                    const best_time = state_ptr.getUserBestTime(state_ptr.config.local.player.username);

                    if (rank > 0) {
                        var rank_buf: [64]u8 = undefined;
                        const rank_str = std.fmt.bufPrintZ(&rank_buf, "Your rank: #{d} (Best: {d:.2}s)", .{ rank, best_time }) catch "Your rank: N/A";
                        ig.igText(rank_str.ptr);
                    } else {
                        ig.igText("Not on leaderboard yet");
                    }
                    ig.igSeparator();
                }

                // Show top entries
                ig.igText("Top Times:");
                ig.igSeparator();

                const max_display = @min(state_ptr.config.leaderboard.len, 20); // Show top 20
                for (state_ptr.config.leaderboard[0..max_display], 0..) |entry, i| {
                    // Mark current user with an arrow
                    const is_current_user = std.mem.eql(u8, entry.username, state_ptr.config.local.player.username);
                    const marker = if (is_current_user) ">" else " ";

                    var entry_buf: [128]u8 = undefined;
                    const entry_str = std.fmt.bufPrintZ(&entry_buf, "{s}#{d:2}  {s:<20} {d:6.2}s", .{ marker, i + 1, entry.username, entry.time }) catch "Error";
                    ig.igText(entry_str.ptr);
                }
                ig.igSeparator();

                // Close button
                if (ig.igButton("Close (R to restart)")) {
                    ig.igEnd();
                    return true; // Signal to close leaderboard
                }
            }
            ig.igEnd();
            return false; // Keep leaderboard open
        }
    };

    pub inline fn render(block: world.Block, input_system: *const input.Input, speedrun_time: ?f32, state_ptr: *@import("state.zig").State) void {
        draw.crosshair();
        draw.hud(block, speedrun_time);
        draw.touchControls(input_system);

        // Show leaderboard if requested
        if (state_ptr.show_leaderboard) {
            if (draw.leaderboard(state_ptr)) {
                state_ptr.show_leaderboard = false;
            }
        }
    }
};
