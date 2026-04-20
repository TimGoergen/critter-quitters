## Enemy.gd
## A pest that follows the calculated path from entrance to exit.
##
## Movement model:
##   The enemy tracks two cells at all times:
##     _current_cell — the last cell centre the enemy arrived at
##     _target_cell  — the next cell centre it is moving toward
##
##   Movement is always a straight line between adjacent cell centres.
##
## Rerouting model:
##   Arena calls update_path() with a fresh A* result from _current_cell
##   to the exit whenever the grid changes. The enemy redirects immediately
##   to the new optimal path without backtracking.
##
## Waddle model:
##   The visual mesh is translated perpendicular to the direction of travel
##   using a sin() oscillation, producing a visible side-to-side sway.
##
## HP and death:
##   take_damage() reduces current HP. On reaching zero, _die() plays a
##   brief white flash and then frees the node. Movement stops immediately
##   on death so the tween plays in place.
##
## Usage: instantiate via Arena, then call initialize() before the node
## is added to the scene tree.

extends Node3D

const Grid = preload("res://arena/Grid.gd")

const ANT_FRAMES: Array[Texture2D] = [
	preload("res://assets/ant_walk_1.svg"),
	preload("res://assets/ant_walk_2.svg"),
	preload("res://assets/ant_walk_3.svg"),
	preload("res://assets/ant_walk_4.svg"),
]


# ---------------------------------------------------------------------------
# Enemy type
# ---------------------------------------------------------------------------

enum EnemyType { ANT, CRICKET, BEETLE, COCKROACH, RAT }

## Per-type stat table. All numeric values are placeholders — tuned via playtesting.
##   hp            — starting (and maximum) hit points
##   speed         — movement speed in cells per second
##   infestation   — Infestation Level increase when this pest reaches the exit
##   color         — placeholder cylinder colour (replaced by ASCII billboard in Phase 3)
const STATS := {
	EnemyType.ANT:       { "hp": 10,  "speed": 3.0, "infestation": 1,  "bounty": 2,  "color": Color(0.85, 0.35, 0.15) },
	EnemyType.CRICKET:   { "hp":  8,  "speed": 5.0, "infestation": 1,  "bounty": 2,  "color": Color(0.50, 0.80, 0.20) },
	EnemyType.BEETLE:    { "hp": 40,  "speed": 1.5, "infestation": 3,  "bounty": 2,  "color": Color(0.20, 0.40, 0.80) },
	EnemyType.COCKROACH: { "hp": 80,  "speed": 1.0, "infestation": 5,  "bounty": 2,  "color": Color(0.55, 0.30, 0.10) },
	EnemyType.RAT:       { "hp": 200, "speed": 0.7, "infestation": 10, "bounty": 2,  "color": Color(0.70, 0.65, 0.60) },
}


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Waddle oscillation rate in radians/second.
const WADDLE_SPEED: float = 24.0

## Lateral sway distance in world units.
const WADDLE_OFFSET: float = 0.03

## How close (in world units) the enemy must be to a cell centre before
## it is considered to have arrived and advances to the next cell.
const ARRIVAL_THRESHOLD: float = 0.05

## Duration of the death flash in seconds.
const DEATH_FLASH_DURATION: float = 0.12


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the enemy reaches the exit cell and is about to despawn.
signal reached_exit

## Emitted when the enemy's HP reaches zero. Arena connects this to award
## Bug Bucks and remove the enemy from the active list.
signal died

## Emitted each time the enemy arrives at a new cell and advances its target.
## Arena uses this to trim the path display so the line only shows ahead.
signal cell_advanced


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

# The last cell centre the enemy fully arrived at.
var _current_cell: Vector2i = Vector2i.ZERO

# The cell centre the enemy is currently moving toward.
var _target_cell: Vector2i = Vector2i.ZERO

# The current path and the index of _target_cell within it.
var _path: Array[Vector2i] = []
var _path_index: int = 0

# Reference to the visual mesh so _process can apply the waddle each frame.
var _visual: MeshInstance3D = null

# Accumulated time driving the waddle oscillation.
var _waddle_time: float = 0.0

# Per-instance stats set from STATS at initialize() time.
var _move_speed: float = 0.0
var _max_hp: float = 0.0
var _current_hp: float = 0.0
var _infestation_damage: int = 0

# Set to true when _die() is called; stops movement and prevents re-entry.
var _is_dead: bool = false
var _bounty: int = 0

# Accumulated walk time used to index into ANT_FRAMES.
var _walk_time: float = 0.0

# Stored so _process can swap the walk frame without rebuilding the material.
var _visual_material: StandardMaterial3D = null

# Base color for this enemy type — stored so the hit flash can return to it.
var _base_color: Color = Color.WHITE

# Tracks the active hit-flash tween so a second hit cancels the first.
var _hit_tween: Tween = null


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Positions the enemy at the entrance cell, applies type stats, and begins movement.
## Must be called by Arena after instantiation and before adding to the tree.
func initialize(initial_path: Array[Vector2i], enemy_type: EnemyType = EnemyType.ANT) -> void:
	if initial_path.size() < 2:
		return

	var stats          = STATS[enemy_type]
	_move_speed        = stats["speed"]
	_max_hp            = stats["hp"]
	_current_hp        = _max_hp
	_infestation_damage = stats["infestation"]
	_bounty            = stats["bounty"]

	_path         = initial_path
	_current_cell = _path[0]
	_path_index   = 1
	_target_cell  = _path[_path_index]

	global_position   = _cell_to_world(_current_cell)
	global_position.y = 0.25

	_base_color = stats["color"]
	_spawn_visual(_base_color)


# ---------------------------------------------------------------------------
# Combat
# ---------------------------------------------------------------------------

