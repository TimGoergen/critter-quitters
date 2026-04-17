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
const COLOR_GRID_GLOW    := Color(0.65, 0.90, 1.0)       # cool blue-white for cursor glow
const COLOR_WALL_FILL    := Color(0.72, 0.72, 0.72, 1.0) # light gray wall fill
const COLOR_WALL_BORDER  := Color(0.25, 0.25, 0.25, 1.0) # dark gray cell border lines


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

# Wave spawning — enemies launch one at a time with a small gap between them.
const WAVE_SIZE: int = 3
const SPAWN_INTERVAL: float = 1.2   # seconds between each enemy in the wave
var _enemies_left_to_spawn: int = 0

# The path currently drawn as yellow markers. Updated on every grid change
# and trimmed forward as the enemy advances through cells.
var _display_path: Array[Vector2i] = []

# Grid highlight — a single ImmediateMesh rebuilt each time the hover cell changes.
var _grid_highlight: MeshInstance3D = null
var _hover_cell: Vector2i = Vector2i(-1, -1)

# Single-placement drag state — press starts a drag, release commits.
var _pressing: bool = false
var _preview_trap: MeshInstance3D = null

# Multi-placement state — activated by double-click, drag draws a line of ghosts.
var _multi_placing: bool = false
var _multi_origin: Vector2i = Vector2i(-1, -1)
var _multi_anchors: Array[Vector2i] = []
var _multi_ghosts: Array[MeshInstance3D] = []

# Outside-wall reference positions (x only matters; y is chosen per enemy).
var _spawn_cell: Vector2i = Vector2i.ZERO    # centre spawn cell (used for x and gap centre)
var _despawn_cell: Vector2i = Vector2i.ZERO  # fixed despawn cell on the exit side

# The three rows an enemy may spawn from (randomly chosen each spawn).
var _entrance_rows: Array[int] = []


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Phase 1: entrance and exit are hardcoded for the prototype.
	var entrance := Vector2i(0, 14)
	var exit     := Vector2i(29, 15)

	_spawn_cell   = Vector2i(entrance.x - 2, entrance.y)
	_despawn_cell = Vector2i(exit.x + 2, exit.y)

	# Three rows the enemy may enter from; gap is centred on the canonical row.
	for i in range(3):
		_entrance_rows.append(entrance.y - 1 + i)   # [13, 14, 15]

	# Mark the centre entrance/exit cells first, then the two flanking cells.
	# Done before pathfinder.initialize() so cell_changed isn't connected yet
	# and won't fire premature recalculations.
	_grid.setup_run(entrance, exit)
	_grid.set_cell(Vector2i(entrance.x, entrance.y - 1), Grid.CellState.ENTRANCE)
	_grid.set_cell(Vector2i(entrance.x, entrance.y + 1), Grid.CellState.ENTRANCE)
	_grid.set_cell(Vector2i(exit.x, exit.y - 1), Grid.CellState.EXIT)
	_grid.set_cell(Vector2i(exit.x, exit.y + 1), Grid.CellState.EXIT)

	GameState.start_run(entrance, exit)
	_pathfinder.initialize(_grid)
	_pathfinder.path_updated.connect(_on_path_updated)

	# Spawn one elongated marker covering all 3 rows for entrance and exit.
	_spawn_zone_marker(_spawn_cell,   3, COLOR_ENTRANCE)
	_spawn_zone_marker(_despawn_cell, 3, COLOR_EXIT)

	_setup_grid_highlight()
	_spawn_arena_border()

	_pathfinder.recalculate()
	_start_wave()


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell := _screen_to_grid(event.position)
		if cell != _hover_cell:
			_hover_cell = cell
			_update_grid_highlight()
			if _multi_placing:
				_update_multi_ghosts(cell)
			elif _pressing:
				_update_preview_position(cell)
		return

	# Mobile: a second finger tap while multi-placing cancels the action.
	if event is InputEventScreenTouch:
		if event.pressed and event.index > 0 and _multi_placing:
			_cancel_multi_placement()
		return

	if not event is InputEventMouseButton:
		return

	var cell := _screen_to_grid(event.position)

	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				if event.double_click:
					# Double-click cancels any single-press in progress and
					# enters multi-placement mode.
					_pressing = false
					_clear_preview()
					if _grid.is_in_bounds(cell):
						_start_multi_placement(cell)
				elif not _multi_placing and _grid.is_in_bounds(cell):
					_start_placement(cell)
			else:
				if _multi_placing:
					_finish_multi_placement()
				else:
					_finish_placement(cell)
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if _multi_placing:
					_cancel_multi_placement()
				elif _grid.is_in_bounds(cell):
					_try_remove_trap(cell)


