# Claude Code — Project Standards

These rules apply to all code written in this project. Follow them consistently
across every file, feature, and refactor. Readability and maintainability are
the top priorities — this codebase is read far more often than it is written.

This project uses **Godot 4** and **GDScript**. All conventions follow the
[GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)
unless otherwise noted.

---

## Naming Conventions

- **Variables and functions**: snake_case → `player_health`, `calculate_damage`
- **Classes and types**: PascalCase → `EnemySpawner`, `GameState`
- **Constants**: SCREAMING_SNAKE_CASE → `MAX_ENEMIES`, `BASE_MOVE_SPEED`
- **Booleans**: prefix with `is_`, `has_`, or `can_` → `is_alive`, `has_shield`, `can_jump`
- **Signals**: snake_case, past tense → `enemy_died`, `wave_completed`, `trap_placed`
- **Enums**: PascalCase name, SCREAMING_SNAKE_CASE values:
  ```
  enum PestType { ANT, CRICKET, BEETLE, COCKROACH, RAT }
  ```
- **Collections**: plural nouns → `enemies`, `active_projectiles`, `spawn_points`
- **No abbreviations** unless universally understood — `pos` is fine, `plyr` is not
- **If a variable needs a comment to explain what it holds, rename it instead**

---

## Function Design

- Each function does **exactly one thing** — if you need "and" to describe it, split it
- Keep functions **under 30 lines**; extract named helpers if they grow beyond that
- Name functions as **verb phrases** that describe what they do → `spawn_enemy`, not `enemy`
- **Prefer early returns** over deeply nested conditionals
- **No side effects** in functions whose names don't imply them
- Parameters should read naturally: `deal_damage(target, amount)` not `deal_damage(amount, target)`
- If a function takes more than 3–4 parameters, group them into a typed Dictionary or a dedicated class/resource

```
# Prefer this:
func spawn_enemy(config: EnemyConfig) -> Enemy:

# Over this:
func spawn_enemy(type: int, x: float, y: float, health: float) -> Enemy:
```

---

## File & Node Structure

- **One class or major concept per file**
- **Group related files in feature folders** → `/enemies`, `/ui`, `/audio`, `/traps`
- **Keep files under 300 lines** — split into smaller scripts when they grow beyond that
- File names should match their primary class → `EnemySpawner.gd` defines `EnemySpawner`
- Use Godot's node hierarchy intentionally — scene structure should reflect logical ownership
- Circular dependencies are never acceptable — restructure or use signals instead

---

## Signals

Signals are the preferred way to communicate between decoupled nodes. Use them
instead of direct node references wherever the sender should not need to know
about the receiver.

- Declare signals at the top of the script, before variables
- Signal names are past tense and describe what just happened: `pest_reached_exit`, `trap_sold`
- Connect signals in the parent or a dedicated manager — not inside the emitting node
- Do not use signals for communication within a single tightly coupled class

---

## Comments

- Write comments that explain **WHY, not WHAT** — the code already shows what it does
- Flag non-obvious decisions:
  ```
  # Using object pool here — instantiating during gameplay causes GC spikes on mobile
  ```
- **No commented-out code** — use git history to recover old code
- **No redundant comments** that restate the code:
  ```
  # BAD: increment the player score by 1
  player_score += 1

  # GOOD: no comment needed — the code is self-explanatory
  player_score += 1
  ```
- TODOs must include what is needed and why:
  ```
  # TODO: replace linear search with spatial hash once enemy count exceeds ~50
  ```

---

## Constants & Magic Numbers

- **No magic numbers** — extract to named constants
- Include units in the name where relevant:
  ```
  const RESPAWN_DELAY_SEC: float = 3.0
  const MAX_PROJECTILES_PER_FRAME: int = 5
  const GRID_CELL_SIZE_PX: int = 44
  ```
- Group related constants in a clearly named class or as top-of-file const blocks:
  ```
  const MAX_ACTIVE_ENEMIES: int = 40
  const ENEMY_SPAWN_INTERVAL_SEC: float = 0.8
  const ENEMY_DESPAWN_DISTANCE_PX: float = 1200.0
  ```

---

## Code Structure & Formatting

- **Maximum nesting depth: 3 levels** — extract to a named function if deeper
- Blank lines between logical sections inside a function; keep related lines together
- Always use explicit types on variables and function signatures where practical:
  ```
  var health: int = 100
  func take_damage(amount: int) -> void:
  ```
- Destructure or alias early to avoid repeated property chains:
  ```
  # Prefer:
  var pos: Vector2 = enemy.global_position

  # Over:
  enemy.global_position ... enemy.global_position
  ```
- Use `@export` for values that should be tunable in the Godot editor
- Use `@onready` for node references rather than fetching them mid-function

---

## What to Avoid

- **Single-letter variable names** even for short loop indices — use `index` or `enemy_index`
- **Clever one-liners** that sacrifice readability for brevity
- **Deep nested `if` chains** — use early returns or extract to helpers
- **Boolean parameters** that flip function behavior — use two named functions instead:
  ```
  # BAD:
  spawn_enemy(true)

  # GOOD:
  spawn_elite_enemy()
  ```
- **Implicit type coercion** — be explicit about types and conversions
- **Mutating function arguments** — treat parameters as read-only unless the name implies mutation
- **Direct node path strings** like `get_node("../../UI/HUD")` in logic code — assign via `@export` or `@onready` instead

---

## Self-Review Checklist

Before considering any implementation complete, verify:

- [ ] Every function name describes what it does as a verb phrase
- [ ] No function exceeds 30 lines
- [ ] No magic numbers remain in logic — all extracted to named constants
- [ ] No abbreviations that would confuse a new developer
- [ ] Comments explain why, not what
- [ ] No commented-out code
- [ ] Nesting depth is 3 or fewer levels
- [ ] File is under 300 lines (split if not)
- [ ] Signals used for cross-node communication rather than direct references
- [ ] Types declared on all variables and function signatures

---

## Work Process

These rules govern how Claude approaches work on this project in every session.

**GDD maintenance** — The GDD (`docs/critter_quitters_gdd.md`) is a live document.
Update it whenever work changes, adds, or removes a design decision, mechanic, or system.
Do not wait to be asked — keep it current as implementation evolves.

**Feature branches** — All work must be done on a feature branch, never directly on `main`.
At the start of every session, check the active branch. If the working branch is `main`,
stop and ask which feature branch to use or create before writing any code.

**Game balance** — For any numeric value that affects gameplay (damage, speed, cost, cooldowns,
wave sizes, infestation amounts, etc.), propose a specific value with a brief rationale.
Respect any existing playtesting notes — if a proposed value conflicts with a recorded
playtesting observation, flag the conflict and ask before proceeding.

**Scope** — Before expanding work beyond the stated task (touching additional files, refactoring
adjacent code, adding unrequested features), flag what you noticed and ask whether to include it.

---

## Folder-Level CLAUDE.md Files

Subsystem folders may contain their own `CLAUDE.md` with rules specific to that
module (e.g., performance constraints, required base classes, architectural
patterns). Those rules are **additive** — they extend, not replace, this file.
When working in a subfolder, honor both this file and any local `CLAUDE.md`.
