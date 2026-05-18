## BoostUnit.gd
## A player-placed unit that applies a passive benefit to nearby traps, the
## economy, or infestation control. Unlike Traps, Boosts do not attack enemies
## directly — they amplify or compensate in other ways.
##
## Boost types:
##   PHEROMONE_DISPENSER — aura that increases damage of nearby traps
##   COMPRESSOR          — aura that increases fire rate of nearby traps
##   CASH_REGISTER       — awards passive income each wave and a bonus per kill
##   AIR_FRESHENER       — absorbs some infestation when pests reach the exit (perishable)
##   QUARANTINE_MARKER   — restores infestation per kill in its aura (perishable)
##
## Upgrade system (mirrors Trap.gd):
##   Three upgrade stats per Boost, labelled A (Range), B (primary), C (secondary).
##   Pheromone Dispenser and Compressor have only 2 stats (A and B); has_stat_c() is
##   false for those types. All stats upgrade 0–3 levels. A full-upgrade bonus of 7.5%
##   to range and the primary stat fires once when all applicable stats are maxed.
##
## Perishable Boosts (AIR_FRESHENER, QUARANTINE_MARKER) emit boost_depleted when
## their capacity is exhausted; Arena removes them automatically in response.
##
## Arena-driven callbacks (all no-ops for non-applicable types):
##   absorb_infestation(amount, exit_pos) — called when an enemy reaches the exit
##   on_enemy_died_near(death_pos)        — called when any enemy dies
##   on_wave_started()                    — called when a new wave begins
##
## Usage: Arena instantiates this and calls initialize() before adding to the scene tree.

extends Node3D

const Grid                  = preload("res://arena/Grid.gd")
const SHADOW_OUTLINE_SHADER = preload("res://assets/shadow_outline.gdshader")
const UIFonts               = preload("res://ui/UIFonts.gd")


# ---------------------------------------------------------------------------
# Boost type
# ---------------------------------------------------------------------------

enum BoostType {
	PHEROMONE_DISPENSER,   # trap damage aura
	COMPRESSOR,            # trap fire-rate aura
	CASH_REGISTER,         # passive income + kill bonus
	AIR_FRESHENER,         # absorbs exit infestation (perishable)
	QUARANTINE_MARKER,     # restores infestation per kill (perishable)
}

## Per-type base stat table. All numeric values are placeholders — tuned via playtesting.
##   range            — aura radius in world units (1 unit = 1 cell)
##   cost             — Bug Bucks to place one Boost of this type
##   damage_bonus     — PHEROMONE_DISPENSER: fraction added to trap damage multiplier
##   fire_rate_bonus  — COMPRESSOR: fraction added to trap fire-rate multiplier
##   income_per_wave  — CASH_REGISTER: Bug Bucks awarded at wave start
##   kill_bonus       — CASH_REGISTER: Bug Bucks per kill in range
##   reduction        — AIR_FRESHENER: fraction of infestation absorbed per exit event
##   capacity         — perishable Boosts: total absorption/restore before destroyed
##   restore_per_kill — QUARANTINE_MARKER: infestation restored per kill in range
const STATS: Dictionary = {
	BoostType.PHEROMONE_DISPENSER: { "range": 4.0, "cost": 50, "damage_bonus":    0.25 },
	BoostType.COMPRESSOR:          { "range": 4.0, "cost": 50, "fire_rate_bonus":  0.20 },
	BoostType.CASH_REGISTER:       { "range": 5.0, "cost": 45, "income_per_wave":  5,   "kill_bonus":       2    },
	BoostType.AIR_FRESHENER:       { "range": 3.0, "cost": 35, "reduction":        0.50, "capacity":        50.0 },
	BoostType.QUARANTINE_MARKER:   { "range": 4.0, "cost": 40, "restore_per_kill": 2.0,  "capacity":        80.0 },
}

const MAX_UPGRADE_LEVEL: int = 3

## Cost to upgrade each stat from level N to N+1. Index = current level (0, 1, 2).
const UPGRADE_COSTS: Dictionary = {
	BoostType.PHEROMONE_DISPENSER: [15, 25, 40],
	BoostType.COMPRESSOR:          [15, 25, 40],
	BoostType.CASH_REGISTER:       [20, 35, 55],
	BoostType.AIR_FRESHENER:       [15, 25, 40],
	BoostType.QUARANTINE_MARKER:   [15, 25, 40],
}

## Absolute amount added to stat B per upgrade level.
const STAT_B_DELTA: Dictionary = {
	BoostType.PHEROMONE_DISPENSER: 0.08,   # +8 percentage points of damage bonus
	BoostType.COMPRESSOR:          0.07,   # +7 percentage points of fire-rate bonus
	BoostType.CASH_REGISTER:       3,      # +3 Bug Bucks income per wave
	BoostType.AIR_FRESHENER:       0.10,   # +10 percentage points of infestation reduction
	BoostType.QUARANTINE_MARKER:   1.0,    # +1.0 infestation points restored per kill
}

## Absolute amount added to stat C per upgrade level (3-stat boosts only).
const STAT_C_DELTA: Dictionary = {
	BoostType.CASH_REGISTER:     1,      # +1 Bug Buck per kill
	BoostType.AIR_FRESHENER:    25.0,   # +25 total absorption capacity
	BoostType.QUARANTINE_MARKER: 40.0,  # +40 total restoration capacity
}


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when a perishable Boost exhausts its capacity.
## Arena connects here to remove the unit from the board automatically.
signal boost_depleted

## Emitted after any stat upgrade so the open BoostUpgradePanel can refresh.
signal stats_changed


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _boost_type:     BoostType = BoostType.PHEROMONE_DISPENSER
var _range:          float     = 0.0
var _cost:           int       = 0

# Snapshot of _range at initialize time — used to compute per-level range increments.
var _base_range: float = 0.0

# Upgrade levels — 0 to MAX_UPGRADE_LEVEL for each stat.
var _range_level:  int = 0   # stat A: all boost types
var _stat_b_level: int = 0   # stat B: primary bonus stat (varies by type)
var _stat_c_level: int = 0   # stat C: secondary stat (3-stat boosts only; unused otherwise)

