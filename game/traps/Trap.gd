## Trap.gd
## A player-placed trap that scans for enemies within its range and fires
## on a cooldown, dealing damage instantly on fire.
##
## Targeting model:
##   Each trap type has its own targeting priority:
##     SNAP_TRAP  — nearest enemy in range
##     ZAPPER     — farthest-along-path enemy in range (Phase 4)
##     FOGGER     — all enemies in range simultaneously (Phase 4)
##     GLUE_BOARD — passive slow; no projectile (Phase 4)
##
##   "Farthest along path" is determined by the enemy's path index —
##   higher index means closer to the exit, so it is the greater threat.
##
## Damage model:
##   Damage is applied instantly when the trap fires. The projectile that
##   follows is purely cosmetic — it travels to where the enemy was at
##   fire time and does nothing on arrival.
##
## Upgrade model:
##   Each trap instance tracks three independent upgrade levels — one per
##   stat (Damage, Range, Fire Rate). Each stat can be upgraded up to
##   MAX_UPGRADE_LEVEL (3) times. Costs per level are defined in UPGRADE_COSTS.
##
## Usage: instantiate via Arena, call initialize(), set position, then
## add to the scene tree.

extends Node3D

const Grid       = preload("res://arena/Grid.gd")
const Projectile = preload("res://traps/Projectile.gd")
const FogCloud   = preload("res://traps/FogCloud.gd")


# ---------------------------------------------------------------------------
# Trap type
# ---------------------------------------------------------------------------

enum TrapType { SNAP_TRAP, ZAPPER, FOGGER, GLUE_BOARD }

## Per-type stat table. All numeric values are placeholders — tuned via playtesting.
##   damage   — HP removed from each target per shot
##   range    — circular detection radius in world units (1 unit = 1 cell)
##   cooldown — seconds between shots; 0.0 = passive (no shots fired)
##   cost     — Bug Bucks to place one trap of this type
##   color    — placeholder box colour (replaced by sprites in Phase 3)
const STATS := {
	TrapType.SNAP_TRAP:  { "damage": 3.375, "range": 5.6, "cooldown": 1.0, "cost": 25, "color": Color(0.40, 0.40, 0.80) },
	TrapType.ZAPPER:     { "damage": 56.25, "range": 9.6, "cooldown": 2.5, "cost": 60, "color": Color(0.90, 0.85, 0.20) },
	TrapType.FOGGER:     { "damage": 4.5,   "range": 4.0, "cooldown": 2.2, "cost": 50, "color": Color(0.60, 0.90, 0.60) },
	TrapType.GLUE_BOARD: { "damage": 0.0,   "range": 4.8, "cooldown": 0.0, "cost": 35, "color": Color(0.80, 0.70, 0.30) },
}

## Each stat can be upgraded this many times independently.
const MAX_UPGRADE_LEVEL: int = 3

## Stat increment per upgrade level, as a fraction of the base value.
const UPGRADE_DAMAGE_FACTOR:    float = 0.25  # +25% of base damage per level
const UPGRADE_RANGE_FACTOR:     float = 0.10  # +10% of base range per level
const UPGRADE_FIRE_RATE_FACTOR: float = 0.08  # −8% of base cooldown per level (faster shots)

## Bug Bucks cost for each upgrade level per trap type.
## Index 0 = first upgrade, 1 = second, 2 = third.
## All values are tuning placeholders — finalize via playtesting.
const UPGRADE_COSTS := {
	TrapType.SNAP_TRAP:  [20, 30, 50],
	TrapType.ZAPPER:     [50, 75, 120],
	TrapType.FOGGER:     [40, 60, 100],
	TrapType.GLUE_BOARD: [30, 45, 70],
}


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when a point-target trap fires (Snap Trap, Zapper). Arena spawns
## a Projectile in response so the trap does not need a scene tree reference.
signal fired(from_pos: Vector3, to_pos: Vector3, target: Node3D, damage: float, trap_type: TrapType)

## Emitted once per Fogger firing cycle. Arena spawns a FogCloud that owns
## the damage logic — it expands outward and damages each enemy when the wave
## reaches them, so hits are staggered by distance rather than instant.
signal aoe_fired(from_pos: Vector3, aoe_range: float, damage: float, active_enemies: Array)

## Emitted after any upgrade is applied. TrapUpgradePanel connects here to
## keep its display current without polling.
signal stats_changed


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _trap_type: TrapType       = TrapType.SNAP_TRAP
var _damage:   float           = 0.0
var _range:    float           = 0.0
var _cooldown: float           = 0.0
var _cooldown_remaining: float = 0.0
var _cost:     int             = 0

# Upgrade state — each stat tracks its own level independently (0–MAX_UPGRADE_LEVEL).
var _damage_level: int = 0
var _range_level:  int = 0
var _rate_level:   int = 0   # always stays 0 for passive traps

