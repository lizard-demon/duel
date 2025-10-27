# Unified Input System

A clean, minimal, and elegant input system that seamlessly handles both desktop and mobile input for the bhop game.

## Architecture

The new input system consists of three main components:

### 1. `src/lib/input.zig` - Core Input System
- **InputState**: Clean state structure containing all input data
- **Input**: Main input processor that unifies desktop and mobile input
- **TouchInput**: Specialized touch input handler for mobile devices

### 2. `src/lib/touch_ui.zig` - Touch UI Rendering
- **TouchUI**: Renders touch controls with elegant fade-in/fade-out
- Automatically shows controls when touch input is detected
- Minimal visual interference with clean, modern design

### 3. Integration Points
- **Player**: Updated to use unified input system
- **Render**: Clean touch UI integration
- **Main**: Simple initialization and update loop

## Features

### Desktop Input
- **WASD**: Movement
- **Mouse**: Look around (with mouse lock support)
- **Space**: Jump
- **Shift**: Crouch
- **Z/X**: Break/Place blocks
- **Q/E**: Change block colors
- **R**: Pick block color
- **Escape**: Unlock mouse

### Mobile Touch Input
- **Movement Joystick** (bottom-left): Virtual analog stick for WASD movement
- **Jump Button** (bottom-right): Large, responsive jump button
- **Crouch Button** (left side): Hold to crouch
- **Look Area** (right side): Touch and drag to look around
- **Auto-fade**: Controls appear on touch and fade out when not in use

### Advanced Features
- **Autostrafe**: Automatic strafing during bhop jumps when turning
- **Hybrid Input**: Desktop and mobile input work simultaneously
- **Smooth Transitions**: Elegant fade animations for touch controls
- **Minimal Overhead**: Zero performance impact when not using touch

## Code Quality

The new system maintains the minimalist aesthetic of the original codebase:

- **Clean APIs**: Simple, intuitive function signatures
- **Unified State**: Single source of truth for all input
- **Zero Duplication**: No redundant input handling code
- **Elegant Integration**: Seamless with existing player systems

## Usage

The system is completely transparent to existing code. The player update loop automatically handles both input types:

```zig
// In player update loop
player.input.update(&player.io);  // Process all input
const input_state = &player.input.state;  // Access unified state

// Touch UI updates automatically
touch_ui.update(&player.input, dt);
touch_ui.render(&player.input);
```

## Touch Control Layout

```
┌─────────────────────────────────────────┐
│                                    LOOK │
│  [C]                              AREA  │
│                                         │
│                                         │
│  [M]                               [J]  │
└─────────────────────────────────────────┘

[M] = Movement Joystick
[J] = Jump Button  
[C] = Crouch Button
LOOK AREA = Touch and drag to look around
```

The result is a perfectly unified input system that preserves the game's minimalist elegance while adding comprehensive mobile support.