# True once the full-upgrade bonus (7.5% to range + stat B) has been applied.
var _bonus_applied: bool = false

# -1.0 means infinite capacity; perishable types start at their capacity stat value.
var _remaining_capacity: float = -1.0

# Max capacity for perishable boosts — increases as stat C is upgraded.
var _max_capacity: float = -1.0

# Direct references to Arena's live collections (reference semantics — always current).
var _active_enemies: Array       = []
var _trap_nodes:     Dictionary  = {}   # anchor Vector2i → Trap node

# Traps currently inside this Boost's aura radius.
# Used to remove the boost effect when a trap leaves range or the Boost is sold.
var _aura_traps: Array = []

# Type-specific stats, set from STATS during initialize().
var _damage_bonus:    float = 0.0
var _fire_rate_bonus: float = 0.0
var _income_per_wave: int   = 0
var _kill_bonus:      int   = 0
var _reduction:       float = 0.0
var _restore_per_kill: float = 0.0

var _base_color:   Color                     = Color.WHITE

# When true, this node is a visual-only placement preview: no aura logic runs.
# Set by initialize_preview() before the node enters the tree.
var _is_preview: bool = false

# Range indicator shown during placement and when the upgrade panel is open.
var _indicator_pinned: bool              = false
var _range_indicator:  Node3D           = null
var _range_fill_mat:   StandardMaterial3D = null
var _range_ring_mat:   StandardMaterial3D = null

# Star display — one Label3D per possible star (max 3), mirrors Trap._star_labels.
var _star_labels:  Array[Label3D]            = []

# Upgrade tint — kept so _update_star_display() can lerp outline and shadow toward gold.
var _outline_mats: Array[StandardMaterial3D] = []
var _shadow_mat:   ShaderMaterial            = null


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Lightweight preview-only initializer used by the HUD icon SubViewport.
## Passes empty collections so no aura or callback logic runs.
func initialize_preview(boost_type: BoostType) -> void:
	_is_preview = true
	initialize(boost_type, [], {})


## Configures the Boost for a given type and wires it to the live collections.
## Must be called by Arena before adding to the scene tree.
func initialize(boost_type: BoostType, active_enemies: Array, trap_nodes: Dictionary) -> void:
	_boost_type     = boost_type
	_active_enemies = active_enemies
	_trap_nodes     = trap_nodes

	var stats: Dictionary = STATS[boost_type]
	_range      = stats["range"]
	_base_range = stats["range"]
	_cost       = stats["cost"]

	match boost_type:
		BoostType.PHEROMONE_DISPENSER:
			_damage_bonus        = stats["damage_bonus"]
		BoostType.COMPRESSOR:
			_fire_rate_bonus     = stats["fire_rate_bonus"]
		BoostType.CASH_REGISTER:
			_income_per_wave     = stats["income_per_wave"]
			_kill_bonus          = stats["kill_bonus"]
		BoostType.AIR_FRESHENER:
			_reduction           = stats["reduction"]
			_remaining_capacity  = stats["capacity"]
			_max_capacity        = stats["capacity"]
		BoostType.QUARANTINE_MARKER:
			_restore_per_kill    = stats["restore_per_kill"]
			_remaining_capacity  = stats["capacity"]
			_max_capacity        = stats["capacity"]

	_spawn_visual()
	_spawn_star_display()
	stats_changed.connect(_rebuild_range_indicator)
	stats_changed.connect(_update_star_display)


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	match _boost_type:
		BoostType.PHEROMONE_DISPENSER, BoostType.COMPRESSOR:
			_update_trap_aura()


func _ready() -> void:
	_spawn_range_indicator()
	if _is_preview:
		if _range_indicator != null:
			_range_indicator.visible = true
		return
	# Apply the aura immediately on placement rather than waiting for the first
	# _process frame — ensures nearby traps are boosted before any panel opens.
	match _boost_type:
		BoostType.PHEROMONE_DISPENSER, BoostType.COMPRESSOR:
			_update_trap_aura()


func _exit_tree() -> void:
	# Remove this Boost's contribution from all traps it was affecting.
	_remove_all_aura_effects()


# ---------------------------------------------------------------------------
# Arena callbacks
# ---------------------------------------------------------------------------

## Called by Arena when any enemy reaches the exit.
## AIR_FRESHENER: absorbs a fraction of the infestation if the exit is in range.
## Returns the remaining infestation that was not absorbed.
func absorb_infestation(amount: float, exit_pos: Vector3) -> float:
	if _boost_type != BoostType.AIR_FRESHENER or _remaining_capacity <= 0.0:
		return amount
	if _xz_distance(exit_pos) > _range:
		return amount

	var absorbed := amount * _reduction
	absorbed = minf(absorbed, _remaining_capacity)
	_remaining_capacity -= absorbed

	if _remaining_capacity <= 0.0:
		_remaining_capacity = 0.0
		boost_depleted.emit()

	return amount - absorbed


## Called by Arena when any enemy dies.
## QUARANTINE_MARKER: restores infestation if the kill was within range.
## CASH_REGISTER: awards a kill bonus if the kill was within range.
func on_enemy_died_near(death_pos: Vector3) -> void:
	if _xz_distance(death_pos) > _range:
		return

	if _boost_type == BoostType.CASH_REGISTER:
		GameState.add_bug_bucks(_kill_bonus)

	elif _boost_type == BoostType.QUARANTINE_MARKER and _remaining_capacity > 0.0:
		var restore := minf(_restore_per_kill, _remaining_capacity)
		_remaining_capacity -= restore
		GameState.add_infestation(-restore)   # negative = reduce infestation
		if _remaining_capacity <= 0.0:
			_remaining_capacity = 0.0
			boost_depleted.emit()


## Called by Arena at the start of each new wave.
## CASH_REGISTER: awards passive wave income.
func on_wave_started() -> void:
	if _boost_type == BoostType.CASH_REGISTER:
		GameState.add_bug_bucks(_income_per_wave)


# ---------------------------------------------------------------------------
# Upgrade system — stat A: Range (all boost types)
# ---------------------------------------------------------------------------

