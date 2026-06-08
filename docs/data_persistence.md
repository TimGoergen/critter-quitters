# Critter Quitters — Data Persistence Reference

This document describes everything the game saves between sessions, how and when it is written, and how to add developer control over persistent values (upgrade tiers, service fees, etc.).

---

## Overview

The game persists two distinct categories of data to disk:

| File | Purpose | Autoload that owns it |
|---|---|---|
| `user://save.cfg` | Player progression (service fees, upgrade tiers) | `GameState` |
| `user://settings.cfg` | User preferences (audio, display) | `HUD` |

Both files use Godot's **ConfigFile** format — a human-readable INI-like structure. You can open and edit them manually in a text editor for debugging.

The `user://` path resolves to a platform-specific location. On Windows it is typically:

```
C:\Users\<username>\AppData\Roaming\Godot\app_userdata\Critter Quitters\
```

You can also open this folder from the Godot editor via **Project → Open User Data Folder**.

---

## Progression Save (`user://save.cfg`)

### What is saved

```ini
[meta]
service_fees = <int>

[upgrades]
reinforced_mechanisms = <0-10>
extended_range        = <0-10>
tuned_triggers        = <0-10>
wider_selection       = <0-10>
starting_capital      = <0-10>
hazard_insurance      = <0-10>
salvage_value         = <0-10>
bulk_discount         = <0-10>
field_experience      = <0-10>
show_me               = <0-10>
strengthen_defenses   = <0-10>
```

`service_fees` is the accumulated inter-run currency used to purchase permanent upgrades. Each upgrade key stores how many tiers the player has purchased (0 = not owned, 10 = maxed).

### When it is written

`GameState._save_persistent()` is called in exactly two places:

1. **End of a run** — inside `award_run_service_fees()`, after adding the earned fees to the balance.
2. **After an upgrade purchase** — inside `purchase_upgrade()`, after deducting the cost and incrementing the tier.

The file is **never written mid-run**. If the player force-quits during a run, that run's service fee earnings are lost (which is by design — runs must complete normally).

### When it is read

`GameState._load_persistent()` is called once from `_ready()` at startup. All values are loaded into in-memory variables (`service_fees`, `permanent_upgrades` dictionary) before any scene is shown. If the file does not exist (first launch), all values default to zero.

### How upgrades are applied to runs

At the start of each run, `_apply_permanent_upgrade_bonuses()` reads the `permanent_upgrades` dictionary and computes multipliers. These are applied to the run's starting state (e.g., `bug_bucks`, trap stats). The bonuses are additive per tier:

| Upgrade key | Effect per tier | Max (tier 10) |
|---|---|---|
| `reinforced_mechanisms` | +5% trap base damage | +50% |
| `extended_range` | +4% trap targeting radius | +40% |
| `tuned_triggers` | +4% fire rate | +40% |
| `wider_selection` | +1 card offered in selection | +4 offered |
| `starting_capital` | +25 Bug Bucks per run | +250 |
| `hazard_insurance` | +5% infestation threshold | +50% |
| `salvage_value` | +3% refund on sell | +30% |
| `bulk_discount` | +3% upgrade cost reduction | capped at 80% |
| `field_experience` | +10% XP per kill | +100% |
| `show_me` | +5% Bug Bucks per kill | +50% |
| `strengthen_defenses` | −4% infestation damage | −40% |

---

## Settings Save (`user://settings.cfg`)

### What is saved

```ini
[audio]
music = <0.0-1.0>
sfx   = <0.0-1.0>

[display]
grid_lines_overview = <true/false>
grid_lines_zoomed   = <true/false>
```

### When it is written

Settings are saved immediately whenever the player changes a value — slider moves or toggle changes trigger a write. There is no "apply" button.

### When it is read

`HUD` loads settings in its `_ready()`. The Arena scene reads grid line preferences at startup and listens for in-session changes via signal.

### Default values (file absent)

| Setting | Default |
|---|---|
| Music volume | 1.0 (100%) |
| SFX volume | 1.0 (100%) |
| Grid lines — overview | false |
| Grid lines — zoomed | true |

Settings are intentionally separate from progression so a player can reset their run history without losing audio preferences (and vice versa).

---

## Data that is NOT persisted (run-scoped)

The following exists only in memory for the duration of a single run and is discarded when the run ends or the game is restarted:

