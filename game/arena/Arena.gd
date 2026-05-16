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
##   Tap an empty cell to place one trap there. Drag to pan the camera when
##   zoomed in. Right-click (dev / desktop only) removes the trap under the cursor.
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
const FlyStripCloud     = preload("res://traps/FlyStripCloud.gd")
const BoostUnit         = preload("res://boosts/BoostUnit.gd")
const UIFonts           = preload("res://ui/UIFonts.gd")
const HUD               = preload("res://ui/HUD.gd")
const TrapUpgradePanel  = preload("res://ui/TrapUpgradePanel.gd")
const EnemyStatsPanel   = preload("res://ui/EnemyStatsPanel.gd")
const DebugStartDialog  = preload("res://ui/DebugStartDialog.gd")


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Set to true to render the yellow path line during play. Off by default —
# the path visualisation is a debug aid; it clutters the arena during normal play.
const SHOW_PATH_LINE: bool = false

const COLOR_TRAP         := Color(0.40, 0.40, 0.80, 1.0)   # blue-grey box
const COLOR_PATH         := Color(0.80, 0.70, 0.20, 0.5)   # yellow, semi-transparent
const COLOR_GRID_GLOW    := Color(0.65, 0.90, 1.0)         # cool blue-white for cursor glow
const COLOR_WALL_FILL    := Color(0.58, 0.56, 0.52, 1.0)   # light warm stone wall fill
const COLOR_WALL_BORDER  := Color(0.28, 0.27, 0.25, 1.0)   # medium warm gray cell border lines
const COLOR_TRAP_SELECTED := Color(0.90, 0.70, 0.10, 1.0)  # gold outline on selected trap



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

# Boost units — parallel structure to traps; Boosts block pathfinding like traps.
var _boost_nodes:   Dictionary = {}       # anchor Vector2i -> BoostUnit node
var _boost_anchors: Dictionary = {}       # Vector2i -> anchor Vector2i

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
const SPAWN_INTERVAL: float = 0.36     # delay before the first enemy in a wave; subsequent gaps are per-type
# Minimum desired clear space (in cells) between consecutive enemies of the same type.
# The actual gap time is derived from this value and the enemy's speed + visual size,
# so slow/large enemies automatically get longer waits than fast/small ones.
const SPAWN_GAP_CELLS: float = 0.4
const WAVE_COUNTDOWN: int  = 5         # seconds of countdown before each wave

var _enemies_left_to_spawn: int  = 0
var _wave_total_enemies:    int  = 0      # total enemies queued at _launch_wave; used for spawn-progress signal
var _countdown_active: bool      = false  # true while between-wave countdown is ticking
var _seconds_remaining: int      = 0     # last value broadcast during the active countdown

# Static enemy review mode — when true, each wave spawns 3 of every enemy type
# in order instead of using normal wave composition. Toggled at startup via DebugStartDialog.
const STATIC_GROUP_SIZE: int  = 3
const STATIC_GROUP_GAP: float = 1.5   # seconds of pause between each enemy type group
var _static_enemies_mode: bool                   = false
var _static_spawn_queue:  Array[Enemy.EnemyType] = []

# The path currently drawn as yellow markers. Updated on every grid change
# and trimmed forward as the enemy advances through cells.
var _display_path: Array[Vector2i] = []

# Gold perimeter drawn around the 2×2 footprint of the currently open upgrade panel.
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

# Touch/mouse input state machine.
#
# IDLE             → no pointer down
# PENDING_CLASSIFY → pointer down; waiting to see if this is a tap, a pan, or a drag
# DRAGGING         → movement exceeded DRAG_THRESHOLD_PX first; panning the camera
# DRAG_PLACING     → active while an HUD-initiated drag-and-drop is in progress
enum TouchState { IDLE, PENDING_CLASSIFY, DRAGGING, DRAG_PLACING }
var _touch_state:    TouchState = TouchState.IDLE
var _touch_down_pos: Vector2    = Vector2.ZERO   # screen position where the pointer landed
var _touch_last_pos: Vector2    = Vector2.ZERO   # most recent drag/move position
var _touch_hold_time: float     = 0.0            # kept for compatibility; no longer drives hold logic
const DRAG_THRESHOLD_PX: float  = 15.0           # movement before classifying as drag/pan

# Pinch-to-zoom — two-finger gesture that toggles between the two zoom levels.
# While _pinch_active is true all single-finger routing is suspended.
var _pinch_active:      bool    = false
var _pinch_finger0_pos: Vector2 = Vector2.ZERO   # current world position of finger 0
var _pinch_finger1_pos: Vector2 = Vector2.ZERO   # current world position of finger 1
var _pinch_start_span:  float   = 0.0            # finger distance when the gesture began
# Minimum span change (px) required to register a zoom direction.
const PINCH_THRESHOLD_PX: float = 40.0

# Ghost preview node shown while in DRAG_PLACING mode.
var _drag_place_preview: Node3D  = null
var _drag_place_anchor:  Vector2i = Vector2i(-1, -1)

# The placed trap whose range indicator is shown while the preview hovers over it.
# Cleared when the preview moves away or is released.
var _placement_hover_trap: Node = null

# True while the HUD is driving a drag-and-drop placement gesture.
# When set, Arena's own pointer state machine stays idle and placement
# is controlled entirely by HUD calling begin/update/commit_hud_drag().
var _hud_drag_active: bool = false

# Camera zoom — two discrete levels: overview (full-arena fit) and zoomed-in (2×).
enum ZoomState { OVERVIEW, ZOOMED_IN }
var _zoom_state:           ZoomState = ZoomState.OVERVIEW
var _overview_camera_size: float     = 0.0   # camera.size at the overview level; set by _fit_camera_to_grid
var _camera_base_h_offset: float     = 0.0   # h_offset that centres the arena between the two panels
var _pan_world_pos:         Vector2  = Vector2.ZERO   # current camera XZ pan offset (world units)
var _arena_world_half:      float    = 0.0   # half the grid world width (X); used for pan clamping
var _arena_world_half_z:    float    = 0.0   # half the grid world height (Z); used for pan clamping
var _followed_enemy:        Node3D   = null  # non-null while enemy-follow mode is active
var _enemy_stats_panel:    Node     = null  # EnemyStatsPanel instance
var _floor_mi:           MeshInstance3D = null  # floor mesh; material_override swapped on zoom
var _floor_mat_overview: ShaderMaterial  = null  # no grid lines (overview)
var _floor_mat_zoomed:   ShaderMaterial  = null  # grid lines visible (zoomed in)

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
	# Keep processing input even when the scene tree is paused (user-triggered pause
	# or upgrade panel pause) so camera pan and trap placement remain available.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Phase 1: entrance and exit are hardcoded for the prototype.
	# Grid is 31×29; row 14 is the exact vertical centre — both gaps
	# land there, spanning rows 13–15 (3 rows each).
	var entrance := Vector2i(0, 14)
	var exit     := Vector2i(30, 14)

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
	for row in range(Grid.GRID_ROWS):
		if row not in ent_gap:
			_grid.set_cell(Vector2i(entrance.x, row), Grid.CellState.WALL)
		if row not in ex_gap:
			_grid.set_cell(Vector2i(exit.x, row), Grid.CellState.WALL)

	# Mark the top and bottom border rows (0 and GRID_ROWS-1) as WALL for all
	# interior columns. Geometry placed outside the grid at z = ±14.5 consistently
	# failed to render regardless of mesh type, so walls are placed on the outermost
	# grid rows instead — symmetric with the left/right approach using columns 0/30.
	# Columns 0 and GRID_SIZE-1 are already WALL from the column loop above.
	for col in range(1, Grid.GRID_SIZE - 1):
		_grid.set_cell(Vector2i(col, 0),                   Grid.CellState.WALL)
		_grid.set_cell(Vector2i(col, Grid.GRID_ROWS - 1),  Grid.CellState.WALL)

	GameState.start_run(entrance, exit)
	_pathfinder.initialize(_grid)
	_pathfinder.path_updated.connect(_on_path_updated)

	# Spawn the cave image at the entrance and exit gaps.
	# Entrance is rotated 180° relative to the exit so the image reads correctly for each side.
	_spawn_cave_marker(_spawn_cell,   90.0)
	_spawn_cave_marker(_despawn_cell, -90.0)

	_setup_selected_trap_outline()
	_init_path_marker_pool()
	_spawn_floor()
	_apply_floor_grid_lines_from_cfg()  # apply saved preference before first frame
	_spawn_arena_border()
	_spawn_outer_border_ring()

	get_viewport().physics_object_picking = true

	_pathfinder.recalculate()
	GameState.grid_lines_changed.connect(_on_grid_lines_changed)
	add_child(HUD.new())
	_enemy_stats_panel = EnemyStatsPanel.new()
	add_child(_enemy_stats_panel)
	GameState.wave_skip_requested.connect(_on_wave_skip_requested)
	GameState.wave_skip_multi_requested.connect(_on_wave_skip_multi_requested)
	GameState.run_ended.connect(_close_upgrade_panel)
	GameState.run_ended.connect(_on_run_ended_camera)
	GameState.trap_type_selected.connect(_on_trap_type_changed)
	GameState.zoom_toggle_requested.connect(_toggle_zoom)
	# Release enemy follow when a new wave launches (countdown expires).
	GameState.wave_countdown_changed.connect(func(sec: int) -> void:
		if sec == 0:
			_set_followed_enemy(null)
	)

	# Audio — music and phase-change sounds.
	GameState.run_started.connect(AudioManager.start_music)
	GameState.run_ended.connect(func() -> void:
		AudioManager.play_ui("run_end")
		AudioManager.stop_music()
	)
	GameState.phase_changed.connect(_on_phase_changed_audio)
	GameState.bug_bucks_changed.connect(func(_amt: int) -> void:
		AudioManager.play_ui("bucks_earn")
	)

	# Size the camera to fit the arena inside the usable area between side panels,
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