# ---------------------------------------------------------------------------
# Placement logic
# ---------------------------------------------------------------------------

## Called on mouse/finger down. Spawns an invisible ghost showing where the
## trap will land. The player can drag before releasing to reposition it.
func _start_placement(anchor: Vector2i) -> void:
	_pressing = true
	_spawn_preview_trap(anchor)


## Called on mouse/finger up. Commits the trap at the current hover cell
## and removes the ghost regardless of whether placement succeeds.
func _finish_placement(cell: Vector2i) -> void:
	_pressing = false
	_clear_preview()
	if _grid.is_in_bounds(cell):
		_try_place_trap(cell)


# ---------------------------------------------------------------------------
# Multi-placement
# ---------------------------------------------------------------------------

## Enters multi-placement mode at the double-clicked anchor cell.
func _start_multi_placement(anchor: Vector2i) -> void:
	_multi_placing = true
	_multi_origin  = anchor
	_update_multi_ghosts(anchor)


## Rebuilds the line of ghost traps from origin to target.
## Ghosts step every 2 cells along the dominant axis.
func _update_multi_ghosts(target: Vector2i) -> void:
	_clear_multi_ghosts()
	_multi_anchors = _compute_multi_anchors(_multi_origin, target)
	for anchor in _multi_anchors:
		if _get_trap_cells(anchor).is_empty():
			continue
		var ghost  := _make_box_mesh_instance(
			Vector3(Grid.CELL_SIZE * 1.9, Grid.CELL_SIZE * 0.5, Grid.CELL_SIZE * 1.9),
			Color(COLOR_TRAP.r, COLOR_TRAP.g, COLOR_TRAP.b, 0.50)
		)
		var center := _cell_to_world(anchor) + Vector3(Grid.CELL_SIZE * 0.5, 0.0, Grid.CELL_SIZE * 0.5)
		ghost.position = center + Vector3(0.0, Grid.CELL_SIZE * 0.25, 0.0)
		add_child(ghost)
		_multi_ghosts.append(ghost)


## On release, commits all anchors in order from origin to target.
## Phase 1: no currency — places every valid trap.
## When currency is added: stop once Bug Bucks are exhausted.
func _finish_multi_placement() -> void:
	_multi_placing = false
	_clear_multi_ghosts()
	for anchor in _multi_anchors:
		_try_place_trap(anchor)
	_multi_anchors.clear()


## Cancels multi-placement without committing any traps.
## Triggered by right-click (desktop) or second-finger tap (mobile).
func _cancel_multi_placement() -> void:
	_multi_placing = false
	_clear_multi_ghosts()
	_multi_anchors.clear()


## Returns a sequence of 2x2 trap anchor cells from origin toward target.
##
## Anchors are placed by stepping exactly 2 cells along the dominant axis
## per trap, with the minor axis scaled proportionally. This guarantees
## consecutive 2x2 footprints are always touching — no gaps can appear.
## The line extends as far as the dominant-axis distance allows; the last
## trap advances only when the cursor moves far enough to fit another trap.
func _compute_multi_anchors(origin: Vector2i, target: Vector2i) -> Array[Vector2i]:
	var dir      := target - origin
	var dominant := maxi(abs(dir.x), abs(dir.y))

	if dominant == 0:
		return [origin]

	# One trap per 2-cell step in the dominant axis.
	var n := dominant / 2 + 1

	var anchors: Array[Vector2i] = []
	for i in range(n):
		# Step exactly 2*i in the dominant axis so spacing is always uniform.
		var t   := float(i * 2) / float(dominant)
		var pos := Vector2(origin) + Vector2(dir) * t
		anchors.append(Vector2i(roundi(pos.x), roundi(pos.y)))
	return anchors


## Frees all ghost nodes from the current multi-placement line.
func _clear_multi_ghosts() -> void:
	for ghost in _multi_ghosts:
		ghost.queue_free()
	_multi_ghosts.clear()


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
	_display_path = new_path
	for enemy in _active_enemies:
		var current: Vector2i = enemy.get_current_cell()
		# If the enemy is still in the outside approach cell, A* must start
		# from the entrance (first in-bounds cell) to stay within the grid.
		var from: Vector2i = current if _grid.is_in_bounds(current) else GameState.entrance_cell
		var grid_path := _pathfinder.find_path_from(from)
		if grid_path.is_empty():
			continue
		var full: Array[Vector2i] = []
		var wall_out := Vector2i(_despawn_cell.x - 1, _despawn_cell.y)
		if not _grid.is_in_bounds(current):
			# Preserve the enemy's approach row when rebuilding from outside.
			full = _build_full_path(grid_path, current.y)
		else:
			full.append_array(grid_path)
			full.append(wall_out)
			full.append(_despawn_cell)
		enemy.update_path(full)
		_display_path = grid_path
	_redraw_path_display()