# Set to true once the full-upgrade bonus has been applied, so it only fires once.
var _bonus_applied: bool = false

# Base stats stored at initialize time so each upgrade step is a consistent
# fraction of the original value regardless of how many upgrades have been applied.
var _base_damage:   float = 0.0
var _base_range:    float = 0.0
var _base_cooldown: float = 0.0

# Direct reference to Arena._active_enemies. GDScript arrays are reference
# types, so this always reflects the live list without any extra bookkeeping.
var _active_enemies: Array = []

# Enemies currently inside this Glue Board's range. Used to track who enters
# and leaves so we can call add/remove_slow_source exactly once per transition.
var _slowed_enemies: Array[Node3D] = []

# When true, this node is a visual-only placement preview: no combat, no hover area,
# no range indicator. Set by initialize_preview() before the node enters the tree.
var _is_preview: bool = false

# Range indicator shown on mouse hover.
var _is_hovered:      bool   = false
var _range_indicator: Node3D = null
var _hover_area:      Area3D = null
# When true, the indicator stays visible regardless of hover state (upgrade panel open).
var _indicator_pinned: bool  = false

# Snap Trap animation nodes — null for all other trap types.
var _snap_bar_pivot: Node3D         = null
var _snap_cheese:    MeshInstance3D = null
var _snap_animating: bool           = false

# Fogger animation nodes — null for all other trap types.
# _fogger_root bobs up/down at idle; _fogger_nozzle presses down on each shot.
var _fogger_root:          Node3D = null
var _fogger_nozzle:        Node3D = null
var _fogger_nozzle_base_y: float  = 0.0
var _fogger_bob_time:      float  = 0.0
var _fogger_animating:     bool   = false

# Zapper animation nodes — null for all other trap types.
# _zapper_uv_light is the container node for the UV cylinder + glow halo;
# scaling it on fire creates the electric-discharge pulse visible from above.
var _zapper_uv_light: Node3D = null
var _zapper_animating: bool  = false

# Tracks how many particle batches from this trap are still visually alive.
# Each fire increments the count; a timer decrements it after the particles expire.
# Firing is blocked when the count reaches FOG_BATCH_CAP (~6 puffs on screen).
const FOG_BATCH_CAP: int = 2   # 2 batches × 3–4 puffs each ≈ 6 puffs max
var _active_fog_batches: int = 0


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Configures the trap for a given type and wires it to the active enemy list.
## Must be called by Arena before the node is added to the scene tree.
func initialize(trap_type: TrapType, active_enemies: Array) -> void:
	_trap_type      = trap_type
	_active_enemies = active_enemies

	var stats  = STATS[trap_type]
	_damage    = stats["damage"]
	_range     = stats["range"]
	_cooldown  = stats["cooldown"]
	_cost      = stats["cost"]

	# Store originals so each upgrade increment is a consistent fraction
	# of the starting value regardless of how many upgrades have been applied.
	_base_damage   = _damage
	_base_range    = _range
	_base_cooldown = _cooldown

	_spawn_visual(stats["color"])
	stats_changed.connect(_rebuild_range_indicator)


## Lightweight setup for placement preview ghosts.
## Builds the visual only — no combat state, range indicator, or hover area.
## Caller should set process_mode = DISABLED before adding to the tree.
func initialize_preview(trap_type: TrapType) -> void:
	_is_preview = true
	_trap_type  = trap_type
	_spawn_visual(STATS[trap_type]["color"])


func _ready() -> void:
	if _is_preview:
		return
	_spawn_range_indicator()
	_spawn_hover_area()


# ---------------------------------------------------------------------------
# Upgrade — cost
# ---------------------------------------------------------------------------

## Bug Bucks cost for the next upgrade to each stat. Returns 0 when already maxed.
func get_damage_upgrade_cost() -> int:
	if _damage_level >= MAX_UPGRADE_LEVEL:
		return 0
	return UPGRADE_COSTS[_trap_type][_damage_level]

func get_range_upgrade_cost() -> int:
	if _range_level >= MAX_UPGRADE_LEVEL:
		return 0
	return UPGRADE_COSTS[_trap_type][_range_level]

func get_rate_upgrade_cost() -> int:
	if _rate_level >= MAX_UPGRADE_LEVEL or _base_cooldown == 0.0:
		return 0
	return UPGRADE_COSTS[_trap_type][_rate_level]


# ---------------------------------------------------------------------------
# Upgrade — stat previews
# ---------------------------------------------------------------------------

## Damage this trap would have after one damage upgrade.
func get_damage_after_upgrade() -> float:
	return _damage + _base_damage * UPGRADE_DAMAGE_FACTOR

## Range this trap would have after one range upgrade.
func get_range_after_upgrade() -> float:
	return _range + _base_range * UPGRADE_RANGE_FACTOR

## Current fire rate in shots per second. Returns 0.0 for passive traps.
func get_shots_per_sec() -> float:
	return 1.0 / _cooldown if _cooldown > 0.0 else 0.0

