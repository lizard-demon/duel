const std = @import("std");
const sokol = @import("sokol");
const saudio = sokol.audio;

// Simple audio system for jump sounds
pub const Audio = struct {
    initialized: bool = false,

    pub fn init() Audio {
        audio_shutting_down = false;

        saudio.setup(.{
            .sample_rate = 44100,
            .num_channels = 2,
            .buffer_frames = 1024,
            .stream_cb = audioCallback,
        });

        return Audio{
            .initialized = saudio.isvalid(),
        };
    }

    pub fn deinit() void {
        // Set shutdown flag first to prevent any new audio calls
        audio_shutting_down = true;

        // Now safely shutdown
        if (saudio.isvalid()) {
            saudio.shutdown();
        }
    }

    pub fn playJumpSound() void {
        // Don't play if shutting down or audio invalid
        if (audio_shutting_down or !saudio.isvalid()) return;
        jump_triggered = true;
    }

    pub fn playLandSound() void {
        // Don't play if shutting down or audio invalid
        if (audio_shutting_down or !saudio.isvalid()) return;
        land_triggered = true;
    }
};

// Global shutdown flag to prevent audio calls during shutdown
var audio_shutting_down: bool = false;

// Simple jump sound generation
var jump_triggered: bool = false;
var jump_phase: f32 = 0.0;
var jump_duration: f32 = 0.0;

var land_triggered: bool = false;
var land_phase: f32 = 0.0;
var land_duration: f32 = 0.0;

const JUMP_SOUND_DURATION = 0.15; // 150ms
const JUMP_FREQUENCY_START = 220.0; // A3
const JUMP_FREQUENCY_END = 440.0; // A4

const LAND_SOUND_DURATION = 0.08; // 80ms
const LAND_FREQUENCY_START = 150.0; // Lower frequency
const LAND_FREQUENCY_END = 80.0; // Even lower

fn audioCallback(buffer: [*c]f32, num_frames: i32, num_channels: i32) callconv(.c) void {
    // Safety check: if shutting down or audio system is not valid, fill with silence
    if (audio_shutting_down or !saudio.isvalid()) {
        const total_samples = @as(usize, @intCast(num_frames * num_channels));
        @memset(buffer[0..total_samples], 0.0);
        return;
    }

    const frames = @as(usize, @intCast(num_frames));
    const channels = @as(usize, @intCast(num_channels));
    const sample_rate = @as(f32, @floatFromInt(saudio.sampleRate()));

    for (0..frames) |i| {
        var sample: f32 = 0.0;

        // Generate jump sound if triggered
        if (jump_triggered or jump_duration > 0.0) {
            if (jump_triggered) {
                jump_triggered = false;
                jump_duration = JUMP_SOUND_DURATION;
                jump_phase = 0.0;
            }

            if (jump_duration > 0.0) {
                // Progress through the sound (0.0 to 1.0)
                const progress = 1.0 - (jump_duration / JUMP_SOUND_DURATION);

                // Frequency sweep from low to high
                const frequency = JUMP_FREQUENCY_START + (JUMP_FREQUENCY_END - JUMP_FREQUENCY_START) * progress;

                // Envelope: quick attack, exponential decay
                const envelope = @exp(-progress * 8.0) * (1.0 - progress * 0.3);

                // Generate sine wave
                sample += @sin(jump_phase * 2.0 * std.math.pi) * envelope * 0.3;

                // Update phase
                jump_phase += frequency / sample_rate;
                if (jump_phase >= 1.0) jump_phase -= 1.0;

                // Update duration
                jump_duration -= 1.0 / sample_rate;
                if (jump_duration <= 0.0) {
                    jump_duration = 0.0;
                    jump_phase = 0.0;
                }
            }
        }

        // Generate land sound if triggered
        if (land_triggered or land_duration > 0.0) {
            if (land_triggered) {
                land_triggered = false;
                land_duration = LAND_SOUND_DURATION;
                land_phase = 0.0;
            }

            if (land_duration > 0.0) {
                // Progress through the sound (0.0 to 1.0)
                const progress = 1.0 - (land_duration / LAND_SOUND_DURATION);

                // Frequency sweep from high to low (opposite of jump)
                const frequency = LAND_FREQUENCY_START + (LAND_FREQUENCY_END - LAND_FREQUENCY_START) * progress;

                // Sharp attack, quick decay
                const envelope = @exp(-progress * 12.0) * (1.0 - progress * 0.5);

                // Generate sine wave with some simple noise
                const noise = (@sin(land_phase * 13.7) * 0.3 + @sin(land_phase * 27.1) * 0.2) * 0.1;
                sample += (@sin(land_phase * 2.0 * std.math.pi) + noise) * envelope * 0.2;

                // Update phase
                land_phase += frequency / sample_rate;
                if (land_phase >= 1.0) land_phase -= 1.0;

                // Update duration
                land_duration -= 1.0 / sample_rate;
                if (land_duration <= 0.0) {
                    land_duration = 0.0;
                    land_phase = 0.0;
                }
            }
        }

        // Write to all channels
        for (0..channels) |ch| {
            buffer[i * channels + ch] = sample;
        }
    }
}
