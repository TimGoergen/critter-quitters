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
## rendering is Phase 3 work.
##
## Placement model:
##   Press and drag draws a line of ghost traps from the press origin to the
##   cursor. Release commits them in order from origin to end; traps that
##   cannot be afforded are skipped (cost validation is a stub until the
##   currency system exists). Right-click cancels the drag without placing.
##   Right-click outside a drag removes the trap under the cursor.
##
## Coordinate conventions:
##   Grid  — Vector2i(col, row), origin top-left, col = X, row = Z
##   World — Vector3(x, y, z), grid mapped to XZ plane at y = 0

class_name Arena
extends Node3D

# Explicit dependencies — preloading makes cross-script references visible
# at the top of the file rather than relying on the global class registry.
const Grid              = preload("res://arena/Grid.gd")
const Pathfinder        = preload("res://arena/Pathfinder.gd")
const Enemy             = preload("res://enemies/Enemy.gd")
const Trap              = preload("res://traps/Trap.gd")
const Projectile        = preload("res://traps/Projectile.gd")
const FogCloud          = preload("res://traps/FogCloud.gd")
const HUD               = preload("res://ui/HUD.gd")
const TrapUpgradePanel  = preload("res://ui/TrapUpgradePanel.gd")
const DebugStartDialog  = preload("res://ui/DebugStartDialog.gd")


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Set to true to render the yellow path line during play. Off by default —
# the path visualisation is a debug aid; it clutters the arena during normal play.
const SHOW_PATH_LINE: bool = false

# Fixed HUD heights in screen pixels — must match the corresponding constants in HUD.gd.
# The selector strip is added to HUD_BOT_PX per orientation (see _fit_camera_to_grid).
# Infestation bar moved to the top panel, so HUD_BOT_PX is now 0 — the selector
# sits directly at the screen's bottom edge with no additional strip below it.
const HUD_TOP_PX: float = 72.0   # top stats bar (HUD.PANEL_H)
const HUD_BOT_PX: float = 0.0    # no persistent bottom strip below the selector

# Phase 1 placeholder colours. These are replaced by ASCII billboards in Phase 3.
const COLOR_ENTRANCE  := Color(0.40, 0.60, 0.42, 1.0)   # muted sage green
const COLOR_EXIT      := Color(0.62, 0.38, 0.38, 1.0)   # muted dusty red
const COLOR_TRAP      := Color(0.40, 0.40, 0.80, 1.0)   # blue-grey box
const COLOR_PATH      := Color(0.80, 0.70, 0.20, 0.5)   # yellow, semi-transparent
const COLOR_GRID_GLOW    := Color(0.65, 0.90, 1.0)       # cool blue-white for cursor glow
const COLOR_WALL_FILL    := Color(0.72, 0.72, 0.72, 1.0) # light gray wall fill
const COLOR_WALL_BORDER  := Color(0.25, 0.25, 0.25, 1.0) # dark gray cell border lines
const COLOR_TRAP_SELECTED := Color(0.90, 0.70, 0.10, 1.0) # gold outline on selected trap


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

# Pre-created path marker nodes. Repositioned and shown/hidden on each
# path update rather than freed and re-created.
const PATH_MARKER_POOL_SIZE: int = 128
var _path_marker_pool: Array[MeshInstance3D] = []

# All enemy nodes currently active on the arena.
# Each enemy is forwarded path updates so it can reroute in real time.
var _active_enemies: Array[Node3D] = []

# Wave spawning — enemies launch one at a time with a small gap between them.
const WAVE_SIZE: int = 10   # default; overridden at runtime by the debug start dialog
var _wave_size: int = WAVE_SIZE
const SPAWN_INTERVAL: float = 0.36     # seconds between each enemy in the wave
const WAVE_COUNTDOWN: int  = 5         # seconds of countdown before each wave

var _enemies_left_to_spawn: int = 0
var _countdown_active: bool     = false  # true while between-wave countdown is ticking

# The path currently drawn as yellow markers. Updated on every grid change
# and trimmed forward as the enemy advances through cells.
var _display_path: Array[Vector2i] = []

# Grid highlight — a single ImmediateMesh rebuilt each time the hover cell changes.
var _grid_highlight: MeshInstance3D = null
var _hover_cell: Vector2i = Vector2i(-1, -1)

# Gold perimeter drawn around the 2×2 footprint of the currently open upgrade panel.
# Separate node from _grid_highlight so cursor movement does not clear it.
var _selected_trap_outline: MeshInstance3D = null

# Per-placed-trap inset perimeter outlines. Redrawn when hover or selection state changes.
var _trap_outlines: Dictionary = {}           # anchor Vector2i -> MeshInstance3D
var _hovered_trap_anchor:  Vector2i = Vector2i(-1, -1)
var _selected_trap_anchor: Vector2i = Vector2i(-1, -1)

# The currently open upgrade panel, or null if none is open.
# Only one panel is open at a time — opening a new one closes the previous.
var _upgrade_panel: Node = null

# The trap whose upgrade panel is currently open. Kept so the range indicator
# can be shown while the panel is open and hidden again when it closes.
var _selected_trap: Node = null

# True while the panel is the reason the tree is paused, so close knows to unpause.
var _panel_paused: bool = false

# Drag placement state — press starts, drag extends a line of ghost traps,
# release commits them in order; right-click cancels without placing.
var _pressing: bool = false
var _drag_origin: Vector2i = Vector2i(-1, -1)
var _drag_anchors: Array[Vector2i] = []
var _drag_ghosts: Array[Node3D] = []

# A single ghost of the selected trap shown at the hover position before pressing.
# Rebuilt when trap type changes; repositioned on every cursor move.
var _hover_preview:      Node3D = null
var _hover_preview_type: int    = -1