func _unhandled_input(event: InputEvent) -> void:
	# --- Touch ---
	if event is InputEventScreenTouch:
		if event.index == 0:
			_pinch_finger0_pos = event.position
			if event.pressed:
				_on_pointer_down(event.position)
			elif _pinch_active:
				_end_pinch()   # finger 0 lifted while pinching — evaluate and clear
			else:
				_on_pointer_released(event.position)
		elif event.index == 1:
			if event.pressed:
				# Second finger landed — fold the in-progress single-finger gesture
				# into a pinch.  _touch_last_pos holds finger 0's current position.
				_pinch_finger0_pos = _touch_last_pos
				_pinch_finger1_pos = event.position
				_begin_pinch()
			elif _pinch_active:
				_end_pinch()   # finger 1 lifted while pinching — evaluate and clear
		return

	if event is InputEventScreenDrag:
		if event.index == 0:
			_pinch_finger0_pos = event.position
			if _pinch_active:
				return   # swallow single-finger routing during pinch
			_on_pointer_dragged(event.position, event.relative)
		elif event.index == 1 and _pinch_active:
			_pinch_finger1_pos = event.position
		return

	# --- Mouse ---
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_on_pointer_down(event.position)
			else:
				_on_pointer_released(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_try_remove_trap(_screen_to_grid(event.position))
		return

	# InputEventMouseMotion carries no button state — guard with is_mouse_button_pressed.
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_on_pointer_dragged(event.position, event.relative)
		return

	# Keyboard shortcuts for desktop/dev use.
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event.keycode)


# ---------------------------------------------------------------------------
# Unified pointer dispatch (touch + mouse share the same state machine)
# ---------------------------------------------------------------------------

## Called on finger-down or left mouse button press.
func _on_pointer_down(screen_pos: Vector2) -> void:
	_touch_state     = TouchState.PENDING_CLASSIFY
	_touch_down_pos  = screen_pos
	_touch_last_pos  = screen_pos
	_touch_hold_time = 0.0


## Called on finger-up or left mouse button release.
func _on_pointer_released(screen_pos: Vector2) -> void:
	match _touch_state:
		TouchState.PENDING_CLASSIFY:
			_handle_tap(_touch_down_pos)
		TouchState.DRAG_PLACING:
			_commit_drag_place()
	_clear_drag_preview()
	_touch_state = TouchState.IDLE


## Called on finger drag or mouse motion while left button is held.
func _on_pointer_dragged(screen_pos: Vector2, relative: Vector2) -> void:
	_touch_last_pos = screen_pos

	if _touch_state == TouchState.PENDING_CLASSIFY:
		if screen_pos.distance_to(_touch_down_pos) >= DRAG_THRESHOLD_PX:
			_touch_state = TouchState.DRAGGING

	if _touch_state == TouchState.DRAGGING:
		# Pan when zoomed in and either free (no follow target) or paused (follow is suspended).
		if _zoom_state == ZoomState.ZOOMED_IN and (_followed_enemy == null or get_tree().paused):
			var vp           := get_viewport().get_visible_rect().size
			var world_per_px := _camera.size / vp.y
			_apply_pan(_pan_world_pos - relative * world_per_px)
	elif _touch_state == TouchState.DRAG_PLACING:
		_update_drag_preview(screen_pos)


# ---------------------------------------------------------------------------
# Drag-to-place (driven by HUD drag-and-drop; see begin_hud_drag / update_hud_drag)
# ---------------------------------------------------------------------------

## Positions or repositions the ghost preview at the cell under screen_pos.
## Rebuilds the preview node only when the anchor cell changes.
## Shows a valid (semi-transparent) or invalid (grey) ghost based on placement rules.
func _update_drag_preview(screen_pos: Vector2) -> void:
	var anchor := _clamp_to_anchor(_screen_to_grid(screen_pos))
	if anchor == _drag_place_anchor:
		return   # still on the same cell — nothing to rebuild

	# Clear the old preview first, then record the new anchor.
	# Order matters: _clear_drag_preview() resets _drag_place_anchor to (-1,-1),
	# so the assignment must come after the clear or the anchor is lost on release.
	_clear_drag_preview()
	_drag_place_anchor = anchor

	if not _is_in_arena(anchor):
		return

	var cells := _get_trap_cells(anchor)
	var valid  := not cells.is_empty() \
		and _all_cells_buildable(cells) \
		and not _footprint_overlaps_enemy(cells) \
		and _can_place_at(cells)
	_drag_place_preview = _make_trap_preview(GameState.selected_trap_type, 0.5, valid)
	var center := _cell_to_world(anchor) + Vector3(Grid.CELL_SIZE * 0.5, 0.0, Grid.CELL_SIZE * 0.5)
	_drag_place_preview.position = center + Vector3(0.0, Grid.CELL_SIZE * 0.25, 0.0)

	# When placement is invalid, suppress the preview's range circle.
	# If the footprint covers an existing trap, surface that trap's range indicator
	# so the player can see the conflict clearly.
	if not valid:
		_drag_place_preview.hide_range_indicator()
		var blocked_trap := _find_trap_at_cells(cells)
		if blocked_trap != null:
			blocked_trap.show_range_indicator()
			_placement_hover_trap = blocked_trap


## Places a trap at the last previewed anchor and frees the preview.
func _commit_drag_place() -> void:
	var anchor := _drag_place_anchor
	_clear_drag_preview()
	if anchor == Vector2i(-1, -1) or not _can_afford_trap():
		return
	var cells := _get_trap_cells(anchor)
	if not cells.is_empty() and not _footprint_overlaps_enemy(cells):
		_try_place_trap(anchor)


## Frees the ghost preview node and resets the tracked anchor.
func _clear_drag_preview() -> void:
	if _drag_place_preview != null and is_instance_valid(_drag_place_preview):
		_drag_place_preview.queue_free()
	_drag_place_preview   = null
	_drag_place_anchor    = Vector2i(-1, -1)
	_release_placement_hover_trap()


# ---------------------------------------------------------------------------
# HUD drag-and-drop placement API
# Called by HUD.gd when the user drags a trap icon from the left panel.
# ---------------------------------------------------------------------------

## Called by HUD when the user begins dragging a trap icon.
## placement_screen_pos is the centre of the floating icon (cursor + offset),
## which is the cell the trap will be placed in — not the raw cursor position.
func begin_hud_drag(_trap_type: int, placement_screen_pos: Vector2) -> void:
	_hud_drag_active = true
	_touch_state     = TouchState.IDLE   # keep Arena's own state machine inert
	# GameState.selected_trap_type is already set by HUD before this call.
	_update_drag_preview(placement_screen_pos)


## Called by HUD each frame as the floating icon moves.
func update_hud_drag(placement_screen_pos: Vector2) -> void:
	if _hud_drag_active:
		_update_drag_preview(placement_screen_pos)


## Called by HUD when the user releases the drag.  Attempts placement.
func commit_hud_drag() -> void:
	if _hud_drag_active:
		_commit_drag_place()
		_hud_drag_active = false


## Called by HUD if the drag is cancelled without releasing (e.g. second finger).
func cancel_hud_drag() -> void:
	_clear_drag_preview()
	_hud_drag_active = false


# ---------------------------------------------------------------------------
# Pinch-to-zoom
# ---------------------------------------------------------------------------

## Called when a second finger lands while finger 0 is already down.
## Cancels any in-progress single-finger operation and begins tracking span.
func _begin_pinch() -> void:
	_clear_drag_preview()
	_hud_drag_active  = false   # cancel any active HUD drag when a pinch starts
	_touch_state      = TouchState.IDLE
	_pinch_active     = true
	_pinch_start_span = _pinch_finger0_pos.distance_to(_pinch_finger1_pos)


## Called when either finger lifts during a pinch.
## Compares final span to starting span and toggles zoom if the change is large enough.
## Spreading fingers (span grows) zooms in; pinching (span shrinks) zooms out.
func _end_pinch() -> void:
	_pinch_active = false
	_touch_state  = TouchState.IDLE
	var delta := _pinch_finger0_pos.distance_to(_pinch_finger1_pos) - _pinch_start_span
	if delta > PINCH_THRESHOLD_PX and _zoom_state == ZoomState.OVERVIEW:
		_toggle_zoom()
	elif delta < -PINCH_THRESHOLD_PX and _zoom_state == ZoomState.ZOOMED_IN:
		_toggle_zoom()


# ---------------------------------------------------------------------------
# Touch dispatch
# ---------------------------------------------------------------------------

## Dispatches a confirmed tap (finger lifted without crossing DRAG_THRESHOLD_PX).
func _handle_tap(screen_pos: Vector2) -> void:
	# Enemy tap takes priority — enemies sit above the floor plane.
	var tapped_enemy := _find_enemy_near_screen(screen_pos, 40.0)
	if tapped_enemy != null:
		_handle_enemy_tap(tapped_enemy)
		return

	# Any tap that does not land on the followed enemy clears the follow and
	# closes the stats panel — this covers empty cells, trap taps, and anything else.
	_set_followed_enemy(null)

	var cell := _screen_to_grid(screen_pos)

	# Tap on a placed trap → center camera (if zoomed) and open upgrade panel.
	if _trap_anchors.has(cell):
		if _zoom_state == ZoomState.ZOOMED_IN:
			_set_followed_enemy(null)
			var wp := _cell_to_world(_trap_anchors[cell])
			_apply_pan(Vector2(wp.x, wp.z))
		_open_upgrade_panel(_trap_anchors[cell])
		return

	# Tapping an empty arena cell no longer places a trap.
	# Traps are placed only via drag-and-drop from the HUD panel icons.
	if _is_in_arena(cell):
		_close_upgrade_panel()


## Returns the nearest active enemy whose projected screen position is within
## max_dist_px of screen_pos, or null if none qualifies.
func _find_enemy_near_screen(screen_pos: Vector2, max_dist_px: float) -> Node3D:
	var best: Node3D = null
	var best_dist := max_dist_px
	for enemy in _active_enemies:
		if not is_instance_valid(enemy):
			continue
		var projected := _camera.unproject_position(enemy.global_position)
		var d := projected.distance_to(screen_pos)
		if d < best_dist:
			best_dist = d
			best = enemy
	return best


## Sets the followed enemy, keeps the selection glow in sync, and
## shows or hides the stats panel for the new target.
func _set_followed_enemy(enemy: Node3D) -> void:
	if _followed_enemy == enemy:
		return
	if is_instance_valid(_followed_enemy):
		_followed_enemy.hide_selection_glow()
	_followed_enemy = enemy
	if is_instance_valid(_followed_enemy):
		_followed_enemy.show_selection_glow()
	if _enemy_stats_panel != null:
		_enemy_stats_panel.set_enemy(_followed_enemy)


## Handles a tap on an enemy: zooms in and follows, or cancels follow.
func _handle_enemy_tap(enemy: Node3D) -> void:
	if _zoom_state == ZoomState.OVERVIEW:
		# Zoom in and begin following this enemy.
		_zoom_state  = ZoomState.ZOOMED_IN
		_camera.size = _overview_camera_size * 0.5
		if _floor_mi != null:
			_floor_mi.material_override = _floor_mat_zoomed
		_set_followed_enemy(enemy)
		GameState.zoom_state_changed.emit(true)
	elif _followed_enemy == enemy:
		# Tap the same enemy again → back to overview.
		_toggle_zoom()
	else:
		# Switch follow to this new enemy (stay zoomed).
		_set_followed_enemy(enemy)


# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------

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


## Returns true only if every cell in the footprint is available for building.
## Catches TRAP, WALL, and OBSTACLE states that _can_place_at() does not reject.
func _all_cells_buildable(cells: Array[Vector2i]) -> bool:
	for cell in cells:
		if not _grid.is_buildable(cell):
			return false
	return true


## Returns the placed Trap node whose footprint contains any of the given cells,
## or null if no placed trap occupies those cells.
func _find_trap_at_cells(cells: Array[Vector2i]) -> Node:
	for cell in cells:
		if _trap_anchors.has(cell):
			var anchor: Vector2i = _trap_anchors[cell]
			if _trap_nodes.has(anchor):
				return _trap_nodes[anchor]
	return null


## Hides the range indicator on any trap that was shown during an invalid placement
## hover, then clears the reference.
func _release_placement_hover_trap() -> void:
	if _placement_hover_trap != null and is_instance_valid(_placement_hover_trap):
		_placement_hover_trap.hide_range_indicator()
	_placement_hover_trap = null


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

	var is_bait_station := (GameState.selected_trap_type == Trap.TrapType.BAIT_STATION)
	for cell in cells:
		# Bait Station uses FLOOR_TRAP so enemies walk over it; all other traps use TRAP.
		if is_bait_station:
			_grid.place_floor_trap(cell)
		else:
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
		_spawn_sell_coin_burst(_trap_nodes[anchor])
	_try_remove_trap_by_anchor(anchor)


## Spawns gold coin particles at the trap's screen position, identical to the
## burst shown when selling via the upgrade panel.
func _spawn_sell_coin_burst(trap_node: Node3D) -> void:
	var burst_pos := _camera.unproject_position(trap_node.global_position)

	var host := CanvasLayer.new()
	host.layer        = 10
	host.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(host)

	var particles := CPUParticles2D.new()
	particles.process_mode         = Node.PROCESS_MODE_ALWAYS
	particles.position             = burst_pos
	particles.amount               = 28
	particles.lifetime             = 0.9
	particles.one_shot             = true
	particles.explosiveness        = 1.0
	particles.emitting             = true
	particles.direction            = Vector2(0.0, -1.0)
	particles.spread               = 180.0
	particles.initial_velocity_min = 100.0
	particles.initial_velocity_max = 260.0
	particles.gravity              = Vector2(0.0, 380.0)
	particles.scale_amount_min     = 5.0
	particles.scale_amount_max     = 10.0
	particles.color                = Color(1.00, 0.82, 0.10, 1.0)
	host.add_child(particles)

	var timer := get_tree().create_timer(particles.lifetime + 0.2)
	timer.timeout.connect(host.queue_free)


## Opens the upgrade panel for the trap at anchor, closing any existing panel first.
## When zoomed in, centers the camera on the trap before opening the panel.
func _open_upgrade_panel(anchor: Vector2i) -> void:
	_close_upgrade_panel()
	if not _trap_nodes.has(anchor):
		return

	if _zoom_state == ZoomState.ZOOMED_IN:
		_set_followed_enemy(null)
		var wp := _cell_to_world(anchor)
		_apply_pan(Vector2(wp.x, wp.z))

	var panel := TrapUpgradePanel.new()
	panel.closed.connect(_on_upgrade_panel_closed)
	panel.sell_requested.connect(_on_sell_trap_requested.bind(anchor))
	add_child(panel)
	panel.initialize(_trap_nodes[anchor])
	_upgrade_panel  = panel
	_selected_trap  = _trap_nodes[anchor]
	_selected_trap.show_range_indicator()
	_show_selected_trap_outline(anchor)
	_selected_trap_anchor = anchor
	if _trap_outlines.has(anchor):
		_draw_trap_outline(anchor)
	if not get_tree().paused:
		get_tree().paused = true
		_panel_paused = true


## Sells the trap at anchor (70% refund) and closes the upgrade panel.
func _on_sell_trap_requested(anchor: Vector2i) -> void:
	_close_upgrade_panel()
	_try_remove_trap_by_anchor(anchor)


## Removes the trap at anchor and refunds placement cost plus all upgrade costs at 70%.
func _try_remove_trap_by_anchor(anchor: Vector2i) -> void:
	if _trap_nodes.has(anchor):
		var trap: Node3D = _trap_nodes[anchor]
		var sell_value: int = trap.get_sell_value()
		GameState.add_bug_bucks(sell_value)
		_spawn_earn_label(_camera.unproject_position(trap.global_position), sell_value)
		trap.queue_free()
		_trap_nodes.erase(anchor)
	if _trap_outlines.has(anchor):
		_trap_outlines[anchor].queue_free()
		_trap_outlines.erase(anchor)
	if _hovered_trap_anchor == anchor:
		_hovered_trap_anchor = Vector2i(-1, -1)
	for c in _get_trap_cells(anchor):
		# Bait Station occupies FLOOR_TRAP cells; all others use TRAP.
		if _grid.get_cell(c) == Grid.CellState.FLOOR_TRAP:
			_grid.remove_floor_trap(c)
		else:
			_grid.remove_trap(c)
		_trap_anchors.erase(c)


## Closes and frees the upgrade panel if one is open, then unpauses if we paused.
func _close_upgrade_panel() -> void:
	if _upgrade_panel != null and is_instance_valid(_upgrade_panel):
		_upgrade_panel.queue_free()
	if _selected_trap != null and is_instance_valid(_selected_trap):
		_selected_trap.hide_range_indicator()
	_upgrade_panel = null
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
	if _selected_trap != null and is_instance_valid(_selected_trap):
		_selected_trap.hide_range_indicator()
	_upgrade_panel = null
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
		var from: Vector2i
		if _grid.is_in_bounds(current):
			from = current
		else:
			# Enemy is still approaching from outside. Use the cell it is actually
			# heading toward (its entrance-gap row) rather than GameState.entrance_cell,
			# which is always row 15 and may have been trapped. Routing from the wrong
			# row produces a grid_path that skips the enemy's real target, causing
			# update_path() to fall back to new_path[1] — which can be a trap cell.
			var entry: Vector2i = enemy.get_target_cell()
			if not _grid.is_in_bounds(entry) or not _grid.is_passable(entry):
				continue  # entrance cell is blocked; skip until the next recalculation
			from = entry
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
	# The grid is centred on the world origin; X and Z use separate half-extents
	# because the grid is no longer square (31 cols × 29 rows).
	var half_w := (Grid.GRID_SIZE * Grid.CELL_SIZE) / 2.0
	var half_h := (Grid.GRID_ROWS * Grid.CELL_SIZE) / 2.0
	var col    := floori((world_pos.x + half_w) / Grid.CELL_SIZE)
	var row    := floori((world_pos.z + half_h) / Grid.CELL_SIZE)

	return Vector2i(col, row)


## Converts a grid coordinate to its world-space centre position at y = 0.
func _cell_to_world(cell: Vector2i) -> Vector3:
	var half_w := (Grid.GRID_SIZE * Grid.CELL_SIZE) / 2.0
	var half_h := (Grid.GRID_ROWS * Grid.CELL_SIZE) / 2.0
	var x      := cell.x * Grid.CELL_SIZE - half_w + Grid.CELL_SIZE * 0.5
	var z      := cell.y * Grid.CELL_SIZE - half_h + Grid.CELL_SIZE * 0.5
	return Vector3(x, 0.0, z)


# ---------------------------------------------------------------------------
# Enemy spawning
# ---------------------------------------------------------------------------

## Seconds to wait after spawning an enemy before the next one appears.
## Derived from the enemy's visual size and movement speed so there is always
## at least SPAWN_GAP_CELLS of clear air between consecutive enemies —
## slow/large enemies automatically get a much longer gap than fast/small ones.
func _spawn_gap_for_type(enemy_type: Enemy.EnemyType) -> float:
	var speed: float      = Enemy.STATS[enemy_type]["speed"]
	var visual_size: float = Enemy.VISUAL_QUAD_SIZE[enemy_type]
	return (visual_size + SPAWN_GAP_CELLS) / speed


## Returns which enemy type to spawn for the given wave number.
## Wave 1 is pure gnats (tutorial difficulty). Every 10th wave is a rat boss wave.
## New types unlock progressively; gnats phase out after wave 6 as heavier enemies dominate.
func _enemy_type_for_wave(wave: int) -> Enemy.EnemyType:
	if wave == 1:
		return Enemy.EnemyType.GNAT
	if wave % 10 == 0:
		return Enemy.EnemyType.RAT

	# Build a weighted pool from all unlocked types.
	# Appending the same type multiple times controls its spawn weight.
	var pool: Array[Enemy.EnemyType] = []
	pool.append_array([Enemy.EnemyType.ANT, Enemy.EnemyType.ANT, Enemy.EnemyType.ANT])
	if wave <= 6:
		pool.append_array([Enemy.EnemyType.GNAT, Enemy.EnemyType.GNAT, Enemy.EnemyType.GNAT])
	if wave >= 3:
		pool.append_array([Enemy.EnemyType.CRICKET, Enemy.EnemyType.CRICKET])
	if wave >= 5:
		pool.append_array([Enemy.EnemyType.BEETLE, Enemy.EnemyType.BEETLE])
	if wave >= 8:
		pool.append_array([Enemy.EnemyType.COCKROACH, Enemy.EnemyType.COCKROACH, Enemy.EnemyType.COCKROACH])

	return pool[randi() % pool.size()]


## Instantiates one enemy, places it at the entrance, and starts it moving.
func _spawn_enemy(path: Array[Vector2i], enemy_type: Enemy.EnemyType) -> void:
	var enemy: Node3D = Enemy.new()

	# Register before adding to tree so signals are connected before
	# _ready fires on the enemy node.
	_active_enemies.append(enemy)
	enemy.reached_exit.connect(_on_enemy_reached_exit.bind(enemy))
	enemy.died.connect(_on_enemy_died.bind(enemy))
	enemy.cell_advanced.connect(_redraw_path_display)

	# Arena is PROCESS_MODE_ALWAYS so input works during pause; override here
	# so enemies actually stop when the player pauses.
	enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(enemy)
	enemy.initialize(path, enemy_type, GameState.current_wave)


## Spawns a new enemy mid-arena starting from grid_pos.
## Used for on-death effects (Cockroach Nymph splits, Mouse gnat swarm).
## Finds a fresh path from the given cell; does nothing if no path exists.
func spawn_enemy_at_grid_position(grid_pos: Vector2i, enemy_type: Enemy.EnemyType) -> void:
	var path := _find_shortest_exit_path(grid_pos)
	if path.is_empty():
		return
	_spawn_enemy(path, enemy_type)


