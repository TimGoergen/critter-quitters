## Enemy.gd
## A basic pest that follows the calculated path from entrance to exit.
##
## Phase 1 placeholder — a coloured moving box with no HP, damage, or
## pest type. The sole purpose here is to prove that path-following and
## real-time rerouting work correctly before the rest of the game is built.
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
## Usage: instantiate via Arena, then call initialize() before the node
## is added to the scene tree.

extends Node3D

const Grid = preload("res://arena/Grid.gd")


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## World units per second. One cell = one Grid.CELL_SIZE world unit,
## so this is effectively cells-per-second at the default cell size.
## TODO: replace with per-pest-type speed values once the enemy roster exists
const MOVE_SPEED: float = 3.0

## Colour of the placeholder box. Replaced by ASCII billboard in Phase 3.
const COLOR_ENEMY := Color(0.85, 0.35, 0.15, 1.0)   # orange

## How close (in world units) the enemy must be to a cell centre before
## it is considered to have arrived and advances to the next cell.
const ARRIVAL_THRESHOLD: float = 0.05


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the enemy reaches the exit cell and is about to despawn.
signal reached_exit


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

# The last cell centre the enemy fully arrived at.
# Always a passable cell. Used as the starting point for backtrack paths.
var _current_cell: Vector2i = Vector2i.ZERO

# The cell centre the enemy is currently moving toward.
# Always adjacent to _current_cell, so the movement segment never
# crosses an obstacle cell.
var _target_cell: Vector2i = Vector2i.ZERO

# The current path and the index of _target_cell within it.
var _path: Array[Vector2i] = []
var _path_index: int = 0


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Positions the enemy at the entrance cell and begins movement.
## Must be called by Arena after instantiation and before adding to the tree.
func initialize(initial_path: Array[Vector2i]) -> void:
	if initial_path.size() < 2:
		return

	_path         = initial_path
	_current_cell = _path[0]
	_path_index   = 1
	_target_cell  = _path[_path_index]

	global_position   = _cell_to_world(_current_cell)
	global_position.y = 0.25   # sit above the floor, same height as trap boxes

	_spawn_visual()


# ---------------------------------------------------------------------------
# Path updates
# ---------------------------------------------------------------------------

## Called by Arena whenever the grid changes.
## new_path is a fresh A* result from _current_cell to the exit — Arena
## computes it per-enemy so the path is always optimal from here.
## new_path[0] == _current_cell; new_path[1] is the immediate next step.
func update_path(new_path: Array[Vector2i]) -> void:
	if new_path.size() < 2:
		_path = new_path
		return
	_path = new_path
	var target_idx := new_path.find(_target_cell)
	if target_idx > 0:
		# Already heading toward a cell on the new path — finish the segment
		# without interruption rather than snapping to a new direction mid-cell.
		_path_index = target_idx
	else:
		_path_index  = 1
		_target_cell = new_path[1]


## Returns the last cell the enemy fully arrived at.
## Arena reads this to compute the per-enemy reroute path.
func get_current_cell() -> Vector2i:
	return _current_cell


# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _path.is_empty() or _path_index >= _path.size():
		return

	var target_world   := _cell_to_world(_target_cell)
	target_world.y      = global_position.y   # move only on the XZ plane

	var offset   := target_world - global_position
	var distance := offset.length()

	if distance <= ARRIVAL_THRESHOLD:
		# Arrived — snap to cell centre, advance to the next cell.
		global_position = target_world
		_current_cell   = _target_cell
		_path_index    += 1

		if _path_index >= _path.size():
			reached_exit.emit()
			queue_free()
			return

		_target_cell = _path[_path_index]
	else:
		var move_amount := MOVE_SPEED * Grid.CELL_SIZE * delta
		global_position += offset.normalized() * minf(move_amount, distance)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Converts a grid coordinate to its world-space centre at y = 0.
## Mirrors the same function in Arena.gd — shared once a utility exists.
func _cell_to_world(cell: Vector2i) -> Vector3:
	var half_grid := (Grid.GRID_SIZE * Grid.CELL_SIZE) / 2.0
	var x         := cell.x * Grid.CELL_SIZE - half_grid + Grid.CELL_SIZE * 0.5
	var z         := cell.y * Grid.CELL_SIZE - half_grid + Grid.CELL_SIZE * 0.5
	return Vector3(x, 0.0, z)


## Creates the Phase 1 placeholder visual as a child MeshInstance3D.
## Replaced by an ASCII billboard node in Phase 3.
func _spawn_visual() -> void:
	var mesh_instance := MeshInstance3D.new()

	var radius       := Grid.CELL_SIZE * 0.675   # 1.8 * 0.75 / 2
	var cylinder     := CylinderMesh.new()
	cylinder.top_radius    = radius
	cylinder.bottom_radius = radius
	cylinder.height        = Grid.CELL_SIZE * 0.5
	mesh_instance.mesh = cylinder

	var material          := StandardMaterial3D.new()
	material.albedo_color  = COLOR_ENEMY
	material.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.material_override = material

	add_child(mesh_instance)