func get_range_level() -> int:
	return _range_level

func is_range_maxed() -> bool:
	return _range_level >= MAX_UPGRADE_LEVEL

func get_range_upgrade_cost() -> int:
	if is_range_maxed():
		return 0
	return UPGRADE_COSTS[_boost_type][_range_level]

func get_range_after_upgrade() -> float:
	return _range + _base_range * 0.10

func apply_range_upgrade() -> void:
	_range       += _base_range * 0.10
	_range_level += 1
	_check_full_upgrade_bonus()
	stats_changed.emit()


# ---------------------------------------------------------------------------
# Upgrade system — stat B: primary bonus (varies by type)
# ---------------------------------------------------------------------------

## Human-readable label for stat B, used in the upgrade panel header.
func get_stat_b_name() -> String:
	match _boost_type:
		BoostType.PHEROMONE_DISPENSER: return "Dmg Bonus"
		BoostType.COMPRESSOR:          return "Rate Bonus"
		BoostType.CASH_REGISTER:       return "Wave Income"
		BoostType.AIR_FRESHENER:       return "Reduction"
		BoostType.QUARANTINE_MARKER:   return "Restore/Kill"
	return "Stat B"

func get_stat_b_level() -> int:
	return _stat_b_level

func is_stat_b_maxed() -> bool:
	return _stat_b_level >= MAX_UPGRADE_LEVEL

func get_stat_b_upgrade_cost() -> int:
	if is_stat_b_maxed():
		return 0
	return UPGRADE_COSTS[_boost_type][_stat_b_level]

## Returns the raw current value of stat B.
func get_stat_b_value() -> float:
	match _boost_type:
		BoostType.PHEROMONE_DISPENSER: return _damage_bonus
		BoostType.COMPRESSOR:          return _fire_rate_bonus
		BoostType.CASH_REGISTER:       return float(_income_per_wave)
		BoostType.AIR_FRESHENER:       return _reduction
		BoostType.QUARANTINE_MARKER:   return _restore_per_kill
	return 0.0

## Returns what stat B will be after the next upgrade, for panel preview.
func get_stat_b_after_upgrade() -> float:
	return get_stat_b_value() + float(STAT_B_DELTA[_boost_type])

## Formats a stat B value as a display string (current or after-upgrade).
func format_stat_b(v: float) -> String:
	match _boost_type:
		BoostType.PHEROMONE_DISPENSER: return "%d%%" % int(v * 100)
		BoostType.COMPRESSOR:          return "%d%%" % int(v * 100)
		BoostType.CASH_REGISTER:       return "🪙%d/wave" % int(v)
		BoostType.AIR_FRESHENER:       return "%d%%" % int(v * 100)
		BoostType.QUARANTINE_MARKER:   return "%.1f inf" % v
	return "%.2f" % v

func apply_stat_b_upgrade() -> void:
	var delta := float(STAT_B_DELTA[_boost_type])
	match _boost_type:
		BoostType.PHEROMONE_DISPENSER: _damage_bonus    += delta
		BoostType.COMPRESSOR:          _fire_rate_bonus  += delta
		BoostType.CASH_REGISTER:       _income_per_wave  += int(delta)
		BoostType.AIR_FRESHENER:       _reduction        += delta
		BoostType.QUARANTINE_MARKER:   _restore_per_kill += delta
	_stat_b_level += 1
	_check_full_upgrade_bonus()
	stats_changed.emit()


# ---------------------------------------------------------------------------
# Upgrade system — stat C: secondary stat (3-stat boosts only)
# ---------------------------------------------------------------------------

## Returns true for boost types that have a third upgradeable stat.
func has_stat_c() -> bool:
	return _boost_type in [
		BoostType.CASH_REGISTER,
		BoostType.AIR_FRESHENER,
		BoostType.QUARANTINE_MARKER,
	]

## Human-readable label for stat C, used in the upgrade panel header.
func get_stat_c_name() -> String:
	match _boost_type:
		BoostType.CASH_REGISTER:     return "Kill Bonus"
		BoostType.AIR_FRESHENER:     return "Capacity"
		BoostType.QUARANTINE_MARKER: return "Capacity"
	return "Stat C"

func get_stat_c_level() -> int:
	return _stat_c_level

func is_stat_c_maxed() -> bool:
	return _stat_c_level >= MAX_UPGRADE_LEVEL

func get_stat_c_upgrade_cost() -> int:
	if is_stat_c_maxed():
		return 0
	return UPGRADE_COSTS[_boost_type][_stat_c_level]

## Returns the raw current value of stat C.
func get_stat_c_value() -> float:
	match _boost_type:
		BoostType.CASH_REGISTER:     return float(_kill_bonus)
		BoostType.AIR_FRESHENER:     return _max_capacity
		BoostType.QUARANTINE_MARKER: return _max_capacity
	return 0.0

## Returns what stat C will be after the next upgrade, for panel preview.
func get_stat_c_after_upgrade() -> float:
	return get_stat_c_value() + float(STAT_C_DELTA[_boost_type])

## Formats a stat C value as a display string.
func format_stat_c(v: float) -> String:
	match _boost_type:
		BoostType.CASH_REGISTER:     return "🪙%d/kill" % int(v)
		BoostType.AIR_FRESHENER:     return "%.0f cap" % v
		BoostType.QUARANTINE_MARKER: return "%.0f cap" % v
	return "%.1f" % v

func apply_stat_c_upgrade() -> void:
	var delta := float(STAT_C_DELTA[_boost_type])
	match _boost_type:
		BoostType.CASH_REGISTER:
			_kill_bonus     += int(delta)
		BoostType.AIR_FRESHENER:
			_max_capacity       += delta
			# Add the new capacity directly to the remaining amount — upgrading while
			# the unit is partially depleted should extend its remaining life, not reset it.
			_remaining_capacity  = minf(_remaining_capacity + delta, _max_capacity)
		BoostType.QUARANTINE_MARKER:
			_max_capacity       += delta
			_remaining_capacity  = minf(_remaining_capacity + delta, _max_capacity)
	_stat_c_level += 1
	_check_full_upgrade_bonus()
	stats_changed.emit()