# Reference to the playtest setup dialog while it is open; null after it confirms.
var _debug_dialog: Node = null

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
	# Grid is 31×31 (odd) so row 15 is the exact vertical centre — both gaps
	# land there, spanning rows 14–16 (3 rows each).
	var entrance := Vector2i(0, 15)
	var exit     := Vector2i(30, 15)

	_spawn_cell   = Vector2i(entrance.x - 1, entrance.y)
	_despawn_cell = Vector2i(exit.x + 1, exit.y)

	# Three rows the enemy may enter from; gap is centred on the canonical row.
	for i in range(3):
		_entrance_rows.append(entrance.y - 1 + i)   # [14, 15, 16]

	# Mark the centre entrance/exit cells first, then the one flanking cell on each side.
	# Done before pathfinder.initialize() so cell_changed isn't connected yet
	# and won't fire premature recalculations.
	_grid.setup_run(entrance, exit)
	_grid.set_cell(Vector2i(entrance.x, entrance.y - 1), Grid.CellState.ENTRANCE)
	_grid.set_cell(Vector2i(entrance.x, entrance.y + 1), Grid.CellState.ENTRANCE)
	_grid.set_cell(Vector2i(exit.x, exit.y - 1), Grid.CellState.EXIT)
	_grid.set_cell(Vector2i(exit.x, exit.y + 1), Grid.CellState.EXIT)

	# Mark all non-gap cells in the left and right border columns as WALL.
	# The wall sits on the arena floor (columns 0 and 30); the gap rows are the
	# only passable openings in those columns.
	var ent_gap := [entrance.y - 1, entrance.y, entrance.y + 1]
	var ex_gap  := [exit.y - 1, exit.y, exit.y + 1]
	for row in range(Grid.GRID_SIZE):
		if row not in ent_gap:
			_grid.set_cell(Vector2i(entrance.x, row), Grid.CellState.WALL)
		if row not in ex_gap:
			_grid.set_cell(Vector2i(exit.x, row), Grid.CellState.WALL)

	# Mark the top and bottom border rows (0 and GRID_SIZE-1) as WALL for all
	# interior columns. Geometry placed outside the grid at z = ±15.5 consistently
	# failed to render regardless of mesh type, so walls are placed on the outermost
	# grid rows instead — symmetric with the left/right approach using columns 0/30.
	# Columns 0 and GRID_SIZE-1 are already WALL from the column loop above.
	for col in range(1, Grid.GRID_SIZE - 1):
		_grid.set_cell(Vector2i(col, 0),                   Grid.CellState.WALL)
		_grid.set_cell(Vector2i(col, Grid.GRID_SIZE - 1),  Grid.CellState.WALL)

	GameState.start_run(entrance, exit)
	_pathfinder.initialize(_grid)
	_pathfinder.path_updated.connect(_on_path_updated)

	# Spawn one elongated marker covering all 3 rows for entrance and exit.
	_spawn_zone_marker(_spawn_cell,   3, COLOR_ENTRANCE, true)
	_spawn_zone_marker(_despawn_cell, 3, COLOR_EXIT,     true)

	_setup_grid_highlight()
	_setup_selected_trap_outline()
	_init_path_marker_pool()
	_spawn_arena_border()

	get_viewport().physics_object_picking = true

	_pathfinder.recalculate()
	add_child(HUD.new())
	GameState.wave_skip_requested.connect(_on_wave_skip_requested)
	GameState.run_ended.connect(_close_upgrade_panel)
	GameState.trap_type_selected.connect(_on_trap_type_changed)

	# Size the camera to fit the arena inside the non-HUD portion of the screen,
	# and re-fit whenever the window is resized.
	_fit_camera_to_grid()
	get_viewport().size_changed.connect(_fit_camera_to_grid)

	# Show the playtest setup dialog before starting the first wave.
	var dialog := DebugStartDialog.new()
	dialog.confirmed.connect(_on_debug_confirmed)
	add_child(dialog)
	_debug_dialog = dialog


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

## _input fires for every event, even those already consumed by GUI controls.
## We use it only to suppress the reticle when the mouse is over the dialog,
## because the dialog's Control nodes consume mouse-motion events before
## _unhandled_input can see them, leaving the reticle frozen.
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion):
		return
	if _debug_dialog == null or not is_instance_valid(_debug_dialog):
		return
	if not (_debug_dialog as DebugStartDialog).covers_point(event.position):
		return
	_hover_cell = Vector2i(-1, -1)
	_grid_highlight.mesh = null
	_hide_hover_preview()


func _unhandled_input(event: InputEvent) -> void:
	# Mouse motion always updates the reticle — even while paused — so the hover
	# preview stays live during the debug dialog, upgrade panel, or player pause.
	if event is InputEventMouseMotion:
		var cell := _screen_to_grid(event.position)
		if cell != _hover_cell:
			_hover_cell = cell
			_update_grid_highlight()
			if _pressing and not get_tree().paused:
				_update_drag_ghosts(cell)
		return

	# All placement and removal actions are blocked while the tree is paused.
	if get_tree().paused:
		return

	# Mobile: a second finger tap while dragging cancels the placement.
	if event is InputEventScreenTouch:
		if event.pressed and event.index > 0 and _pressing:
			_cancel_drag_placement()
		return

	if event is InputEventKey:
		if event.pressed and not event.echo:
			_handle_key(event.keycode)
		return

	if not event is InputEventMouseButton:
		return

	var cell := _screen_to_grid(event.position)

	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				if _is_in_arena(cell):
					if _trap_anchors.has(cell):
						# Tapping a placed trap opens the upgrade panel for it.
						_open_upgrade_panel(_trap_anchors[cell])
					else:
						_close_upgrade_panel()
						_start_drag_placement(cell)
			else:
				if _pressing:
					_commit_drag_placement()
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if _pressing:
					_cancel_drag_placement()
				else:
					_try_remove_trap(cell)


# ---------------------------------------------------------------------------
# Drag placement
# ---------------------------------------------------------------------------

## Called on press. Records the origin and immediately shows the first ghost.
func _start_drag_placement(cell: Vector2i) -> void:
	_hide_hover_preview()
	_pressing    = true
	_drag_origin = _clamp_to_anchor(cell)
	_update_drag_ghosts(cell)


## Rebuilds the ghost line from origin to the current cursor cell.
## Only cells that are individually buildable get a ghost — ghosts at
## positions blocked by existing traps or walls are silently skipped.
func _update_drag_ghosts(target: Vector2i) -> void:
	_clear_drag_ghosts()
	_drag_anchors = _compute_drag_anchors(_drag_origin, _clamp_to_anchor(target))
	for anchor in _drag_anchors:
		var cells := _get_trap_cells(anchor)
		if cells.is_empty():
			continue
		var buildable := true
		for cell in cells:
			if not _grid.is_buildable(cell):
				buildable = false
				break
		if not buildable:
			continue
		var ghost := _make_trap_preview(GameState.selected_trap_type, 0.45)
		var center := _cell_to_world(anchor) + Vector3(Grid.CELL_SIZE * 0.5, 0.0, Grid.CELL_SIZE * 0.5)
		ghost.position = center + Vector3(0.0, Grid.CELL_SIZE * 0.25, 0.0)
		_drag_ghosts.append(ghost)


## On release, commits anchors in order from origin to end.
## Stops at the first anchor that cannot be afforded or whose footprint
## overlaps an active enemy — that anchor and all after it are skipped.
## TODO: wire _can_afford_trap() to the currency system once it exists.
func _commit_drag_placement() -> void:
	_pressing = false
	_clear_drag_ghosts()
	for anchor in _drag_anchors:
		if not _can_afford_trap():
			break
		var cells := _get_trap_cells(anchor)
		if _footprint_overlaps_enemy(cells):
			break
		if not _try_place_trap(anchor):
			break
	_drag_anchors.clear()
	_drag_origin = Vector2i(-1, -1)


