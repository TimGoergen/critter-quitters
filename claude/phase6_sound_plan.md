# Phase 6 — Sound: Implementation Plan

## Overview

All audio in the game routes through a single autoloaded singleton: `AudioManager`. This mirrors the `GameState` pattern already in the project. Every meaningful game event has a corresponding method on AudioManager; if no audio file is assigned to that slot, the method returns silently. Adding real audio files later requires no code changes — only asset assignment.

---

## Part 1 — Code Infrastructure

### Step 1: Audio Bus Layout

Open **Project > Audio** in the Godot editor and create three buses below Master:

| Bus | Purpose | Suggested effects |
|-----|---------|-------------------|
| `Music` | Background ambient loop | Compressor, low volume default (~60%) |
| `SFX` | All in-game sounds (traps, enemies) | Limiter |
| `UI` | Interface sounds | None — always audible |

Save the layout as the project default. Godot saves this to `project.godot`; no separate file needed.

### Step 2: Asset Folder Structure

Create these directories under `game/assets/audio/`:

```
game/assets/audio/
  music/
    bgm_arena_loop.ogg         ← background music (looping)
  sfx/
    traps/
      snap_fire.wav
      zapper_fire.wav
      fogger_fire.wav
      glue_apply.wav
    enemies/
      hit_snap.wav             ← hit sound varies by what trap hit the enemy
      hit_zapper.wav
      hit_fogger.wav
      hit_glue.wav
      death_small.wav          ← Ant, Gnat
      death_medium.wav         ← Cricket, Beetle
      death_large.wav          ← Cockroach
      death_rat.wav            ← Rat boss
      step_ant.wav
      step_gnat.wav
      step_cricket.wav
      step_beetle.wav
      step_cockroach.wav
      step_rat.wav
    ui/
      button.wav
      wave_start.wav
      wave_clear.wav
      run_end.wav
      bucks_earn.wav
      upgrade.wav
```

OGG is preferred for music (smaller file, Godot streams it). WAV is fine for short SFX (no decode overhead).

### Step 3: AudioManager Autoload

Create `game/core/AudioManager.gd`. Register it as an autoload in Project Settings under the name `AudioManager` (same pattern as `GameState`).

**Design decisions:**
- One `@export var` per named sound slot — files assigned in the Inspector, or `preload()`-ed directly when files are ready.
- Null guard on every play call — if the stream is not assigned, the method returns immediately. The game runs silently until assets are added.
- SFX pool of 8 `AudioStreamPlayer` nodes on the `SFX` bus to allow overlapping sounds (multiple enemies dying simultaneously).
- Footstep pool is separate (4 players) to allow independent volume tuning without affecting other SFX.
- Music uses a single player on the `Music` bus with `stream.loop = true` (set on the imported OGG resource).
- UI uses a pool of 3 players on the `UI` bus.

**Public interface AudioManager exposes:**

```gdscript
# Called by Trap._play_snap_animation(), _play_zapper_animation(), etc.
func play_trap_fire(trap_type: int) -> void

# Called by Enemy.take_damage() — trap_type tells us which hit sound to use.
func play_enemy_hit(enemy_type: int, trap_type: int) -> void

# Called by Enemy._die()
func play_enemy_death(enemy_type: int) -> void

# Called by Enemy._process() on walk-frame advance (rate-limited — max 1 per 0.1 s per enemy).
func play_enemy_footstep(enemy_type: int) -> void

# Called by HUD button handlers.
func play_ui(sound_name: String) -> void

# Called when GameState.run_started fires.
func start_music() -> void

# Called when GameState.run_ended fires.
func stop_music() -> void
```

**Footstep rate limiting:** `play_enemy_footstep` should accept the calling enemy node as a key and track the last-played time per enemy in a `Dictionary`. Skip if called within 0.1 s of the previous footstep for that enemy. This prevents the SFX pool from flooding when many enemies are on screen.

**Bug Bucks chime throttle:** `play_ui("bucks_earn")` should play at most once per 0.15 s regardless of how many `bug_bucks_changed` signals fire in rapid succession (fast enemy kills). Track `_last_bucks_chime_time` and skip if within the throttle window.

### Step 4: Wire Hooks into Existing Scripts

These are the exact call sites to add:

**`Enemy.gd`**

| Where | Call |
|-------|------|
| `take_damage()`, after reducing HP, before `_die()` check | `AudioManager.play_enemy_hit(_enemy_type, trap_type)` — requires adding `trap_type: int` param to `take_damage()` |
| `_die()`, before the tween | `AudioManager.play_enemy_death(_enemy_type)` |
| `_process()`, inside the walk-frame advance block (when `_path_index` increments) | `AudioManager.play_enemy_footstep(self, _enemy_type)` |

Note: `take_damage()` currently takes `amount` and `flash_color`. Add `trap_type: int = -1` as a third optional parameter so all existing call sites continue to work unchanged.

**`Trap.gd`**

| Where | Call |
|-------|------|
| `_play_snap_animation()`, at start | `AudioManager.play_trap_fire(TrapType.SNAP_TRAP)` |
| `_play_zapper_animation()`, at start | `AudioManager.play_trap_fire(TrapType.ZAPPER)` |
| `_play_fogger_animation()`, at start | `AudioManager.play_trap_fire(TrapType.FOGGER)` |
| `_update_glue_slow()`, when `closest != _slowed_enemy` and `closest != null` | `AudioManager.play_trap_fire(TrapType.GLUE_BOARD)` |

**`Arena.gd` (connects to GameState signals)**

