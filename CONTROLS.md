# Voxel Engine Controls

## Movement
- **WASD** - Move forward/backward/left/right
- **Space** - Jump
- **Shift** - Crouch
- **Mouse** - Look around (click to capture mouse)
- **Escape** - Release mouse

## Block Interaction
- **Left Click** - Break blocks (when not shooting)
- **Right Click** - Place blocks (when not charging weapon)

## Block Selection
- **1** - Select Grass blocks
- **2** - Select Dirt blocks  
- **3** - Select Stone blocks

## Weapon System
- **Right Click (Hold)** - Charge weapon
- **Left Click** - Fire weapon (when charged)

## Features
- Physics-based player movement with collision detection
- Real-time block placement and breaking
- Automatic mesh regeneration when world changes
- Weapon system with recoil physics
- Block selection with number keys
- Raycast-based block targeting (5 block reach)
- Collision prevention (can't place blocks inside player)

## HUD Information
The debug HUD shows:
- Player position and velocity
- Camera yaw and pitch
- Ground contact status
- Crouch status
- Weapon charge level
- Currently selected block type