# ---------------------------------------------------------------------------
# Upgrade system — full-upgrade bonus + shared helpers
# ---------------------------------------------------------------------------

## Applies a one-time 7.5% boost to range and the primary stat when all
## applicable stats are maxed. Mirrors Trap._check_full_upgrade_bonus().
func _check_full_upgrade_bonus() -> void:
	if _bonus_applied:
		return
	var all_maxed := _range_level >= MAX_UPGRADE_LEVEL and _stat_b_level >= MAX_UPGRADE_LEVEL
	if has_stat_c():
		all_maxed = all_maxed and _stat_c_level >= MAX_UPGRADE_LEVEL
	if not all_maxed:
		return
	_range *= 1.075
	# Also boost the primary stat by 7.5%.
	match _boost_type:
		BoostType.PHEROMONE_DISPENSER: _damage_bonus    *= 1.075
		BoostType.COMPRESSOR:          _fire_rate_bonus  *= 1.075
		BoostType.CASH_REGISTER:       _income_per_wave   = int(_income_per_wave * 1.075)
		BoostType.AIR_FRESHENER:       _reduction        *= 1.075
		BoostType.QUARANTINE_MARKER:   _restore_per_kill *= 1.075
	_bonus_applied = true


# ---------------------------------------------------------------------------
# Accessors
# ---------------------------------------------------------------------------

func get_type() -> BoostType:
	return _boost_type

func get_type_name() -> String:
	match _boost_type:
		BoostType.PHEROMONE_DISPENSER: return "Pheromone Dispenser"
		BoostType.COMPRESSOR:          return "Compressor"
		BoostType.CASH_REGISTER:       return "Cash Register"
		BoostType.AIR_FRESHENER:       return "Air Freshener"
		BoostType.QUARANTINE_MARKER:   return "Quarantine Marker"
	return "Unknown"

## Short description shown in the upgrade panel.
func get_description() -> String:
	match _boost_type:
		BoostType.PHEROMONE_DISPENSER:
			return "Increases damage dealt by all traps within its aura."
		BoostType.COMPRESSOR:
			return "Increases the fire rate of all traps within its aura."
		BoostType.CASH_REGISTER:
			return "Earns Bug Bucks each wave and pays a bonus per kill inside its aura."
		BoostType.AIR_FRESHENER:
			return "Absorbs infestation from pests that escape through its aura. Perishable — has finite capacity."
		BoostType.QUARANTINE_MARKER:
			return "Restores infestation for every kill inside its aura. Perishable — has finite capacity."
	return ""

func get_cost() -> int:
	return _cost

## Returns 70% of the placement cost — the sell refund amount.
func get_sell_value() -> int:
	return int(_cost * 0.70)

func get_range_radius() -> float:
	return _range

func get_base_color() -> Color:
	return _base_color

## Returns how many stats are currently at MAX_UPGRADE_LEVEL.
func get_maxed_stat_count() -> int:
	var count := 0
	if is_range_maxed():  count += 1
	if is_stat_b_maxed(): count += 1
	if has_stat_c() and is_stat_c_maxed(): count += 1
	return count

## Returns the total number of independently upgradeable stats for this boost type.
func get_total_upgradeable_stats() -> int:
	return 3 if has_stat_c() else 2

## Returns remaining capacity fraction (1.0 = full, 0.0 = depleted).
## Returns 1.0 for infinite-capacity boost types.
func get_capacity_fraction() -> float:
	if _remaining_capacity < 0.0:
		return 1.0
	return _remaining_capacity / _max_capacity if _max_capacity > 0.0 else 0.0


# ---------------------------------------------------------------------------
# Range indicator — mirrors Trap._spawn_range_indicator / show_range_indicator
# ---------------------------------------------------------------------------

## Shows the range indicator. Called by Arena when a placement preview hovers
## over this Boost (dimmed=true) or when the upgrade panel is open (dimmed=false).
func show_range_indicator(dimmed: bool = false) -> void:
	_indicator_pinned = true
	if _range_indicator != null:
		_range_indicator.visible = true
	_set_range_indicator_dimmed(dimmed)


## Hides the range indicator. Called by Arena when the placement preview moves away.
func hide_range_indicator() -> void:
	_indicator_pinned = false
	if _range_indicator != null:
		_range_indicator.visible = false
	_set_range_indicator_dimmed(false)


## Applies or removes the gray tint on the range indicator materials.
func _set_range_indicator_dimmed(dimmed: bool) -> void:
	if _range_fill_mat == null or _range_ring_mat == null:
		return
	var tint := Color(0.50, 0.50, 0.50) if dimmed else Color(1.0, 1.0, 1.0)
	_range_fill_mat.albedo_color = Color(tint.r, tint.g, tint.b,
		_range_fill_mat.albedo_color.a)
	_range_ring_mat.albedo_color = Color(tint.r, tint.g, tint.b,
		_range_ring_mat.albedo_color.a)


## Rebuilds the range indicator after a Range upgrade changes _range.
func _rebuild_range_indicator() -> void:
	if _range_indicator != null:
		_range_indicator.queue_free()
		_range_indicator = null
	_spawn_range_indicator()
	if _range_indicator != null:
		_range_indicator.visible = _indicator_pinned


## Creates a flat filled disc and outline ring at ground level to show boost range.
## Hidden by default. Preview instances show it immediately with higher opacity so
## the aura circle reads clearly while the player is choosing a placement cell.
func _spawn_range_indicator() -> void:
	_range_indicator            = Node3D.new()
	_range_indicator.position.y = 0.02
	_range_indicator.visible    = false

	var fill_alpha := 0.12 if _is_preview else 0.025
	var ring_alpha := 0.90 if _is_preview else 0.55

	# Filled disc
	var fill_mi              := MeshInstance3D.new()
	var fill_mesh            := CylinderMesh.new()
	fill_mesh.top_radius      = _range
	fill_mesh.bottom_radius   = _range
	fill_mesh.height          = 0.001
	fill_mesh.radial_segments = 64
	_range_fill_mat             = StandardMaterial3D.new()
	_range_fill_mat.albedo_color = Color(1.0, 1.0, 1.0, fill_alpha)
	_range_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_range_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_mi.mesh              = fill_mesh
	fill_mi.material_override = _range_fill_mat
	_range_indicator.add_child(fill_mi)

	# Outline ring
	var ring_mi              := MeshInstance3D.new()
	ring_mi.mesh              = _make_ring_mesh(_range, 0.10)
	_range_ring_mat             = StandardMaterial3D.new()
	_range_ring_mat.albedo_color = Color(1.0, 1.0, 1.0, ring_alpha)
	_range_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_range_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mi.material_override = _range_ring_mat
	_range_indicator.add_child(ring_mi)

	add_child(_range_indicator)


