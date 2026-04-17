# CLAUDE.md — Game Subsystem

Extends the root CLAUDE.md. Rules here are additive.

---

## Project Structure

Scenes and scripts are co-located by feature. Each folder owns one system:

| Folder | Contents |
| :----- | :------- |
| `arena/` | Grid, pathfinding, arena evolution, blocking terrain |
| `traps/` | All trap types and their behaviour |
| `enemies/` | All pest types and their behaviour |
| `ui/` | HUD, store, context panels, The Truck hub |
| `core/` | Game state, wave manager, run manager, economy |
| `assets/` | Fonts, textures, audio |

Each feature folder may contain its own `CLAUDE.md` with subsystem-specific rules.

---

## Godot Conventions

- Scenes (`.tscn`) and their primary script (`.gd`) share the same name — `Arena.tscn` / `Arena.gd`
- One scene per major concept — do not combine unrelated systems into a single scene
- Node names use PascalCase — `GridCell`, `EnemySpawner`, `WaveManager`
- Use `@export` for any value that may need tuning — do not hardcode tunables
- Use `@onready` for all node references — never fetch nodes in the middle of logic
- Signals are declared at the top of every script, before variables
- Autoloads (singletons) are reserved for truly global state — `GameState`, `RunManager`. Do not overuse.

---

## Scene Ownership

Each scene is responsible for its own internal logic. Cross-scene communication
goes through signals or autoloads — never through direct node paths like
`get_node("../../something")`.

---

## Renderer Notes

This project uses the **Mobile renderer** targeting iOS, Android, and Web.

- Avoid shader features unsupported by mobile GL (complex lighting, screen-space effects)
- All 3D objects use billboard rendering — MeshInstance3D with a QuadMesh facing the camera
- Camera is fixed orthographic top-down — do not add camera controls beyond debug pan/zoom
