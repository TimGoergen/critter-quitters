## Arena.gd
## Owns the grid, pathfinder, and all arena visuals for one run.
##
## Responsibilities:
##   - Initialise Grid and Pathfinder at run start with entrance/exit positions
##   - Translate screen input into grid coordinates
##   - Validate and commit trap placements (reject if path would be blocked)
##   - Spawn and remove placeholder visual nodes for traps and the path
##
## For Phase 1 all visuals are coloured boxes — final ASCII billboard
## rendering is Phase 3 work. Right-click removes a placed trap.
##
## Coordinate conventions:
##   Grid  — Vector2i(col, row), origin top-left, col = X, row = Z
##   World — Vector3(x, y, z), grid mapped to XZ plane at y = 0

class_name Arena
extends Node3D

# Explicit dependencies — preloading makes cross-script references visible
# at the top of the file rather than relying on the global class registry.
const Grid       = preload("res://arena/Grid.gd")
const Pathfinder = preload("res://arena/Pathfinder.gd")
const Enemy      = preload("res://enemies/Enemy.gd")


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Phase 1 placeholder colours. These are replaced by ASCII billboards in Phase 3.
const COLOR_ENTRANCE  := Color(0.20, 0.80, 0.20, 1.0)   # green
const COLOR_EXIT      := Color(0.80, 0.20, 0.20, 1.0)   # red
const COLOR_TRAP      := Color(0.40, 0.40, 0.80, 1.0)   # blue-grey box
const COLOR_PATH      := Color(0.80, 0.70, 0.20, 0.5)   # yellow, semi-transparent


# ---------------------------------------------------------------------------
# Node references — resolved at scene load via @onready
# ---------------------------------------------------------------------------

@onready var _grid: Grid             = $Grid
@onready var _pathfinder: Pathfinder = $Pathfinder
@onready var _trap_container: Node3D = $TrapContainer
@onready var _path_visual: Node3D    = $PathVisual
@onready var _camera: Camera3D       = $Camera3D


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

# Keeps track of which MeshInstance3D represents each placed trap so we
# can remove the visual when the trap is sold or destroyed by an obstacle.
var _trap_nodes: Dictionary = {}          # Vector2i -> MeshInstance3D

# Path marker nodes spawned each time the path updates. Cleared and
# rebuilt on every path_updated signal.
var _path_nodes: Array[MeshInstance3D] = []

# All enemy nodes currently active on the arena.
# Each enemy is forwarded path updates so it can reroute in real time.
var _active_enemies: Array[Node3D] = []


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Phase 1: entrance and exit are hardcoded for the prototype.
	# In the full game, Arena receives these from the run manager after
	# randomly selecting an arena from the pool.
	var entrance := Vector2i(0, 6)    # left wall, row 6
	var exit     := Vector2i(13, 7)   # right wall, row 7

	_grid.setup_run(entrance, exit)
	GameState.start_run(entrance, exit)
	_pathfinder.initialize(_grid)

	_pathfinder.path_updated.connect(_on_path_updated)

	_spawn_flat_marker(entrance, COLOR_ENTRANCE)
	_spawn_flat_marker(exit, COLOR_EXIT)

	# Trigger the first path calculation now that entrance and exit are set.
	# _on_path_updated will fire as a result, which spawns the first enemy.
	_pathfinder.recalculate()


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return

	var cell := _screen_to_grid(event.position)
	if not _grid.is_in_bounds(cell):
		return

	match event.button_index:
		MOUSE_BUTTON_LEFT:
			_try_place_trap(cell)
		MOUSE_BUTTON_RIGHT:
			_try_remove_trap(cell)


# ---------------------------------------------------------------------------
# Placement logic
# ---------------------------------------------------------------------------

func _try_place_trap(cell: Vector2i) -> void:
	if not _grid.is_buildable(cell):
		return

	if not _pathfinder.can_place_at(cell):
		# This placement would block every path from entrance to exit.
		# Silently reject for now — Phase 5 adds player-facing feedback.
		print("Placement rejected: would block all paths at ", cell)
		return

	_grid.place_trap(cell)
	_spawn_trap_visual(cell)


func _try_remove_trap(cell: Vector2i) -> void:
	if _grid.get_cell(cell) != Grid.CellState.TRAP:
		return

	_grid.remove_trap(cell)

	if _trap_nodes.has(cell):
		_trap_nodes[cell].queue_free()
		_trap_nodes.erase(cell)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_path_updated(new_path: Array[Vector2i]) -> void:
	_clear_path_visuals()

	for cell in new_path:
		# Only draw path markers on traversable cells — skip trap cells
		# (they block the path) and entrance/exit (already have markers).
		var state := _grid.get_cell(cell)
		if state == Grid.CellState.EMPTY \
				or state == Grid.CellState.ENTRANCE \
				or state == Grid.CellState.EXIT:
			_spawn_path_marker(cell)

	# Forward the new path to all active enemies so they reroute immediately.
	for enemy in _active_enemies:
		enemy.update_path(new_path)

	# Phase 1: spawn one enemy if none are active, to keep the arena populated.
	if _active_enemies.is_empty() and not new_path.is_empty():
		_spawn_enemy(new_path)