## Builds a flat triangulated annulus (hollow disc) at the given outer radius and ring width.
## Mirrors Trap._make_ring_mesh().
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
		indices.append_array([a, b, d, a, d, c])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX]  = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ---------------------------------------------------------------------------
# Aura management (PHEROMONE_DISPENSER + COMPRESSOR)
# ---------------------------------------------------------------------------

## Returns true if any part of the trap's 2×2 footprint overlaps the boost's range circle.
## Uses closest-point-on-AABB: clamp the boost center into the trap's bounding box and
## compare the squared distance to the squared range. This beats a simple center check
## so traps whose corner falls inside the aura circle still receive the boost.
func _trap_in_aura_range(trap: Node3D) -> bool:
	var tc   := trap.global_position
	var bc   := global_position
	var half := Grid.CELL_SIZE   # 2×2 footprint → 1-cell half-extent on each axis
	var cx   := clampf(bc.x, tc.x - half, tc.x + half)
	var cz   := clampf(bc.z, tc.z - half, tc.z + half)
	var dx   := bc.x - cx
	var dz   := bc.z - cz
	return dx * dx + dz * dz <= _range * _range


## Updates which traps are in aura range and applies / removes the boost effect.
## Two-pass pattern: clean up traps that left range, then apply to newly-in-range traps.
func _update_trap_aura() -> void:
	# Build the current set of in-range traps from Arena's live trap dictionary.
	var in_range: Array = []
	for trap in _trap_nodes.values():
		if is_instance_valid(trap) and _trap_in_aura_range(trap):
			in_range.append(trap)

	# Remove boost from traps that left range.
	var to_release: Array = []
	for trap in _aura_traps:
		if not is_instance_valid(trap) or not in_range.has(trap):
			to_release.append(trap)
	for trap in to_release:
		_remove_aura_effect(trap)
		_aura_traps.erase(trap)

	# Apply boost to newly-entered traps.
	for trap in in_range:
		if not _aura_traps.has(trap):
			_apply_aura_effect(trap)
			_aura_traps.append(trap)


## Applies this Boost's effect to a single trap.
func _apply_aura_effect(trap: Node3D) -> void:
	match _boost_type:
		BoostType.PHEROMONE_DISPENSER:
			trap.apply_damage_boost(self, _damage_bonus)
		BoostType.COMPRESSOR:
			trap.apply_fire_rate_boost(self, _fire_rate_bonus)


## Removes this Boost's effect from a single trap.
func _remove_aura_effect(trap: Node3D) -> void:
	if not is_instance_valid(trap):
		return
	match _boost_type:
		BoostType.PHEROMONE_DISPENSER:
			trap.remove_damage_boost(self)
		BoostType.COMPRESSOR:
			trap.remove_fire_rate_boost(self)


## Removes this Boost's effect from all traps in its aura. Called on _exit_tree().
func _remove_all_aura_effects() -> void:
	for trap in _aura_traps:
		_remove_aura_effect(trap)
	_aura_traps.clear()


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## XZ-plane distance from this Boost to a world position.
func _xz_distance(world_pos: Vector3) -> float:
	var dx := global_position.x - world_pos.x
	var dz := global_position.z - world_pos.z
	return sqrt(dx * dx + dz * dz)


## Shared helper: creates a standard material with the given color, unshaded.
func _mat(color: Color) -> StandardMaterial3D:
	var m             := StandardMaterial3D.new()
	m.albedo_color     = color
	m.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Shared helper: creates a MeshInstance3D with the given mesh and material.
func _mi(mesh: Mesh, mat: StandardMaterial3D) -> MeshInstance3D:
	var node              := MeshInstance3D.new()
	node.mesh              = mesh
	node.material_override = mat
	return node


# ---------------------------------------------------------------------------
# Star display — mirrors Trap._spawn_star_display / _update_star_display
# ---------------------------------------------------------------------------

## Spawns three Label3D star slots. Called from initialize() only — preview
## instances skip this so the HUD icon SubViewport stays clean.
func _spawn_star_display() -> void:
	var sizes := [88, 66, 66]   # [center, left, right] font sizes
	for sz: int in sizes:
		var lbl                  := Label3D.new()
		lbl.font                  = UIFonts.primary_bold()
		lbl.font_size             = sz
		lbl.pixel_size            = 0.009
		lbl.modulate              = Color(1.0, 0.92, 0.30, 1.0)
		lbl.outline_size          = 8
		lbl.outline_modulate      = Color(0.0, 0.0, 0.0, 0.90)
		lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
		lbl.billboard             = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test         = true
		lbl.text                  = "★"
		lbl.visible               = false
		add_child(lbl)
		_star_labels.append(lbl)


## Refreshes star labels, tints the footprint outline toward gold, and brightens
## the drop shadow as stats are maxed. Connected to stats_changed in initialize().
func _update_star_display() -> void:
	if _star_labels.is_empty():
		return
	var maxed: int = get_maxed_stat_count()

	const STAR_Z:      float = 0.45
	const STAR_Y:      float = 0.65
	const SIDE_OFFSET: float = 0.24

	var positions := [
		Vector3(0.0,          STAR_Y, STAR_Z),
		Vector3(-SIDE_OFFSET, STAR_Y, STAR_Z),
		Vector3( SIDE_OFFSET, STAR_Y, STAR_Z),
	]
	for i in range(_star_labels.size()):
		_star_labels[i].visible  = i < maxed
		_star_labels[i].position = positions[i]

	const GOLD: Color = Color(1.0, 0.82, 0.18)
	var frac := float(maxed) / float(get_total_upgradeable_stats())

	var tint := _base_color.lerp(GOLD, frac)
	for mat: StandardMaterial3D in _outline_mats:
		mat.albedo_color = tint

	if _shadow_mat != null:
		var shadow_tint    := _base_color.lerp(GOLD, frac)
		var brightness     := lerpf(0.18, 0.50, frac)
		var shadow_opacity := lerpf(0.60, 0.90, frac)
		_shadow_mat.set_shader_parameter("shadow_color",
			Vector3(shadow_tint.r * brightness, shadow_tint.g * brightness, shadow_tint.b * brightness))
		_shadow_mat.set_shader_parameter("opacity", shadow_opacity)