func _on_enemy_reached_exit(enemy: Node3D) -> void:
	# Air Freshener Boosts may absorb a fraction of the infestation — pass the full
	# amount through each Boost in sequence, with each returning its unabsorbed remainder.
	var infestation := enemy.get_infestation_damage()
	for boost in _boost_nodes.values():
		if is_instance_valid(boost):
			infestation = boost.absorb_infestation(infestation, enemy.global_position)
	GameState.add_infestation(infestation)
	# Mouse steals Bug Bucks from the player in addition to adding infestation.
	if enemy.get_enemy_type() == Enemy.EnemyType.MOUSE:
		GameState.add_bug_bucks(-enemy.get_bug_bucks_steal())
	_active_enemies.erase(enemy)
	if enemy == _followed_enemy:
		_set_followed_enemy(null)
	# enemy.queue_free() is called inside Enemy.gd — no double-free needed.

	if _active_enemies.is_empty() and _enemies_left_to_spawn == 0:
		_start_wave()


func _on_enemy_died(enemy: Node3D) -> void:
	var bounty: int = enemy.get_bounty()
	GameState.add_bug_bucks(bounty)
	_spawn_earn_label(_camera.unproject_position(enemy.global_position), bounty)
	_active_enemies.erase(enemy)
	if enemy == _followed_enemy:
		_set_followed_enemy(null)
	# enemy.queue_free() is called inside Enemy._die() after the flash tween.

	# Notify all Boost units of the kill (Quarantine Marker + Cash Register use this).
	for boost in _boost_nodes.values():
		if is_instance_valid(boost):
			boost.on_enemy_died_near(enemy.global_position)

	# On-death spawn effects — trigger after erasing from _active_enemies so
	# the spawned children don't cause an immediate false wave-end check.
	var death_cell := enemy.get_current_cell()
	match enemy.get_enemy_type():
		Enemy.EnemyType.COCKROACH_NYMPH:
			# Splits into two smaller cockroaches that continue toward the exit.
			for _i in 2:
				spawn_enemy_at_grid_position(death_cell, Enemy.EnemyType.COCKROACH_MINI)
		Enemy.EnemyType.MOUSE:
			# Releases a swarm of gnats from its position.
			for _i in 3:
				spawn_enemy_at_grid_position(death_cell, Enemy.EnemyType.GNAT)

	if _active_enemies.is_empty() and _enemies_left_to_spawn == 0:
		_start_wave()


## Increments the wave counter and begins the between-wave countdown.
func _start_wave() -> void:
	GameState.current_wave += 1
	# Notify Boost units of the new wave (Cash Register awards passive income here).
	for boost in _boost_nodes.values():
		if is_instance_valid(boost):
			boost.on_wave_started()
	_countdown_active    = true
	_seconds_remaining   = WAVE_COUNTDOWN
	GameState.set_countdown(WAVE_COUNTDOWN)
	get_tree().create_timer(1.0, false).timeout.connect(_on_countdown_tick.bind(WAVE_COUNTDOWN - 1))


## Called once per second during the countdown. Fires the wave when it reaches 0.
func _on_countdown_tick(seconds_remaining: int) -> void:
	if not _countdown_active:
		return
	_seconds_remaining = seconds_remaining
	GameState.set_countdown(seconds_remaining)
	if seconds_remaining > 0:
		get_tree().create_timer(1.0, false).timeout.connect(_on_countdown_tick.bind(seconds_remaining - 1))
	else:
		_countdown_active = false
		_launch_wave()


func _handle_key(_keycode: int) -> void:
	pass


## Receives the confirmed playtest values from DebugStartDialog and starts the run.
func _on_debug_confirmed(bug_bucks: int, wave_size: int, static_enemies: bool) -> void:
	_wave_size            = wave_size
	_static_enemies_mode  = static_enemies
	GameState.bug_bucks   = bug_bucks
	GameState.bug_bucks_changed.emit(bug_bucks)
	_start_wave()


func _on_trap_type_changed(_type: int) -> void:
	pass   # reserved for future type-change side effects


## Handles the "Send Wave Early" button.
## Between waves (countdown active): skips the countdown and awards a time-remaining bonus.
## During a wave (enemies active): launches the next wave immediately for a larger bonus
## scaled by the current wave number.  Both paths are available at any time.
func _on_wave_skip_requested() -> void:
	if _countdown_active:
		_countdown_active = false
		if _seconds_remaining > 0:
			var bonus := _seconds_remaining * GameState.early_wave_bonus_rate
			GameState.add_bug_bucks(bonus)
			_spawn_earn_label(get_viewport().get_visible_rect().get_center(), int(bonus))
			GameState.early_wave_bonus_awarded.emit(bonus)
		GameState.set_countdown(0)
		_launch_wave()
	elif not (_active_enemies.is_empty() and _enemies_left_to_spawn == 0):
		# Wave is active — send the next wave immediately.  Reward equals the
		# per-enemy bounty for each enemy that has not yet spawned; once all
		# enemies are out the reward is 0.
		var bonus := _enemies_left_to_spawn * GameState.EARLY_SEND_PER_ENEMY
		GameState.add_bug_bucks(bonus)
		_spawn_earn_label(get_viewport().get_visible_rect().get_center(), int(bonus))
		GameState.early_wave_bonus_awarded.emit(bonus)
		GameState.early_send_reward_changed.emit(0)
		GameState.current_wave += 1
		_launch_wave()


## Handles the multiplied "Send Wave Early" button (×10, ×100).
##
## All count waves begin simultaneously — each gets its own independent spawn timer so
## enemies arrive count-per-tick rather than in a single elongated stream.
##
## Countdown path: cancel the countdown, award the time-remaining bonus, build the
## combined enemy pool (count × _wave_size), then fire count timers at once.
## The first timer is started by _launch_wave(); the remaining count-1 are started here.
##
## Active-wave path: award the early-send bonus for the current wave's unsent enemies,
## discard them (paid for via the bonus), build count new waves, then start count timers.
## If the previous spawn chain was still running its timer counts as one, so only
## count-1 additional timers are needed.
func _on_wave_skip_multi_requested(count: int) -> void:
	if _countdown_active:
		_countdown_active = false
		if _seconds_remaining > 0:
			var bonus := _seconds_remaining * GameState.early_wave_bonus_rate * count
			GameState.add_bug_bucks(bonus)
			GameState.early_wave_bonus_awarded.emit(bonus)
		GameState.set_countdown(0)
		# Non-additive first call resets the counter and starts spawn stream 1.
		# current_wave was already incremented by _start_wave() when the countdown began.
		_launch_wave()
		for _i in range(count - 1):
			GameState.current_wave += 1
			_launch_wave(true)
		# Start streams 2 through count — same delay as stream 1 so all fire together.
		for _i in range(count - 1):
			get_tree().create_timer(SPAWN_INTERVAL, false).timeout.connect(_spawn_next_in_wave)
	elif not (_active_enemies.is_empty() and _enemies_left_to_spawn == 0):
		# Award the early-send bonus for the current wave's unsent enemies, then discard
		# them so count fresh waves start from a clean slate.
		var bonus := _enemies_left_to_spawn * GameState.EARLY_SEND_PER_ENEMY * count
		GameState.add_bug_bucks(bonus)
		GameState.early_wave_bonus_awarded.emit(bonus)
		GameState.early_send_reward_changed.emit(0)
		# A running spawn chain means one stream is already active; remember this before
		# zeroing the counter so we don't start a redundant timer for it.
		var chain_running := _enemies_left_to_spawn > 0
		_enemies_left_to_spawn = 0
		_wave_total_enemies    = 0
		for _i in range(count):
			GameState.current_wave += 1
			_launch_wave(true)
		# Start count streams total; the existing chain (if any) already counts as one.
		var new_timers := count - (1 if chain_running else 0)
		for _i in range(new_timers):
			get_tree().create_timer(SPAWN_INTERVAL, false).timeout.connect(_spawn_next_in_wave)


## Begins spawning enemies for the wave.
## additive=true layers enemies onto an already-running wave without restarting the
## spawn timer — the existing timer drains the combined queue.
## In static mode, builds a fixed queue of 3 × each enemy type in ascending tier order
## so every type is visible for review regardless of the current wave number.
## In normal mode, spawns _wave_size enemies using the usual random composition.
func _launch_wave(additive: bool = false) -> void:
	var new_enemies: int
	if _static_enemies_mode:
		# Both fresh and additive waves use the same typed queue.
		# Fresh: clear and rebuild. Additive: append another pass so the queue
		# always has enough entries to satisfy _enemies_left_to_spawn.
		if not additive:
			_static_spawn_queue.clear()
		var types: Array[Enemy.EnemyType] = [
			Enemy.EnemyType.GNAT,
			Enemy.EnemyType.ANT,
			Enemy.EnemyType.CRICKET,
			Enemy.EnemyType.BEETLE,
			Enemy.EnemyType.COCKROACH,
			Enemy.EnemyType.RAT,
		]
		for t: Enemy.EnemyType in types:
			for _i in STATIC_GROUP_SIZE:
				_static_spawn_queue.append(t)
		new_enemies = types.size() * STATIC_GROUP_SIZE
	else:
		new_enemies = _wave_size

	if additive:
		# Layer on top of the running wave — the existing spawn timer drains both.
		_enemies_left_to_spawn += new_enemies
		_wave_total_enemies    += new_enemies
	else:
		_enemies_left_to_spawn  = new_enemies
		_wave_total_enemies     = new_enemies

	# Publish the full reward so the HUD can display it before the first spawn.
	GameState.early_send_reward_changed.emit(_enemies_left_to_spawn * GameState.EARLY_SEND_PER_ENEMY)
	# For additive launches the spawn progress position doesn't reset — progress stays
	# where it was relative to the expanded total.  For a fresh wave it resets to 0.
	if additive:
		var already_spawned := _wave_total_enemies - _enemies_left_to_spawn
		GameState.wave_spawn_progress_changed.emit(already_spawned, _wave_total_enemies)
	else:
		GameState.wave_spawn_progress_changed.emit(0, _wave_total_enemies)

	# Only start the spawn timer for fresh waves; additive waves share the running timer.
	if not additive:
		get_tree().create_timer(SPAWN_INTERVAL, false).timeout.connect(_spawn_next_in_wave)