## Cancels the drag without placing any traps.
## Triggered by right-click (desktop) or second-finger tap (mobile).
func _cancel_drag_placement() -> void:
	_pressing = false
	_clear_drag_ghosts()
	_drag_anchors.clear()
	_drag_origin = Vector2i(-1, -1)


## Returns true if the player can afford one more trap of the currently selected type.
func _can_afford_trap() -> bool:
	return GameState.bug_bucks >= Trap.STATS[GameState.selected_trap_type]["cost"]


## Returns true if any active enemy's current or target cell falls inside
## the given footprint. Used to prevent placing a trap on top of a moving enemy.
func _footprint_overlaps_enemy(cells: Array[Vector2i]) -> bool:
	for enemy in _active_enemies:
		if enemy.get_current_cell() in cells:
			return true
		if enemy.get_target_cell() in cells:
			return true
	return false


## Returns a sequence of 2x2 trap anchor cells from origin toward target.
##
## Anchors step exactly 2 cells along the dominant axis per trap, with
## the minor axis scaled proportionally. This keeps consecutive 2x2
## footprints touching with no gaps. The last trap advances only once the
## cursor is far enough to fit another full footprint.
func _compute_drag_anchors(origin: Vector2i, target: Vector2i) -> Array[Vector2i]:
	var dir      := target - origin
	var dominant := maxi(abs(dir.x), abs(dir.y))

	if dominant == 0:
		return [origin]

	var n := dominant / 2 + 1

	var anchors: Array[Vector2i] = []
	for i in range(n):
		var t   := float(i * 2) / float(dominant)
		var pos := Vector2(origin) + Vector2(dir) * t
		anchors.append(Vector2i(roundi(pos.x), roundi(pos.y)))
	return anchors


## Frees all ghost nodes from the current drag line.
func _clear_drag_ghosts() -> void:
	for ghost in _drag_ghosts:
		ghost.queue_free()
	_drag_ghosts.clear()


func _try_place_trap(anchor: Vector2i) -> bool:
	anchor = _clamp_to_anchor(anchor)
	var cells := _get_trap_cells(anchor)
	if cells.is_empty():
		return false

	for cell in cells:
		if not _grid.is_buildable(cell):
			return false

	if not _can_place_at(cells):
		return false

	for cell in cells:
		_grid.place_trap(cell)
		_trap_anchors[cell] = anchor

	_spawn_trap(anchor)
	_draw_trap_outline(anchor)
	return true


func _try_remove_trap(cell: Vector2i) -> void:
	if not _trap_anchors.has(cell):
		return
	_close_upgrade_panel()

	var anchor: Vector2i = _trap_anchors[cell]

	if _trap_nodes.has(anchor):
		GameState.add_bug_bucks(int(_trap_nodes[anchor].get_cost() * 0.7))
		_trap_nodes[anchor].queue_free()
		_trap_nodes.erase(anchor)

	if _trap_outlines.has(anchor):
		_trap_outlines[anchor].queue_free()
		_trap_outlines.erase(anchor)
	if _hovered_trap_anchor == anchor:
		_hovered_trap_anchor = Vector2i(-1, -1)

	for c in _get_trap_cells(anchor):
		_grid.remove_trap(c)
		_trap_anchors.erase(c)


## Opens the upgrade panel for the trap at anchor, closing any existing panel first.
func _open_upgrade_panel(anchor: Vector2i) -> void:
	_close_upgrade_panel()
	if not _trap_nodes.has(anchor):
		return
	var panel := TrapUpgradePanel.new()
	panel.closed.connect(_on_upgrade_panel_closed)
	add_child(panel)
	panel.initialize(_trap_nodes[anchor])
	_upgrade_panel  = panel
	_selected_trap  = _trap_nodes[anchor]
	_selected_trap.show_range_indicator()
	_show_selected_trap_outline(anchor)
	_selected_trap_anchor = anchor
	if _trap_outlines.has(anchor):
		_draw_trap_outline(anchor)
	get_tree().paused = true
	_panel_paused = true


## Closes and frees the upgrade panel if one is open, then unpauses if we paused.
func _close_upgrade_panel() -> void:
	if _upgrade_panel != null and is_instance_valid(_upgrade_panel):
		_upgrade_panel.queue_free()
	_upgrade_panel = null
	if _selected_trap != null and is_instance_valid(_selected_trap):
		_selected_trap.hide_range_indicator()
	_selected_trap = null
	_hide_selected_trap_outline()
	var prev_selected := _selected_trap_anchor
	_selected_trap_anchor = Vector2i(-1, -1)
	if _trap_outlines.has(prev_selected):
		_draw_trap_outline(prev_selected)
	if _panel_paused:
		get_tree().paused = false
		_panel_paused = false


func _on_upgrade_panel_closed() -> void:
	_upgrade_panel = null
	if _selected_trap != null and is_instance_valid(_selected_trap):
		_selected_trap.hide_range_indicator()
	_selected_trap = null
	_hide_selected_trap_outline()
	var prev_selected := _selected_trap_anchor
	_selected_trap_anchor = Vector2i(-1, -1)
	if _trap_outlines.has(prev_selected):
		_draw_trap_outline(prev_selected)
	if _panel_paused:
		get_tree().paused = false
		_panel_paused = false


## Returns true if the given cells can be trapped without sealing either gap.
## Requires at least one entrance row and one exit row to remain passable,
## and a path connecting them to still exist.
func _can_place_at(cells: Array[Vector2i]) -> bool:
	var ent_x := GameState.entrance_cell.x
	var ex_x  := GameState.exit_cell.x

	var open_ent: Array[Vector2i] = []
	for row in _entrance_rows:
		var c := Vector2i(ent_x, row)
		if not (c in cells) and _grid.is_passable(c):
			open_ent.append(c)

	if open_ent.is_empty():
		return false

	var ex_rows := [GameState.exit_cell.y - 1, GameState.exit_cell.y, GameState.exit_cell.y + 1]
	var open_ex: Array[Vector2i] = []
	for row in ex_rows:
		var c := Vector2i(ex_x, row)
		if not (c in cells) and _grid.is_passable(c):
			open_ex.append(c)

	if open_ex.is_empty():
		return false

	for ent in open_ent:
		for ex in open_ex:
			if _pathfinder.can_reach(ent, ex, cells):
				return true
	return false


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_path_updated(new_path: Array[Vector2i]) -> void:
	_display_path = new_path
	if new_path.is_empty():
		_redraw_path_display()
		return
	var best_exit: Vector2i = new_path.back()
	for enemy in _active_enemies:
		var current: Vector2i = enemy.get_current_cell()
		# If the enemy is still in the outside approach cell, A* must start
		# from the entrance (first in-bounds cell) to stay within the grid.
		var from: Vector2i = current if _grid.is_in_bounds(current) else GameState.entrance_cell
		var grid_path := _pathfinder.find_path_from(from, best_exit)
		if grid_path.is_empty():
			continue
		var full: Array[Vector2i] = []
		if not _grid.is_in_bounds(current):
			full = _build_full_path(grid_path, current.y)
		else:
			var exit_row: int = grid_path.back().y
			var despawn  := Vector2i(_despawn_cell.x, exit_row)
			full.append_array(grid_path)
			full.append(despawn)
		enemy.update_path(full)
		_display_path = grid_path
	_redraw_path_display()