# ---------------------------------------------------------------------------
# Visual spawning
# ---------------------------------------------------------------------------

## Spawns the full placeholder visual: shadow halo → background plate →
## footprint outline → per-type body. Visual layers match Trap.gd.
func _spawn_visual() -> void:
	var c: Color
	match _boost_type:
		BoostType.PHEROMONE_DISPENSER: c = Color(0.95, 0.55, 0.10)   # orange
		BoostType.COMPRESSOR:          c = Color(0.10, 0.70, 0.90)   # cyan
		BoostType.CASH_REGISTER:       c = Color(0.20, 0.80, 0.30)   # green
		BoostType.AIR_FRESHENER:       c = Color(0.85, 0.92, 0.98)   # pale blue
		BoostType.QUARANTINE_MARKER:   c = Color(0.90, 0.90, 0.10)   # yellow
		_:                             c = Color(0.75, 0.75, 0.75)
	_base_color = c

	# Shadow halo — same shader and parameters as Trap._spawn_shadow().
	var plane_size    := Grid.CELL_SIZE * 2.4
	var shadow_plane   := PlaneMesh.new()
	shadow_plane.size  = Vector2(plane_size, plane_size)
	var shadow_mi      := MeshInstance3D.new()
	shadow_mi.mesh     = shadow_plane
	var shadow_mat                := ShaderMaterial.new()
	shadow_mat.shader              = SHADOW_OUTLINE_SHADER
	var boundary_half             := (Grid.CELL_SIZE * 1.9 / plane_size) / 2.0
	shadow_mat.set_shader_parameter("boundary_half", boundary_half)
	shadow_mat.set_shader_parameter("opacity",       0.60)
	shadow_mat.set_shader_parameter("shadow_color",  Vector3(c.r * 0.18, c.g * 0.18, c.b * 0.18))
	shadow_mi.material_override    = shadow_mat
	# Store so _update_star_display() can brighten and tint the shadow as stars are earned.
	_shadow_mat = shadow_mat
	shadow_mi.position.y           = 0.05 - 0.25
	add_child(shadow_mi)

	# Background plate — same size as Trap._spawn_background().
	var bg_plane  := PlaneMesh.new()
	bg_plane.size  = Vector2(Grid.CELL_SIZE * 1.85, Grid.CELL_SIZE * 1.85)
	var bg_mi      := MeshInstance3D.new()
	bg_mi.mesh     = bg_plane
	var bg_mat             := StandardMaterial3D.new()
	bg_mat.albedo_color     = Color(c.r * 0.65, c.g * 0.65, c.b * 0.65, 0.92)
	bg_mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mi.position.y        = 0.07 - 0.25
	bg_mi.material_override = bg_mat
	add_child(bg_mi)

	# Footprint outline — four thin bars matching Trap._spawn_footprint_outline().
	var fp        := Grid.CELL_SIZE * 1.9
	var thickness := fp * 0.04
	var bar_h     := 0.008
	var inner_d   := fp - thickness * 2.0
	var ol_y      := 0.005

	for sz: float in [-(fp * 0.5 - thickness * 0.5), fp * 0.5 - thickness * 0.5]:
		var mat              := _mat(c)
		_outline_mats.append(mat)
		var mi               := MeshInstance3D.new()
		var mesh             := BoxMesh.new()
		mesh.size            = Vector3(fp, bar_h, thickness)
		mi.mesh              = mesh
		mi.position          = Vector3(0.0, ol_y, sz)
		mi.material_override = mat
		add_child(mi)

	for sx: float in [-(fp * 0.5 - thickness * 0.5), fp * 0.5 - thickness * 0.5]:
		var mat              := _mat(c)
		_outline_mats.append(mat)
		var mi               := MeshInstance3D.new()
		var mesh             := BoxMesh.new()
		mesh.size            = Vector3(thickness, bar_h, inner_d)
		mi.mesh              = mesh
		mi.position          = Vector3(sx, ol_y, 0.0)
		mi.material_override = mat
		add_child(mi)

	# Per-type body — each boost gets a distinct procedural shape.
	match _boost_type:
		BoostType.PHEROMONE_DISPENSER: _spawn_pheromone_dispenser_visual(c)
		BoostType.COMPRESSOR:          _spawn_compressor_visual(c)
		BoostType.CASH_REGISTER:       _spawn_cash_register_visual(c)
		BoostType.AIR_FRESHENER:       _spawn_air_freshener_visual(c)
		BoostType.QUARANTINE_MARKER:   _spawn_quarantine_marker_visual(c)


