const std = @import("std");

pub const State = struct {
    json: struct {
        local: struct {
            player: struct { username: []const u8 },
            state: enum { build, speedrun },
        },

        leaderboard: []struct {
            username: []const u8,
            time: f32,
        },

        data: []const u8,
    },

    allocator: std.mem.Allocator,
    parsed: std.json.Parsed(@TypeOf(@field(@This(){}, "json"))),

    pub fn init(allocator: std.mem.Allocator) State {
        return State{
            .json = .{
                .local = .{ .player = .{ .username = "" }, .state = .build },
                .leaderboard = &.{},
                .data = "",
            },
            .allocator = allocator,
            .parsed = undefined,
        };
    }

    pub fn deinit(self: *State) void {
        self.parsed.deinit();
    }

    pub fn load(self: *State) !void {
        const file = try std.fs.cwd().openFile("state.json", .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        self.parsed = try std.json.parseFromSlice(@TypeOf(self.json), self.allocator, content, .{});
        self.json = self.parsed.value;
    }

    pub fn save(self: State) !void {
        const file = try std.fs.cwd().createFile("state.json", .{});
        defer file.close();

        try std.json.stringify(self.json, .{ .whitespace = .indent_2 }, file.writer());
    }
};