## Redraws the yellow path markers starting from the active enemy's current
## target cell, so the line only appears ahead of the enemy.
## Falls back to the full display path when no enemies are active.
func _redraw_path_display() -> void:
	_clear_path_visuals()
	var start_idx := 0
	if not _active_enemies.is_empty():
		var target: Vector2i = _active_enemies[0].get_target_cell()
		var idx    := _display_path.find(target)
		if idx >= 0:
			start_idx = idx
	for i in range(start_idx, _display_path.size()):
		var cell  := _display_path[i]
		var state := _grid.get_cell(cell)
		if state == Grid.CellState.EMPTY \
				or state == Grid.CellState.ENTRANCE \
				or state == Grid.CellState.EXIT:
			_spawn_path_marker(cell)


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
	enemy.cell_advanced.connect(_redraw_path_display)

	add_child(enemy)
	enemy.initialize(path)


func _on_enemy_reached_exit(enemy: Node3D) -> void:
	_active_enemies.erase(enemy)
	# enemy.queue_free() is called inside Enemy.gd — no double-free needed.

	# Phase 1: when the last enemy of the wave exits, start a new wave.
	if _active_enemies.is_empty() and _enemies_left_to_spawn == 0:
		_start_wave()


## Begins spawning WAVE_SIZE enemies, one every SPAWN_INTERVAL seconds.
func _start_wave() -> void:
	_enemies_left_to_spawn = WAVE_SIZE
	_spawn_next_in_wave()


## Spawns one enemy then schedules the next, until the wave is exhausted.
## Each enemy picks a random row from the entrance gap.
func _spawn_next_in_wave() -> void:
	if _enemies_left_to_spawn <= 0:
		return
	_enemies_left_to_spawn -= 1
	var spawn_row: int  = _entrance_rows[randi() % _entrance_rows.size()]
	var spawn_grid      := Vector2i(GameState.entrance_cell.x, spawn_row)
	var grid_path       := _pathfinder.find_path_from(spawn_grid)
	if grid_path.is_empty():
		grid_path = _pathfinder.get_current_path()
	if not grid_path.is_empty():
		_spawn_enemy(_build_full_path(grid_path, spawn_row))
	if _enemies_left_to_spawn > 0:
		get_tree().create_timer(SPAWN_INTERVAL).timeout.connect(_spawn_next_in_wave)


## Builds the full enemy path: outside spawn → wall gap → grid → wall gap → outside despawn.
## spawn_row selects which of the 3 entrance rows this enemy enters through.
func _build_full_path(grid_path: Array[Vector2i], spawn_row: int) -> Array[Vector2i]:
	var outside_spawn := Vector2i(_spawn_cell.x,     spawn_row)
	var wall_in       := Vector2i(_spawn_cell.x + 1, spawn_row)
	var wall_out      := Vector2i(_despawn_cell.x - 1, _despawn_cell.y)
	var full: Array[Vector2i] = [outside_spawn, wall_in]
	full.append_array(grid_path)
	full.append(wall_out)
	full.append(_despawn_cell)
	return full


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


## Rebuilds the grid glow mesh for the current hover cell.
## Each cell's alpha is derived from its Manhattan distance to the nearest
## cell in the 2x2 footprint — cells right against the trap are brightest,
## fading smoothly outward for up to MAX_GLOW_DIST cells.
func _update_grid_highlight() -> void:
	if not _grid.is_in_bounds(_hover_cell):
		_grid_highlight.mesh = null
		return

	const MAX_GLOW_DIST: int = 2

	var im := ImmediateMesh.new()
	var hs := Grid.CELL_SIZE * 0.5
	var y  := 0.08   # sit above path markers and floor markers

	im.surface_begin(Mesh.PRIMITIVE_LINES)

	for dr in range(-MAX_GLOW_DIST, 2 + MAX_GLOW_DIST):
		for dc in range(-MAX_GLOW_DIST, 2 + MAX_GLOW_DIST):
			var cell := Vector2i(_hover_cell.x + dc, _hover_cell.y + dr)
			if not _grid.is_in_bounds(cell):
				continue
			var dist  := _dist_to_footprint(cell, _hover_cell)
			if dist == 0 or dist > MAX_GLOW_DIST:
				continue
			var alpha := 0.80 * pow(1.0 - float(dist) / float(MAX_GLOW_DIST + 1), 2.5)
			_draw_cell_glow(im, cell, hs, y, alpha)

	# Draw the 2x2 footprint as a single outer rectangle — no interior lines.
	# Skip entirely while pressing; the ghost trap is already visible there.
	if not _pressing:
		_draw_2x2_perimeter(im, _hover_cell, hs, y, 0.80)

	im.surface_end()
	_grid_highlight.mesh = im