## Fire rate (shots/sec) this trap would have after one fire rate upgrade.
func get_shots_per_sec_after_upgrade() -> float:
	var new_cooldown := maxf(_cooldown - _base_cooldown * UPGRADE_FIRE_RATE_FACTOR, 0.1)
	return 1.0 / new_cooldown


# ---------------------------------------------------------------------------
# Upgrade — apply
# ---------------------------------------------------------------------------

## Increases damage by 25% of base. Only call when not maxed.
func apply_damage_upgrade() -> void:
	_damage += _base_damage * UPGRADE_DAMAGE_FACTOR
	_damage_level += 1
	_check_full_upgrade_bonus()
	stats_changed.emit()

## Increases range by 10% of base. Only call when not maxed.
func apply_range_upgrade() -> void:
	_range += _base_range * UPGRADE_RANGE_FACTOR
	_range_level += 1
	_check_full_upgrade_bonus()
	stats_changed.emit()

## Reduces cooldown by 8% of base (faster shots). Only call when not maxed.
## Cooldown is clamped to 0.1 s minimum to prevent instant-fire edge cases.
func apply_fire_rate_upgrade() -> void:
	_cooldown = maxf(_cooldown - _base_cooldown * UPGRADE_FIRE_RATE_FACTOR, 0.1)
	_rate_level += 1
	_check_full_upgrade_bonus()
	stats_changed.emit()


# ---------------------------------------------------------------------------
# Upgrade — accessors
# ---------------------------------------------------------------------------

func get_damage_level() -> int:
	return _damage_level

func get_range_level() -> int:
	return _range_level

func get_rate_level() -> int:
	return _rate_level

func is_damage_maxed() -> bool:
	return _damage_level >= MAX_UPGRADE_LEVEL

func is_range_maxed() -> bool:
	return _range_level >= MAX_UPGRADE_LEVEL

func is_rate_maxed() -> bool:
	return _rate_level >= MAX_UPGRADE_LEVEL

## True when every upgradeable stat is at MAX_UPGRADE_LEVEL.
## Passive traps (no fire rate) are fully upgraded after 6 total upgrades;
## active traps require all 9.
func is_fully_upgraded() -> bool:
	if _base_cooldown == 0.0:
		return is_damage_maxed() and is_range_maxed()
	return is_damage_maxed() and is_range_maxed() and is_rate_maxed()

func get_damage() -> float:
	return _damage

func get_range_radius() -> float:
	return _range

func get_cooldown() -> float:
	return _cooldown

## Returns true for traps that deal no direct damage and have no fire cycle
## (e.g. Glue Board). Fire Rate upgrade is not applicable to passive traps.
func is_passive() -> bool:
	return _base_cooldown == 0.0

func get_type_name() -> String:
	match _trap_type:
		TrapType.SNAP_TRAP:  return "Snap Trap"
		TrapType.ZAPPER:     return "Zapper"
		TrapType.FOGGER:     return "Fogger"
		TrapType.GLUE_BOARD: return "Glue Board"
	return "Unknown"

## Returns the Bug Bucks cost to place this trap.
func get_cost() -> int:
	return _cost


# ---------------------------------------------------------------------------
# Combat loop
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _trap_type == TrapType.GLUE_BOARD:
		_update_glue_slow()
		return

	# Fogger idle animation: gentle sine-wave float between shots.
	if _trap_type == TrapType.FOGGER and _fogger_root != null:
		_fogger_bob_time += delta
		_fogger_root.position.y = sin(_fogger_bob_time * 1.5) * Grid.CELL_SIZE * 0.035

	_cooldown_remaining -= delta
	if _cooldown_remaining > 0.0:
		return

	var did_fire := false
	if _trap_type == TrapType.FOGGER:
		did_fire = _fire_fogger()
		if did_fire:
			aoe_fired.emit(global_position, _range, _damage, _active_enemies)
			_play_fogger_animation()
			_active_fog_batches += 1
			var expire := FogCloud.PARTICLE_LIFETIME * 2.0 + 0.20
			get_tree().create_timer(expire).timeout.connect(
				func(): _active_fog_batches = maxi(0, _active_fog_batches - 1)
			)
	else:
		var target := _find_target()
		if target != null:
			fired.emit(global_position, target.global_position, target, _damage, _trap_type)
			did_fire = true
			if _trap_type == TrapType.SNAP_TRAP:
				_play_snap_animation()
			if _trap_type == TrapType.ZAPPER:
				_play_zapper_animation()

	if did_fire:
		_cooldown_remaining = _cooldown


func _exit_tree() -> void:
	# Release any slow sources this trap was holding so enemies return to
	# normal speed the moment the trap is sold or overwritten.
	for enemy in _slowed_enemies:
		if is_instance_valid(enemy):
			enemy.remove_slow_source()
	_slowed_enemies.clear()