## Pheromone Dispenser — emitter sprinkler head.
## Top-down silhouette: octagonal hub with four radiating nozzle arms at the cardinal points.
func _spawn_pheromone_dispenser_visual(c: Color) -> void:
	var fp  := Grid.CELL_SIZE * 1.9
	var dim := Color(c.r * 0.65, c.g * 0.65, c.b * 0.65)

	# Flat octagonal base plate — 8 segments gives a clear polygon silhouette from above.
	var base_mesh              := CylinderMesh.new()
	base_mesh.top_radius        = fp * 0.38
	base_mesh.bottom_radius     = fp * 0.38
	base_mesh.height            = fp * 0.03
	base_mesh.radial_segments   = 8
	var base_mi                := _mi(base_mesh, _mat(dim))
	base_mi.position.y          = fp * 0.015
	add_child(base_mi)

	# Central dome hub.
	var hub_mesh            := CylinderMesh.new()
	hub_mesh.top_radius      = fp * 0.12
	hub_mesh.bottom_radius   = fp * 0.12
	hub_mesh.height          = fp * 0.12
	hub_mesh.radial_segments = 10
	var hub_mi              := _mi(hub_mesh, _mat(c))
	hub_mi.position.y        = fp * 0.09
	add_child(hub_mi)

	# Four nozzle arms — one at each cardinal direction on the XZ plane.
	# Each is a thin box extending from the hub center outward.
	var arm_mesh      := BoxMesh.new()
	arm_mesh.size      = Vector3(fp * 0.14, fp * 0.03, fp * 0.06)
	for offset: Vector3 in [
		Vector3( fp * 0.25, fp * 0.04, 0.0),   # +X
		Vector3(-fp * 0.25, fp * 0.04, 0.0),   # -X
		Vector3(0.0,        fp * 0.04,  fp * 0.25),  # +Z
		Vector3(0.0,        fp * 0.04, -fp * 0.25),  # -Z
	]:
		var arm_mi              := MeshInstance3D.new()
		arm_mi.mesh              = arm_mesh
		arm_mi.material_override = _mat(c)
		arm_mi.position          = offset
		add_child(arm_mi)

	# Small nozzle tip dot at the end of each arm.
	var tip_mesh            := CylinderMesh.new()
	tip_mesh.top_radius      = fp * 0.04
	tip_mesh.bottom_radius   = fp * 0.04
	tip_mesh.height          = fp * 0.06
	tip_mesh.radial_segments = 6
	for offset: Vector3 in [
		Vector3( fp * 0.36, fp * 0.05, 0.0),
		Vector3(-fp * 0.36, fp * 0.05, 0.0),
		Vector3(0.0,        fp * 0.05,  fp * 0.36),
		Vector3(0.0,        fp * 0.05, -fp * 0.36),
	]:
		var tip_mi              := MeshInstance3D.new()
		tip_mi.mesh              = tip_mesh
		tip_mi.material_override = _mat(Color(1.0, 1.0, 1.0, 1.0))   # bright white tips
		tip_mi.position          = offset
		add_child(tip_mi)


## Compressor — compressed-air tank on a rectangular base.
## Top-down silhouette: long rectangular base with a round tank circle offset to one side.
func _spawn_compressor_visual(c: Color) -> void:
	var fp  := Grid.CELL_SIZE * 1.9
	var dim := Color(c.r * 0.55, c.g * 0.55, c.b * 0.55)

	# Rectangular base chassis.
	var base_mesh      := BoxMesh.new()
	base_mesh.size      = Vector3(fp * 0.65, fp * 0.06, fp * 0.46)
	var base_mi        := _mi(base_mesh, _mat(dim))
	base_mi.position    = Vector3(0.0, fp * 0.03, 0.0)
	add_child(base_mi)

	# Round pressure tank — offset toward -X so the gauge on +X is visible.
	var tank_mesh            := CylinderMesh.new()
	tank_mesh.top_radius      = fp * 0.17
	tank_mesh.bottom_radius   = fp * 0.17
	tank_mesh.height          = fp * 0.22
	tank_mesh.radial_segments = 16
	var tank_mi              := _mi(tank_mesh, _mat(c))
	tank_mi.position          = Vector3(-fp * 0.12, fp * 0.17, 0.0)
	add_child(tank_mi)

	# Pressure band ring around the tank — a darker, slightly wider ring at mid-height.
	var band_mesh            := CylinderMesh.new()
	band_mesh.top_radius      = fp * 0.175
	band_mesh.bottom_radius   = fp * 0.175
	band_mesh.height          = fp * 0.04
	band_mesh.radial_segments = 16
	var band_mi              := _mi(band_mesh, _mat(dim))
	band_mi.position          = Vector3(-fp * 0.12, fp * 0.17, 0.0)
	add_child(band_mi)

	# Pressure gauge — small box protruding on the +X side of the chassis.
	var gauge_mesh      := BoxMesh.new()
	gauge_mesh.size      = Vector3(fp * 0.08, fp * 0.10, fp * 0.08)
	var gauge_mi        := _mi(gauge_mesh, _mat(Color(0.85, 0.85, 0.85)))
	gauge_mi.position    = Vector3(fp * 0.22, fp * 0.11, 0.0)
	add_child(gauge_mi)

	# Gauge face — tiny dark circle on the front of the gauge box.
	var face_mesh            := CylinderMesh.new()
	face_mesh.top_radius      = fp * 0.028
	face_mesh.bottom_radius   = fp * 0.028
	face_mesh.height          = fp * 0.012
	face_mesh.radial_segments = 8
	var face_mi              := _mi(face_mesh, _mat(Color(0.15, 0.15, 0.15)))
	face_mi.position          = Vector3(fp * 0.265, fp * 0.11, 0.0)
	add_child(face_mi)


## Cash Register — stacked coins viewed from above.
## Top-down silhouette: three concentric disc layers decreasing in diameter.
func _spawn_cash_register_visual(c: Color) -> void:
	var fp   := Grid.CELL_SIZE * 1.9
	var gold := Color(1.00, 0.82, 0.10)
	var mid  := Color(0.90, 0.72, 0.08)
	var top  := Color(1.00, 0.95, 0.60)
	var dark := Color(c.r * 0.45, c.g * 0.55, c.b * 0.30)

	# Bottom coin — largest, full green-gold.
	var bot_mesh            := CylinderMesh.new()
	bot_mesh.top_radius      = fp * 0.37
	bot_mesh.bottom_radius   = fp * 0.37
	bot_mesh.height          = fp * 0.04
	bot_mesh.radial_segments = 24
	var bot_mi              := _mi(bot_mesh, _mat(gold))
	bot_mi.position.y        = fp * 0.02
	add_child(bot_mi)

	# Middle coin — slightly smaller and lighter.
	var mid_mesh            := CylinderMesh.new()
	mid_mesh.top_radius      = fp * 0.28
	mid_mesh.bottom_radius   = fp * 0.28
	mid_mesh.height          = fp * 0.04
	mid_mesh.radial_segments = 24
	var mid_mi              := _mi(mid_mesh, _mat(mid))
	mid_mi.position.y        = fp * 0.065
	add_child(mid_mi)

	# Top coin — smallest, palest.
	var top_mesh            := CylinderMesh.new()
	top_mesh.top_radius      = fp * 0.18
	top_mesh.bottom_radius   = fp * 0.18
	top_mesh.height          = fp * 0.04
	top_mesh.radial_segments = 24
	var top_mi              := _mi(top_mesh, _mat(top))
	top_mi.position.y        = fp * 0.11
	add_child(top_mi)

	# Dollar-sign nub — small dark cylinder at the apex of the stack.
	var nub_mesh            := CylinderMesh.new()
	nub_mesh.top_radius      = fp * 0.05
	nub_mesh.bottom_radius   = fp * 0.05
	nub_mesh.height          = fp * 0.06
	nub_mesh.radial_segments = 8
	var nub_mi              := _mi(nub_mesh, _mat(dark))
	nub_mi.position.y        = fp * 0.16
	add_child(nub_mi)


