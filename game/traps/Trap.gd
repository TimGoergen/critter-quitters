## Trap.gd
## A player-placed trap that scans for enemies within its range and fires
## on a cooldown, dealing damage instantly on fire.
##
## Targeting model:
##   Each trap type has its own targeting priority:
##     SNAP_TRAP  — nearest enemy in range
##     ZAPPER     — farthest-along-path enemy in range (Phase 4)
##     FOGGER     — all enemies in range simultaneously (Phase 4)
##     GLUE_BOARD — passive slow; no projectile (Phase 4)
##
##   "Farthest along path" is determined by the enemy's path index —
##   higher index means closer to the exit, so it is the greater threat.
##
## Damage model:
##   Damage is applied instantly when the trap fires. The projectile that
##   follows is purely cosmetic — it travels to where the enemy was at
##   fire time and does nothing on arrival.
##
## Upgrade model:
##   Each trap instance tracks a star level (0–5) and a tier (0+). On each
##   upgrade the player chooses Damage, Range, or Fire Rate; that stat
##   improves and the star level advances by one. At star 5 the next
##   purchase is a tier-up: the tier increases, the star resets to 0, and
##   a dramatic variation is applied (placeholder until Phase 5).
##
## Usage: instantiate via Arena, call initialize(), set position, then
## add to the scene tree.

extends Node3D

const Grid       = preload("res://arena/Grid.gd")
const Projectile = preload("res://traps/Projectile.gd")


# ---------------------------------------------------------------------------
# Trap type
# ---------------------------------------------------------------------------

enum TrapType { SNAP_TRAP, ZAPPER, FOGGER, GLUE_BOARD }

## Per-type stat table. All numeric values are placeholders — tuned via playtesting.
##   damage   — HP removed from each target per shot
##   range    — circular detection radius in world units (1 unit = 1 cell)
##   cooldown — seconds between shots; 0.0 = passive (no shots fired)
##   cost     — Bug Bucks to place one trap of this type
##   color    — placeholder box colour (replaced by sprites in Phase 3)
const STATS := {
	TrapType.SNAP_TRAP:  { "damage": 3.375, "range": 5.6, "cooldown": 1.0, "cost": 25, "color": Color(0.40, 0.40, 0.80) },
	TrapType.ZAPPER:     { "damage": 56.25, "range": 9.6, "cooldown": 2.5, "cost": 60, "color": Color(0.90, 0.85, 0.20) },
	TrapType.FOGGER:     { "damage": 33.75, "range": 6.4, "cooldown": 2.0, "cost": 50, "color": Color(0.60, 0.90, 0.60) },
	TrapType.GLUE_BOARD: { "damage": 0.0,   "range": 4.8, "cooldown": 0.0, "cost": 35, "color": Color(0.80, 0.70, 0.30) },
}

## Fraction of the base stat added per normal upgrade. Marked as tuning values.
const UPGRADE_DAMAGE_FACTOR:    float = 0.25  # +25% of base damage per star
const UPGRADE_RANGE_FACTOR:     float = 0.10  # +10% of base range per star
const UPGRADE_FIRE_RATE_FACTOR: float = 0.08  # −8% of base cooldown per star (faster shots)


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the trap fires. Arena spawns a Projectile in response so
## the trap itself does not need a reference to the scene tree root.
signal fired(from_pos: Vector3, to_pos: Vector3, target: Node3D, damage: float)

## Emitted after any upgrade is applied. TrapUpgradePanel connects here to
## keep its display current without polling.
signal stats_changed


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _trap_type: TrapType       = TrapType.SNAP_TRAP
var _damage:   float           = 0.0
var _range:    float           = 0.0
var _cooldown: float           = 0.0
var _cooldown_remaining: float = 0.0
var _cost:     int             = 0

# Upgrade state.
var _tier: int = 0   # increments each time the trap tiers up
var _star: int = 0   # 0–5; resets to 0 on tier-up

# Base stats stored at initialize time so each upgrade step is a consistent
# fraction of the original value regardless of how many upgrades have been applied.
var _base_damage:   float = 0.0
var _base_range:    float = 0.0
var _base_cooldown: float = 0.0

# Direct reference to Arena._active_enemies. GDScript arrays are reference
# types, so this always reflects the live list without any extra bookkeeping.
var _active_enemies: Array = []


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Configures the trap for a given type and wires it to the active enemy list.
## Must be called by Arena before the node is added to the scene tree.
func initialize(trap_type: TrapType, active_enemies: Array) -> void:
	_trap_type      = trap_type
	_active_enemies = active_enemies

	var stats  = STATS[trap_type]
	_damage    = stats["damage"]
	_range     = stats["range"]
	_cooldown  = stats["cooldown"]
	_cost      = stats["cost"]

	# Store originals so each upgrade increment is a consistent fraction
	# of the starting value regardless of how many upgrades have been applied.
	_base_damage   = _damage
	_base_range    = _range
	_base_cooldown = _cooldown

	_spawn_visual(stats["color"])


# ---------------------------------------------------------------------------
# Upgrade — cost
# ---------------------------------------------------------------------------

## Cost in Bug Bucks to perform the next upgrade on this trap.
## Normal upgrades (star 0–4) use the target star level in the formula.
## Tier-up (star 5) is calculated as though the target star were 6,
## then multiplied by 1.2 to reflect the premium on tier transitions.
func get_upgrade_cost() -> int:
	if _star < 5:
		return int(_tier * _cost + (_star + 1) * _cost * 0.8)
	return int((_tier * _cost + 6.0 * _cost * 0.8) * 1.2)


# ---------------------------------------------------------------------------
# Upgrade — stat previews
# ---------------------------------------------------------------------------