# ---------------------------------------------------------------------------
# Targeting
# ---------------------------------------------------------------------------

func _find_target() -> Node3D:
	match _trap_type:
		TrapType.SNAP_TRAP:
			return _nearest_in_range()
		TrapType.ZAPPER:
			return _farthest_in_range()
	return null


## Returns true if at least one enemy is in range and the batch cap has not been reached.
## Damage is NOT applied here — FogCloud applies it as the wave expands.
func _fire_fogger() -> bool:
	if _active_fog_batches >= FOG_BATCH_CAP:
		return false
	for enemy in _active_enemies:
		if not is_instance_valid(enemy):
			continue
		if _xz_distance(enemy.global_position) <= _range:
			return true
	return false


## Applies or removes the slow source on each enemy as they cross the range boundary.
func _update_glue_slow() -> void:
	# Remove entries for enemies that have died or despawned.
	var i := _slowed_enemies.size() - 1
	while i >= 0:
		if not is_instance_valid(_slowed_enemies[i]):
			_slowed_enemies.remove_at(i)
		i -= 1

	for enemy in _active_enemies:
		if not is_instance_valid(enemy):
			continue
		var in_range:   bool = _xz_distance(enemy.global_position) <= _range
		var is_tracked: bool = enemy in _slowed_enemies
		if in_range and not is_tracked:
			_slowed_enemies.append(enemy)
			enemy.add_slow_source()
		elif not in_range and is_tracked:
			_slowed_enemies.erase(enemy)
			enemy.remove_slow_source()


## Returns the enemy in range closest to this trap (used by Snap Trap).
func _nearest_in_range() -> Node3D:
	var best: Node3D = null
	var best_dist    := INF
	for enemy in _active_enemies:
		if not is_instance_valid(enemy):
			continue
		var dist := _xz_distance(enemy.global_position)
		if dist <= _range and dist < best_dist:
			best_dist = dist
			best      = enemy
	return best


## Returns the enemy in range farthest along the path to the exit
## (used by Zapper — highest path index = closest to exit = biggest threat).
func _farthest_in_range() -> Node3D:
	var best: Node3D = null
	var best_index   := -1
	for enemy in _active_enemies:
		if not is_instance_valid(enemy):
			continue
		if _xz_distance(enemy.global_position) <= _range:
			var idx: int = enemy.get_path_index()
			if idx > best_index:
				best_index = idx
				best       = enemy
	return best


## Returns the XZ-plane distance from this trap to a world position.
func _xz_distance(world_pos: Vector3) -> float:
	var dx := global_position.x - world_pos.x
	var dz := global_position.z - world_pos.z
	return sqrt(dx * dx + dz * dz)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Called after each upgrade. If all stats are now maxed and the bonus has not
## yet been applied, boosts every stat by 10% as a reward for full investment.
## Fire rate boost reduces cooldown so shots-per-second increases by ~11%.
func _check_full_upgrade_bonus() -> void:
	if _bonus_applied or not is_fully_upgraded():
		return
	_damage  *= 1.1
	_range   *= 1.1
	if _base_cooldown > 0.0:
		_cooldown = maxf(_cooldown / 1.1, 0.1)
	_bonus_applied = true


## Forces the range indicator visible and pins it so hover-exit cannot hide it.
## Called by Arena when the upgrade panel opens for this trap.
func show_range_indicator() -> void:
	_indicator_pinned = true
	if _range_indicator != null:
		_range_indicator.visible = true


## Unpins the indicator and hides it unless the mouse is still over the trap.
## Called by Arena when the upgrade panel closes.
func hide_range_indicator() -> void:
	_indicator_pinned = false
	if _range_indicator != null:
		_range_indicator.visible = _is_hovered


func _on_hover_enter() -> void:
	_is_hovered = true
	if _range_indicator != null:
		_range_indicator.visible = true


func _on_hover_exit() -> void:
	_is_hovered = false
	if _indicator_pinned:
		return
	if _range_indicator != null:
		_range_indicator.visible = false


## Rebuilds the range indicator after an upgrade changes _range.
func _rebuild_range_indicator() -> void:
	if _range_indicator != null:
		_range_indicator.queue_free()
		_range_indicator = null
	_spawn_range_indicator()
	if _range_indicator != null:
		_range_indicator.visible = _is_hovered or _indicator_pinned


