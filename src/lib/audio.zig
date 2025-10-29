// Minimal audio system
const std = @import("std");
const sokol = @import("sokol");
const saudio = sokol.audio;

pub const Audio = struct {
    pub fn init() Audio {
        saudio.setup(.{
            .sample_rate = 44100,
            .num_channels = 2,
            .buffer_frames = 1024,
            .stream_cb = callback,
        });
        return .{};
    }

    pub fn deinit() void {
        shutdown = true;
        if (saudio.isvalid()) saudio.shutdown();
    }

    pub fn playJumpSound() void {
        if (!shutdown and saudio.isvalid()) {
            jump_trigger = true;
            recordJump();
        }
    }

    pub fn playLandSound() void {
        if (!shutdown and saudio.isvalid()) land_trigger = true;
    }
};

var shutdown: bool = false;
var jump_trigger: bool = false;
var jump_time: f32 = 0;
var jump_phase: f32 = 0;
var land_trigger: bool = false;
var land_time: f32 = 0;
var land_phase: f32 = 0;

// Jump frequency tracking for volume adjustment
var jump_history: [10]f32 = [_]f32{0} ** 10; // Store last 10 jump times
var jump_history_index: usize = 0;
var current_time: f32 = 0;
var jump_volume_multiplier: f32 = 1.0;

fn callback(buffer: [*c]f32, num_frames: i32, num_channels: i32) callconv(.c) void {
    if (shutdown) {
        const total_samples = @as(usize, @intCast(num_frames * num_channels));
        @memset(buffer[0..total_samples], 0.0);
        return;
    }

    const frames = @as(usize, @intCast(num_frames));
    const channels = @as(usize, @intCast(num_channels));
    const sample_rate: f32 = 44100.0;
    const dt = 1.0 / sample_rate;

    for (0..frames) |i| {
        var sample: f32 = 0;

        // Update current time for jump frequency tracking
        current_time += dt;
        updateJumpVolumeMultiplier();

        // Jump sound: frequency sweep with strong envelope like original
        if (jump_trigger) {
            jump_trigger = false;
            jump_time = 0.15;
            jump_phase = 0;
        }
        if (jump_time > 0) {
            const progress = 1.0 - (jump_time / 0.15);
            const frequency = 220.0 + (440.0 - 220.0) * progress;
            const envelope = @exp(-progress * 8.0) * (1.0 - progress * 0.3);

            // Apply volume multiplier based on jump frequency
            sample += @sin(jump_phase * 2.0 * std.math.pi) * envelope * 0.3 * jump_volume_multiplier;
            jump_phase += frequency / sample_rate;
            if (jump_phase >= 1.0) jump_phase -= 1.0;
            jump_time -= 1.0 / sample_rate;
        }

        // Land sound: falling frequency with noise like original
        if (land_trigger) {
            land_trigger = false;
            land_time = 0.08;
            land_phase = 0;
        }
        if (land_time > 0) {
            const progress = 1.0 - (land_time / 0.08);
            const frequency = 150.0 + (80.0 - 150.0) * progress;
            const envelope = @exp(-progress * 12.0) * (1.0 - progress * 0.5);

            // Add noise like the original for that satisfying thump
            const noise = (@sin(land_phase * 13.7) * 0.3 + @sin(land_phase * 27.1) * 0.2) * 0.1;
            sample += (@sin(land_phase * 2.0 * std.math.pi) + noise) * envelope * 0.2;

            land_phase += frequency / sample_rate;
            if (land_phase >= 1.0) land_phase -= 1.0;
            land_time -= 1.0 / sample_rate;
        }

        // Write to all channels
        for (0..channels) |ch| {
            buffer[i * channels + ch] = sample;
        }
    }
}

fn recordJump() void {
    // Record the current time in the circular buffer
    jump_history[jump_history_index] = current_time;
    jump_history_index = (jump_history_index + 1) % jump_history.len;
}

fn updateJumpVolumeMultiplier() void {
    // Count jumps in the last 2 seconds
    const time_window: f32 = 2.0;
    const current = current_time;
    var recent_jumps: u32 = 0;

    for (jump_history) |recorded_time| {
        if (recorded_time > 0 and (current - recorded_time) <= time_window) {
            recent_jumps += 1;
        }
    }

    // Normal rate: 1-3 jumps per 2 seconds = full volume
    // Fast rate: 4-6 jumps per 2 seconds = reduced volume
    // Very fast rate: 7+ jumps per 2 seconds = very low volume
    if (recent_jumps <= 3) {
        jump_volume_multiplier = 1.0; // Full volume
    } else if (recent_jumps <= 6) {
        // Gradually reduce volume from 1.0 to 0.3
        const excess = @as(f32, @floatFromInt(recent_jumps - 3));
        jump_volume_multiplier = 1.0 - (excess / 3.0) * 0.7; // 1.0 -> 0.3
    } else {
        // Very low volume for excessive jumping
        jump_volume_multiplier = 0.1;
    }
}