## Redraws the yellow path markers starting from the active enemy's current
## target cell, so the line only appears ahead of the enemy.
## Falls back to the full display path when no enemies are active.
## Does nothing when SHOW_PATH_LINE is false — all markers stay hidden.
func _redraw_path_display() -> void:
	if not SHOW_PATH_LINE:
		for marker in _path_marker_pool:
			marker.visible = false
		return

	var start_idx := 0
	if not _active_enemies.is_empty():
		var target: Vector2i = _active_enemies[0].get_target_cell()
		var idx    := _display_path.find(target)
		if idx >= 0:
			start_idx = idx
	var pool_idx := 0
	for i in range(start_idx, _display_path.size()):
		var cell  := _display_path[i]
		var state := _grid.get_cell(cell)
		if state == Grid.CellState.EMPTY \
				or state == Grid.CellState.ENTRANCE \
				or state == Grid.CellState.EXIT:
			if pool_idx < PATH_MARKER_POOL_SIZE:
				var marker := _path_marker_pool[pool_idx]
				marker.position = _cell_to_world(cell)
				marker.visible = true
				pool_idx += 1
	for i in range(pool_idx, PATH_MARKER_POOL_SIZE):
		_path_marker_pool[i].visible = false


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

	# Register before adding to tree so signals are connected before
	# _ready fires on the enemy node.
	_active_enemies.append(enemy)
	enemy.reached_exit.connect(_on_enemy_reached_exit.bind(enemy))
	enemy.died.connect(_on_enemy_died.bind(enemy))
	enemy.cell_advanced.connect(_redraw_path_display)

	add_child(enemy)
	enemy.initialize(path, Enemy.EnemyType.ANT, GameState.current_wave)


func _on_enemy_reached_exit(enemy: Node3D) -> void:
	GameState.add_infestation(enemy.get_infestation_damage())
	_active_enemies.erase(enemy)
	# enemy.queue_free() is called inside Enemy.gd — no double-free needed.

	if _active_enemies.is_empty() and _enemies_left_to_spawn == 0:
		_start_wave()


func _on_enemy_died(enemy: Node3D) -> void:
	GameState.add_bug_bucks(enemy.get_bounty())
	_active_enemies.erase(enemy)
	# enemy.queue_free() is called inside Enemy._die() after the flash tween.

	if _active_enemies.is_empty() and _enemies_left_to_spawn == 0:
		_start_wave()


## Increments the wave counter and begins the between-wave countdown.
func _start_wave() -> void:
	GameState.current_wave += 1
	_countdown_active = true
	GameState.set_countdown(WAVE_COUNTDOWN)
	get_tree().create_timer(1.0).timeout.connect(_on_countdown_tick.bind(WAVE_COUNTDOWN - 1))


## Called once per second during the countdown. Fires the wave when it reaches 0.
func _on_countdown_tick(seconds_remaining: int) -> void:
	if not _countdown_active:
		return
	GameState.set_countdown(seconds_remaining)
	if seconds_remaining > 0:
		get_tree().create_timer(1.0).timeout.connect(_on_countdown_tick.bind(seconds_remaining - 1))
	else:
		_countdown_active = false
		_launch_wave()


func _handle_key(_keycode: int) -> void:
	pass


## Receives the confirmed playtest values from DebugStartDialog and starts the run.
func _on_debug_confirmed(bug_bucks: int, wave_size: int) -> void:
	_wave_size = wave_size
	GameState.bug_bucks = bug_bucks
	GameState.bug_bucks_changed.emit(bug_bucks)
	_start_wave()


## Clears the hover preview whenever the selected trap type changes so the
## next cursor move spawns a fresh ghost matching the new selection.
func _on_trap_type_changed(_type: int) -> void:
	if _hover_preview != null and is_instance_valid(_hover_preview):
		_hover_preview.queue_free()
	_hover_preview      = null
	_hover_preview_type = -1


## Skips any active countdown and starts the wave immediately.
## Triggered by the "Send Wave Early" HUD button via GameState.wave_skip_requested.
func _on_wave_skip_requested() -> void:
	if _countdown_active:
		_countdown_active = false
		GameState.set_countdown(0)
		_launch_wave()


## Begins spawning WAVE_SIZE enemies, one every SPAWN_INTERVAL seconds.
func _launch_wave() -> void:
	_enemies_left_to_spawn = _wave_size
	get_tree().create_timer(SPAWN_INTERVAL).timeout.connect(_spawn_next_in_wave)


## Spawns one enemy then schedules the next, until the wave is exhausted.
## Picks randomly from entrance rows that are currently open (not trapped).
func _spawn_next_in_wave() -> void:
	if _enemies_left_to_spawn <= 0:
		return
	_enemies_left_to_spawn -= 1

	var open_rows: Array[int] = []
	for row in _entrance_rows:
		if _grid.is_passable(Vector2i(GameState.entrance_cell.x, row)):
			open_rows.append(row)
	if open_rows.is_empty():
		open_rows = _entrance_rows  # fallback: should never happen if can_place_at is correct

	var spawn_row: int  = open_rows[randi() % open_rows.size()]
	var spawn_grid      := Vector2i(GameState.entrance_cell.x, spawn_row)
	var grid_path       := _find_shortest_exit_path(spawn_grid)
	if grid_path.is_empty():
		grid_path = _pathfinder.get_current_path()
	if not grid_path.is_empty():
		_spawn_enemy(_build_full_path(grid_path, spawn_row))
	if _enemies_left_to_spawn > 0:
		get_tree().create_timer(SPAWN_INTERVAL).timeout.connect(_spawn_next_in_wave)


## Runs A* from start to each of the three exit-gap cells and returns
## the shortest result. Returns empty if none of the three are reachable.
func _find_shortest_exit_path(start: Vector2i) -> Array[Vector2i]:
	var exit_x := GameState.exit_cell.x
	var exit_y := GameState.exit_cell.y
	var shortest: Array[Vector2i] = []
	for row in [exit_y - 1, exit_y, exit_y + 1]:
		var path := _pathfinder.find_path_from(start, Vector2i(exit_x, row))
		if path.is_empty():
			continue
		if shortest.is_empty() or path.size() < shortest.size():
			shortest = path
	return shortest