## Creates a flat filled disc and outline ring at ground level to show trap range.
## Hidden by default; shown on mouse hover via _hover_area.
func _spawn_range_indicator() -> void:
	_range_indicator            = Node3D.new()
	_range_indicator.position.y = 0.02
	_range_indicator.visible    = false

	# Filled disc — white, 80% transparent (alpha 0.20)
	var fill_mi              := MeshInstance3D.new()
	var fill_mesh            := CylinderMesh.new()
	fill_mesh.top_radius      = _range
	fill_mesh.bottom_radius   = _range
	fill_mesh.height          = 0.001
	fill_mesh.radial_segments = 64
	var fill_mat             := StandardMaterial3D.new()
	fill_mat.albedo_color     = Color(1.0, 1.0, 1.0, 0.0175)
	fill_mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_mi.mesh              = fill_mesh
	fill_mi.material_override = fill_mat
	_range_indicator.add_child(fill_mi)

	# Outline ring — white, 60% transparent (alpha 0.40)
	var ring_mi              := MeshInstance3D.new()
	ring_mi.mesh              = _make_ring_mesh(_range, 0.10)
	var ring_mat             := StandardMaterial3D.new()
	ring_mat.albedo_color     = Color(1.0, 1.0, 1.0, 0.035)
	ring_mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mi.material_override = ring_mat
	_range_indicator.add_child(ring_mi)

	add_child(_range_indicator)


## Builds a flat triangulated annulus (hollow disc) at the given outer radius and ring width.
func _make_ring_mesh(radius: float, width: float) -> ArrayMesh:
	var inner    := radius - width
	var segments := 64
	var verts    := PackedVector3Array()
	var indices  := PackedInt32Array()

	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		var c     := cos(angle)
		var s     := sin(angle)
		verts.append(Vector3(c * inner,  0.0, s * inner))
		verts.append(Vector3(c * radius, 0.0, s * radius))

	for i in range(segments):
		var nx := (i + 1) % segments
		var a  := i * 2
		var b  := i * 2 + 1
		var c  := nx * 2
		var d  := nx * 2 + 1
		indices.append_array([a, b, c, b, d, c])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX]  = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Creates a flat Area3D over the trap footprint for mouse-enter/exit hover detection.
func _spawn_hover_area() -> void:
	_hover_area                    = Area3D.new()
	_hover_area.collision_layer    = 8   # dedicated layer — no gameplay collisions
	_hover_area.collision_mask     = 0
	_hover_area.monitoring         = false
	_hover_area.monitorable        = false
	_hover_area.input_ray_pickable = true

	var shape     := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(Grid.CELL_SIZE * 1.9, Grid.CELL_SIZE * 0.5, Grid.CELL_SIZE * 1.9)
	shape.shape    = box_shape
	_hover_area.add_child(shape)

	_hover_area.mouse_entered.connect(_on_hover_enter)
	_hover_area.mouse_exited.connect(_on_hover_exit)
	add_child(_hover_area)


## Creates the trap's placeholder visual. Snap Trap, Zapper, and Fogger get
## multi-part procedural meshes; remaining types get a flat colored box.
func _spawn_visual(color: Color) -> void:
	if _trap_type == TrapType.SNAP_TRAP:
		_spawn_snap_trap_visual()
		return
	if _trap_type == TrapType.ZAPPER:
		_spawn_zapper_visual()
		return
	if _trap_type == TrapType.FOGGER:
		_spawn_fogger_visual()
		return

	var mi   := MeshInstance3D.new()
	var box  := BoxMesh.new()
	box.size  = Vector3(Grid.CELL_SIZE * 1.9, Grid.CELL_SIZE * 0.5, Grid.CELL_SIZE * 1.9)
	mi.mesh   = box

	var mat           := StandardMaterial3D.new()
	mat.albedo_color   = color
	mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat

	add_child(mi)