## Air Freshener — spray can viewed from above.
## Top-down silhouette: a narrow cylinder (can body) with a rectangular nozzle cap.
func _spawn_air_freshener_visual(c: Color) -> void:
	var fp  := Grid.CELL_SIZE * 1.9
	var dim := Color(c.r * 0.70, c.g * 0.75, c.b * 0.80)

	# Wider base ring — gives the can a stable, planted look.
	var base_mesh            := CylinderMesh.new()
	base_mesh.top_radius      = fp * 0.22
	base_mesh.bottom_radius   = fp * 0.24
	base_mesh.height          = fp * 0.03
	base_mesh.radial_segments = 16
	var base_mi              := _mi(base_mesh, _mat(dim))
	base_mi.position.y        = fp * 0.015
	add_child(base_mi)

	# Can body — tall, narrow cylinder.
	var body_mesh            := CylinderMesh.new()
	body_mesh.top_radius      = fp * 0.18
	body_mesh.bottom_radius   = fp * 0.20
	body_mesh.height          = fp * 0.28
	body_mesh.radial_segments = 16
	var body_mi              := _mi(body_mesh, _mat(c))
	body_mi.position.y        = fp * 0.17
	add_child(body_mi)

	# Label stripe — a thin darker band across the middle of the can.
	var stripe_mesh            := CylinderMesh.new()
	stripe_mesh.top_radius      = fp * 0.185
	stripe_mesh.bottom_radius   = fp * 0.185
	stripe_mesh.height          = fp * 0.06
	stripe_mesh.radial_segments = 16
	var stripe_mi              := _mi(stripe_mesh, _mat(dim))
	stripe_mi.position.y        = fp * 0.17
	add_child(stripe_mi)

	# Flat nozzle cap — box sitting on top of the can body.
	var cap_mesh      := BoxMesh.new()
	cap_mesh.size      = Vector3(fp * 0.20, fp * 0.05, fp * 0.16)
	var cap_mi        := _mi(cap_mesh, _mat(dim))
	cap_mi.position    = Vector3(0.0, fp * 0.335, 0.0)
	add_child(cap_mi)

	# Spray nozzle tip — tiny box protruding from the front of the cap.
	var tip_mesh      := BoxMesh.new()
	tip_mesh.size      = Vector3(fp * 0.05, fp * 0.04, fp * 0.08)
	var tip_mi        := _mi(tip_mesh, _mat(Color(0.60, 0.65, 0.70)))
	tip_mi.position    = Vector3(0.0, fp * 0.330, fp * 0.12)
	add_child(tip_mi)


## Quarantine Marker — biohazard zone disc viewed from above.
## Top-down silhouette: nested concentric rings with three small hazard tabs at 120° intervals.
func _spawn_quarantine_marker_visual(c: Color) -> void:
	var fp      := Grid.CELL_SIZE * 1.9
	var dark    := Color(c.r * 0.50, c.g * 0.50, c.b * 0.05)
	var bright  := Color(1.00, 1.00, 0.30)

	# Outer flat disc.
	var outer_mesh            := CylinderMesh.new()
	outer_mesh.top_radius      = fp * 0.40
	outer_mesh.bottom_radius   = fp * 0.40
	outer_mesh.height          = fp * 0.02
	outer_mesh.radial_segments = 32
	var outer_mi              := _mi(outer_mesh, _mat(c))
	outer_mi.position.y        = fp * 0.01
	add_child(outer_mi)

	# Middle raised ring — slightly taller and darker, creating a visible step.
	var mid_mesh            := CylinderMesh.new()
	mid_mesh.top_radius      = fp * 0.27
	mid_mesh.bottom_radius   = fp * 0.27
	mid_mesh.height          = fp * 0.05
	mid_mesh.radial_segments = 32
	var mid_mi              := _mi(mid_mesh, _mat(dark))
	mid_mi.position.y        = fp * 0.035
	add_child(mid_mi)

	# Inner dot — bright accent, the focal point of the biohazard symbol.
	var dot_mesh            := CylinderMesh.new()
	dot_mesh.top_radius      = fp * 0.10
	dot_mesh.bottom_radius   = fp * 0.10
	dot_mesh.height          = fp * 0.07
	dot_mesh.radial_segments = 12
	var dot_mi              := _mi(dot_mesh, _mat(bright))
	dot_mi.position.y        = fp * 0.055
	add_child(dot_mi)

	# Three hazard tabs at 120° intervals — small boxes offset radially from center.
	# Rotated 90° so two tabs are on the sides and one is toward the top.
	var tab_mesh      := BoxMesh.new()
	tab_mesh.size      = Vector3(fp * 0.07, fp * 0.04, fp * 0.08)
	for i in 3:
		var angle    := deg_to_rad(90.0 + i * 120.0)
		var tab_mi   := MeshInstance3D.new()
		tab_mi.mesh              = tab_mesh
		tab_mi.material_override = _mat(bright)
		tab_mi.position          = Vector3(cos(angle) * fp * 0.32, fp * 0.045, sin(angle) * fp * 0.32)
		add_child(tab_mi)