## Returns the Manhattan distance from cell to the nearest cell in the
## 2x2 footprint anchored at anchor (top-left). Returns 0 if cell is
## inside the footprint.
func _dist_to_footprint(cell: Vector2i, anchor: Vector2i) -> int:
	var dx := maxi(0, maxi(anchor.x - cell.x, cell.x - (anchor.x + 1)))
	var dy := maxi(0, maxi(anchor.y - cell.y, cell.y - (anchor.y + 1)))
	return dx + dy


## Draws the outer perimeter of the 2x2 footprint as a single rectangle.
## Anchored at the top-left cell; spans 2 cell widths in each direction.
func _draw_2x2_perimeter(im: ImmediateMesh, anchor: Vector2i, hs: float, y: float, alpha: float) -> void:
	var color := Color(COLOR_GRID_GLOW.r, COLOR_GRID_GLOW.g, COLOR_GRID_GLOW.b, alpha)
	var c  := _cell_to_world(anchor)
	var tl := Vector3(c.x - hs,                    y, c.z - hs)
	var tr := Vector3(c.x + hs + Grid.CELL_SIZE,    y, c.z - hs)
	var bl := Vector3(c.x - hs,                    y, c.z + hs + Grid.CELL_SIZE)
	var br := Vector3(c.x + hs + Grid.CELL_SIZE,    y, c.z + hs + Grid.CELL_SIZE)
	im.surface_set_color(color); im.surface_add_vertex(tl)
	im.surface_set_color(color); im.surface_add_vertex(tr)
	im.surface_set_color(color); im.surface_add_vertex(tr)
	im.surface_set_color(color); im.surface_add_vertex(br)
	im.surface_set_color(color); im.surface_add_vertex(br)
	im.surface_set_color(color); im.surface_add_vertex(bl)
	im.surface_set_color(color); im.surface_add_vertex(bl)
	im.surface_set_color(color); im.surface_add_vertex(tl)


## Draws the four border edges of a single cell as line segments into im.
func _draw_cell_glow(im: ImmediateMesh, cell: Vector2i, hs: float, y: float, alpha: float) -> void:
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


# ---------------------------------------------------------------------------
# Placement preview
# ---------------------------------------------------------------------------

## Spawns a nearly transparent ghost trap so the player can see placement
## position while dragging. Very low alpha keeps the path visible beneath.
func _spawn_preview_trap(anchor: Vector2i) -> void:
	_clear_preview()
	var cells := _get_trap_cells(anchor)
	if cells.is_empty():
		return
	_preview_trap = _make_box_mesh_instance(
		Vector3(Grid.CELL_SIZE * 1.9, Grid.CELL_SIZE * 0.5, Grid.CELL_SIZE * 1.9),
		Color(COLOR_TRAP.r, COLOR_TRAP.g, COLOR_TRAP.b, 0.50)
	)
	var center := _cell_to_world(anchor) + Vector3(Grid.CELL_SIZE * 0.5, 0.0, Grid.CELL_SIZE * 0.5)
	_preview_trap.position = center + Vector3(0.0, Grid.CELL_SIZE * 0.25, 0.0)
	add_child(_preview_trap)


## Moves the ghost trap to a new anchor position while the player is dragging.
func _update_preview_position(anchor: Vector2i) -> void:
	if _preview_trap == null:
		return
	var cells := _get_trap_cells(anchor)
	if cells.is_empty():
		return
	var center := _cell_to_world(anchor) + Vector3(Grid.CELL_SIZE * 0.5, 0.0, Grid.CELL_SIZE * 0.5)
	_preview_trap.position = center + Vector3(0.0, Grid.CELL_SIZE * 0.25, 0.0)


## Removes the ghost trap node.
func _clear_preview() -> void:
	if _preview_trap != null:
		_preview_trap.queue_free()
		_preview_trap = null


# ---------------------------------------------------------------------------
# Visual helpers — Phase 1 placeholder geometry
# ---------------------------------------------------------------------------