## Builds the Snap Trap visual: a wooden base plate (portrait — taller than wide),
## a coil spring at the hinge end, a U-shaped wire kill bar that slams down when
## the trap fires, and a cheese wedge on the trigger platform that vanishes during
## the snap and reappears on reset.
func _spawn_snap_trap_visual() -> void:
	var fp := Grid.CELL_SIZE * 1.9

	# Wooden base — portrait orientation: narrow width, long depth.
	var base_mi   := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(fp * 0.42, fp * 0.032, fp * 0.82)
	base_mi.mesh   = base_mesh
	base_mi.position.y = fp * 0.016
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.52, 0.32, 0.12)
	base_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	base_mi.material_override = base_mat
	add_child(base_mi)

	# Coil spring — fixed at the far end of the base (the hinge side).
	var spring_mi   := MeshInstance3D.new()
	var spring_mesh := CylinderMesh.new()
	spring_mesh.radial_segments = 16
	spring_mesh.top_radius      = fp * 0.055
	spring_mesh.bottom_radius   = fp * 0.055
	spring_mesh.height          = fp * 0.075
	spring_mi.mesh     = spring_mesh
	spring_mi.position = Vector3(0.0, fp * 0.032 + fp * 0.0375, -fp * 0.34)
	var spring_mat := StandardMaterial3D.new()
	spring_mat.albedo_color = Color(0.62, 0.62, 0.66)
	spring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spring_mi.material_override = spring_mat
	add_child(spring_mi)

	# Kill bar pivot — hinge at the spring, at base-top height.
	_snap_bar_pivot          = Node3D.new()
	_snap_bar_pivot.position = Vector3(0.0, fp * 0.032, -fp * 0.34)
	_snap_bar_pivot.rotation_degrees.x = -65.0   # armed: bar raised steeply
	add_child(_snap_bar_pivot)

	# U-shaped kill bar — two thin arms running along Z, joined by a crossbar at
	# the front. Wire proportions (3% of footprint) read as metal rod, not plate.
	var wire_mat := StandardMaterial3D.new()
	wire_mat.albedo_color = Color(0.72, 0.72, 0.76)
	wire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for side_x: float in [-fp * 0.155, fp * 0.155]:
		var arm_mi   := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size   = Vector3(fp * 0.030, fp * 0.030, fp * 0.68)
		arm_mi.mesh     = arm_mesh
		arm_mi.position = Vector3(side_x, 0.0, fp * 0.34)
		arm_mi.material_override = wire_mat
		_snap_bar_pivot.add_child(arm_mi)

	var cross_mi   := MeshInstance3D.new()
	var cross_mesh := BoxMesh.new()
	cross_mesh.size   = Vector3(fp * 0.34, fp * 0.030, fp * 0.030)
	cross_mi.mesh     = cross_mesh
	cross_mi.position = Vector3(0.0, 0.0, fp * 0.68)
	cross_mi.material_override = wire_mat
	_snap_bar_pivot.add_child(cross_mi)

	# Trigger platform — small darker rectangle near the center of the base.
	var trigger_mi   := MeshInstance3D.new()
	var trigger_mesh := BoxMesh.new()
	trigger_mesh.size   = Vector3(fp * 0.18, fp * 0.022, fp * 0.14)
	trigger_mi.mesh     = trigger_mesh
	trigger_mi.position = Vector3(0.0, fp * 0.032 + fp * 0.011, fp * 0.06)
	var trigger_mat := StandardMaterial3D.new()
	trigger_mat.albedo_color = Color(0.42, 0.25, 0.09)
	trigger_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trigger_mi.material_override = trigger_mat
	add_child(trigger_mi)

	# Cheese wedge — triangular prism on the trigger platform. Hidden during snap.
	_snap_cheese = MeshInstance3D.new()
	var cheese_mesh             := CylinderMesh.new()
	cheese_mesh.radial_segments  = 3
	cheese_mesh.top_radius       = fp * 0.072
	cheese_mesh.bottom_radius    = fp * 0.072
	cheese_mesh.height           = fp * 0.10
	_snap_cheese.mesh             = cheese_mesh
	_snap_cheese.position         = Vector3(0.0, fp * 0.032 + fp * 0.022 + fp * 0.05, fp * 0.06)
	_snap_cheese.rotation_degrees.y = 15.0
	var cheese_mat := StandardMaterial3D.new()
	cheese_mat.albedo_color = Color(0.95, 0.82, 0.15)
	cheese_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_snap_cheese.material_override = cheese_mat
	add_child(_snap_cheese)


