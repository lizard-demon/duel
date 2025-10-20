const math = @import("lib/math.zig");
const world = @import("core/world.zig");
const player = @import("core/player.zig");

const Vec3 = math.Vec3;
const Map = world.Map;
const Player = player.Player;
const AABB = player.AABB;

pub const lib = struct {
    pub fn lookdir(yaw: f32, pitch: f32) Vec3 {
        return Vec3.new(@sin(yaw) * @cos(pitch), -@sin(pitch), -@cos(yaw) * @cos(pitch));
    }

    pub fn bbox(pos: Vec3, crouch: bool, crouch_height: f32, stand_height: f32, width: f32) AABB {
        const h: f32 = if (crouch) crouch_height else stand_height;
        const w: f32 = width;
        return AABB{
            .min = pos.add(Vec3.new(-w, -h / 2.0, -w)),
            .max = pos.add(Vec3.new(w, h / 2.0, w)),
        };
    }

    pub fn standbox(pos: Vec3, width: f32, height: f32) AABB {
        const box = AABB{
            .min = Vec3.new(-width, -height / 2.0, -width),
            .max = Vec3.new(width, height / 2.0, width),
        };
        return box.at(pos);
    }

    pub fn blockbox(pos: Vec3) AABB {
        return AABB{
            .min = pos,
            .max = pos.add(Vec3.new(1, 1, 1)),
        };
    }
};

pub const handle = struct {
    pub fn movement(p: *Player, yaw: f32, dt: f32, cfg: anytype) void {
        const mv = p.io.vec2(.a, .d, .s, .w);
        var dir = Vec3.zero();
        if (mv.x != 0) dir = dir.add(Vec3.new(@cos(yaw), 0, @sin(yaw)).scale(mv.x));
        if (mv.y != 0) dir = dir.add(Vec3.new(@sin(yaw), 0, -@cos(yaw)).scale(mv.y));
        Player.update.pos(p, cfg, dir, dt);
    }

    pub fn crouch(p: *Player, world_map: *Map, stand_height: f32, crouch_height: f32, width: f32) void {
        const wish = p.io.shift();

        if (p.crouch and !wish) {
            const diff = (stand_height - crouch_height) / 2.0;
            const test_pos = Vec3.new(p.pos.data[0], p.pos.data[1] + diff, p.pos.data[2]);
            const standing = lib.standbox(test_pos, width, stand_height);

            if (!player.checkStaticCollision(world_map, standing)) {
                p.pos.data[1] += diff;
                p.crouch = false;
            }
        } else {
            p.crouch = wish;
        }
    }

    pub fn jump(p: *Player, jump_power: f32) void {
        if (p.io.pressed(.space) and p.ground) {
            p.vel.data[1] = jump_power;
            p.ground = false;
        }
    }

    pub fn camera(p: *Player, sensitivity: f32, pitch_limit: f32) void {
        if (!p.io.mouse.locked()) return;

        p.yaw += p.io.mouse.dx * sensitivity;
        p.pitch = @max(-pitch_limit, @min(pitch_limit, p.pitch + p.io.mouse.dy * sensitivity));
    }

    pub fn blocks(p: *Player, world_map: *Map, reach: f32, crouch_height: f32, stand_height: f32, width: f32) bool {
        if (!p.io.mouse.locked()) return false;

        const look = lib.lookdir(p.yaw, p.pitch);
        const hit = player.raycast(world_map, p.pos, look, reach) orelse return false;
        const pos = [3]i32{
            @intFromFloat(@floor(hit.data[0])),
            @intFromFloat(@floor(hit.data[1])),
            @intFromFloat(@floor(hit.data[2])),
        };

        // Break block
        if (p.io.mouse.leftPressed()) {
            return world_map.set(pos[0], pos[1], pos[2], 0);
        }

        // Place block
        if (p.io.mouse.rightPressed()) {
            const prev = hit.sub(look.scale(0.1));
            const place_pos = [3]i32{
                @intFromFloat(@floor(prev.data[0])),
                @intFromFloat(@floor(prev.data[1])),
                @intFromFloat(@floor(prev.data[2])),
            };
            const block_pos = Vec3.new(@floatFromInt(place_pos[0]), @floatFromInt(place_pos[1]), @floatFromInt(place_pos[2]));

            const player_box = lib.bbox(p.pos, p.crouch, crouch_height, stand_height, width);
            const block_box = lib.blockbox(block_pos);

            if (!AABB.overlaps(player_box, block_box)) {
                return world_map.set(place_pos[0], place_pos[1], place_pos[2], p.block);
            }
        }

        // Pick block color
        if (p.io.justPressed(.r)) {
            const target = world_map.get(pos[0], pos[1], pos[2]);
            if (target != 0) p.block = target;
        }

        return false;
    }

    pub fn color(p: *Player) void {
        if (!p.io.mouse.locked()) return;

        if (p.io.justPressed(.q)) p.block -%= 1;
        if (p.io.justPressed(.e)) p.block +%= 1;
    }

    pub fn mouse(p: *Player) void {
        if (p.io.justPressed(.escape)) p.io.mouse.unlock();
        if (p.io.mouse.left and !p.io.mouse.locked()) p.io.mouse.lock();
    }
};

// Configuration struct to pass game settings
pub const Config = struct {
    sensitivity: f32,
    pitch_limit: f32,
    stand_height: f32,
    crouch_height: f32,
    width: f32,
    jump_power: f32,
    reach: f32,
};

pub fn tick(player_ptr: *Player, world_map: *Map, dt: f32, cfg: Config, game_cfg: anytype) bool {
    handle.movement(player_ptr, player_ptr.yaw, dt, game_cfg);
    handle.crouch(player_ptr, world_map, cfg.stand_height, cfg.crouch_height, cfg.width);
    handle.jump(player_ptr, cfg.jump_power);
    handle.camera(player_ptr, cfg.sensitivity, cfg.pitch_limit);
    const world_changed = handle.blocks(player_ptr, world_map, cfg.reach, cfg.crouch_height, cfg.stand_height, cfg.width);
    handle.color(player_ptr);
    handle.mouse(player_ptr);
    return world_changed;
}
