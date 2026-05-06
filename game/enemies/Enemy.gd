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

const Grid          = preload("res://arena/Grid.gd")
const SHADOW_BLOB_SHADER = preload("res://assets/shadow_blob.gdshader")

const ANT_FRAMES: Array[Texture2D] = [
	preload("res://assets/ant_walk_1.svg"),
	preload("res://assets/ant_walk_2.svg"),
	preload("res://assets/ant_walk_3.svg"),
	preload("res://assets/ant_walk_4.svg"),
]
const GNAT_FRAMES: Array[Texture2D] = [
	preload("res://assets/gnat_walk_1.svg"),
	preload("res://assets/gnat_walk_2.svg"),
	preload("res://assets/gnat_walk_3.svg"),
	preload("res://assets/gnat_walk_4.svg"),
]
const CRICKET_FRAMES: Array[Texture2D] = [
	preload("res://assets/cricket_walk_1.svg"),
	preload("res://assets/cricket_walk_2.svg"),
	preload("res://assets/cricket_walk_3.svg"),
	preload("res://assets/cricket_walk_4.svg"),
]
const BEETLE_FRAMES: Array[Texture2D] = [
	preload("res://assets/beetle_walk_1.svg"),
	preload("res://assets/beetle_walk_2.svg"),
	preload("res://assets/beetle_walk_3.svg"),
	preload("res://assets/beetle_walk_4.svg"),
]
const COCKROACH_FRAMES: Array[Texture2D] = [
	preload("res://assets/cockroach_walk_1.svg"),
	preload("res://assets/cockroach_walk_2.svg"),
	preload("res://assets/cockroach_walk_3.svg"),
	preload("res://assets/cockroach_walk_4.svg"),
]
const RAT_FRAMES: Array[Texture2D] = [
	preload("res://assets/rat_walk_1.svg"),
	preload("res://assets/rat_walk_2.svg"),
	preload("res://assets/rat_walk_3.svg"),
	preload("res://assets/rat_walk_4.svg"),
]


# ---------------------------------------------------------------------------
# Enemy type
# ---------------------------------------------------------------------------

enum EnemyType { ANT, GNAT, CRICKET, BEETLE, COCKROACH, RAT }

## Per-type stat table. All numeric values are placeholders — tuned via playtesting.
##   hp            — starting (and maximum) hit points
##   speed         — movement speed in cells per second
##   infestation   — Infestation Level increase when this pest reaches the exit
##   color         — used only for kill-burst particle color
const STATS := {
	EnemyType.ANT:       { "hp": 10,  "speed": 2.55,  "infestation": 1,  "bounty": 10, "color": Color(0.85, 0.35, 0.15) },
	EnemyType.GNAT:      { "hp":  5,  "speed": 5.80,  "infestation": 1,  "bounty": 8,  "color": Color(0.16, 0.14, 0.19) },
	EnemyType.CRICKET:   { "hp":  8,  "speed": 4.25,  "infestation": 1,  "bounty": 2,  "color": Color(0.35, 0.55, 0.12) },
	EnemyType.BEETLE:    { "hp": 40,  "speed": 1.275, "infestation": 3,  "bounty": 2,  "color": Color(0.10, 0.22, 0.50) },
	EnemyType.COCKROACH: { "hp": 80,  "speed": 0.85,  "infestation": 5,  "bounty": 2,  "color": Color(0.48, 0.21, 0.06) },
	EnemyType.RAT:       { "hp": 200, "speed": 0.595, "infestation": 10, "bounty": 2,  "color": Color(0.56, 0.53, 0.50) },
}