## Builds the full enemy path: outside spawn → grid (entrance gap first) → outside despawn.
## spawn_row selects which entrance row this enemy uses.
## The exit row is derived from the last cell of grid_path (the nearest exit opening).
## The entrance and exit gap cells are part of the grid path, so no separate wall steps.
func _build_full_path(grid_path: Array[Vector2i], spawn_row: int) -> Array[Vector2i]:
	var outside_spawn := Vector2i(_spawn_cell.x, spawn_row)
	var exit_row: int = grid_path.back().y
	var despawn       := Vector2i(_despawn_cell.x, exit_row)
	var full: Array[Vector2i] = [outside_spawn]
	full.append_array(grid_path)
	full.append(despawn)
	return full


# ---------------------------------------------------------------------------
# Grid highlight
# ---------------------------------------------------------------------------

## Pre-creates PATH_MARKER_POOL_SIZE path marker nodes, all hidden.
## _redraw_path_display repositions and shows/hides them in place of
## freeing and re-creating nodes on every update.
func _init_path_marker_pool() -> void:
	for i in range(PATH_MARKER_POOL_SIZE):
		var marker := _make_box_mesh_instance(
			Vector3(Grid.CELL_SIZE * 0.9, 0.05, Grid.CELL_SIZE * 0.9),
			COLOR_PATH
		)
		marker.visible = false
		_path_visual.add_child(marker)
		_path_marker_pool.append(marker)


## Creates the MeshInstance3D used for the selected-trap gold outline.
## The mesh is rebuilt each time a panel opens and cleared when it closes.
func _setup_selected_trap_outline() -> void:
	_selected_trap_outline = MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	_selected_trap_outline.material_override = mat
	add_child(_selected_trap_outline)


## Draws a gold perimeter around the 2×2 footprint of the trap at anchor.
## Three concentric rectangles simulate line thickness (Godot 4 has no 3D line width).
func _show_selected_trap_outline(anchor: Vector2i) -> void:
	var im  := ImmediateMesh.new()
	var hs  := Grid.CELL_SIZE * 0.5
	var y   := 0.12   # slightly above the cursor glow layer (0.08)
	var c   := _cell_to_world(anchor)
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for e: float in [-Grid.CELL_SIZE * 0.03, 0.0, Grid.CELL_SIZE * 0.03]:
		var tl := Vector3(c.x - hs - e,                  y, c.z - hs - e)
		var tr := Vector3(c.x + hs + Grid.CELL_SIZE + e, y, c.z - hs - e)
		var bl := Vector3(c.x - hs - e,                  y, c.z + hs + Grid.CELL_SIZE + e)
		var br := Vector3(c.x + hs + Grid.CELL_SIZE + e, y, c.z + hs + Grid.CELL_SIZE + e)
		im.surface_set_color(COLOR_TRAP_SELECTED); im.surface_add_vertex(tl)
		im.surface_set_color(COLOR_TRAP_SELECTED); im.surface_add_vertex(tr)
		im.surface_set_color(COLOR_TRAP_SELECTED); im.surface_add_vertex(tr)
		im.surface_set_color(COLOR_TRAP_SELECTED); im.surface_add_vertex(br)
		im.surface_set_color(COLOR_TRAP_SELECTED); im.surface_add_vertex(br)
		im.surface_set_color(COLOR_TRAP_SELECTED); im.surface_add_vertex(bl)
		im.surface_set_color(COLOR_TRAP_SELECTED); im.surface_add_vertex(bl)
		im.surface_set_color(COLOR_TRAP_SELECTED); im.surface_add_vertex(tl)
	im.surface_end()
	_selected_trap_outline.mesh = im


## Clears the selected-trap outline by removing its mesh.
func _hide_selected_trap_outline() -> void:
	if _selected_trap_outline != null:
		_selected_trap_outline.mesh = null


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


## Returns the anchor cell clamped so its 2x2 footprint stays fully in bounds.
## Clicking on the last column or row would otherwise produce an OOB footprint.
func _clamp_to_anchor(cell: Vector2i) -> Vector2i:
	return Vector2i(
		clampi(cell.x, 0, Grid.GRID_SIZE - 2),
		clampi(cell.y, 0, Grid.GRID_SIZE - 2)
	)




## Returns true when a cell is within the arena, defined as the 31x31 floor
## plus the 1-cell-wide wall border surrounding it (x: -1..31, y: -1..31).
## Cells beyond that boundary are outside the arena entirely.
func _is_in_arena(cell: Vector2i) -> bool:
	return cell.x >= -1 and cell.x <= Grid.GRID_SIZE \
		and cell.y >= -1 and cell.y <= Grid.GRID_SIZE


## Rebuilds the grid glow mesh for the current hover cell.
## Each cell's alpha is derived from its Manhattan distance to the nearest
## cell in the 2x2 footprint — cells right against the trap are brightest,
## fading smoothly outward for up to MAX_GLOW_DIST cells.
##
## The reticle always draws at the clamped anchor — the same position that
## placement will use if the player clicks now — so the visual is always
## consistent with what will happen.
##
## Visibility rules:
##   Cursor outside the arena border (x/y beyond ±1 of grid edge) → hidden
##   Footprint contains a TRAP or OBSTACLE                         → 20% opacity
##   Footprint is clear (EMPTY / ENTRANCE / EXIT only)             → 100% opacity
func _update_grid_highlight() -> void:
	if not _is_in_arena(_hover_cell):
		_grid_highlight.mesh = null
		_hide_hover_preview()
		return

	var anchor := _clamp_to_anchor(_hover_cell)

	# Swap trap outline between neutral and neon as the cursor enters/leaves footprints.
	var new_hovered: Vector2i = Vector2i(-1, -1)
	if _trap_anchors.has(_hover_cell):
		new_hovered = _trap_anchors[_hover_cell]
	if new_hovered != _hovered_trap_anchor:
		var prev_hovered := _hovered_trap_anchor
		_hovered_trap_anchor = new_hovered   # update before drawing so state checks are correct
		if prev_hovered != Vector2i(-1, -1) and _trap_outlines.has(prev_hovered):
			_draw_trap_outline(prev_hovered)
		if new_hovered != Vector2i(-1, -1) and _trap_outlines.has(new_hovered):
			_draw_trap_outline(new_hovered)

	# Show a ghost of the selected trap at the anchor before pressing.
	# During drag, the drag ghosts serve this role instead.
	if not _pressing:
		_update_hover_preview(anchor)
	else:
		_hide_hover_preview()

	var blocked := false
	for dr in range(2):
		if blocked:
			break
		for dc in range(2):
			var s := _grid.get_cell(Vector2i(anchor.x + dc, anchor.y + dr))
			if s == Grid.CellState.TRAP or s == Grid.CellState.OBSTACLE or s == Grid.CellState.WALL:
				blocked = true
				break

	var opacity_scale := 0.2 if blocked else 1.0
	const MAX_GLOW_DIST: int = 2

	var im := ImmediateMesh.new()
	var hs := Grid.CELL_SIZE * 0.5
	var y  := 0.08

	im.surface_begin(Mesh.PRIMITIVE_LINES)

	for dr in range(-MAX_GLOW_DIST, 2 + MAX_GLOW_DIST):
		for dc in range(-MAX_GLOW_DIST, 2 + MAX_GLOW_DIST):
			var cell := Vector2i(anchor.x + dc, anchor.y + dr)
			if not _grid.is_in_bounds(cell):
				continue
			var dist := _dist_to_footprint(cell, anchor)
			if dist == 0 or dist > MAX_GLOW_DIST:
				continue
			var alpha := 0.56 * opacity_scale * pow(1.0 - float(dist) / float(MAX_GLOW_DIST + 1), 2.5)
			_draw_cell_glow(im, cell, hs, y, alpha)

	if not _pressing:
		_draw_2x2_perimeter(im, anchor, hs, y, 0.56 * opacity_scale)

	im.surface_end()
	_grid_highlight.mesh = im