## Spawns one enemy then schedules the next, until the wave is exhausted.
## Picks randomly from entrance rows that are currently open (not trapped).
func _spawn_next_in_wave() -> void:
	if _enemies_left_to_spawn <= 0:
		return
	_enemies_left_to_spawn -= 1
	GameState.early_send_reward_changed.emit(_enemies_left_to_spawn * GameState.EARLY_SEND_PER_ENEMY)
	GameState.wave_spawn_progress_changed.emit(_wave_total_enemies - _enemies_left_to_spawn, _wave_total_enemies)

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
	# Pick type before the path check so the same type drives both the spawn
	# and the gap timer — even if the path was empty this wave slot is consumed.
	var enemy_type: Enemy.EnemyType
	if _static_enemies_mode:
		enemy_type = _static_spawn_queue.pop_front()
	else:
		enemy_type = _enemy_type_for_wave(GameState.current_wave)

	if not grid_path.is_empty():
		_spawn_enemy(_build_full_path(grid_path, spawn_row), enemy_type)

	if _enemies_left_to_spawn > 0:
		# In static mode, use a longer pause when the next enemy is a different type.
		# Within the same group, use the normal per-type gap.
		var gap: float
		if _static_enemies_mode and not _static_spawn_queue.is_empty() \
				and _static_spawn_queue[0] != enemy_type:
			gap = STATIC_GROUP_GAP
		else:
			gap = _spawn_gap_for_type(enemy_type)
		get_tree().create_timer(gap, false).timeout.connect(_spawn_next_in_wave)


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


## Returns the anchor cell clamped so its 2x2 footprint stays fully in bounds.
## Clicking on the last column or row would otherwise produce an OOB footprint.
func _clamp_to_anchor(cell: Vector2i) -> Vector2i:
	return Vector2i(
		clampi(cell.x, 0, Grid.GRID_SIZE - 2),
		clampi(cell.y, 0, Grid.GRID_ROWS - 2)
	)




## Returns true when a cell is within the arena, defined as the 31×29 floor
## plus the 1-cell-wide wall border surrounding it (x: -1..31, y: -1..29).
## Cells beyond that boundary are outside the arena entirely.
func _is_in_arena(cell: Vector2i) -> bool:
	return cell.x >= -1 and cell.x <= Grid.GRID_SIZE \
		and cell.y >= -1 and cell.y <= Grid.GRID_ROWS


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
## Surface 0 — solid neon fill (TRIANGLES): flat 20% opacity triangle fan
##   covering the full footprint at 3% opacity.
## Surface 1 — rounded outline (LINES): two concentric inset rounded-corner
##   rectangles simulate ~2 px line width.
func _draw_trap_outline(anchor: Vector2i) -> void:
	var trap_type: int = _trap_nodes[anchor].get_type()
	var base: Color    = Trap.STATS[trap_type]["color"]
	var neon: Color    = _neon_color(base)

	var is_selected := anchor == _selected_trap_anchor
	var is_hovered  := anchor == _hovered_trap_anchor

	var outline_color: Color
	if is_selected:
		outline_color = base.lightened(0.70); outline_color.a = 1.0
	elif is_hovered:
		outline_color = base.lightened(0.45); outline_color.a = 1.0
	else:
		outline_color = base.darkened(0.2);   outline_color.a = 0.60

	var fill_color := neon
	fill_color.a   = 0.03

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

	# --- Surface 0: solid neon fill ---
	var fill_pts := _rounded_rect_pts(min_x, max_x, min_z, max_z, y_fill, CORNER_R, CORNER_SEGS)
	var center   := Vector3(cx, y_fill, cz)

	var n := fill_pts.size()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(n):
		var a: Vector3 = fill_pts[i]
		var b: Vector3 = fill_pts[(i + 1) % n]
		im.surface_set_color(fill_color); im.surface_add_vertex(center)
		im.surface_set_color(fill_color); im.surface_add_vertex(a)
		im.surface_set_color(fill_color); im.surface_add_vertex(b)
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

## Covers the full 31×31 arena grid with a single textured plane.
## A random 16% crop of the source image is selected each run and stretched
## across the floor, so each run shows a different patch of the backyard.
##
## Place the source image at:  res://assets/arena/backyard_floor.png
## If the file is missing a warning is printed and no floor is drawn.

# Shader source embedded here so no separate .gdshader file needs to be loaded —
# avoids a null-shader if Godot hasn't rescanned the project after adding the file.
const _FLOOR_SHADER_CODE: String = """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D floor_texture : source_color, filter_linear, repeat_disable;
uniform vec2  crop_offset = vec2(0.2, 0.2);
uniform float crop_size   = 0.400;

// Darkens the floor so game objects read clearly against it.
const float BRIGHTNESS = 0.7;

// Grid dimensions — must match Grid.GRID_SIZE and Grid.GRID_ROWS.
const vec2 GRID_CELLS = vec2(31.0, 29.0);

// Line fade: distance (as fraction of a cell) where the line reaches zero opacity.
const float LINE_HALF_WIDTH = 0.04;
// Set at material-build time: 0.0 for overview material, 0.15 for zoomed material.
uniform float line_alpha = 0.0;

void fragment() {
	vec2 uv = crop_offset + UV * crop_size;
	vec3 floor_color = texture(floor_texture, uv).rgb * BRIGHTNESS;

	// Map UV to cell space; fract gives position within each cell (0..1).
	// min(f, 1-f) gives distance to the nearest grid line edge (0..0.5).
	vec2 f = fract(UV * GRID_CELLS);
	float nearest = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float line = 1.0 - smoothstep(0.0, LINE_HALF_WIDTH, nearest);

	vec3 line_color = vec3(0.92, 0.90, 0.85);
	ALBEDO = mix(floor_color, line_color, line * line_alpha);
}
"""

# Shader for the large background plane that sits beneath and around the arena floor.
# It samples the same texture as the floor, but uses world position to derive UV so
# the edge pixels of the crop window are stretched outward beyond the arena bounds
# rather than repeating or cutting to a solid colour.
const _BACKGROUND_SHADER_CODE: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

// filter_linear_mipmap is required for textureLod blurring below.
uniform sampler2D floor_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2  crop_offset = vec2(0.2, 0.2);
uniform float crop_size   = 0.400;
// Half the arena world-unit dimensions; converts world XZ to arena UV [0,1].
uniform vec2  arena_half  = vec2(15.5, 14.5);

