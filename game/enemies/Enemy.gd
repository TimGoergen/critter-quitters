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
##     _target_cell  — the cell centre it is currently moving toward
##
##   Movement is always a straight line between adjacent cell centres.
##   A straight line between adjacent cells can never cross an obstacle
##   (obstacles are full cells, and adjacent cell centres are separated
##   by exactly one cell width). This makes obstacle traversal impossible
##   by construction, regardless of how the path changes.
##
##   _history records every cell centre the enemy has arrived at, in order.
##   It is the foundation of the backtracking reroute model.
##
## Rerouting model:
##   When the path updates, two cases are possible:
##
##   1. _target_cell is still in the new path.
##      Keep moving to _target_cell, then follow the new path from there.
##      No interruption, no direction change mid-segment.
##
##   2. _target_cell was blocked (no longer in the new path).
##      Walk backward through _history until the most recent cell that
##      is also on the new path. Build a combined path:
##        [_current_cell, prev_cell, ..., rejoin_cell, new_path_forward...]
##      Every step in this combined path is adjacent-to-adjacent, so
##      the enemy physically retraces its route rather than cutting across.
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

# Ordered list of every cell centre the enemy has arrived at.
# Most recent entry is _current_cell. Used to construct backtrack routes
# that step through previously visited (and therefore passable) cells.
var _history: Array[Vector2i] = []


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
	_history      = [_current_cell]

	global_position   = _cell_to_world(_current_cell)
	global_position.y = 0.25   # sit above the floor, same height as trap boxes

	_spawn_visual()


# ---------------------------------------------------------------------------
# Path updates
# ---------------------------------------------------------------------------

## Called by Arena whenever the Pathfinder recalculates the path.
##
## Case 1 — target still valid:
##   Update the stored path and index. The enemy continues toward
##   _target_cell without changing direction, then follows the new path.
##
## Case 2 — target was blocked:
##   Search backward through _history for the most recent cell that
##   appears on the new path (the "rejoin cell"). Build a combined path
##   that backtracks step-by-step from _current_cell to that rejoin cell,
##   then continues forward along the new path. Because every step in the
##   backtrack portion was previously traversed, all steps are adjacent
##   and no obstacle can be crossed.
func update_path(new_path: Array[Vector2i]) -> void:
	if new_path.is_empty():
		_path = new_path
		return

	var target_index := new_path.find(_target_cell)

	if target_index >= 0:
		# Target is still on the new path — continue toward it, then follow
		# the new path from that point onward.
		_path       = new_path
		_path_index = target_index
		return

	# Target was blocked. Find the most recent history cell that is also
	# on the new path — this is where the backtrack route rejoins.
	var rejoin_history_idx := -1
	var rejoin_path_idx    := -1
	for i in range(_history.size() - 1, -1, -1):
		var idx := new_path.find(_history[i])
		if idx >= 0:
			rejoin_history_idx = i
			rejoin_path_idx    = idx
			break

	if rejoin_history_idx < 0:
		# No common cell found — shouldn't occur in normal play since the
		# pathfinder always guarantees a valid path from entrance to exit.
		_path = new_path
		return

	# Build a combined path:
	#   backtrack: _history[size-1] → _history[size-2] → ... → _history[rejoin]
	#   forward:   new_path[rejoin+1] → ... → exit
	# All backtrack steps are between previously visited adjacent cells.
	var combined: Array[Vector2i] = []
	for i in range(_history.size() - 1, rejoin_history_idx - 1, -1):
		combined.append(_history[i])
	for i in range(rejoin_path_idx + 1, new_path.size()):
		combined.append(new_path[i])

	# combined[0] == _current_cell. The enemy first finishes returning to
	# _current_cell (it is currently between _current_cell and the old
	# blocked _target_cell), then steps backward through history until
	# reaching the rejoin cell, then follows the new path forward.
	_path        = combined
	_path_index  = 0
	_target_cell = combined[0]


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
		_history.append(_current_cell)
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

	var box_mesh  := BoxMesh.new()
	box_mesh.size  = Vector3(
		Grid.CELL_SIZE * 1.8,
		Grid.CELL_SIZE * 1.8,
		Grid.CELL_SIZE * 1.8
	)
	mesh_instance.mesh = box_mesh

	var material          := StandardMaterial3D.new()
	material.albedo_color  = COLOR_ENEMY
	material.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.material_override = material

	add_child(mesh_instance)
