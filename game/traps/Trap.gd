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
##   Each trap instance tracks three independent upgrade levels — one per
##   stat (Damage, Range, Fire Rate). Each stat can be upgraded up to
##   MAX_UPGRADE_LEVEL (3) times. Costs per level are defined in UPGRADE_COSTS.
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
	TrapType.FOGGER:     { "damage": 8.0,   "range": 6.4, "cooldown": 2.2, "cost": 50, "color": Color(0.60, 0.90, 0.60) },
	TrapType.GLUE_BOARD: { "damage": 0.0,   "range": 4.8, "cooldown": 0.0, "cost": 35, "color": Color(0.80, 0.70, 0.30) },
}

## Each stat can be upgraded this many times independently.
const MAX_UPGRADE_LEVEL: int = 3

## Stat increment per upgrade level, as a fraction of the base value.
const UPGRADE_DAMAGE_FACTOR:    float = 0.25  # +25% of base damage per level
const UPGRADE_RANGE_FACTOR:     float = 0.10  # +10% of base range per level
const UPGRADE_FIRE_RATE_FACTOR: float = 0.08  # −8% of base cooldown per level (faster shots)

## Bug Bucks cost for each upgrade level per trap type.
## Index 0 = first upgrade, 1 = second, 2 = third.
## All values are tuning placeholders — finalize via playtesting.
const UPGRADE_COSTS := {
	TrapType.SNAP_TRAP:  [20, 30, 50],
	TrapType.ZAPPER:     [50, 75, 120],
	TrapType.FOGGER:     [40, 60, 100],
	TrapType.GLUE_BOARD: [30, 45, 70],
}


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when a point-target trap fires (Snap Trap, Zapper). Arena spawns
## a Projectile in response so the trap does not need a scene tree reference.
signal fired(from_pos: Vector3, to_pos: Vector3, target: Node3D, damage: float, trap_type: TrapType)

## Emitted once per Fogger firing cycle (not per enemy). Arena spawns a single
## FogCloud covering the full range — one cloud regardless of how many enemies
## were hit. Damage is applied directly in _fire_fogger(); this signal is visual only.
signal aoe_fired(from_pos: Vector3, aoe_range: float)

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

# Upgrade state — each stat tracks its own level independently (0–MAX_UPGRADE_LEVEL).
var _damage_level: int = 0
var _range_level:  int = 0
var _rate_level:   int = 0   # always stays 0 for passive traps

# Set to true once the full-upgrade bonus has been applied, so it only fires once.
var _bonus_applied: bool = false

# Base stats stored at initialize time so each upgrade step is a consistent
# fraction of the original value regardless of how many upgrades have been applied.
var _base_damage:   float = 0.0
var _base_range:    float = 0.0
var _base_cooldown: float = 0.0

# Direct reference to Arena._active_enemies. GDScript arrays are reference
# types, so this always reflects the live list without any extra bookkeeping.
var _active_enemies: Array = []

# Enemies currently inside this Glue Board's range. Used to track who enters
# and leaves so we can call add/remove_slow_source exactly once per transition.
var _slowed_enemies: Array[Node3D] = []


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

## Bug Bucks cost for the next upgrade to each stat. Returns 0 when already maxed.
func get_damage_upgrade_cost() -> int:
	if _damage_level >= MAX_UPGRADE_LEVEL:
		return 0
	return UPGRADE_COSTS[_trap_type][_damage_level]

func get_range_upgrade_cost() -> int:
	if _range_level >= MAX_UPGRADE_LEVEL:
		return 0
	return UPGRADE_COSTS[_trap_type][_range_level]

func get_rate_upgrade_cost() -> int:
	if _rate_level >= MAX_UPGRADE_LEVEL or _base_cooldown == 0.0:
		return 0
	return UPGRADE_COSTS[_trap_type][_rate_level]


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

## Increases damage by 25% of base. Only call when not maxed.
func apply_damage_upgrade() -> void:
	_damage += _base_damage * UPGRADE_DAMAGE_FACTOR
	_damage_level += 1
	_check_full_upgrade_bonus()
	stats_changed.emit()

## Increases range by 10% of base. Only call when not maxed.
func apply_range_upgrade() -> void:
	_range += _base_range * UPGRADE_RANGE_FACTOR
	_range_level += 1
	_check_full_upgrade_bonus()
	stats_changed.emit()

