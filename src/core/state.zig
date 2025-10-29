const std = @import("std");

// The state.json format
pub const Config = struct {
    local: struct {
        player: struct { username: []const u8 },
        state: enum { build, speedrun },
    },
    leaderboard: []struct {
        username: []const u8,
        time: f32,
    },
    data: []const u8,
};

// Simple state manager
pub const State = struct {
    config: Config,
    allocator: std.mem.Allocator,
    parsed: ?std.json.Parsed(Config),

    pub fn init(allocator: std.mem.Allocator) State {
        return .{
            .config = .{
                .local = .{ .player = .{ .username = "" }, .state = .build },
                .leaderboard = &.{},
                .data = "",
            },
            .allocator = allocator,
            .parsed = null,
        };
    }

    pub fn load(self: *State) !void {
        const file = std.fs.cwd().openFile("state.json", .{}) catch return;
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        self.parsed = try std.json.parseFromSlice(Config, self.allocator, content, .{});
        self.config = self.parsed.?.value;

        // Make a copy of the data string to ensure it's owned by us
        if (self.config.data.len > 0) {
            const data_copy = try self.allocator.dupe(u8, self.config.data);
            self.config.data = data_copy;
        }
    }

    pub fn save(self: State, writer_buffer: []u8) !void {
        const file = try std.fs.cwd().createFile("state.json", .{});
        defer file.close();

        // Use the new std.Io.Writer interface with buffering
        var file_writer = file.writer(writer_buffer);

        // Try to use JSON stringify with the new writer interface
        try file_writer.interface.print("{{\n", .{});
        try file_writer.interface.print("  \"local\": {{\n", .{});
        try file_writer.interface.print("    \"player\": {{\n", .{});
        try file_writer.interface.print("      \"username\": \"{s}\"\n", .{self.config.local.player.username});
        try file_writer.interface.print("    }},\n", .{});
        try file_writer.interface.print("    \"state\": \"{s}\"\n", .{@tagName(self.config.local.state)});
        try file_writer.interface.print("  }},\n", .{});
        try file_writer.interface.print("  \"leaderboard\": [\n", .{});

        for (self.config.leaderboard, 0..) |entry, i| {
            if (i > 0) try file_writer.interface.print(",\n", .{});
            try file_writer.interface.print("    {{\n", .{});
            try file_writer.interface.print("      \"username\": \"{s}\",\n", .{entry.username});
            try file_writer.interface.print("      \"time\": {d}\n", .{entry.time});
            try file_writer.interface.print("    }}", .{});
        }

        try file_writer.interface.print("\n  ],\n", .{});
        try file_writer.interface.print("  \"data\": \"{s}\"\n", .{self.config.data});
        try file_writer.interface.print("}}\n", .{});

        // Ensure all buffered data is written
        try file_writer.interface.flush();
    }

    pub fn deinit(self: *State, writer_buffer: []u8) void {
        self.save(writer_buffer) catch {};

        // Free our copied data
        if (self.config.data.len > 0) {
            self.allocator.free(@constCast(self.config.data));
        }

        if (self.parsed) |parsed| parsed.deinit();
    }

    // Load world data from state into Map
    pub fn loadWorldData(self: *const State, map: *@import("world.zig").Map) !void {
        if (self.config.data.len == 0) return;

        // Safety check for base64 data
        if (self.config.data.len < 4) return; // Base64 needs at least 4 chars

        const decoder = std.base64.standard.Decoder;
        const decoded_len = decoder.calcSizeForSlice(self.config.data) catch |err| {
            std.log.err("Failed to calculate base64 decode size: {}", .{err});
            return;
        };

        const compressed = try self.allocator.alloc(u8, decoded_len);
        defer self.allocator.free(compressed);
        decoder.decode(compressed, self.config.data) catch |err| {
            std.log.err("Failed to decode base64 data: {}", .{err});
            return;
        };

        // RLE decompress
        map.blocks = std.mem.zeroes([64][64][64]@import("world.zig").Block);
        var read_pos: usize = 0;
        var block_pos: usize = 0;

        while (read_pos < compressed.len and block_pos < 64 * 64 * 64) {
            const run_length = compressed[read_pos];
            const block_value = compressed[read_pos + 1];
            read_pos += 2;

            for (0..run_length) |_| {
                if (block_pos >= 64 * 64 * 64) break;
                const x = block_pos / (64 * 64);
                const y = (block_pos % (64 * 64)) / 64;
                const z = block_pos % 64;
                map.blocks[x][y][z] = block_value;
                block_pos += 1;
            }
        }
    }

    // Save world data from Map into state
    pub fn saveWorldData(self: *State, map: *const @import("world.zig").Map) !void {
        // RLE compress the world data
        const compressed = try self.allocator.alloc(u8, 64 * 64 * 64 * 2);
        defer self.allocator.free(compressed);

        var write_pos: usize = 0;
        var current_block = map.blocks[0][0][0];
        var run_length: u8 = 1;

        for (0..64) |x| {
            for (0..64) |y| {
                for (0..64) |z| {
                    if (x == 0 and y == 0 and z == 0) continue;

                    const block = map.blocks[x][y][z];
                    if (block == current_block and run_length < 255) {
                        run_length += 1;
                    } else {
                        compressed[write_pos] = run_length;
                        compressed[write_pos + 1] = current_block;
                        write_pos += 2;
                        current_block = block;
                        run_length = 1;
                    }
                }
            }
        }
        compressed[write_pos] = run_length;
        compressed[write_pos + 1] = current_block;
        write_pos += 2;

        // Encode to base64
        const encoder = std.base64.standard.Encoder;
        const encoded_len = encoder.calcSize(write_pos);

        // Free old data if it exists
        if (self.config.data.len > 0) {
            self.allocator.free(@constCast(self.config.data));
        }

        const encoded_data = try self.allocator.alloc(u8, encoded_len);
        _ = encoder.encode(encoded_data, compressed[0..write_pos]);

        // Update config data
        self.config.data = encoded_data;
    }
};