## Reduces HP by amount. Triggers death if HP reaches zero.
## Has no effect if the enemy is already dead.
func take_damage(amount: float) -> void:
	if _is_dead:
		return
	_current_hp = maxf(_current_hp - amount, 0.0)
	if _current_hp == 0.0:
		_die()
	else:
		_flash_hit()


## Briefly flashes the enemy white then returns to its base color.
## Cancels any in-progress flash so rapid hits don't stack.
func _flash_hit() -> void:
	if _visual == null:
		return
	if _hit_tween != null:
		_hit_tween.kill()
	var mat: StandardMaterial3D = _visual.material_override
	_hit_tween = create_tween()
	_hit_tween.tween_property(mat, "albedo_color", Color.WHITE, 0.04)
	_hit_tween.tween_property(mat, "albedo_color", _base_color, 0.08)


## Returns current HP as a fraction of max HP (0.0–1.0).
func get_hp_fraction() -> float:
	return _current_hp / _max_hp if _max_hp > 0.0 else 0.0


## Returns the Infestation Level damage this pest deals on exit.
func get_infestation_damage() -> int:
	return _infestation_damage


## Returns the Bug Bucks awarded to the player for killing this pest.
func get_bounty() -> int:
	return _bounty


# ---------------------------------------------------------------------------
# Path updates
# ---------------------------------------------------------------------------

## Called by Arena whenever the grid changes.
func update_path(new_path: Array[Vector2i]) -> void:
	if _is_dead:
		return
	if new_path.size() < 2:
		_path = new_path
		return
	_path = new_path
	var target_idx := new_path.find(_target_cell)
	if target_idx > 0:
		_path_index = target_idx
	else:
		_path_index  = 1
		_target_cell = new_path[1]


## Returns the last cell the enemy fully arrived at.
func get_current_cell() -> Vector2i:
	return _current_cell


## Returns the cell the enemy is currently moving toward.
func get_target_cell() -> Vector2i:
	return _target_cell


## Returns how far along the path this enemy is.
## Higher index = closer to the exit. Used by traps to rank targets.
func get_path_index() -> int:
	return _path_index


# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _is_dead or _path.is_empty() or _path_index >= _path.size():
		return

	var target_world   := _cell_to_world(_target_cell)
	target_world.y      = global_position.y

	var offset   := target_world - global_position
	var distance := offset.length()

	if distance <= ARRIVAL_THRESHOLD:
		global_position = target_world
		_current_cell   = _target_cell
		_path_index    += 1

		if _path_index >= _path.size():
			reached_exit.emit()
			queue_free()
			return

		_target_cell = _path[_path_index]
		cell_advanced.emit()
	else:
		var move_amount := _move_speed * Grid.CELL_SIZE * delta
		global_position += offset.normalized() * minf(move_amount, distance)

	if _visual != null:
		_waddle_time += delta
		var sway       := sin(_waddle_time * WADDLE_SPEED) * WADDLE_OFFSET
		var travel_dir := _target_cell - _current_cell
		if travel_dir.x != 0:
			_visual.position.x = 0.0
			_visual.position.z = sway
		else:
			_visual.position.z = 0.0
			_visual.position.x = sway
		_visual.basis = _facing_basis(travel_dir)
		_walk_time += delta
		_visual_material.albedo_texture = ANT_FRAMES[int(_walk_time * _move_speed * 3.0) % ANT_FRAMES.size()]


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Kills the enemy: stops movement, emits died, plays a white flash, then frees.
func _die() -> void:
	_is_dead = true
	died.emit()

	if _visual == null:
		queue_free()
		return

	var mat: StandardMaterial3D = _visual.material_override
	var tween := create_tween()
	tween.tween_property(mat, "albedo_color", Color.WHITE, DEATH_FLASH_DURATION)
	tween.tween_callback(queue_free)


## Returns a Basis that orients the ant quad flat on the XZ plane (normal = +Y,
## visible from the top-down camera) with the ant's head pointing in dir.
func _facing_basis(dir: Vector2i) -> Basis:
	if dir == Vector2i.ZERO:
		return Basis.IDENTITY
	var forward := Vector3(float(dir.x), 0.0, float(dir.y)).normalized()
	return Basis(forward.cross(Vector3.UP), forward, Vector3.UP)


## Converts a grid coordinate to its world-space centre at y = 0.
## Mirrors the same function in Arena.gd — shared once a utility exists.
func _cell_to_world(cell: Vector2i) -> Vector3:
	var half_grid := (Grid.GRID_SIZE * Grid.CELL_SIZE) / 2.0
	var x         := cell.x * Grid.CELL_SIZE - half_grid + Grid.CELL_SIZE * 0.5
	var z         := cell.y * Grid.CELL_SIZE - half_grid + Grid.CELL_SIZE * 0.5
	return Vector3(x, 0.0, z)


## Creates the enemy visual as a billboard quad using the ant sprite.
## The color is darkened so enemies read as distinct from the bright icon.
## Replaced by an ASCII billboard node in Phase 3.
func _spawn_visual(color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()

	var quad  := QuadMesh.new()
	quad.size  = Vector2(Grid.CELL_SIZE * 2.1, Grid.CELL_SIZE * 2.1)
	mesh_instance.mesh = quad

	var dark_color := Color(color.r * 0.85, color.g * 0.85, color.b * 0.85, 1.0)
	_base_color     = dark_color

	var material                  := StandardMaterial3D.new()
	material.albedo_color          = dark_color
	material.albedo_texture        = ANT_FRAMES[0]
	material.shading_mode          = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency          = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = material
	_visual_material               = material
	mesh_instance.basis            = _facing_basis(_target_cell - _current_cell)

	_visual = mesh_instance
	add_child(mesh_instance)