- `bug_bucks` — current in-run currency
- `infestation_level` — current run threat progress
- `current_wave` — wave counter
- `current_player_level` / `current_xp` — mid-run level progression
- All campaign buff state (global damage, range, fire rate, crit bonuses)
- Placed trap and boost counts
- Unlocked trap and boost types for the current run

---

## Adding Developer Control Over Persistent Values

There is no in-game cheat/debug panel for persistence values. The approaches below are ordered by effort and invasiveness.

### Option A — Edit the save file directly (no code required)

The simplest approach for one-off testing. Close the game, open the file, edit it, relaunch.

**File location:**
```
C:\Users\<username>\AppData\Roaming\Godot\app_userdata\Critter Quitters\save.cfg
```

Set any upgrade tier to a value between 0 and 10, or set `service_fees` to any integer. The game will read these values on next startup with no validation — there are no checksums.

**Risk:** Setting a tier above 10 or a negative fee balance will not crash the game but may produce unexpected bonus values since the upgrade math assumes 0–10.

### Option B — A debug autoload with keybinds (recommended for ongoing development)

Add a new autoload `DebugTools.gd` that is only active in non-export builds. It listens for key combinations and manipulates `GameState` directly.

**`core/DebugTools.gd`:**

```gdscript
extends Node

# Only active in debug builds — export builds strip this automatically via OS.is_debug_build()
func _ready() -> void:
    if not OS.is_debug_build():
        queue_free()
        return
    set_process_input(true)

func _input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed:
        return

    # Ctrl+Shift+M — add 100 service fees
    if event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_M:
        GameState.service_fees += 100
        GameState._save_persistent()
        print("[Debug] service_fees set to %d" % GameState.service_fees)

    # Ctrl+Shift+U — max all upgrades
    if event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_U:
        _max_all_upgrades()

    # Ctrl+Shift+R — reset all progression
    if event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_R:
        _reset_progression()

func _max_all_upgrades() -> void:
    for key in GameState.permanent_upgrades:
        GameState.permanent_upgrades[key] = 10
    GameState._save_persistent()
    print("[Debug] All upgrades maxed.")

func _reset_progression() -> void:
    GameState.service_fees = 0
    for key in GameState.permanent_upgrades:
        GameState.permanent_upgrades[key] = 0
    GameState._save_persistent()
    print("[Debug] Progression reset.")
```

Register it in `project.godot` under AutoLoad. Because it calls `queue_free()` on release builds, it compiles away without needing conditional exports.

Note: `GameState._save_persistent()` is currently a private method (prefixed with `_`). You will need to either make it public (rename to `save_persistent()`) or expose a thin wrapper method `func debug_save() -> void: _save_persistent()` — both are safe changes.

### Option C — An in-game debug screen (for systematic testing)

If you need to test specific upgrade configurations repeatedly, a dedicated debug scene is more ergonomic than keybinds. Add a scene (e.g., `ui/DebugScreen.tscn`) that shows sliders or spinboxes bound directly to `GameState.service_fees` and each entry in `GameState.permanent_upgrades`. Gate it behind a dev-only menu option or the same `OS.is_debug_build()` guard.

This is the right choice when you are doing upgrade balance tuning, since it lets you set arbitrary tier combinations and immediately start a run without closing the game.

### Option D — GDScript REPL via the Godot debugger

While the game is running in the editor, use the **Remote** tab in the Scene tree or the **Debugger → Expression Evaluator** to run one-off expressions:

```gdscript
GameState.service_fees = 500
GameState.permanent_upgrades["starting_capital"] = 5
GameState._save_persistent()
```

This has no persistence across editor sessions and requires the game to be running, but it is instant and requires no code changes.

---

## How Settings and Progression Interact

The two save files are independent. The only point of coupling is that **audio settings take effect immediately at runtime** — the HUD applies loaded values to `AudioManager` on startup, so audio state is always consistent with the saved preference regardless of what progression state is loaded.

There is no mechanism for settings to affect upgrade costs, unlock conditions, or run parameters. Settings are purely cosmetic and quality-of-life preferences.

---

## Known Gaps in the Current System

These are not bugs but are relevant if you plan to extend persistence:

- **No cloud sync** — saves are local only; no cross-device support.
- **No save slots** — one progression file per installation.
- **No mid-run save** — force-quitting during a run loses that run's service fees.
- **No migration system** — if an upgrade key is renamed or a new one added, existing saves will simply default the missing key to 0 (which is safe but silent).
- **No validation** — corrupted or hand-edited values outside the expected range are accepted without warning.
- **No statistics** — runs played, best wave, total kills, etc. are not tracked.
