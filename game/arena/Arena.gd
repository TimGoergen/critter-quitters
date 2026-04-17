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
const COLOR_GRID_GLOW := Color(0.65, 0.90, 1.0)         # cool blue-white for cursor glow

## How many cells outward from the cursor the grid glow extends.
const GRID_GLOW_RADIUS: int = 3


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

# Maps the anchor cell (top-left of the 2x2 footprint) to its visual node.
var _trap_nodes: Dictionary = {}          # anchor Vector2i -> MeshInstance3D

# Maps every cell in a trap's 2x2 footprint back to that trap's anchor cell.
# Used to find and remove the whole trap when the player clicks any of its cells.
var _trap_anchors: Dictionary = {}        # Vector2i -> anchor Vector2i

# Path marker nodes spawned each time the path updates. Cleared and
# rebuilt on every path_updated signal.
var _path_nodes: Array[MeshInstance3D] = []

# All enemy nodes currently active on the arena.
# Each enemy is forwarded path updates so it can reroute in real time.
var _active_enemies: Array[Node3D] = []

# Grid highlight — a single ImmediateMesh rebuilt each time the hover cell changes.
var _grid_highlight: MeshInstance3D = null
var _hover_cell: Vector2i = Vector2i(-1, -1)


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Phase 1: entrance and exit are hardcoded for the prototype.
	# In the full game, Arena receives these from the run manager after
	# randomly selecting an arena from the pool.
	var entrance := Vector2i(0, 14)    # left wall, row 14
	var exit     := Vector2i(29, 15)  # right wall, row 15

	_grid.setup_run(entrance, exit)
	GameState.start_run(entrance, exit)
	_pathfinder.initialize(_grid)

	_pathfinder.path_updated.connect(_on_path_updated)

	_spawn_flat_marker(entrance, COLOR_ENTRANCE)
	_spawn_flat_marker(exit, COLOR_EXIT)

	_setup_grid_highlight()

	# Trigger the first path calculation now that entrance and exit are set.
	_pathfinder.recalculate()


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell := _screen_to_grid(event.position)
		if cell != _hover_cell:
			_hover_cell = cell
			_update_grid_highlight()
		return

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

func _try_place_trap(anchor: Vector2i) -> void:
	var cells := _get_trap_cells(anchor)
	if cells.is_empty():
		return

	for cell in cells:
		if not _grid.is_buildable(cell):
			return

	if not _pathfinder.can_place_at(cells):
		print("Placement rejected: would block all paths at ", anchor)
		return

	for cell in cells:
		_grid.place_trap(cell)
		_trap_anchors[cell] = anchor

	_spawn_trap_visual(anchor)


func _try_remove_trap(cell: Vector2i) -> void:
	if not _trap_anchors.has(cell):
		return

	var anchor: Vector2i = _trap_anchors[cell]
	for c in _get_trap_cells(anchor):
		_grid.remove_trap(c)
		_trap_anchors.erase(c)

	if _trap_nodes.has(anchor):
		_trap_nodes[anchor].queue_free()
		_trap_nodes.erase(anchor)


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


# ---------------------------------------------------------------------------
# Grid highlight
# ---------------------------------------------------------------------------

## Creates the MeshInstance3D used for the cursor grid glow.
## The material uses vertex colours so each line segment can have its own alpha.
func _setup_grid_highlight() -> void:
	_grid_highlight = MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	_grid_highlight.material_override = mat
	add_child(_grid_highlight)


## Rebuilds the grid glow mesh around the current hover cell.
## Each cell within GRID_GLOW_RADIUS has its four edges drawn as line segments.
## Alpha falls off quadratically so cells further away appear dimmer.
func _update_grid_highlight() -> void:
	if not _grid.is_in_bounds(_hover_cell):
		_grid_highlight.mesh = null
		return

	var im  := ImmediateMesh.new()
	var hs  := Grid.CELL_SIZE * 0.5
	var y   := 0.08   # sit above path markers and floor markers

	im.surface_begin(Mesh.PRIMITIVE_LINES)

	for dr in range(-GRID_GLOW_RADIUS, GRID_GLOW_RADIUS + 1):
		for dc in range(-GRID_GLOW_RADIUS, GRID_GLOW_RADIUS + 1):
			var cell := Vector2i(_hover_cell.x + dc, _hover_cell.y + dr)
			if not _grid.is_in_bounds(cell):
				continue

			var dist  := maxi(absi(dc), absi(dr))
			var t     := float(dist) / float(GRID_GLOW_RADIUS + 1)
			var alpha := pow(1.0 - t, 2.0)
			var color := Color(COLOR_GRID_GLOW.r, COLOR_GRID_GLOW.g, COLOR_GRID_GLOW.b, alpha)

			var c  := _cell_to_world(cell)
			var tl := Vector3(c.x - hs, y, c.z - hs)
			var tr := Vector3(c.x + hs, y, c.z - hs)
			var bl := Vector3(c.x - hs, y, c.z + hs)
			var br := Vector3(c.x + hs, y, c.z + hs)

			im.surface_set_color(color); im.surface_add_vertex(tl)
			im.surface_set_color(color); im.surface_add_vertex(tr)
			im.surface_set_color(color); im.surface_add_vertex(tr)
			im.surface_set_color(color); im.surface_add_vertex(br)
			im.surface_set_color(color); im.surface_add_vertex(br)
			im.surface_set_color(color); im.surface_add_vertex(bl)
			im.surface_set_color(color); im.surface_add_vertex(bl)
			im.surface_set_color(color); im.surface_add_vertex(tl)

	im.surface_end()
	_grid_highlight.mesh = im


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


## Spawns a raised box centred on the 2x2 footprint of the trap.
func _spawn_trap_visual(anchor: Vector2i) -> void:
	var trap_visual := _make_box_mesh_instance(
		Vector3(Grid.CELL_SIZE * 1.9, Grid.CELL_SIZE * 0.5, Grid.CELL_SIZE * 1.9),
		COLOR_TRAP
	)
	# Centre of the 2x2 footprint sits half a cell right and down from the
	# anchor cell centre. Raise by half the box height so it sits on y = 0.
	var center := _cell_to_world(anchor) + Vector3(Grid.CELL_SIZE * 0.5, 0.0, Grid.CELL_SIZE * 0.5)
	trap_visual.position = center + Vector3(0.0, Grid.CELL_SIZE * 0.25, 0.0)
	_trap_container.add_child(trap_visual)
	_trap_nodes[anchor] = trap_visual


## Returns the four cells of a 2x2 trap footprint given its top-left anchor.
## Returns an empty array if any cell in the footprint is out of bounds.
func _get_trap_cells(anchor: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dr in range(2):
		for dc in range(2):
			var c := Vector2i(anchor.x + dc, anchor.y + dr)
			if not _grid.is_in_bounds(c):
				return []
			cells.append(c)
	return cells


## Spawns a flat square to indicate one cell on the current path.
func _spawn_path_marker(cell: Vector2i) -> void:
	var path_marker := _make_box_mesh_instance(
		Vector3(Grid.CELL_SIZE * 0.9, 0.05, Grid.CELL_SIZE * 0.9),
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