## Reduces cooldown by 8% of base (faster shots). Only call when not maxed.
## Cooldown is clamped to 0.1 s minimum to prevent instant-fire edge cases.
func apply_fire_rate_upgrade() -> void:
	_cooldown = maxf(_cooldown - _base_cooldown * UPGRADE_FIRE_RATE_FACTOR, 0.1)
	_rate_level += 1
	_check_full_upgrade_bonus()
	stats_changed.emit()


# ---------------------------------------------------------------------------
# Upgrade — accessors
# ---------------------------------------------------------------------------

func get_damage_level() -> int:
	return _damage_level

func get_range_level() -> int:
	return _range_level

func get_rate_level() -> int:
	return _rate_level

func is_damage_maxed() -> bool:
	return _damage_level >= MAX_UPGRADE_LEVEL

func is_range_maxed() -> bool:
	return _range_level >= MAX_UPGRADE_LEVEL

func is_rate_maxed() -> bool:
	return _rate_level >= MAX_UPGRADE_LEVEL

## True when every upgradeable stat is at MAX_UPGRADE_LEVEL.
## Passive traps (no fire rate) are fully upgraded after 6 total upgrades;
## active traps require all 9.
func is_fully_upgraded() -> bool:
	if _base_cooldown == 0.0:
		return is_damage_maxed() and is_range_maxed()
	return is_damage_maxed() and is_range_maxed() and is_rate_maxed()

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
	if _trap_type == TrapType.GLUE_BOARD:
		_update_glue_slow()
		return

	_cooldown_remaining -= delta
	if _cooldown_remaining > 0.0:
		return

	var did_fire := false
	if _trap_type == TrapType.FOGGER:
		did_fire = _fire_fogger()
		if did_fire:
			aoe_fired.emit(global_position, _range)
	else:
		var target := _find_target()
		if target != null:
			fired.emit(global_position, target.global_position, target, _damage, _trap_type)
			did_fire = true

	if did_fire:
		_cooldown_remaining = _cooldown


func _exit_tree() -> void:
	# Release any slow sources this trap was holding so enemies return to
	# normal speed the moment the trap is sold or overwritten.
	for enemy in _slowed_enemies:
		if is_instance_valid(enemy):
			enemy.remove_slow_source()
	_slowed_enemies.clear()


# ---------------------------------------------------------------------------
# Targeting
# ---------------------------------------------------------------------------

func _find_target() -> Node3D:
	match _trap_type:
		TrapType.SNAP_TRAP:
			return _nearest_in_range()
		TrapType.ZAPPER:
			return _farthest_in_range()
	return null


## Damages every enemy currently in range. Returns true if at least one was hit.
## Damage is applied here rather than via a projectile — the cloud visual is
## spawned once by the caller; individual per-enemy projectiles are not used.
func _fire_fogger() -> bool:
	var any_hit := false
	for enemy in _active_enemies:
		if not is_instance_valid(enemy):
			continue
		if _xz_distance(enemy.global_position) <= _range:
			enemy.take_damage(_damage)
			any_hit = true
	return any_hit


## Applies or removes the slow source on each enemy as they cross the range boundary.
func _update_glue_slow() -> void:
	# Remove entries for enemies that have died or despawned.
	var i := _slowed_enemies.size() - 1
	while i >= 0:
		if not is_instance_valid(_slowed_enemies[i]):
			_slowed_enemies.remove_at(i)
		i -= 1

	for enemy in _active_enemies:
		if not is_instance_valid(enemy):
			continue
		var in_range:   bool = _xz_distance(enemy.global_position) <= _range
		var is_tracked: bool = enemy in _slowed_enemies
		if in_range and not is_tracked:
			_slowed_enemies.append(enemy)
			enemy.add_slow_source()
		elif not in_range and is_tracked:
			_slowed_enemies.erase(enemy)
			enemy.remove_slow_source()


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

## Called after each upgrade. If all stats are now maxed and the bonus has not
## yet been applied, boosts every stat by 10% as a reward for full investment.
## Fire rate boost reduces cooldown so shots-per-second increases by ~11%.
func _check_full_upgrade_bonus() -> void:
	if _bonus_applied or not is_fully_upgraded():
		return
	_damage  *= 1.1
	_range   *= 1.1
	if _base_cooldown > 0.0:
		_cooldown = maxf(_cooldown / 1.1, 0.1)
	_bonus_applied = true


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