## Draws the arena border as 1-cell-wide light gray slabs with a dark gray
## 1px border around every individual cell, giving a stone-block appearance.
func _spawn_arena_border() -> void:
	var half := (Grid.GRID_SIZE * Grid.CELL_SIZE) / 2.0
	var cs   := Grid.CELL_SIZE

	# 3-cell gaps: one cell above and one cell below the canonical entrance/exit row.
	var ent_top := (GameState.entrance_cell.y - 1) * cs - half
	var ent_bot := (GameState.entrance_cell.y + 2) * cs - half

	var ex_top  := (GameState.exit_cell.y - 1) * cs - half
	var ex_bot  := (GameState.exit_cell.y  + 2) * cs - half

	var full_w := (Grid.GRID_SIZE + 2) * cs

	# --- Fill slabs (light gray) ---
	_spawn_wall_slab(Vector3(0.0, 0.0, -half - cs * 0.5), Vector2(full_w, cs))
	_spawn_wall_slab(Vector3(0.0, 0.0,  half + cs * 0.5), Vector2(full_w, cs))

	var lup  := ent_top - (-half)
	var lbot := half - ent_bot
	if lup  > 0.0: _spawn_wall_slab(Vector3(-half - cs * 0.5, 0.0, -half + lup  * 0.5), Vector2(cs, lup))
	if lbot > 0.0: _spawn_wall_slab(Vector3(-half - cs * 0.5, 0.0,  ent_bot + lbot * 0.5), Vector2(cs, lbot))

	var rup  := ex_top - (-half)
	var rbot := half - ex_bot
	if rup  > 0.0: _spawn_wall_slab(Vector3( half + cs * 0.5, 0.0, -half + rup  * 0.5), Vector2(cs, rup))
	if rbot > 0.0: _spawn_wall_slab(Vector3( half + cs * 0.5, 0.0,  ex_bot + rbot * 0.5), Vector2(cs, rbot))

	# --- Cell border lines (dark gray, one grid per wall cell) ---
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)

	_draw_wall_cell_borders(im, -(half + cs), half + cs, -(half + cs), -half)
	_draw_wall_cell_borders(im, -(half + cs), half + cs,  half,         half + cs)
	if lup  > 0.0: _draw_wall_cell_borders(im, -(half + cs), -half, -half,   ent_top)
	if lbot > 0.0: _draw_wall_cell_borders(im, -(half + cs), -half,  ent_bot, half)
	if rup  > 0.0: _draw_wall_cell_borders(im,  half, half + cs, -half,   ex_top)
	if rbot > 0.0: _draw_wall_cell_borders(im,  half, half + cs,  ex_bot,  half)

	im.surface_end()

	var lines     := MeshInstance3D.new()
	lines.mesh     = im
	var mat       := StandardMaterial3D.new()
	mat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	lines.material_override = mat
	add_child(lines)


## Draws dark gray grid lines at every cell boundary within the given rectangle.
func _draw_wall_cell_borders(
	im: ImmediateMesh,
	min_x: float, max_x: float,
	min_z: float, max_z: float
) -> void:
	var cs := Grid.CELL_SIZE
	var y  := 0.03   # just above the slab surface
	im.surface_set_color(COLOR_WALL_BORDER)
	var x := min_x
	while x <= max_x + 0.001:
		im.surface_add_vertex(Vector3(x, y, min_z))
		im.surface_add_vertex(Vector3(x, y, max_z))
		x += cs
	var z := min_z
	while z <= max_z + 0.001:
		im.surface_add_vertex(Vector3(min_x, y, z))
		im.surface_add_vertex(Vector3(max_x, y, z))
		z += cs


## Creates one flat wall fill slab.
func _spawn_wall_slab(center: Vector3, size: Vector2) -> void:
	var slab := _make_box_mesh_instance(
		Vector3(size.x, 0.05, size.y),
		COLOR_WALL_FILL
	)
	slab.position = center
	add_child(slab)


## Spawns a thin flat square to mark the entrance or exit cell.
func _spawn_flat_marker(cell: Vector2i, color: Color) -> void:
	var marker := _make_box_mesh_instance(
		Vector3(Grid.CELL_SIZE * 0.9, 0.05, Grid.CELL_SIZE * 0.9),
		color
	)
	marker.position = _cell_to_world(cell)
	add_child(marker)


## Spawns a flat marker spanning `rows` cells tall, centred on center_cell.
## Used for the 3-row entrance and exit zone indicators.
func _spawn_zone_marker(center_cell: Vector2i, rows: int, color: Color) -> void:
	var marker := _make_box_mesh_instance(
		Vector3(Grid.CELL_SIZE * 0.9, 0.05, Grid.CELL_SIZE * rows * 0.9),
		color
	)
	marker.position = _cell_to_world(center_cell)
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
