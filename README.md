# Zig Particles Demo

Real-time particle simulation written in Zig.
Implements spatial partitioning (uniform grid).
Uses Raylib for rendering.
Supports up to 20k particles.

Project done as a effect of weekend home hackathon.
Main goal was to learn how to optimize simulation of particle movement.
Code is done basicaly in single file, to check how readable it would be this way.

![Screenshot](https://github.com/ppgertos/ZigParticlesDemo/releases/download/README_Image/zigHeartDemo-2026-03-03.07-50.gif)

## Getting Started

### Requirements

- **Zig:** 0.14.1 or later (tested with 0.15.2)
- **Raylib:** Automatically fetched during build
- **System:** Linux/Windows/macOS with graphics support

### Build & Run

1. Clone the repository:
   ```sh
   git clone https://github.com/ppgertos/ZigParticlesDemo.git
   cd ZigParticlesDemo
   ```
2. Build and run the project:
   ```sh
   zig build run
   ```

## Keyboard Shortcuts

<kbd>`</kbd> - No shape\
<kbd>1</kbd> - Heart shape\
<kbd>2</kbd> - Flower shape\
<kbd>3</kbd> - Lissajous shape\
<kbd>4</kbd> - Circle shape\
<kbd>F</kbd> - Toggle FPS counter\
<kbd>S</kbd> - Toggle shape outline\
<kbd>G</kbd> - Toggle grid\
<kbd>Esc</kbd> - Exit                 

## Configuration

- *agentRadius* (type: float, default: 0.001) 
 Influences distance required to trigger collision.

- *attractionFactor* (type: float, default: 100) 
 How much particles are attracted to target shape.

- *collisionPenalty* (type: float, default: 0.0001) 
 How much speed is reduced during collision.

- *epsilonAtZero* (type: float, default: 1e-6) 
 Value used to estimate value of zero.

- *finalShape* (type: enum Shape, default: Heart)
 Used to select target shape of particles.
 Possible values are:

 | Value     | Result                      |
 |-----------|-----------------------------|
 | Random    | Particles placed randomly   |
 | Heart     | Heart shape                 | 
 | Flower    | Rose curve k=7 n=5          |
 | Lissajous | Lissajous curve k=7 j=5     |
 | Circle    | Circle shape                |
    
- *maxAgents* (type: unsigned, default: 10000) 
 Number of particles - the bigger the more memory and CPU time consuming.

- *randSeed* (type: unsigned, default: 0xDEADBEEF) 
 Value that is seed of random number generator.

- *regionsNumberX* (type: unsigned, default: 131) 
 How many vertical spatial divisions should be done.

- *regionsNumberY* (type: unsigned, default: 70) 
 How many horizontal spatial divisions should be done.

- *screenHeight* (type: signed) and *screenWidth* (type: signed) 
 Overwriting size of a window. By default window size is set to screen size.

- *showFps* (type: bool, default: 0) 
 Shows FPS counter in upper left corner.

- *showGrid* (type: bool, default: 0) 
 Shows spatial divisions.

- *showShape* (type: bool, default: 0) 
 Shows red outline of selected target shape.

- *frictionFactor* (type: float, default: 125) 
 Makes movement of particles harder.

- *speedLimit* (type: float, default: 200) 
 Clamps speed of particles to given value.

## Code Description

The code simulates particle(agent) movement using Zig, focusing on performance and readability.
Logic is contained in a single file.

The main simulation logic resides in `src/main.zig`.
This file defines the particle (agent) structures,
simulation constants, and the main loop for updating and rendering particle positions.
It handles initialization, configuration loading, region-based spatial partitioning,
agent movement, collision detection, and rendering using Raylib.

The code is organized to keep most logic in a single file for clarity and experimentation.

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## Further goal

For now, project will get to more passive development. 
I will focus more on further optimisations, and refactor.

## License

[MIT](LICENSE)
