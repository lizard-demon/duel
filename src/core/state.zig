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
    show_leaderboard: bool = false,
    last_run_time: f32 = 0,

    pub fn init(allocator: std.mem.Allocator) State {
        return .{
            .config = .{
                .local = .{ .player = .{ .username = "Player" }, .state = .build },
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

        // Make copies of all strings to ensure they're owned by us
        if (self.config.local.player.username.len > 0) {
            const username_copy = try self.allocator.dupe(u8, self.config.local.player.username);
            self.config.local.player.username = username_copy;
        }

        if (self.config.data.len > 0) {
            const data_copy = try self.allocator.dupe(u8, self.config.data);
            self.config.data = data_copy;
        }

        // Copy leaderboard usernames
        for (self.config.leaderboard, 0..) |entry, i| {
            if (entry.username.len > 0) {
                const name_copy = try self.allocator.dupe(u8, entry.username);
                self.config.leaderboard[i].username = name_copy;
            }
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

        // Free all our copied strings
        if (self.config.local.player.username.len > 0) {
            self.allocator.free(@constCast(self.config.local.player.username));
        }

        if (self.config.data.len > 0) {
            self.allocator.free(@constCast(self.config.data));
        }

        // Free leaderboard usernames
        for (self.config.leaderboard) |entry| {
            if (entry.username.len > 0) {
                self.allocator.free(@constCast(entry.username));
            }
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

        while (read_pos + 1 < compressed.len and block_pos < 64 * 64 * 64) {
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

    // Add or update leaderboard entry
    pub fn updateLeaderboard(self: *State, username: []const u8, time: f32) !bool {
        const max_entries = 100;

        // Check if user already exists on leaderboard
        for (self.config.leaderboard, 0..) |entry, i| {
            if (std.mem.eql(u8, entry.username, username)) {
                // Update existing entry if new time is better
                if (time < entry.time) {
                    self.config.leaderboard[i].time = time;
                    self.sortLeaderboard();
                    return true;
                }
                return false; // Time wasn't better
            }
        }

        // Check if leaderboard is full and time doesn't qualify
        if (self.config.leaderboard.len >= max_entries) {
            if (time >= self.config.leaderboard[self.config.leaderboard.len - 1].time) {
                return false; // Time doesn't qualify for top 100
            }
        }

        // Simple approach: recreate the entire leaderboard array
        const new_size = @min(self.config.leaderboard.len + 1, max_entries);
        const new_leaderboard = try self.allocator.alloc(@TypeOf(self.config.leaderboard[0]), new_size);

        // Copy existing entries
        var copied: usize = 0;
        for (self.config.leaderboard) |entry| {
            if (copied < new_size - 1) { // Leave space for new entry
                const username_copy = try self.allocator.dupe(u8, entry.username);
                new_leaderboard[copied] = .{ .username = username_copy, .time = entry.time };
                copied += 1;
            }
        }

        // Add new entry
        const username_copy = try self.allocator.dupe(u8, username);
        new_leaderboard[copied] = .{ .username = username_copy, .time = time };

        // Free old leaderboard
        for (self.config.leaderboard) |entry| {
            self.allocator.free(@constCast(entry.username));
        }
        if (self.config.leaderboard.len > 0) {
            self.allocator.free(self.config.leaderboard);
        }

        // Update config
        self.config.leaderboard = new_leaderboard;
        self.sortLeaderboard();
        return true;
    }

    // Sort leaderboard by time (ascending)
    fn sortLeaderboard(self: *State) void {
        const Entry = @TypeOf(self.config.leaderboard[0]);
        const lessThan = struct {
            fn lessThan(_: void, a: Entry, b: Entry) bool {
                return a.time < b.time;
            }
        }.lessThan;

        std.mem.sort(Entry, self.config.leaderboard, {}, lessThan);
    }

    // Get user's rank on leaderboard (1-based, 0 if not found)
    pub fn getUserRank(self: *const State, username: []const u8) usize {
        for (self.config.leaderboard, 0..) |entry, i| {
            if (std.mem.eql(u8, entry.username, username)) {
                return i + 1;
            }
        }
        return 0;
    }

    // Get user's best time (0 if not found)
    pub fn getUserBestTime(self: *const State, username: []const u8) f32 {
        for (self.config.leaderboard) |entry| {
            if (std.mem.eql(u8, entry.username, username)) {
                return entry.time;
            }
        }
        return 0;
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