## Builds the Fogger visual: a squat aerosol canister with a yellow label band,
## an angled shoulder dome, a silver nozzle stem, and an orange spray tip.
## From above (top-down camera) this reads as concentric coloured rings:
## green body → yellow label ring → dark shoulder dome → silver nozzle → orange tip.
func _spawn_fogger_visual() -> void:
	var fp := Grid.CELL_SIZE * 1.9

	# _fogger_root is the container that bobs up/down for the idle animation.
	_fogger_root = Node3D.new()
	add_child(_fogger_root)

	# Main canister body — squat green cylinder.
	var body_mi   := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.radial_segments = 16
	body_mesh.top_radius      = fp * 0.27
	body_mesh.bottom_radius   = fp * 0.27
	body_mesh.height          = fp * 0.36
	body_mi.mesh       = body_mesh
	body_mi.position.y = fp * 0.18   # centred: bottom at y=0, top at fp*0.36
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.12, 0.58, 0.22)
	body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	body_mi.material_override = body_mat
	_fogger_root.add_child(body_mi)

	# Yellow label band — slightly wider thin ring around the can's midsection.
	var band_mi   := MeshInstance3D.new()
	var band_mesh := CylinderMesh.new()
	band_mesh.radial_segments = 32
	band_mesh.top_radius      = fp * 0.30
	band_mesh.bottom_radius   = fp * 0.30
	band_mesh.height          = fp * 0.11
	band_mi.mesh       = band_mesh
	band_mi.position.y = fp * 0.18   # same centre as body
	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = Color(0.95, 0.88, 0.15)
	band_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	band_mi.material_override = band_mat
	_fogger_root.add_child(band_mi)

	# Bottom rim — slight inward taper at the base, silver-gray.
	var rim_mi   := MeshInstance3D.new()
	var rim_mesh := CylinderMesh.new()
	rim_mesh.radial_segments = 16
	rim_mesh.top_radius      = fp * 0.27
	rim_mesh.bottom_radius   = fp * 0.24
	rim_mesh.height          = fp * 0.04
	rim_mi.mesh       = rim_mesh
	rim_mi.position.y = fp * 0.02
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.62, 0.62, 0.66)
	rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim_mi.material_override = rim_mat
	_fogger_root.add_child(rim_mi)

	# Shoulder dome — tapers from body radius down to nozzle base.
	var shoulder_mi   := MeshInstance3D.new()
	var shoulder_mesh := CylinderMesh.new()
	shoulder_mesh.radial_segments = 16
	shoulder_mesh.top_radius      = fp * 0.10
	shoulder_mesh.bottom_radius   = fp * 0.27
	shoulder_mesh.height          = fp * 0.09
	shoulder_mi.mesh       = shoulder_mesh
	shoulder_mi.position.y = fp * 0.405   # sits flush on top of body (fp*0.36 + half fp*0.09)
	var shoulder_mat := StandardMaterial3D.new()
	shoulder_mat.albedo_color = Color(0.10, 0.46, 0.18)
	shoulder_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shoulder_mi.material_override = shoulder_mat
	_fogger_root.add_child(shoulder_mi)

	# Nozzle assembly — child node so it can be pressed down independently on fire.
	_fogger_nozzle_base_y  = fp * 0.45   # sits on top of shoulder (fp*0.36 + fp*0.09)
	_fogger_nozzle         = Node3D.new()
	_fogger_nozzle.position.y = _fogger_nozzle_base_y
	_fogger_root.add_child(_fogger_nozzle)

	# Nozzle stem — silver cylinder, slightly tapered.
	var stem_mi   := MeshInstance3D.new()
	var stem_mesh := CylinderMesh.new()
	stem_mesh.radial_segments = 8
	stem_mesh.top_radius      = fp * 0.116
	stem_mesh.bottom_radius   = fp * 0.150
	stem_mesh.height          = fp * 0.10
	stem_mi.mesh       = stem_mesh
	stem_mi.position.y = fp * 0.05   # centred in the stem height
	var stem_mat := StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.72, 0.72, 0.76)
	stem_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stem_mi.material_override = stem_mat
	_fogger_nozzle.add_child(stem_mi)

	# Spray tip — small orange sphere at the top of the stem; visible from above as
	# the bright centre dot that colour-codes the Fogger at a glance.
	var tip_mi   := MeshInstance3D.new()
	var tip_mesh := SphereMesh.new()
	tip_mesh.radius = fp * 0.060
	tip_mesh.height = fp * 0.120
	tip_mi.mesh       = tip_mesh
	tip_mi.position.y = fp * 0.10 + fp * 0.060   # sits on top of stem
	var tip_mat := StandardMaterial3D.new()
	tip_mat.albedo_color = Color(0.88, 0.32, 0.08)
	tip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tip_mi.material_override = tip_mat
	_fogger_nozzle.add_child(tip_mi)