Connect in `_ready()`:
```gdscript
GameState.run_started.connect(AudioManager.start_music)
GameState.run_ended.connect(func(): AudioManager.play_ui("run_end"); AudioManager.stop_music())
GameState.phase_changed.connect(_on_phase_changed_audio)
GameState.bug_bucks_changed.connect(func(_amt): AudioManager.play_ui("bucks_earn"))
```

In `_on_phase_changed_audio(new_phase)`:
- `Phase.WAVE` → `AudioManager.play_ui("wave_start")`
- `Phase.PLACING` (when `current_wave > 0`) → `AudioManager.play_ui("wave_clear")`

**`HUD.gd` — button press sounds**

Any button `pressed` signal handler that doesn't already have an obvious audio effect: call `AudioManager.play_ui("button")` at the top.

### Step 5: Volume Controls

Add mute/volume sliders for Music and SFX to the right panel in `HUD.gd`. These call `AudioServer.set_bus_volume_db()` on the named buses. Keep UI always audible (no volume control for the UI bus). Persist settings to `user://settings.cfg` using `ConfigFile` — read on startup, write on change.

---

## Part 2 — Pattern for Adding Audio Files

When a real audio file is ready to be added:

1. **Drop the file** into the correct subfolder under `game/assets/audio/`.
2. **Import settings** — for music OGG files: open the import dock, check **Loop** on. For SFX WAV files: defaults are fine.
3. **Assign the stream** — in `AudioManager.gd`, replace the `null` placeholder with a `preload("res://assets/audio/...")` for that slot. Alternatively, select the `AudioManager` node in the scene tree and assign via the Inspector export.

No changes to Enemy.gd, Trap.gd, Arena.gd, or HUD.gd are needed. The hook calls are already in place.

To test a single sound in isolation: call `AudioManager.play_trap_fire(0)` (or any other method) from the Godot remote debugger console while the game is running.

---

## Part 3 — Sound Inventory

Total assets required: **25**

### Background Music (1)

| Slot name | Description |
|-----------|-------------|
| `bgm_arena_loop` | 60–90 second ambient loop. Tone: understated, slightly quirky, pest control vibe. Think a lo-fi procedural score with occasional odd organic sounds. Should not compete with SFX. |

Suggested search terms: *"ambient game loop quirky"*, *"pest control comedy background"*, *"lo-fi procedural loop"*

### Trap Fire Sounds (4)

| Slot name | Trap | Character |
|-----------|------|-----------|
| `snap_fire` | Snap Trap | Sharp mechanical snap — a spring releasing. Short (< 0.3 s). |
| `zapper_fire` | Zapper | Electric zap/buzz with brief crackle. Medium length (0.4–0.8 s). |
| `fogger_fire` | Fogger | Pressurized hiss/spray burst. Short (0.3–0.5 s). |
| `glue_apply` | Glue Board | Soft wet squelch or sticky slap. Short (< 0.3 s). |

### Enemy Hit Sounds (4 — keyed by trap type, not enemy type)

Hit sound reflects what just hit the enemy, not who was hit. One sound per trap type.

| Slot name | Trap that hit | Character |
|-----------|---------------|-----------|
| `hit_snap` | Snap Trap | Thwack/crunch — solid impact. |
| `hit_zapper` | Zapper | Brief electric sting, slight sizzle. |
| `hit_fogger` | Fogger | Soft chemical impact, slightly muffled. |
| `hit_glue` | Glue Board | Muted thud with slight stickiness. |

### Enemy Death Sounds (4 — keyed by enemy tier)

| Slot name | Enemy type(s) | Character |
|-----------|--------------|-----------|
| `death_small` | Ant, Gnat | Light pop or crunch. Very short (< 0.2 s). |
| `death_medium` | Cricket, Beetle | Heavier crunch. Short (0.2–0.4 s). |
| `death_large` | Cockroach | Wet crunch. Satisfying but not gross. |
| `death_rat` | Rat (boss) | Heavy thud plus brief squeal or grunt. Distinct from others — should feel like a boss kill. |

### Enemy Footstep Sounds (6 — one per enemy type)

Each footstep is played on walk-frame advance, rate-limited to max 1 per 0.1 s per enemy. Files should be very short (< 0.1 s) with no tail — they will be triggered repeatedly.

| Slot name | Enemy | Character |
|-----------|-------|-----------|
| `step_ant` | Ant | Rapid light skitter — tiny tapping. |
| `step_gnat` | Gnat | Extremely light — faint wing-tap or near-silence. |
| `step_cricket` | Cricket | Chirpy skitter — slightly erratic feel. |
| `step_beetle` | Beetle | Heavier click-clack — hard shell on surface. |
| `step_cockroach` | Cockroach | Medium scrabbling — six-legged scramble. |
| `step_rat` | Rat | Padding thud — heavier than insects, slower. |

### UI Sounds (6)

| Slot name | Trigger | Character |
|-----------|---------|-----------|
| `button` | Any HUD button press | Generic tap/click. Neutral, clean. |
| `wave_start` | Wave begins (phase → WAVE) | Short announcement sting — something starting. |
| `wave_clear` | Wave ends (phase → PLACING, wave > 0) | Satisfying short chime or flourish. |
| `run_end` | Infestation maxed (INFESTED!) | Ominous low sting or failure sound. |
| `bucks_earn` | Bug Bucks increases (throttled to 1/150 ms) | Light coin chime — non-intrusive. |
| `upgrade` | Upgrade applied to trap | Confirmation ding or positive chime. |

---

## Implementation Order

1. Audio bus layout (editor-only, ~5 min)
2. `AudioManager.gd` with all export vars set to null and pool players wired (no audio files yet — game runs silently)
3. Hook calls added to Enemy.gd, Trap.gd, Arena.gd, HUD.gd
4. Volume controls added to HUD, settings persisted
5. Drop in audio files one category at a time; verify each in-game
