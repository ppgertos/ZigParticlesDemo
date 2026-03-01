# Zig Particle Demo

Project done as a effect of weekend home hackathon.
Main goal was to learn how to optimize simulation of particle movement.
Code is done basicaly in single file, to check how readable it would be this way.

![Screenshot]()

## Getting Started

1. Clone the repository:
   ```sh
   git clone <repo-url>
   cd ZigParticleDemo
   ```
2. Build and run the project:
   ```sh
   zig build
   ```

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
