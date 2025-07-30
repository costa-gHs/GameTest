# Copilot Instructions for SLIME: Tempest Trials (LÖVE2D Lua)

## Project Overview
- **Rogue-lite** game inspired by "That Time I Got Reincarnated as a Slime".
- Built on **LÖVE2D** (Lua), using a modular, ECS-based architecture.
- Features procedural sprite/world generation, AI advisor (Sábio/Raphael), and trait-based progression.

## Architecture & Key Components
- **Entry Points:**
  - `main.lua`: Launches either the main game (`game_main.lua`) or the sprite generator (`sprite_generator.lua`) based on CLI args.
  - `game_main.lua`: Integrates all core systems for the full game.
  - `sprite_generator.lua`: Standalone procedural sprite generator with UI and export features.
- **Core Systems (in `src/`):**
  - `core/ecs.lua`: Entity Component System (ECS) for modular game logic.
  - `core/eventbus.lua`: Decoupled event system for inter-module communication.
  - `core/rng.lua`: Deterministic RNG for reproducibility (Xorshift).
  - `core/app.lua`: Game state and main loop manager.
  - `core/save.lua`: JSON-based save/load for metaprogression.
  - `gameplay/`: Systems for predation, analysis, sage (AI advisor), skills, and slime controller.
  - `combat/`, `enemy_ai_system.lua`: Combat and AI logic.
  - `render/ui.lua`: UI rendering and management.
  - `world/gen.lua`: Procedural world/room/biome generation.

## Developer Workflows
- **Run the Game:**
  - Windows: Double-click `EXECUTAR_JOGO.bat` or `SLIME - Tempest Trials.vbs`.
  - Linux/Mac: Run `./executar_jogo.sh`.
  - CLI: `love .` (main game) or `love . --generator` (sprite generator).
- **Debugging:**
  - `F1`: Toggle debug info overlay.
  - `R`: Respawn enemies.
  - ECS and event logs available in real time.
- **Exporting Sprites:**
  - Use UI buttons or hotkeys in the sprite generator to export PNGs.

## Project Conventions & Patterns
- **ECS Pattern:**
  - Entities are IDs; components are pure data; systems process entities by component type.
  - Use `ECS:createEntity`, `ECS:addComponent`, and system registration patterns as in `ecs.lua`.
- **EventBus:**
  - Use `EventBus:on(event, callback)` for decoupled communication.
  - Events are queued and processed per frame; see `eventbus.lua` for custom events.
- **Deterministic RNG:**
  - Always use `RNG:setSeed(seed)` for reproducible runs (important for procedural content).
- **Settings/Presets:**
  - Sprite generator and game use settings tables; presets are deep-copied and can be saved/loaded.
- **UI/Controls:**
  - UI is managed by `UIManager` (see `sprite_generator.lua` and `render/ui.lua`).
  - Hotkeys and controls are mapped in `README.md` and code comments.

## Integration Points
- **Sprite Generator:**
  - Can be run standalone or as part of the main game.
  - Exports PNGs via `ExportManager`.
- **AI Advisor (Sábio/Raphael):**
  - Modular, with levels of advice and auto-analysis; see `gameplay/sage.lua`.
- **Procedural Generation:**
  - World and sprites are generated deterministically using seeds.

## File/Directory References
- `main.lua`, `game_main.lua`, `sprite_generator.lua`: Entry points.
- `src/core/`, `src/gameplay/`, `src/combat/`, `src/render/`, `src/world/`: Major systems.
- `README.md`: Full gameplay, controls, and architecture documentation.

## Tips for AI Agents
- Always check for settings, seeds, and system initialization order (see `love.load` in entry points).
- Use the event system for cross-module actions instead of direct calls.
- Follow ECS and modular patterns for new features.
- Reference `README.md` for gameplay logic, controls, and system overviews.