## Damage this trap would have after one damage upgrade.
func get_damage_after_upgrade() -> float:
	return _damage + _base_damage * UPGRADE_DAMAGE_FACTOR

## Range this trap would have after one range upgrade.
func get_range_after_upgrade() -> float:
	return _range + _base_range * UPGRADE_RANGE_FACTOR

## Current fire rate in shots per second. Returns 0.0 for passive traps.
func get_shots_per_sec() -> float:
	return 1.0 / _cooldown if _cooldown > 0.0 else 0.0

## Fire rate (shots/sec) this trap would have after one fire rate upgrade.
func get_shots_per_sec_after_upgrade() -> float:
	var new_cooldown := maxf(_cooldown - _base_cooldown * UPGRADE_FIRE_RATE_FACTOR, 0.1)
	return 1.0 / new_cooldown


# ---------------------------------------------------------------------------
# Upgrade — apply
# ---------------------------------------------------------------------------

## Increases damage by 25% of base and advances the star level.
## Only call when star < 5.
func apply_damage_upgrade() -> void:
	_damage += _base_damage * UPGRADE_DAMAGE_FACTOR
	_advance_star()

## Increases range by 10% of base and advances the star level.
## Only call when star < 5.
func apply_range_upgrade() -> void:
	_range += _base_range * UPGRADE_RANGE_FACTOR
	_advance_star()

## Reduces cooldown by 8% of base (faster shots) and advances the star level.
## Cooldown is clamped to 0.1 s minimum to prevent instant-fire edge cases.
## Only call when star < 5.
func apply_fire_rate_upgrade() -> void:
	_cooldown = maxf(_cooldown - _base_cooldown * UPGRADE_FIRE_RATE_FACTOR, 0.1)
	_advance_star()

## Applies a tier-up: increments the tier and resets the star to 0.
## variation is 0, 1, or 2 — which dramatic option the player chose.
## Variation-specific stat changes are TODO until Phase 5 defines them per trap type.
func apply_tier_up(variation: int) -> void:
	_tier += 1
	_star  = 0
	# TODO Phase 5: apply dramatic stat change based on variation index.
	stats_changed.emit()


# ---------------------------------------------------------------------------
# Upgrade — accessors
# ---------------------------------------------------------------------------

func get_tier() -> int:
	return _tier

func get_star() -> int:
	return _star

func get_damage() -> float:
	return _damage

func get_range_radius() -> float:
	return _range

func get_cooldown() -> float:
	return _cooldown

## Returns true for traps that deal no direct damage and have no fire cycle
## (e.g. Glue Board). Fire Rate upgrade is not applicable to passive traps.
func is_passive() -> bool:
	return _base_cooldown == 0.0

func get_type_name() -> String:
	match _trap_type:
		TrapType.SNAP_TRAP:  return "Snap Trap"
		TrapType.ZAPPER:     return "Zapper"
		TrapType.FOGGER:     return "Fogger"
		TrapType.GLUE_BOARD: return "Glue Board"
	return "Unknown"

## Returns the Bug Bucks cost to place this trap.
func get_cost() -> int:
	return _cost


# ---------------------------------------------------------------------------
# Combat loop
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _cooldown <= 0.0:
		return   # passive trap type — no firing logic

	_cooldown_remaining -= delta
	if _cooldown_remaining > 0.0:
		return

	var target := _find_target()
	if target == null:
		return

	fired.emit(global_position, target.global_position, target, _damage)
	_cooldown_remaining = _cooldown


# ---------------------------------------------------------------------------
# Targeting
# ---------------------------------------------------------------------------

func _find_target() -> Node3D:
	match _trap_type:
		TrapType.SNAP_TRAP:
			return _nearest_in_range()
		TrapType.ZAPPER:
			return _farthest_in_range()
		_:
			return _nearest_in_range()


## Returns the enemy in range closest to this trap (used by Snap Trap).
func _nearest_in_range() -> Node3D:
	var best: Node3D = null
	var best_dist    := INF
	for enemy in _active_enemies:
		if not is_instance_valid(enemy):
			continue
		var dist := _xz_distance(enemy.global_position)
		if dist <= _range and dist < best_dist:
			best_dist = dist
			best      = enemy
	return best


## Returns the enemy in range farthest along the path to the exit
## (used by Zapper — highest path index = closest to exit = biggest threat).
func _farthest_in_range() -> Node3D:
	var best: Node3D = null
	var best_index   := -1
	for enemy in _active_enemies:
		if not is_instance_valid(enemy):
			continue
		if _xz_distance(enemy.global_position) <= _range:
			var idx: int = enemy.get_path_index()
			if idx > best_index:
				best_index = idx
				best       = enemy
	return best


## Returns the XZ-plane distance from this trap to a world position.
func _xz_distance(world_pos: Vector3) -> float:
	var dx := global_position.x - world_pos.x
	var dz := global_position.z - world_pos.z
	return sqrt(dx * dx + dz * dz)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Advances the star level by one (capped at 5) and notifies listeners.
func _advance_star() -> void:
	_star = mini(_star + 1, 5)
	stats_changed.emit()


## Creates the placeholder visual as a child MeshInstance3D.
## Replaced by a sprite node in Phase 3.
func _spawn_visual(color: Color) -> void:
	var mi   := MeshInstance3D.new()
	var box  := BoxMesh.new()
	box.size  = Vector3(Grid.CELL_SIZE * 1.9, Grid.CELL_SIZE * 0.5, Grid.CELL_SIZE * 1.9)
	mi.mesh   = box

	var mat           := StandardMaterial3D.new()
	mat.albedo_color   = color
	mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat

	add_child(mi)