## Builds the Zapper visual: a dark navy housing plate, a raised frame border,
## a 3×3 pale silver-blue wire grid, and a bright purple UV light cylinder at
## the centre. From above the grid crosshatch and the purple dot identify it
## instantly. The UV light node is stored so the fire animation can scale it.
func _spawn_zapper_visual() -> void:
	var fp := Grid.CELL_SIZE * 1.9

	# Dark navy housing base plate.
	var base_mi   := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(fp * 0.90, fp * 0.040, fp * 0.90)
	base_mi.mesh   = base_mesh
	base_mi.position.y = fp * 0.020
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.10, 0.13, 0.22)
	base_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	base_mi.material_override = base_mat
	add_child(base_mi)

	# Raised outer frame: two bars running along X (front/back) and two along Z (sides).
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.20, 0.25, 0.42)
	frame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for side_z: float in [-fp * 0.415, fp * 0.415]:
		var bar_mi   := MeshInstance3D.new()
		var bar_mesh := BoxMesh.new()
		bar_mesh.size   = Vector3(fp * 0.90, fp * 0.07, fp * 0.06)
		bar_mi.mesh     = bar_mesh
		bar_mi.position = Vector3(0.0, fp * 0.035, side_z)
		bar_mi.material_override = frame_mat
		add_child(bar_mi)
	for side_x: float in [-fp * 0.415, fp * 0.415]:
		var bar_mi   := MeshInstance3D.new()
		var bar_mesh := BoxMesh.new()
		bar_mesh.size   = Vector3(fp * 0.06, fp * 0.07, fp * 0.76)
		bar_mi.mesh     = bar_mesh
		bar_mi.position = Vector3(side_x, fp * 0.035, 0.0)
		bar_mi.material_override = frame_mat
		add_child(bar_mi)

	# Wire grid: 3 wires along X and 3 along Z, pale silver-blue.
	# Spacing at ±0.24 and 0 keeps wires inside the frame with even gaps.
	var wire_mat := StandardMaterial3D.new()
	wire_mat.albedo_color = Color(0.65, 0.72, 0.88)
	wire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for wire_z: float in [-fp * 0.24, 0.0, fp * 0.24]:
		var w_mi   := MeshInstance3D.new()
		var w_mesh := BoxMesh.new()
		w_mesh.size   = Vector3(fp * 0.72, fp * 0.015, fp * 0.015)
		w_mi.mesh     = w_mesh
		w_mi.position = Vector3(0.0, fp * 0.055, wire_z)
		w_mi.material_override = wire_mat
		add_child(w_mi)
	for wire_x: float in [-fp * 0.24, 0.0, fp * 0.24]:
		var w_mi   := MeshInstance3D.new()
		var w_mesh := BoxMesh.new()
		w_mesh.size   = Vector3(fp * 0.015, fp * 0.015, fp * 0.72)
		w_mi.mesh     = w_mesh
		w_mi.position = Vector3(wire_x, fp * 0.055, 0.0)
		w_mi.material_override = wire_mat
		add_child(w_mi)

	# UV light: bright purple cylinder in the centre. Stored in a Node3D container
	# so _play_zapper_animation() can scale the whole assembly (cylinder + halo).
	_zapper_uv_light = Node3D.new()
	_zapper_uv_light.position.y = fp * 0.055
	add_child(_zapper_uv_light)

	var uv_mi   := MeshInstance3D.new()
	var uv_mesh := CylinderMesh.new()
	uv_mesh.radial_segments = 12
	uv_mesh.top_radius      = fp * 0.085
	uv_mesh.bottom_radius   = fp * 0.085
	uv_mesh.height          = fp * 0.08
	uv_mi.mesh       = uv_mesh
	uv_mi.position.y = fp * 0.040
	var uv_mat := StandardMaterial3D.new()
	uv_mat.albedo_color = Color(0.55, 0.20, 1.00)
	uv_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	uv_mi.material_override = uv_mat
	_zapper_uv_light.add_child(uv_mi)

	# Soft glow halo: transparent sphere around the UV cylinder for a bloom effect.
	var glow_mi   := MeshInstance3D.new()
	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = fp * 0.17
	glow_mesh.height = fp * 0.34
	glow_mi.mesh       = glow_mesh
	glow_mi.position.y = fp * 0.040
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.65, 0.40, 1.0, 0.18)
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mi.material_override = glow_mat
	_zapper_uv_light.add_child(glow_mi)


## Plays the fire animation: the UV light node scales outward sharply then
## eases back, simulating the electric discharge flash visible from above.
func _play_zapper_animation() -> void:
	if _zapper_uv_light == null or _zapper_animating:
		return
	_zapper_animating = true

	var burst := create_tween()
	burst.tween_property(_zapper_uv_light, "scale",
		Vector3(4.0, 1.5, 4.0), 0.06).set_ease(Tween.EASE_OUT)
	await burst.finished

	if not is_inside_tree():
		_zapper_animating = false
		return

	var settle := create_tween()
	settle.tween_property(_zapper_uv_light, "scale",
		Vector3(1.0, 1.0, 1.0), 0.30).set_ease(Tween.EASE_OUT)
	await settle.finished

	_zapper_animating = false


## Plays the spray animation: squishes the can outward on XZ then springs back.
## Y-axis movement is invisible from the top-down camera, so the animation
## operates on scale — the can briefly expands radially and the player sees
## the green circle pulse outward on each shot.
func _play_fogger_animation() -> void:
	if _fogger_root == null or _fogger_animating:
		return
	_fogger_animating = true

	# Fast squish: expand XZ, compress Y — the "exhale" burst.
	var squish := create_tween()
	squish.tween_property(_fogger_root, "scale",
		Vector3(1.35, 0.65, 1.35), 0.07).set_ease(Tween.EASE_OUT)
	await squish.finished

	# Slow spring back to resting size.
	var spring := create_tween()
	spring.tween_property(_fogger_root, "scale",
		Vector3(1.0, 1.0, 1.0), 0.28).set_ease(Tween.EASE_OUT)
	await spring.finished

	_fogger_animating = false


## Plays the snap animation: slams the bar down, hides the cheese, then resets
## both after half the cooldown has elapsed. Guards against overlap so a fast
## trigger rate cannot stack multiple tweens on the same bar.
func _play_snap_animation() -> void:
	if _snap_bar_pivot == null or _snap_animating:
		return
	_snap_animating      = true
	_snap_cheese.visible = false

	var snap_tween := create_tween()
	snap_tween.tween_property(_snap_bar_pivot, "rotation_degrees:x", 8.0, 0.07)

	await get_tree().create_timer(_cooldown * 0.50).timeout
	if not is_inside_tree():
		_snap_animating = false
		return

	var reset_tween := create_tween()
	reset_tween.tween_property(_snap_bar_pivot, "rotation_degrees:x", -55.0, 0.18)
	await reset_tween.finished

	_snap_cheese.visible = true
	_snap_animating      = false