// Darker than the arena floor (floor BRIGHTNESS = 0.7).
const float BRIGHTNESS = 0.22;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 arena_uv = (world_pos.xz + arena_half) / (arena_half * 2.0);
	// Slight inset (0.03–0.97) so we never clamp to the absolute edge pixels,
	// which may be disproportionately dark due to content near the crop boundary.
	vec2 clamped_uv = clamp(arena_uv, 0.03, 0.97);
	vec2 crop_uv    = crop_offset + clamped_uv * crop_size;

	// Mip 9 collapses the entire crop to ~1 texel — effectively the mean colour.
	// This gives a neutral tone that no single dark edge pixel can drag down.
	vec2 center_uv = crop_offset + vec2(0.5) * crop_size;
	vec3 avg_color  = textureLod(floor_texture, center_uv, 8.0).rgb;
	vec3 edge_color = textureLod(floor_texture, crop_uv,    5.0).rgb;

	// Measure how far the edge sample sits from the crop average in RGB space.
	// Common colours (small deviation) are allowed to show through at full weight;
	// high-contrast outliers (e.g. a black shadow pixel at the crop boundary) are
	// smoothly suppressed back toward the average so they can't form visible stripes.
	float deviation = length(edge_color - avg_color);
	float weight    = 0.50 * (1.0 - smoothstep(0.10, 0.25, deviation));
	vec3  color     = mix(avg_color, edge_color, weight);

	ALBEDO = color * BRIGHTNESS;
	ALPHA  = 0.6;
}
"""

func _spawn_floor() -> void:
	var texture := load("res://assets/arena/backyard_floor.png") as Texture2D
	if texture == null:
		push_warning("Arena: floor texture not found — expected at res://assets/arena/backyard_floor.png")
		return

	# 16% of image area = a crop window with side length sqrt(0.16) ≈ 0.400.
	# A random UV offset places the window anywhere it fits inside the full image.
	const CROP_SIZE: float = 0.400
	var max_offset  := 1.0 - CROP_SIZE
	var crop_offset := Vector2(randf() * max_offset, randf() * max_offset)

	var shader := Shader.new()
	shader.code = _FLOOR_SHADER_CODE

	# Build a helper so both materials share the same texture bindings.
	var _make_mat := func(alpha: float) -> ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("floor_texture", texture)
		m.set_shader_parameter("crop_offset",   crop_offset)
		m.set_shader_parameter("crop_size",     CROP_SIZE)
		m.set_shader_parameter("line_alpha",    alpha)
		return m

	_floor_mat_overview = _make_mat.call(0.0)
	_floor_mat_zoomed   = _make_mat.call(0.15)

	var grid_w := Grid.GRID_SIZE * Grid.CELL_SIZE
	var grid_h := Grid.GRID_ROWS * Grid.CELL_SIZE
	var plane   := PlaneMesh.new()
	plane.size   = Vector2(grid_w, grid_h)
	_floor_mi               = MeshInstance3D.new()
	_floor_mi.mesh          = plane
	_floor_mi.position      = Vector3(0.0, 0.010, 0.0)
	_floor_mi.material_override = _floor_mat_overview
	add_child(_floor_mi)

	# Background plane — larger than the arena so it fills whatever the camera can see
	# beyond the walls.  It sits just below the floor (Y=0.0 vs floor Y=0.010) so the
	# floor renders on top within the arena bounds with no Z-fighting.
	var bg_shader := Shader.new()
	bg_shader.code = _BACKGROUND_SHADER_CODE

	var bg_mat := ShaderMaterial.new()
	bg_mat.shader = bg_shader
	bg_mat.set_shader_parameter("floor_texture", texture)
	bg_mat.set_shader_parameter("crop_offset",   crop_offset)
	bg_mat.set_shader_parameter("crop_size",     CROP_SIZE)
	bg_mat.set_shader_parameter("arena_half",    Vector2(grid_w * 0.5, grid_h * 0.5))

	var bg_plane := PlaneMesh.new()
	bg_plane.size = Vector2(grid_w * 4.0, grid_h * 4.0)

	var bg_mi := MeshInstance3D.new()
	bg_mi.mesh              = bg_plane
	bg_mi.position          = Vector3(0.0, 0.0, 0.0)
	bg_mi.material_override = bg_mat
	add_child(bg_mi)


## Renders the inner arena border — the outermost row/column ring of the 31×31 grid.
## Collects the wall cell positions and delegates all geometry to _spawn_wall_ring,
## which applies jittered block shapes, border lines, and surface detail (moss and
## dark smudges) consistent with the outer ring.
func _spawn_arena_border() -> void:
	var ent_row := GameState.entrance_cell.y
	var ex_row  := GameState.exit_cell.y
	var ent_gap := [ent_row - 1, ent_row, ent_row + 1]
	var ex_gap  := [ex_row  - 1, ex_row,  ex_row  + 1]

	var cells: Array[Vector2i] = []
	# Top row (row 0) and bottom row (row GRID_ROWS-1) — full width
	for col in range(Grid.GRID_SIZE):
		cells.append(Vector2i(col, 0))
		cells.append(Vector2i(col, Grid.GRID_ROWS - 1))
	# Left column (col 0) and right column (col GRID_SIZE-1), rows 1..GRID_ROWS-2.
	# Rows 0 and GRID_ROWS-1 are already in the top/bottom sets above.
	for row in range(1, Grid.GRID_ROWS - 1):
		if row not in ent_gap:
			cells.append(Vector2i(0, row))
		if row not in ex_gap:
			cells.append(Vector2i(Grid.GRID_SIZE - 1, row))

	_spawn_wall_ring(cells)


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
func _spawn_wall_slab(center: Vector3, size: Vector2, color: Color = COLOR_WALL_FILL) -> void:
	var mi    := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	mi.mesh   = plane
	var mat              := StandardMaterial3D.new()
	mat.albedo_color      = color
	mat.shading_mode      = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency      = BaseMaterial3D.TRANSPARENCY_DISABLED
	mi.material_override  = mat
	mi.position           = Vector3(center.x, 0.025, center.z)
	add_child(mi)


## Returns a randomised wall colour in the medium-dark gray range.
## Wide brightness variation produces blocks that range from near-charcoal
## to plain gray, giving the ring a rough, uneven stone appearance.
func _randomised_wall_color() -> Color:
	var brightness := 1.0 + randf_range(-0.22, 0.28)
	return Color(
		clampf(COLOR_WALL_FILL.r * brightness, 0.0, 1.0),
		clampf(COLOR_WALL_FILL.g * brightness, 0.0, 1.0),
		clampf(COLOR_WALL_FILL.b * brightness, 0.0, 1.0),
		1.0
	)


## Returns 4 corner positions for a wall cell with a small random jitter on each corner,
## in [TL, TR, BL, BR] order. Jitter is seeded by cell position so calling this twice
## for the same cell (once for fills, once for borders) produces identical corners.
func _jittered_cell_corners(cell: Vector2i, jitter: float, y: float) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	# Combine x and y with large primes to avoid collisions at any grid coordinate.
	rng.seed = (cell.x * 73856093) ^ (cell.y * 19349663) ^ 0xABCD1234
	var c  := _cell_to_world(cell)
	var hs := Grid.CELL_SIZE * 0.5
	var corners: Array[Vector3] = []
	for dz in [-hs, hs]:
		for dx in [-hs, hs]:
			corners.append(Vector3(
				c.x + dx + rng.randf_range(-jitter, jitter),
				y,
				c.z + dz + rng.randf_range(-jitter, jitter)
			))
	return corners  # order: [TL, TR, BL, BR]


## Adds one weed clump into an already-open TRIANGLES surface.
## The clump is an irregular filled polygon — random center within the cell,
## random radius at each perimeter vertex to produce an organic shape.
## Roughly 25% of clumps are living (muted olive-green); the rest are dead
## (earthy brown to tan), giving a neglected, overgrown appearance.
func _add_weed_patch_to_surface(im: ImmediateMesh, cell: Vector2i, y: float) -> void:
	var c      := _cell_to_world(cell)
	var inset  := Grid.CELL_SIZE * 0.15
	var hs     := Grid.CELL_SIZE * 0.5
	var cx     := c.x + randf_range(-(hs - inset), hs - inset)
	var cz     := c.z + randf_range(-(hs - inset), hs - inset)
	var center := Vector3(cx, y, cz)
	var radius := randf_range(0.14, 0.28) * Grid.CELL_SIZE
	var segs   := randi_range(6, 10)
	var weed_color: Color
	if randf() < 0.25:
		# Live weed: muted olive-green
		weed_color = Color(
			randf_range(0.18, 0.32),
			randf_range(0.32, 0.50),
			randf_range(0.06, 0.16),
			1.0
		)
	else:
		# Dead weed: earthy brown to dry tan
		weed_color = Color(
			randf_range(0.38, 0.58),
			randf_range(0.24, 0.38),
			randf_range(0.06, 0.14),
			1.0
		)
	# Triangle fan: center → each perimeter edge.
	# Each perimeter point has its own random radius so the clump is irregular.
	for i in range(segs):
		var a0 := (float(i)     / float(segs)) * TAU
		var a1 := (float(i + 1) / float(segs)) * TAU
		im.surface_set_color(weed_color)
		im.surface_add_vertex(center)
		im.surface_set_color(weed_color)
		im.surface_add_vertex(Vector3(cx + cos(a0) * radius * randf_range(0.55, 1.45),
				y, cz + sin(a0) * radius * randf_range(0.55, 1.45)))
		im.surface_set_color(weed_color)
		im.surface_add_vertex(Vector3(cx + cos(a1) * radius * randf_range(0.55, 1.45),
				y, cz + sin(a1) * radius * randf_range(0.55, 1.45)))


## Adds a clump of thin grass blades into an already-open TRIANGLES surface.
## Each blade is a narrow triangle: wide base at the clump centre, pointed tip
## angled outward. Multiple blades spread in random directions to read as a
## tuft of grass rather than a leafy blob.
func _add_grass_clump_to_surface(im: ImmediateMesh, cell: Vector2i, y: float) -> void:
	var c     := _cell_to_world(cell)
	var inset := Grid.CELL_SIZE * 0.20
	var hs    := Grid.CELL_SIZE * 0.5
	var cx    := c.x + randf_range(-(hs - inset), hs - inset)
	var cz    := c.z + randf_range(-(hs - inset), hs - inset)
	var blade_count := randi_range(4, 8)
	for _b in range(blade_count):
		var angle  := randf() * TAU
		var length := randf_range(0.16, 0.32) * Grid.CELL_SIZE
		var half_w := randf_range(0.018, 0.042) * Grid.CELL_SIZE
		# Tip colour is a brighter green; base colour slightly darker/yellower.
		var tip_green := Color(
			randf_range(0.10, 0.24),
			randf_range(0.38, 0.55),
			randf_range(0.06, 0.14),
			1.0
		)
		var base_green := Color(
			randf_range(0.20, 0.36),
			randf_range(0.28, 0.44),
			randf_range(0.04, 0.12),
			1.0
		)
		var perp   := angle + PI * 0.5
		var tip    := Vector3(cx + cos(angle) * length, y, cz + sin(angle) * length)
		var base_l := Vector3(cx + cos(perp) *  half_w, y, cz + sin(perp) *  half_w)
		var base_r := Vector3(cx + cos(perp) * -half_w, y, cz + sin(perp) * -half_w)
		im.surface_set_color(base_green); im.surface_add_vertex(base_l)
		im.surface_set_color(base_green); im.surface_add_vertex(base_r)
		im.surface_set_color(tip_green);  im.surface_add_vertex(tip)


## Adds one dark stain or smudge blob into an already-open TRIANGLES surface.
## Simulates water staining, biological growth, or accumulated grime on the wall face.
## Structurally identical to the moss patch but uses a dark brownish-gray palette.
func _add_dark_smudge_to_surface(im: ImmediateMesh, cell: Vector2i, y: float) -> void:
	var c      := _cell_to_world(cell)
	var inset  := Grid.CELL_SIZE * 0.12
	var hs     := Grid.CELL_SIZE * 0.5
	var cx     := c.x + randf_range(-(hs - inset), hs - inset)
	var cz     := c.z + randf_range(-(hs - inset), hs - inset)
	var center := Vector3(cx, y, cz)
	var radius := randf_range(0.10, 0.20) * Grid.CELL_SIZE
	var segs   := randi_range(5, 8)
	var dark   := Color(
		randf_range(0.10, 0.24),
		randf_range(0.10, 0.22),
		randf_range(0.06, 0.16),
		1.0
	)
	for i in range(segs):
		var a0 := (float(i)     / float(segs)) * TAU
		var a1 := (float(i + 1) / float(segs)) * TAU
		im.surface_set_color(dark)
		im.surface_add_vertex(center)
		im.surface_set_color(dark)
		im.surface_add_vertex(Vector3(cx + cos(a0) * radius * randf_range(0.55, 1.45),
				y, cz + sin(a0) * radius * randf_range(0.55, 1.45)))
		im.surface_set_color(dark)
		im.surface_add_vertex(Vector3(cx + cos(a1) * radius * randf_range(0.55, 1.45),
				y, cz + sin(a1) * radius * randf_range(0.55, 1.45)))


## Renders a set of wall cells. Spawns three MeshInstance3D nodes per ring:
##
##   Fill mesh (TRANSPARENCY_ALPHA, CULL_DISABLED) — gray block fills at Y=0.025.
##   Border mesh (TRANSPARENCY_ALPHA) — dark cell-edge lines at Y=0.030.
##   Detail mesh (TRANSPARENCY_ALPHA, CULL_DISABLED) — weed clumps and smudges at Y=0.040.
##
## All three use TRANSPARENCY_ALPHA. ImmediateMesh vertex colours only render
## reliably in the transparent pass. The Y offsets (0.025 / 0.030 / 0.040)
## guarantee the correct back-to-front draw order without depth-write tricks.
## CULL_DISABLED on fill and detail avoids any back-face culling issues that
## arise from winding-order precision at this scale.
##
## Both rings (inner and outer) call this function so they share the same
## visual treatment and surface detail density.
func _spawn_wall_ring(cells: Array[Vector2i]) -> void:
	const Y_FILL:   float = 0.025
	const Y_BORDER: float = 0.030
	const Y_DETAIL: float = 0.040
	const JITTER:   float = Grid.CELL_SIZE * 0.035

	# -----------------------------------------------------------------------
	# Fill mesh: one TRIANGLES surface, one MeshInstance — mirrors the setup
	# used by the detail mesh which is known to render correctly.
	# -----------------------------------------------------------------------
	var im_fill := ImmediateMesh.new()
	im_fill.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell in cells:
		var color   := _randomised_wall_color()
		var corners := _jittered_cell_corners(cell, JITTER, Y_FILL)
		# CCW from above: TL→BL→BR and TL→BR→TR (normals face +Y toward camera)
		im_fill.surface_set_color(color); im_fill.surface_add_vertex(corners[0])  # TL
		im_fill.surface_set_color(color); im_fill.surface_add_vertex(corners[2])  # BL
		im_fill.surface_set_color(color); im_fill.surface_add_vertex(corners[3])  # BR
		im_fill.surface_set_color(color); im_fill.surface_add_vertex(corners[0])  # TL
		im_fill.surface_set_color(color); im_fill.surface_add_vertex(corners[3])  # BR
		im_fill.surface_set_color(color); im_fill.surface_add_vertex(corners[1])  # TR
	im_fill.surface_end()

	var mi_fill  := MeshInstance3D.new()
	mi_fill.mesh  = im_fill
	var mat_fill := StandardMaterial3D.new()
	mat_fill.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_fill.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_fill.vertex_color_use_as_albedo = true
	mat_fill.cull_mode                  = BaseMaterial3D.CULL_DISABLED
	mi_fill.material_override = mat_fill
	add_child(mi_fill)

	# -----------------------------------------------------------------------
	# Border mesh: one LINES surface for the cell-edge grid lines.
	# -----------------------------------------------------------------------
	var im_border := ImmediateMesh.new()
	im_border.surface_begin(Mesh.PRIMITIVE_LINES)
	for cell in cells:
		var corners := _jittered_cell_corners(cell, JITTER, Y_BORDER)
		im_border.surface_set_color(COLOR_WALL_BORDER)
		im_border.surface_add_vertex(corners[0]); im_border.surface_add_vertex(corners[1])  # TL→TR
		im_border.surface_add_vertex(corners[1]); im_border.surface_add_vertex(corners[3])  # TR→BR
		im_border.surface_add_vertex(corners[3]); im_border.surface_add_vertex(corners[2])  # BR→BL
		im_border.surface_add_vertex(corners[2]); im_border.surface_add_vertex(corners[0])  # BL→TL
	im_border.surface_end()

	var mi_border  := MeshInstance3D.new()
	mi_border.mesh  = im_border
	var mat_border := StandardMaterial3D.new()
	mat_border.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_border.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_border.vertex_color_use_as_albedo = true
	mi_border.material_override = mat_border
	add_child(mi_border)

	# -----------------------------------------------------------------------
	# Detail mesh: moss patches and dark smudges
	# TRANSPARENCY_ALPHA → transparent pass → depth-tested against solid fills
	# CULL_DISABLED covers any winding variance in the irregular triangle fans
	# -----------------------------------------------------------------------
	var im_detail := ImmediateMesh.new()
	im_detail.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell in cells:
		if randf() < 0.60:
			var patch_count := randi_range(1, 4)
			for _p in range(patch_count):
				# ~40% grass blades, ~60% weed blobs
				if randf() < 0.40:
					_add_grass_clump_to_surface(im_detail, cell, Y_DETAIL)
				else:
					_add_weed_patch_to_surface(im_detail, cell, Y_DETAIL)
		if randf() < 0.35:
			var smudge_count := randi_range(1, 2)
			for _s in range(smudge_count):
				_add_dark_smudge_to_surface(im_detail, cell, Y_DETAIL)
	im_detail.surface_end()

	var mi_detail  := MeshInstance3D.new()
	mi_detail.mesh  = im_detail
	var mat_detail := StandardMaterial3D.new()
	mat_detail.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_detail.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_detail.vertex_color_use_as_albedo = true
	mat_detail.cull_mode                  = BaseMaterial3D.CULL_DISABLED
	mi_detail.material_override = mat_detail
	add_child(mi_detail)


## Renders the outer ring of wall cells — one grid square thick, surrounding the inner border.
## Collects outer-ring cell positions and delegates all geometry to _spawn_wall_ring,
## which applies jittered block shapes, border lines, and surface detail consistent
## with the inner ring.
##
## Gap rows in the left and right outer columns match the entrance and exit gaps in the
## inner wall so enemies pass through both wall thicknesses unobstructed.
func _spawn_outer_border_ring() -> void:
	var ent_row := GameState.entrance_cell.y
	var ex_row  := GameState.exit_cell.y
	var ent_gap := [ent_row - 1, ent_row, ent_row + 1]
	var ex_gap  := [ex_row  - 1, ex_row,  ex_row  + 1]

	var cells: Array[Vector2i] = []
	# Top and bottom outer rows — full width including corner cells
	for col in range(-1, Grid.GRID_SIZE + 1):
		cells.append(Vector2i(col, -1))
		cells.append(Vector2i(col, Grid.GRID_ROWS))
	# Left and right outer columns — rows 0..GRID_ROWS-1 (corners covered by top/bottom above)
	for row in range(Grid.GRID_ROWS):
		if row not in ent_gap:
			cells.append(Vector2i(-1, row))
		if row not in ex_gap:
			cells.append(Vector2i(Grid.GRID_SIZE, row))

	_spawn_wall_ring(cells)


## Spawns the cave entrance/exit image at the gap in the border wall.
## rotation_y controls orientation: −90° for the exit (apex faces world +X),
## +90° for the entrance (image flipped 180° so it reads correctly from that side).
## center_cell is the outside spawn/despawn cell adjacent to the gap.
func _spawn_cave_marker(center_cell: Vector2i, rotation_y: float) -> void:
	var texture := load("res://assets/arena/enter_exit_cave.png") as Texture2D

	var plane    := PlaneMesh.new()
	# Local X (3 cells) maps to world Z after −90° Y rotation — spans the 3-row gap.
	# Local Z (1 cell) maps to world X — covers only the border wall column.
	plane.size = Vector2(Grid.CELL_SIZE * 3.0, Grid.CELL_SIZE * 1.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode      = BaseMaterial3D.CULL_DISABLED

	var mi              := MeshInstance3D.new()
	mi.mesh              = plane
	mi.material_override = mat

	var world          := _cell_to_world(center_cell)
	# center_cell is the outer border ring cell — position directly there so the
	# cave aligns with the outer wall. The inner-wall gap cells remain arena background.
	mi.position         = Vector3(world.x, 0.02, world.z)
	mi.rotation_degrees = Vector3(0.0, rotation_y, 0.0)

	add_child(mi)


## Spawns a Trap node centred on the 2x2 footprint and wires it to the
## active enemy list. The trap manages its own visual and combat logic.
func _spawn_trap(anchor: Vector2i) -> void:
	var trap := Trap.new()
	var center := _cell_to_world(anchor) + Vector3(Grid.CELL_SIZE * 0.5, 0.0, Grid.CELL_SIZE * 0.5)
	trap.position = center + Vector3(0.0, Grid.CELL_SIZE * 0.25, 0.0)
	trap.fired.connect(_on_trap_fired)
	trap.aoe_fired.connect(_on_fogger_aoe_fired)
	trap.fly_strip_fired.connect(_on_fly_strip_fired)
	trap.initialize(GameState.selected_trap_type as Trap.TrapType, _active_enemies)
	# Arena is PROCESS_MODE_ALWAYS; override so traps pause with the game.
	trap.process_mode = Node.PROCESS_MODE_PAUSABLE
	_trap_container.add_child(trap)
	GameState.spend_bug_bucks(trap.get_cost())
	_trap_nodes[anchor] = trap


func _on_trap_fired(from_pos: Vector3, to_pos: Vector3, target: Node3D, damage: float, trap_type: int) -> void:
	var proj := Projectile.new()
	proj.initialize(from_pos, to_pos, target, damage, trap_type)
	# Arena is PROCESS_MODE_ALWAYS; override so projectiles pause with the game.
	proj.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(proj)


func _on_fogger_aoe_fired(from_pos: Vector3, aoe_range: float, damage: float, active_enemies: Array) -> void:
	var cloud := FogCloud.new()
	cloud.initialize(from_pos, aoe_range, damage, active_enemies)
	# Arena is PROCESS_MODE_ALWAYS; override so fog clouds pause with the game.
	cloud.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(cloud)


func _on_fly_strip_fired(from_pos: Vector3, aoe_range: float, damage: float,
		adhesion: float, cloud_duration: float, active_enemies: Array) -> void:
	var cloud := FlyStripCloud.new()
	cloud.initialize(from_pos, aoe_range, damage, adhesion, cloud_duration, active_enemies)
	cloud.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(cloud)


## Places a Boost unit at anchor. Boosts block pathfinding like traps.
## Returns true if placement succeeded.
func _try_place_boost(anchor: Vector2i, boost_type: BoostUnit.BoostType) -> bool:
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
		_boost_anchors[cell] = anchor

	var boost := BoostUnit.new()
	var center := _cell_to_world(anchor) + Vector3(Grid.CELL_SIZE * 0.5, 0.0, Grid.CELL_SIZE * 0.5)
	boost.position = center + Vector3(0.0, Grid.CELL_SIZE * 0.25, 0.0)
	boost.process_mode = Node.PROCESS_MODE_PAUSABLE
	boost.initialize(boost_type, _active_enemies, _trap_nodes)
	boost.boost_depleted.connect(_try_remove_boost_by_anchor.bind(anchor))
	add_child(boost)
	_boost_nodes[anchor] = boost
	GameState.spend_bug_bucks(boost.get_cost())
	# cell_changed from place_trap() above triggers Pathfinder recalculation automatically.
	return true


## Removes a Boost unit and refunds 70% of its cost.
func _try_remove_boost_by_anchor(anchor: Vector2i) -> void:
	if _boost_nodes.has(anchor):
		var boost: Node3D = _boost_nodes[anchor]
		var refund: int = int(boost.get_cost() * 0.70)
		GameState.add_bug_bucks(refund)
		boost.queue_free()
		_boost_nodes.erase(anchor)
	for c in _get_trap_cells(anchor):
		_grid.remove_trap(c)
		_boost_anchors.erase(c)
	# cell_changed from remove_trap() triggers Pathfinder recalculation automatically.


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


## Sizes and positions the orthographic camera so the arena fills the space
## between the left and right HUD panels, with the same margins as the HUD
## panel content: MARGIN on the inner panel edges, SCREEN_EDGE_MARGIN on the
## top and bottom screen edges (which may have rounded corners on mobile).
## Stores the resulting size as _overview_camera_size for zoom logic.
##
## v_offset sign convention for this top-down camera (local Y = world −Z):
##   positive → aim shifts toward world −Z → origin appears lower on screen.
func _fit_camera_to_grid() -> void:
	var vp       := get_viewport().get_visible_rect().size
	# Left/right: match the HUD panel inner padding (MARGIN).
	# Top/bottom: match the HUD panel screen-edge inset (SCREEN_EDGE_MARGIN)
	# which clears rounded corners on mobile devices.
	var usable_w := vp.x - HUD.LEFT_PANEL_W - HUD.RIGHT_PANEL_W - HUD.MARGIN * 2.0
	var usable_h := vp.y - HUD.SCREEN_EDGE_MARGIN * 2.0
	if usable_h <= 0.0 or usable_w <= 0.0:
		return

	# +3 keeps a minimal margin beyond the outer wall ring; zoom mode pans within this space.
	var arena_w := Grid.GRID_SIZE * Grid.CELL_SIZE + 3.0
	var arena_h := Grid.GRID_ROWS * Grid.CELL_SIZE + 3.0

	# With KEEP_HEIGHT, horizontal world coverage = size × (vp.x / vp.y).
	# arena_w and arena_h differ now that the grid is not square.
	var size_for_height  := arena_h * vp.y / usable_h
	var size_for_width   := arena_w * vp.y / usable_w
	_overview_camera_size = maxf(size_for_height, size_for_width)
	# Store separate half-extents so pan clamping uses the correct bound per axis.
	_arena_world_half   = arena_w / 2.0
	_arena_world_half_z = arena_h / 2.0

	if _zoom_state == ZoomState.OVERVIEW:
		_camera.size = _overview_camera_size

	# Shift the camera centre to the midpoint of the usable horizontal band
	# (left panel + MARGIN … right panel + MARGIN).
	var world_per_px     := _overview_camera_size / vp.y
	var h_center_px      := HUD.LEFT_PANEL_W + HUD.MARGIN + usable_w * 0.5
	_camera_base_h_offset = (h_center_px - vp.x * 0.5) * world_per_px
	_camera.h_offset      = _camera_base_h_offset
	_camera.v_offset      = 0.0


## Each frame: track the followed enemy, and promote a held pointer to DRAG_PLACING.
func _process(delta: float) -> void:
	# Don't track enemies while paused — the enemy is frozen, and the player
	# should be able to pan freely to inspect the arena during pause.
	if not get_tree().paused and _followed_enemy != null and is_instance_valid(_followed_enemy):
		var p := _followed_enemy.global_position
		_apply_pan(Vector2(p.x, p.z))

	# Hold-to-place from the arena is removed: placement now only initiates
	# via drag from the HUD trap icon panel (see begin_hud_drag / update_hud_drag).


## Toggles between OVERVIEW and ZOOMED_IN camera levels.
## ZOOMED_IN is 2× magnification (half the overview camera.size), with panning enabled.
func _toggle_zoom() -> void:
	if _zoom_state == ZoomState.OVERVIEW:
		_zoom_state     = ZoomState.ZOOMED_IN
		_camera.size    = _overview_camera_size * 0.5
		_pan_world_pos  = Vector2.ZERO
		_apply_pan(_pan_world_pos)
	else:
		_zoom_state      = ZoomState.OVERVIEW
		_set_followed_enemy(null)
		_camera.size     = _overview_camera_size
		_camera.h_offset = _camera_base_h_offset
		_camera.v_offset = 0.0
	var zoomed_in := _zoom_state == ZoomState.ZOOMED_IN
	if _floor_mi != null:
		_floor_mi.material_override = _floor_mat_zoomed if zoomed_in else _floor_mat_overview
	GameState.zoom_state_changed.emit(zoomed_in)


## Pans the camera to pos (world XZ), clamped so the arena never scrolls off-screen.
func _apply_pan(pos: Vector2) -> void:
	var vp            := get_viewport().get_visible_rect().size
	var world_per_px  := _camera.size / vp.y
	var visible_half_w := (vp.x - HUD.LEFT_PANEL_W - HUD.RIGHT_PANEL_W - HUD.MARGIN * 2.0) * world_per_px * 0.5
	var visible_half_h := (vp.y - HUD.SCREEN_EDGE_MARGIN * 2.0) * world_per_px * 0.5
	var cx := clampf(pos.x, -_arena_world_half   + visible_half_w, _arena_world_half   - visible_half_w)
	var cz := clampf(pos.y, -_arena_world_half_z + visible_half_h, _arena_world_half_z - visible_half_h)
	_pan_world_pos   = Vector2(cx, cz)
	_camera.h_offset = _camera_base_h_offset + cx
	_camera.v_offset = -cz


## Resets camera to overview when a run ends.
func _on_run_ended_camera() -> void:
	_set_followed_enemy(null)
	if _zoom_state == ZoomState.ZOOMED_IN:
		_toggle_zoom()


## Plays phase-transition audio cues.
## wave_start fires when a wave begins; wave_clear fires between waves
## (but not before wave 1 — there is nothing to clear yet).
func _on_phase_changed_audio(new_phase: GameState.Phase) -> void:
	match new_phase:
		GameState.Phase.WAVE:
			AudioManager.play_ui("wave_start")
		GameState.Phase.PLACING:
			if GameState.current_wave > 0:
				AudioManager.play_ui("wave_clear")


## Builds a Trap preview node: full mesh hierarchy, no combat logic, no hover area.
## All mesh materials are duplicated and dimmed to alpha so the result reads as a ghost.
## When valid=false, materials are overridden to neutral gray to signal an invalid location.
func _make_trap_preview(trap_type: int, alpha: float, valid: bool = true) -> Node3D:
	var preview := Trap.new()
	preview.process_mode = Node.PROCESS_MODE_DISABLED
	preview.initialize_preview(trap_type as Trap.TrapType)
	_apply_ghost_transparency(preview, alpha, valid)
	add_child(preview)
	return preview


## Recursively dims all MeshInstance3D materials in a node subtree.
## Duplicates each material so the original asset is not modified.
## When valid=false, albedo is replaced with neutral gray regardless of the original color.
func _apply_ghost_transparency(node: Node, alpha: float, valid: bool = true) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.material_override != null:
				var mat := mi.material_override as StandardMaterial3D
				if mat != null:
					mat = mat.duplicate() as StandardMaterial3D
					if valid:
						mat.albedo_color.a = alpha
					else:
						# Blend 50% toward mid-gray — desaturates and dims without going fully colorless.
						mat.albedo_color = mat.albedo_color.lerp(Color(0.5, 0.5, 0.5, mat.albedo_color.a), 0.5)
						mat.albedo_color.a = alpha
					mat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
					mi.material_override = mat
		_apply_ghost_transparency(child, alpha, valid)


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


# ---------------------------------------------------------------------------
# Grid line display settings
# ---------------------------------------------------------------------------

## Reads grid line preferences from settings.cfg and applies them to the floor
## materials.  Called once at startup so the floor is correct before the first
## frame renders, independently of when HUD initialises and emits its signal.
func _apply_floor_grid_lines_from_cfg() -> void:
	var cfg := ConfigFile.new()
	var show_overview: bool = false
	var show_zoomed:   bool = true
	if cfg.load("user://settings.cfg") == OK:
		show_overview = cfg.get_value("display", "grid_lines_overview", false)
		show_zoomed   = cfg.get_value("display", "grid_lines_zoomed",   true)
	_set_floor_grid_lines(show_overview, show_zoomed)


## Receives the signal emitted by HUD when the player changes a grid line toggle.
func _on_grid_lines_changed(show_overview: bool, show_zoomed: bool) -> void:
	_set_floor_grid_lines(show_overview, show_zoomed)


## Updates line_alpha on both floor shader materials and re-applies the active
## one so the change is visible immediately without waiting for a zoom toggle.
func _set_floor_grid_lines(show_overview: bool, show_zoomed: bool) -> void:
	if _floor_mat_overview == null or _floor_mat_zoomed == null:
		return
	_floor_mat_overview.set_shader_parameter("line_alpha", 0.15 if show_overview else 0.0)
	_floor_mat_zoomed.set_shader_parameter("line_alpha",   0.15 if show_zoomed  else 0.0)
	# Re-apply whichever material is currently in use so the updated alpha takes
	# effect right away instead of waiting for the next zoom toggle.
	if _floor_mi != null:
		var currently_zoomed := _zoom_state == ZoomState.ZOOMED_IN
		_floor_mi.material_override = _floor_mat_zoomed if currently_zoomed else _floor_mat_overview


# ---------------------------------------------------------------------------
# Earn label
# ---------------------------------------------------------------------------

## Spawns a gold "+N🪙" label at screen_pos that drifts upward and fades out over 1.4 s.
## Called from every site that awards bug bucks so the player always sees what they earned.
## Uses a Node2D subclass (_EarnTextNode) to draw the text — a Control (Label) would collapse
## to zero size in a CanvasLayer because CanvasLayer bypasses the Control layout system.
func _spawn_earn_label(screen_pos: Vector2, amount: int) -> void:
	if amount <= 0:
		return

	var host := CanvasLayer.new()
	host.layer        = 10
	host.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(host)

	var node := _EarnTextNode.new()
	node.setup("+%d" % amount, UIFonts.primary_bold(), 23)
	# Offset slightly right and above the event so the text doesn't overlap the sprite.
	node.position = screen_pos + Vector2(14.0, -10.0)
	host.add_child(node)

	# Drift upward while fading: EASE_OUT on position (starts fast, slows)
	# and EASE_IN on alpha (holds briefly, then fades quickly) — natural "announcement" feel.
	var tween := host.create_tween().set_parallel(true)
	tween.tween_property(node, "position:y", node.position.y - 60.0, 1.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(node, "modulate:a", 0.0, 1.4) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	get_tree().create_timer(1.6).timeout.connect(host.queue_free)


## Draws a coin icon followed by a gold number, both without any outline.
## Extends Node2D rather than Control so it renders correctly as a direct child of
## a CanvasLayer — Control nodes need a parent Control for layout; Node2D nodes do not.
class _EarnTextNode extends Node2D:
	var _text:      String    = ""
	var _font:      Font      = null
	var _font_size: int       = 38
	var _coin_tex:  Texture2D = null

	func setup(text: String, font: Font, font_size: int) -> void:
		_text      = text
		_font      = font
		_font_size = font_size
		_coin_tex  = load("res://assets/bug_buck_coin_small.png") as Texture2D

	func _draw() -> void:
		if _font == null:
			return
		# Icon is sized to roughly match the cap-height of the text; positioned so
		# its vertical center aligns with the midpoint of the font's ascent.
		var icon_size := int(_font_size * 0.75)
		var top_y     := -int(_font_size * 0.78)
		if _coin_tex:
			draw_texture_rect(_coin_tex, Rect2(Vector2(0.0, top_y), Vector2(icon_size, icon_size)), false)
		# Text starts immediately to the right of the icon with a small gap.
		var text_x := float(icon_size + 4)
		draw_string(_font, Vector2(text_x, 0.0), _text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			_font_size, Color(1.00, 0.82, 0.10, 1.0))
