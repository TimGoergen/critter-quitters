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
##   color    — placeholder box colour (replaced by ASCII billboard in Phase 3)
const STATS := {
	TrapType.SNAP_TRAP:  { "damage": 5.0,  "range": 3.5, "cooldown": 0.5, "color": Color(0.40, 0.40, 0.80) },
	TrapType.ZAPPER:     { "damage": 25.0, "range": 6.0, "cooldown": 2.5, "color": Color(0.90, 0.85, 0.20) },
	TrapType.FOGGER:     { "damage": 15.0, "range": 4.0, "cooldown": 2.0, "color": Color(0.60, 0.90, 0.60) },
	TrapType.GLUE_BOARD: { "damage": 0.0,  "range": 3.0, "cooldown": 0.0, "color": Color(0.80, 0.70, 0.30) },
}


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the trap fires. Arena spawns a Projectile in response so
## the trap itself does not need a reference to the scene tree root.
## target and damage are forwarded to the Projectile so damage is applied
## on impact rather than instantly at fire time.
signal fired(from_pos: Vector3, to_pos: Vector3, target: Node3D, damage: float)


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _trap_type: TrapType = TrapType.SNAP_TRAP
var _damage: float       = 0.0
var _range: float        = 0.0
var _cooldown: float     = 0.0
var _cooldown_remaining: float = 0.0

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

	_spawn_visual(stats["color"])


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


## Returns the enemy in range that is farthest along the path to the exit
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

## Creates the placeholder visual as a child MeshInstance3D.
## Replaced by an ASCII billboard node in Phase 3.
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
