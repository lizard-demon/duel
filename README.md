# Voxels

A minimalist voxel world built with Zig and Sokol.

## Features

- **Build Mode**: Create and modify voxel structures
- **Speedrun Mode**: Race through levels with precision movement
- **Leaderboards**: Track your best times
- **Smooth Physics**: Bunnyhopping and wall sliding mechanics
- **Cross-Platform**: Native desktop and web support

## Controls

| Action | Key |
|--------|-----|
| Move | `WASD` |
| Jump | `Space` |
| Crouch | `Shift` |
| Place Block | `X` |
| Break Block | `Z` |
| Pick Block | `R` |
| Restart | `R` |

## Building

```bash
zig build
```

## Running

```bash
zig build run
```

## Web Build

```bash
zig build -Dtarget=wasm32-emscripten
```

---

*Built with [Zig](https://ziglang.org) and [Sokol](https://github.com/floooh/sokol)*