# ---------------------------------------------------------------------------
# Coordinate conversion
# ---------------------------------------------------------------------------

## Projects a screen-space position to a grid cell coordinate.
## Returns Vector2i(-1, -1) if the ray does not intersect the arena floor.
func _screen_to_grid(screen_pos: Vector2) -> Vector2i:
	var ray_origin := _camera.project_ray_origin(screen_pos)
	var ray_dir    := _camera.project_ray_normal(screen_pos)

	# Find where the ray intersects the Y = 0 plane (the arena floor).
	# t = distance along the ray to the intersection point.
	if abs(ray_dir.y) < 0.001:
		# Ray is nearly parallel to the floor — no usable intersection.
		return Vector2i(-1, -1)

	var t         := -ray_origin.y / ray_dir.y
	var world_pos := ray_origin + ray_dir * t

	# Convert world XZ position to grid column and row.
	# The grid is centred on the world origin, so we offset by half the
	# total grid width before dividing by cell size.
	var half_grid := (Grid.GRID_SIZE * Grid.CELL_SIZE) / 2.0
	var col       := floori((world_pos.x + half_grid) / Grid.CELL_SIZE)
	var row       := floori((world_pos.z + half_grid) / Grid.CELL_SIZE)

	return Vector2i(col, row)


## Converts a grid coordinate to its world-space centre position at y = 0.
func _cell_to_world(cell: Vector2i) -> Vector3:
	var half_grid := (Grid.GRID_SIZE * Grid.CELL_SIZE) / 2.0
	var x         := cell.x * Grid.CELL_SIZE - half_grid + Grid.CELL_SIZE * 0.5
	var z         := cell.y * Grid.CELL_SIZE - half_grid + Grid.CELL_SIZE * 0.5
	return Vector3(x, 0.0, z)


# ---------------------------------------------------------------------------
# Enemy spawning
# ---------------------------------------------------------------------------

## Instantiates one enemy, places it at the entrance, and starts it moving.
func _spawn_enemy(path: Array[Vector2i]) -> void:
	var enemy: Node3D = Enemy.new()

	# Register before adding to tree so the signal is connected before
	# _ready fires on the enemy node.
	_active_enemies.append(enemy)
	enemy.reached_exit.connect(_on_enemy_reached_exit.bind(enemy))

	add_child(enemy)
	enemy.initialize(path)


func _on_enemy_reached_exit(enemy: Node3D) -> void:
	_active_enemies.erase(enemy)
	# enemy.queue_free() is called inside Enemy.gd — no double-free needed.

	# Phase 1: immediately respawn so the arena stays active for testing.
	var current_path := _pathfinder.get_current_path()
	if not current_path.is_empty():
		_spawn_enemy(current_path)


# ---------------------------------------------------------------------------
# Visual helpers — Phase 1 placeholder geometry
# ---------------------------------------------------------------------------

## Spawns a thin flat square to mark the entrance or exit cell.
func _spawn_flat_marker(cell: Vector2i, color: Color) -> void:
	var marker := _make_box_mesh_instance(
		Vector3(Grid.CELL_SIZE * 0.9, 0.05, Grid.CELL_SIZE * 0.9),
		color
	)
	marker.position = _cell_to_world(cell)
	add_child(marker)


## Spawns a raised box to represent a placed trap.
func _spawn_trap_visual(cell: Vector2i) -> void:
	var trap_visual := _make_box_mesh_instance(
		Vector3(Grid.CELL_SIZE * 0.8, Grid.CELL_SIZE * 0.5, Grid.CELL_SIZE * 0.8),
		COLOR_TRAP
	)
	# Raise the box so its base sits on y = 0 rather than centring on it.
	trap_visual.position = _cell_to_world(cell) + Vector3(0.0, 0.25, 0.0)
	_trap_container.add_child(trap_visual)
	_trap_nodes[cell] = trap_visual


## Spawns a thin flat square to indicate one cell on the current path.
func _spawn_path_marker(cell: Vector2i) -> void:
	var path_marker := _make_box_mesh_instance(
		Vector3(Grid.CELL_SIZE * 0.55, 0.02, Grid.CELL_SIZE * 0.55),
		COLOR_PATH
	)
	path_marker.position = _cell_to_world(cell)
	_path_visual.add_child(path_marker)
	_path_nodes.append(path_marker)


## Frees all path marker nodes from the previous path calculation.
func _clear_path_visuals() -> void:
	for node in _path_nodes:
		node.queue_free()
	_path_nodes.clear()


## Creates a MeshInstance3D with a BoxMesh of the given size and colour.
## Materials are UNSHADED so the scene requires no light sources.
func _make_box_mesh_instance(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()

	var box_mesh  := BoxMesh.new()
	box_mesh.size  = size
	mesh_instance.mesh = box_mesh

	var material                := StandardMaterial3D.new()
	material.albedo_color        = color
	material.shading_mode        = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency        = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = material

	return mesh_instance