# Visual quad size and shadow size vary by type so larger enemies read bigger on screen.
const VISUAL_QUAD_SIZE: Dictionary = {
	EnemyType.ANT:       2.10,
	EnemyType.GNAT:      1.60,
	EnemyType.CRICKET:   1.90,
	EnemyType.BEETLE:    2.40,
	EnemyType.COCKROACH: 2.60,
	EnemyType.RAT:       3.20,
}
const SHADOW_PLANE_SIZE: Dictionary = {
	EnemyType.ANT:       2.72,
	EnemyType.GNAT:      2.10,
	EnemyType.CRICKET:   2.50,
	EnemyType.BEETLE:    3.10,
	EnemyType.COCKROACH: 3.40,
	EnemyType.RAT:       4.20,
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

## Speed multiplier applied while at least one Glue Board is in range.
## 0.285 = 71.5% slowdown (up 30% from the original 55% slowdown at 0.45).
const SLOW_FACTOR: float = 0.285


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

# Enemy type stored so visual and shadow setup can look up per-type sizes and frames.
var _enemy_type: EnemyType = EnemyType.ANT

# Walk frame set for this enemy — assigned in initialize() based on type.
var _walk_frames: Array[Texture2D] = []

# The last cell centre the enemy fully arrived at.
var _current_cell: Vector2i = Vector2i.ZERO

# The cell centre the enemy is currently moving toward.
var _target_cell: Vector2i = Vector2i.ZERO

# The current path and the index of _target_cell within it.
var _path: Array[Vector2i] = []
var _path_index: int = 0

# Reference to the visual mesh so _process can apply the waddle each frame.
var _visual: MeshInstance3D = null

# Flat shadow quad positioned just above the floor; its basis stays in sync with _visual.
var _shadow_mi: MeshInstance3D = null

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

# Slow state — tracks how many Glue Boards currently have this enemy in range.
# Speed is reduced while count > 0 and restored when it drops back to zero.
var _base_move_speed: float = 0.0
var _slow_source_count: int = 0

# Glue splatter visual — spawned when the first slow source is applied,
# freed when the last one is removed.
var _glue_splatter: Node3D = null

# Accumulated walk time used to index into _walk_frames.
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
func initialize(initial_path: Array[Vector2i], enemy_type: EnemyType = EnemyType.ANT, wave: int = 1) -> void:
	if initial_path.size() < 2:
		return

	_enemy_type    = enemy_type
	_walk_frames   = _frames_for_type(enemy_type)

	var stats          = STATS[enemy_type]
	_move_speed        = stats["speed"]
	_base_move_speed   = _move_speed
	_max_hp            = wave * 1.02 + stats["hp"]
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
	_spawn_shadow()


# ---------------------------------------------------------------------------
# Combat
# ---------------------------------------------------------------------------

## Reduces HP by amount. Triggers death if HP reaches zero.
## Has no effect if the enemy is already dead.
func take_damage(amount: float, flash_color: Color = Color.WHITE) -> void:
	if _is_dead:
		return
	_current_hp = maxf(_current_hp - amount, 0.0)
	if _current_hp == 0.0:
		_die()
	else:
		_flash_hit(flash_color)


## Called by a Glue Board when this enemy enters its range circle.
## Reference-counted so overlapping boards compose correctly.
func add_slow_source() -> void:
	_slow_source_count += 1
	if _slow_source_count == 1:
		_move_speed = _base_move_speed * SLOW_FACTOR
		_show_glue_splatter()


## Called by a Glue Board when this enemy leaves its range circle (or the board is removed).
func remove_slow_source() -> void:
	_slow_source_count = maxi(_slow_source_count - 1, 0)
	if _slow_source_count == 0:
		_move_speed = _base_move_speed
		_hide_glue_splatter()


## Briefly flashes the enemy white then returns to its base color.
## Cancels any in-progress flash so rapid hits don't stack.
func _flash_hit(color: Color) -> void:
	if _visual == null:
		return
	if _hit_tween != null:
		_hit_tween.kill()
	var mat: StandardMaterial3D = _visual.material_override
	_hit_tween = create_tween()
	# Overbright tint in the trap's theme color, then return to neutral white.
	_hit_tween.tween_property(mat, "albedo_color", Color(color.r * 4.0, color.g * 4.0, color.b * 4.0, 1.0), 0.04)
	_hit_tween.tween_property(mat, "albedo_color", Color.WHITE, 0.08)


## Returns current HP as a fraction of max HP (0.0–1.0).
func get_hp_fraction() -> float:
	return _current_hp / _max_hp if _max_hp > 0.0 else 0.0


## Returns the Infestation Level damage this pest deals on exit.
func get_infestation_damage() -> int:
	return _infestation_damage


## Returns the Bug Bucks awarded to the player for killing this pest.
func get_bounty() -> int:
	return _bounty


## Returns the base color for this enemy type (used by kill-burst particles).
func get_color() -> Color:
	return _base_color


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
		_visual_material.albedo_texture = _walk_frames[int(_walk_time * _move_speed * 3.0) % _walk_frames.size()]


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
	# Flash overbright then fade to transparent — readable with colored sprites.
	tween.tween_property(mat, "albedo_color", Color(4.0, 4.0, 4.0, 1.0), DEATH_FLASH_DURATION * 0.35)
	tween.tween_property(mat, "albedo_color", Color(1.0, 1.0, 1.0, 0.0), DEATH_FLASH_DURATION * 0.65)
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


## Spawns the glue splatter overlay on first contact with a Glue Board.
## Each instance generates a fresh random layout so no two enemies wear
## the same badge — one large central blob plus 3–5 satellite drops.
func _show_glue_splatter() -> void:
	if _glue_splatter != null:
		return
	_glue_splatter            = Node3D.new()
	_glue_splatter.position.y = 0.015   # sits just above the enemy sprite

	var cs    := Grid.CELL_SIZE
	var color := Color(0.88, 0.70, 0.18, 0.88)   # amber, matches Glue Board trap color

	# Central blob — largest piece
	_add_splatter_blob(_glue_splatter, Vector3.ZERO, cs * randf_range(0.13, 0.19), color)

	# Satellite blobs — randomised count, angle, distance, and size
	var count := randi_range(3, 5)
	for _i in range(count):
		var angle := randf_range(0.0, TAU)
		var dist  := cs * randf_range(0.12, 0.27)
		var pos   := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		_add_splatter_blob(_glue_splatter, pos, cs * randf_range(0.05, 0.11), color)

	add_child(_glue_splatter)


## Frees the splatter overlay when the last slow source is removed.
func _hide_glue_splatter() -> void:
	if _glue_splatter == null:
		return
	_glue_splatter.queue_free()
	_glue_splatter = null


## Adds one flat irregular blob to parent at pos.
## Shape is generated by _build_glue_blob_mesh, which perturbs each radius
## independently — no two blobs are the same shape.
func _add_splatter_blob(parent: Node3D, pos: Vector3, base_r: float, color: Color) -> void:
	var mi     := MeshInstance3D.new()
	mi.mesh     = _build_glue_blob_mesh(base_r, color)
	mi.position = pos
	var mat                       := StandardMaterial3D.new()
	mat.albedo_color               = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode                  = BaseMaterial3D.CULL_DISABLED
	mi.material_override           = mat
	parent.add_child(mi)


## Builds a flat ImmediateMesh polygon on the XZ plane.
## Each of the 7 radii is independently scaled by a random factor so the
## outline is irregular — blobby rather than circular.
func _build_glue_blob_mesh(base_r: float, color: Color) -> ImmediateMesh:
	var im       := ImmediateMesh.new()
	var segments := 7
	var pts: Array[Vector3] = []
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		var r     := base_r * randf_range(0.60, 1.40)
		pts.append(Vector3(cos(angle) * r, 0.0, sin(angle) * r))
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		im.surface_set_color(color); im.surface_add_vertex(Vector3.ZERO)
		im.surface_set_color(color); im.surface_add_vertex(pts[i])
		im.surface_set_color(color); im.surface_add_vertex(pts[(i + 1) % segments])
	im.surface_end()
	return im


## Returns the walk-frame array for the given enemy type.
func _frames_for_type(enemy_type: EnemyType) -> Array[Texture2D]:
	match enemy_type:
		EnemyType.ANT:       return ANT_FRAMES
		EnemyType.GNAT:      return GNAT_FRAMES
		EnemyType.CRICKET:   return CRICKET_FRAMES
		EnemyType.BEETLE:    return BEETLE_FRAMES
		EnemyType.COCKROACH: return COCKROACH_FRAMES
		EnemyType.RAT:       return RAT_FRAMES
	return ANT_FRAMES


## Creates the enemy visual as a billboard quad using the per-type sprite.
## Each SVG carries its own baked colors; albedo_color stays white.
## Quad size scales with enemy type so larger enemies read bigger on screen.
func _spawn_visual(color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()

	var quad_cells := VISUAL_QUAD_SIZE[_enemy_type]
	var quad       := QuadMesh.new()
	quad.size       = Vector2(Grid.CELL_SIZE * quad_cells, Grid.CELL_SIZE * quad_cells)
	mesh_instance.mesh = quad

	# _base_color is kept for particle effects; the sprite carries its own baked colors.
	_base_color = color

	var material                  := StandardMaterial3D.new()
	material.albedo_color          = Color.WHITE   # do not tint — SVG colors are baked in
	material.albedo_texture        = _walk_frames[0]
	material.shading_mode          = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency          = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = material
	_visual_material               = material
	mesh_instance.basis            = _facing_basis(_target_cell - _current_cell)

	_visual = mesh_instance
	add_child(mesh_instance)


## Adds a soft drop shadow on the floor beneath the enemy.
## PlaneMesh is used because it is already horizontal (XZ plane) and requires no
## basis manipulation.  The facing direction is passed as a shader uniform instead
## so the shadow silhouette stays aligned with the ant's movement direction.
##
## The shadow sits just above the floor (world y = 0.013). Because the enemy root
## is at y = 0.25, the local Y offset is -0.237.
func _spawn_shadow() -> void:
	_shadow_mi      = MeshInstance3D.new()
	var shadow_cells := SHADOW_PLANE_SIZE[_enemy_type]
	var plane        := PlaneMesh.new()
	plane.size        = Vector2(Grid.CELL_SIZE * shadow_cells, Grid.CELL_SIZE * shadow_cells)
	_shadow_mi.mesh   = plane

	var mat          := ShaderMaterial.new()
	mat.shader        = SHADOW_BLOB_SHADER
	_shadow_mi.material_override = mat

	_shadow_mi.position.y = 0.05 - 0.25
	add_child(_shadow_mi)
