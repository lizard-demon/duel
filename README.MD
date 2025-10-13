# source

**A high-performance, cross-platform game engine in under 1000 lines of Zig.**

`source` is a minimalist, high-performance game engine designed from the ground up for competitive games where precision, speed, and accessibility are non-negotiable. Our goal is to power a competitive shooter that runs flawlessly on everything from a 12-year-old Android phone to a top-tier gaming PC, all from a single, ultra-lean codebase.

## Core Philosophy

`source` is an exercise in radical simplicity. We believe that true performance comes from elegant design, not just brute force. By leveraging the power and safety of the Zig programming language, we aim to deliver a sub-1000-line engine that provides everything you need and nothing you don't.

Performance is Paramount: Every line of code is scrutinized for its performance implications. We target high frame rates and low input latency, even on re``source`-constrained hardware.

Physics You Can Trust: For competitive play, physics cannot be "good enough." They must be deterministic, tight, and responsive. `source` implements a custom physics system built for the demands of high-stakes shooters.

Maximum Portability: Write your game once. Deploy it everywhere. We are building a rendering and input pipeline that abstracts away platform differences without sacrificing performance.

Power Efficiency: By keeping the codebase small and avoiding unnecessary abstractions, `source` is designed to be incredibly power-efficient, ensuring longer play sessions on mobile devices.

## Key Features

Performance: High FPS on a massive range of devices.

Extreme Portability: Target desktops (Windows, macOS, Linux) and mobile (Android, iOS) with a unified codebase.

Tight Physics: A custom-built, deterministic physics engine designed for precision movement and hit detection.

Minimalist & Modern Codebase: Written in Zig for performance, safety, and maintainability. Clean, readable, and under 1000 lines of code.

Low Power Usage: Optimized for battery life on laptops and mobile devices.
