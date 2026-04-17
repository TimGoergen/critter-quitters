## Enemy.gd
## A basic pest that follows the calculated path from entrance to exit.
##
## Phase 1 placeholder — a coloured moving box with no HP, damage, or
## pest type. The sole purpose here is to prove that path-following and
## real-time rerouting work correctly before the rest of the game is built.
##
## Movement model:
##   The enemy holds an index into the current path array. Each frame it
##   moves toward the world-space centre of the cell at that index. When
##   it arrives, it advances the index. If the path changes while the
##   enemy is moving, it finds its current target cell in the new path
##   and continues from there — or snaps to the nearest path cell if its
##   target no longer appears in the new path.
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
## Kept small so the enemy doesn't visibly skip over cell centres.
const ARRIVAL_THRESHOLD: float = 0.05


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the enemy reaches the exit cell and is about to despawn.
## Arena connects here to track infestation and respawn for Phase 1 testing.
signal reached_exit


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _path: Array[Vector2i] = []
var _path_index: int = 0


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Positions the enemy at the first cell in the path and begins movement.
## Must be called by Arena after instantiation and before adding to the tree.
func initialize(initial_path: Array[Vector2i]) -> void:
	_path = initial_path
	_path_index = 0

	if not _path.is_empty():
		global_position = _cell_to_world(_path[0])
		global_position.y = 0.25   # sit above the floor, same height as trap boxes

	_spawn_visual()


# ---------------------------------------------------------------------------
# Path updates
# ---------------------------------------------------------------------------

## Called by Arena whenever the Pathfinder recalculates the path.
## Finds where the enemy currently is in the new path and continues
## from that point — so mid-wave trap placement reroutes smoothly.
func update_path(new_path: Array[Vector2i]) -> void:
	if new_path.is_empty():
		# No valid path exists — enemy holds position until a path reopens.
		_path = new_path
		return

	# Try to find the enemy's current target cell in the new path.
	# If it's there, continue from that index.
	if _path_index < _path.size():
		var current_target := _path[_path_index]
		var new_index := new_path.find(current_target)
		if new_index >= 0:
			_path = new_path
			_path_index = new_index
			return

	# Fallback: the current target cell is no longer on any path
	# (shouldn't happen given the validity check, but handled defensively).
	# Snap to the nearest cell in the new path and continue.
	_path = new_path
	_path_index = _nearest_path_index()


# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _path.is_empty() or _path_index >= _path.size():
		return

	var target_world := _cell_to_world(_path[_path_index])

	# Keep y fixed — only move on the XZ plane.
	target_world.y = global_position.y

	var offset   := target_world - global_position
	var distance := offset.length()

	if distance <= ARRIVAL_THRESHOLD:
		# Snap to the cell centre and advance to the next cell.
		global_position = target_world
		_path_index += 1

		if _path_index >= _path.size():
			reached_exit.emit()
			queue_free()
	else:
		var move_amount := MOVE_SPEED * Grid.CELL_SIZE * delta
		global_position += offset.normalized() * minf(move_amount, distance)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Returns the index in _path of the cell closest to the enemy's current
## world position. Used as a fallback when rerouting after path changes.
func _nearest_path_index() -> int:
	var best_index    := 0
	var best_distance := INF

	for index in range(_path.size()):
		var dist := global_position.distance_to(_cell_to_world(_path[index]))
		if dist < best_distance:
			best_distance = dist
			best_index    = index

	return best_index


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
		Grid.CELL_SIZE * 0.5,
		Grid.CELL_SIZE * 0.5,
		Grid.CELL_SIZE * 0.5
	)
	mesh_instance.mesh = box_mesh

	var material         := StandardMaterial3D.new()
	material.albedo_color = COLOR_ENEMY
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.material_override = material

	add_child(mesh_instance)