## Returns the Manhattan distance from cell to the nearest cell in the
## 2x2 footprint anchored at anchor (top-left). Returns 0 if cell is
## inside the footprint.
func _dist_to_footprint(cell: Vector2i, anchor: Vector2i) -> int:
	var dx := maxi(0, maxi(anchor.x - cell.x, cell.x - (anchor.x + 1)))
	var dy := maxi(0, maxi(anchor.y - cell.y, cell.y - (anchor.y + 1)))
	return dx + dy


## Returns an electric neon version of the given color: same hue, full saturation,
## full brightness. Brown becomes electric orange; tan becomes electric yellow; etc.
func _neon_color(base: Color) -> Color:
	return Color.from_hsv(base.h, 1.0, 1.0)


## Draws (or redraws) the outline + colour fill for a placed trap.
## Glow state is derived from _hovered_trap_anchor / _selected_trap_anchor:
##   selected → brighter outline;  hovered → medium;  default → base.
##
## Surface 0 — neon glow fill (TRIANGLES): two-ring triangle fan.
##   Interior (center → FILL_SOLID_FRAC) is flat at fill_opaque alpha.
##   Narrow outer band fades from fill_opaque to transparent so the glow
##   hugs the sprite and drops off quickly near the outline.
## Surface 1 — rounded outline (LINES): two concentric inset rounded-corner
##   rectangles simulate ~2 px line width.
func _draw_trap_outline(anchor: Vector2i) -> void:
	var trap_type: int = _trap_nodes[anchor].get_type()
	var base: Color    = Trap.STATS[trap_type]["color"]
	var neon: Color    = _neon_color(base)

	# Gradient fades to transparent at this fraction of center→outline distance.
	# 0.88 leaves a ~12% transparent band before the outline (a few pixels at mobile scale).
	const FADE_END_FRAC: float = 0.88

	var is_selected := anchor == _selected_trap_anchor
	var is_hovered  := anchor == _hovered_trap_anchor

	var outline_color: Color
	var fill_center:   Color   # peak opacity at the center vertex
	var fill_clear:    Color   # zero opacity at the fade ring
	if is_selected:
		outline_color = base.lightened(0.70); outline_color.a = 1.0
		fill_center   = neon; fill_center.a   = 0.90
		fill_clear    = neon; fill_clear.a    = 0.0
	elif is_hovered:
		outline_color = base.lightened(0.45); outline_color.a = 1.0
		fill_center   = neon; fill_center.a   = 0.80
		fill_clear    = neon; fill_clear.a    = 0.0
	else:
		outline_color = base.darkened(0.2);   outline_color.a = 0.60
		fill_center   = neon; fill_center.a   = 0.70
		fill_clear    = neon; fill_clear.a    = 0.0

	var hs := Grid.CELL_SIZE * 0.5
	var cs := Grid.CELL_SIZE
	var c  := _cell_to_world(anchor)

	var min_x := c.x - hs;       var max_x := c.x + hs + cs
	var min_z := c.z - hs;       var max_z := c.z + hs + cs
	var cx    := (min_x + max_x) * 0.5
	var cz    := (min_z + max_z) * 0.5

	const CORNER_R:    float = 0.15   # world-unit corner radius (~15% of one cell)
	const CORNER_SEGS: int   = 5      # arc segments per corner; 5 gives smooth top-down look

	var y_fill    := 0.03   # below the outline so the border draws on top
	var y_outline := 0.06   # above floor; below cursor glow (0.08)

	var im := ImmediateMesh.new()

	# --- Surface 0: neon radial glow (center → fade ring) ---
	var fill_pts := _rounded_rect_pts(min_x, max_x, min_z, max_z, y_fill, CORNER_R, CORNER_SEGS)
	var center   := Vector3(cx, y_fill, cz)

	# Fade ring — the gradient reaches full transparency here, well inside the outline.
	var fade_pts: Array[Vector3] = []
	for pt: Vector3 in fill_pts:
		fade_pts.append(center.lerp(pt, FADE_END_FRAC))

	var n := fill_pts.size()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# Single pass: center (peak opacity) → fade ring (transparent).
	# The fill_clear vertices at the ring ensure nothing renders between the ring and outline.
	for i in range(n):
		var a: Vector3 = fade_pts[i]
		var b: Vector3 = fade_pts[(i + 1) % n]
		im.surface_set_color(fill_center); im.surface_add_vertex(center)
		im.surface_set_color(fill_clear);  im.surface_add_vertex(a)
		im.surface_set_color(fill_clear);  im.surface_add_vertex(b)
	im.surface_end()

	# --- Surface 1: rounded outline (two inset passes for ~2 px thickness) ---
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for inset: float in [0.04, 0.08]:
		var r: float = maxf(CORNER_R - inset, 0.0)
		var pts := _rounded_rect_pts(
			min_x + inset, max_x - inset,
			min_z + inset, max_z - inset,
			y_outline, r, CORNER_SEGS
		)
		for i in range(pts.size()):
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[(i + 1) % pts.size()]
			im.surface_set_color(outline_color); im.surface_add_vertex(a)
			im.surface_set_color(outline_color); im.surface_add_vertex(b)
	im.surface_end()

	if _trap_outlines.has(anchor):
		_trap_outlines[anchor].mesh = im
	else:
		var mi  := MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		# Disable back-face culling so the fill quad is visible regardless of winding.
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat
		add_child(mi)
		mi.mesh = im
		_trap_outlines[anchor] = mi


## Returns perimeter points for a rounded rectangle in the XZ plane, traversed
## clockwise from above.  Each of the four corners has CORNER_SEGS+1 points
## (including both tangent endpoints), so the total count is (segs+1)*4.
## The segment between the last point of one corner and the first of the next
## naturally forms the straight edge connecting them.
##
## Corner angles (atan2(dz, dx) in XZ plane, +Z = screen-down):
##   TL: π → 3π/2   TR: 3π/2 → 2π   BR: 0 → π/2   BL: π/2 → π
func _rounded_rect_pts(min_x: float, max_x: float, min_z: float, max_z: float,
		y: float, r: float, segs: int) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	# Flat float array avoids Variant-typed inner arrays: [cx, cz, a0, a1] × 4 corners.
	var corners: Array[float] = [
		min_x + r, min_z + r, PI,           1.5 * PI,
		max_x - r, min_z + r, 1.5 * PI,     2.0 * PI,
		max_x - r, max_z - r, 0.0,          0.5 * PI,
		min_x + r, max_z - r, 0.5 * PI,     PI,
	]
	for ci in range(4):
		var ccx: float = corners[ci * 4]
		var ccz: float = corners[ci * 4 + 1]
		var a0:  float = corners[ci * 4 + 2]
		var a1:  float = corners[ci * 4 + 3]
		for i in range(segs + 1):
			var t: float = float(i) / float(segs)
			var a: float = lerpf(a0, a1, t)
			pts.append(Vector3(ccx + cos(a) * r, y, ccz + sin(a) * r))
	return pts


## Draws the outer perimeter of the 2x2 footprint as two concentric rectangles.
## Godot 4 has no 3D line-width API; inner + outer rects simulate doubled width.
func _draw_2x2_perimeter(im: ImmediateMesh, anchor: Vector2i, hs: float, y: float, alpha: float) -> void:
	var color   := Color(COLOR_GRID_GLOW.r, COLOR_GRID_GLOW.g, COLOR_GRID_GLOW.b, alpha)
	var expand  := Grid.CELL_SIZE * 0.025
	var c       := _cell_to_world(anchor)
	for e: float in [-expand, expand]:
		var tl := Vector3(c.x - hs - e,                  y, c.z - hs - e)
		var tr := Vector3(c.x + hs + Grid.CELL_SIZE + e, y, c.z - hs - e)
		var bl := Vector3(c.x - hs - e,                  y, c.z + hs + Grid.CELL_SIZE + e)
		var br := Vector3(c.x + hs + Grid.CELL_SIZE + e, y, c.z + hs + Grid.CELL_SIZE + e)
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
# Visual helpers — Phase 1 placeholder geometry
# ---------------------------------------------------------------------------

## Draws the arena border as 1-cell-wide light gray slabs with dark gray cell
## border lines, giving a stone-block appearance.
##
## All four walls sit on the outermost rows/columns of the 31×31 grid:
##   Top/bottom — rows 0 and 30 (z = ±15.0)
##   Left/right — columns 0 and 30 (x = ±15.0, with entrance/exit gaps)
##
## Placing geometry outside the grid boundary (z = ±15.5) consistently failed
## to render regardless of mesh type across multiple attempts. Using the
## outermost grid rows is symmetric with the column approach and renders reliably.
func _spawn_arena_border() -> void:
	var half := (Grid.GRID_SIZE * Grid.CELL_SIZE) / 2.0
	var cs   := Grid.CELL_SIZE

	var ent_top := (GameState.entrance_cell.y - 1) * cs - half
	var ent_bot := (GameState.entrance_cell.y + 2) * cs - half
	var ex_top  := (GameState.exit_cell.y - 1) * cs - half
	var ex_bot  := (GameState.exit_cell.y  + 2) * cs - half

	# --- Fill slabs ---
	# Top row (row 0) and bottom row (row 30) — full grid width
	var grid_w := Grid.GRID_SIZE * cs
	_spawn_wall_slab(Vector3(0.0, 0.0, -half + cs * 0.5), Vector2(grid_w, cs))
	_spawn_wall_slab(Vector3(0.0, 0.0,  half - cs * 0.5), Vector2(grid_w, cs))

	# Left column (column 0) above and below the entrance gap.
	# Heights exclude rows 0 and 30, which belong exclusively to the top/bottom slabs.
	var lup  := ent_top - (-half + cs)
	var lbot := (half - cs) - ent_bot
	if lup  > 0.0: _spawn_wall_slab(Vector3(-half + cs * 0.5, 0.0, (-half + cs) + lup  * 0.5), Vector2(cs, lup))
	if lbot > 0.0: _spawn_wall_slab(Vector3(-half + cs * 0.5, 0.0,  ent_bot      + lbot * 0.5), Vector2(cs, lbot))

	# Right column (column 30) above and below the exit gap.
	var rup  := ex_top - (-half + cs)
	var rbot := (half - cs) - ex_bot
	if rup  > 0.0: _spawn_wall_slab(Vector3( half - cs * 0.5, 0.0, (-half + cs) + rup  * 0.5), Vector2(cs, rup))
	if rbot > 0.0: _spawn_wall_slab(Vector3( half - cs * 0.5, 0.0,  ex_bot      + rbot * 0.5), Vector2(cs, rbot))

	# --- Cell border lines for all wall cells ---
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)

	_draw_wall_cell_borders(im, -half, half,       -half,      -half + cs)  # top row
	_draw_wall_cell_borders(im, -half, half,        half - cs,  half)       # bottom row
	if lup  > 0.0: _draw_wall_cell_borders(im, -half, -half + cs, -half + cs, ent_top)
	if lbot > 0.0: _draw_wall_cell_borders(im, -half, -half + cs,  ent_bot,   half - cs)
	if rup  > 0.0: _draw_wall_cell_borders(im,  half - cs, half,  -half + cs, ex_top)
	if rbot > 0.0: _draw_wall_cell_borders(im,  half - cs, half,   ex_bot,    half - cs)

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


## Creates one flat wall fill slab using a PlaneMesh (single upward-facing face,
## no depth) to guarantee the fill colour renders cleanly regardless of slab width.
func _spawn_wall_slab(center: Vector3, size: Vector2) -> void:
	var mi    := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	mi.mesh   = plane
	var mat              := StandardMaterial3D.new()
	mat.albedo_color      = COLOR_WALL_FILL
	mat.shading_mode      = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency      = BaseMaterial3D.TRANSPARENCY_DISABLED
	mi.material_override  = mat
	mi.position           = Vector3(center.x, 0.025, center.z)
	add_child(mi)


## Spawns an entrance or exit zone marker: a muted-colour slab spanning `rows`
## cells tall, with a dark directional triangle on top indicating pest flow.
## Pass arrow_right = true when enemies travel in the +X direction (left→right).
func _spawn_zone_marker(center_cell: Vector2i, rows: int, color: Color, arrow_right: bool) -> void:
	var marker := _make_box_mesh_instance(
		Vector3(Grid.CELL_SIZE * 0.9, 0.05, Grid.CELL_SIZE * rows * 0.9),
		color
	)
	marker.position = _cell_to_world(center_cell)
	add_child(marker)

	# Filled triangle drawn just above the slab surface, lying flat in the XZ
	# plane. The tip points in the direction pests are travelling — +X for a
	# right-pointing arrow, −X for left. Both entrance and exit point right
	# because enemies always travel left to right on the default layout.
	var c      := _cell_to_world(center_cell)
	var sign_x := 1.0 if arrow_right else -1.0
	var half_z := Grid.CELL_SIZE * float(rows) * 0.40   # base half-height (~80% of zone height)
	var tip_x  := c.x + sign_x * Grid.CELL_SIZE * 0.30  # tip: 30% of a cell ahead of centre
	var base_x := c.x - sign_x * Grid.CELL_SIZE * 0.26  # base: 26% of a cell behind centre
	var y      := 0.06                                   # just above the slab top (slab top ≈ 0.025)

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	im.surface_set_color(Color(0.05, 0.05, 0.05, 1.0))
	im.surface_add_vertex(Vector3(base_x, y, c.z - half_z))
	im.surface_add_vertex(Vector3(tip_x,  y, c.z))
	im.surface_add_vertex(Vector3(base_x, y, c.z + half_z))
	im.surface_end()

	var arrow     := MeshInstance3D.new()
	arrow.mesh     = im
	var mat       := StandardMaterial3D.new()
	mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode                  = BaseMaterial3D.CULL_DISABLED  # visible from top-down
	arrow.material_override = mat
	add_child(arrow)


## Spawns a Trap node centred on the 2x2 footprint and wires it to the
## active enemy list. The trap manages its own visual and combat logic.
func _spawn_trap(anchor: Vector2i) -> void:
	var trap := Trap.new()
	var center := _cell_to_world(anchor) + Vector3(Grid.CELL_SIZE * 0.5, 0.0, Grid.CELL_SIZE * 0.5)
	trap.position = center + Vector3(0.0, Grid.CELL_SIZE * 0.25, 0.0)
	trap.fired.connect(_on_trap_fired)
	trap.aoe_fired.connect(_on_fogger_aoe_fired)
	trap.initialize(GameState.selected_trap_type as Trap.TrapType, _active_enemies)
	_trap_container.add_child(trap)
	GameState.spend_bug_bucks(trap.get_cost())
	_trap_nodes[anchor] = trap


func _on_trap_fired(from_pos: Vector3, to_pos: Vector3, target: Node3D, damage: float, trap_type: int) -> void:
	var proj := Projectile.new()
	proj.initialize(from_pos, to_pos, target, damage, trap_type)
	add_child(proj)


func _on_fogger_aoe_fired(from_pos: Vector3, aoe_range: float, damage: float, active_enemies: Array) -> void:
	var cloud := FogCloud.new()
	cloud.initialize(from_pos, aoe_range, damage, active_enemies)
	add_child(cloud)


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


## Sizes and centres the orthographic camera so the arena fills the usable
## screen area — the portion not covered by HUD panels or the trap selector.
##
## The selector now sits at the bottom in both orientations, so the arena
## always uses the full screen width.
##   Landscape — HUD.SELECTOR_LANDSCAPE_STRIP_H (single row of buttons).
##   Portrait  — HUD.SELECTOR_STRIP_H (2×2 grid of buttons).
##
## With KEEP_HEIGHT (Godot default), camera.size is the total world height
## covered by the full viewport. We inflate it until the arena fits in both
## the vertical and horizontal extents of the usable area, then apply
## v_offset to shift the camera's aim to the centre of the usable area.
##
## v_offset sign convention for this top-down camera (local Y = world −Z):
##   positive → aim shifts toward world −Z → origin appears lower on screen.
func _fit_camera_to_grid() -> void:
	var vp       := get_viewport().get_visible_rect().size
	var scr_w    := vp.x
	var scr_h    := vp.y
	var landscape := scr_w >= scr_h

	var bot_add_px := HUD.SELECTOR_LANDSCAPE_STRIP_H if landscape else HUD.SELECTOR_STRIP_H

	var usable_h := scr_h - HUD_TOP_PX - HUD_BOT_PX - bot_add_px
	var usable_w := scr_w
	if usable_h <= 0.0 or usable_w <= 0.0:
		return

	var arena_world := Grid.GRID_SIZE * Grid.CELL_SIZE + 2.0  # +2 = 1-unit margin each side

	# With KEEP_HEIGHT, horizontal world coverage = size × (scr_w / scr_h).
	# For the arena to fit in usable_w pixels: size × (usable_w / scr_h) ≥ arena_world
	# → size ≥ arena_world × (scr_h / usable_w).
	var size_for_height := arena_world * scr_h / usable_h
	var size_for_width  := arena_world * scr_h / usable_w
	_camera.size = maxf(size_for_height, size_for_width)

	var world_per_px := _camera.size / scr_h

	# Arena is horizontally centred on screen; no h_offset needed.
	_camera.h_offset = 0.0
	var top_total := float(HUD_TOP_PX)
	var bot_total := HUD_BOT_PX + bot_add_px
	_camera.v_offset = ((top_total - bot_total) / 2.0) * world_per_px


## Shows (or repositions) the hover preview at the given anchor.
## Rebuilds if the selected trap type has changed since last build.
func _update_hover_preview(anchor: Vector2i) -> void:
	var type := GameState.selected_trap_type
	if _hover_preview_type != type or _hover_preview == null or not is_instance_valid(_hover_preview):
		_hide_hover_preview()
		_hover_preview      = _make_trap_preview(type, 0.35)
		_hover_preview_type = type
	var center := _cell_to_world(anchor) + Vector3(Grid.CELL_SIZE * 0.5, 0.0, Grid.CELL_SIZE * 0.5)
	_hover_preview.position = center + Vector3(0.0, Grid.CELL_SIZE * 0.25, 0.0)
	_hover_preview.visible  = true


func _hide_hover_preview() -> void:
	if _hover_preview != null and is_instance_valid(_hover_preview):
		_hover_preview.visible = false


## Builds a Trap preview node: full mesh hierarchy, no combat logic, no hover area.
## All mesh materials are duplicated and dimmed to alpha so the result reads as a ghost.
func _make_trap_preview(trap_type: int, alpha: float) -> Node3D:
	var preview := Trap.new()
	preview.process_mode = Node.PROCESS_MODE_DISABLED
	preview.initialize_preview(trap_type as Trap.TrapType)
	_apply_ghost_transparency(preview, alpha)
	add_child(preview)
	return preview


## Recursively dims all MeshInstance3D materials in a node subtree.
## Duplicates each material so the original asset is not modified.
func _apply_ghost_transparency(node: Node, alpha: float) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.material_override != null:
				var mat := mi.material_override as StandardMaterial3D
				if mat != null:
					mat = mat.duplicate() as StandardMaterial3D
					mat.albedo_color.a = alpha
					mat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
					mi.material_override = mat
		_apply_ghost_transparency(child, alpha)


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
