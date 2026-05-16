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
## Perishable Boosts (AIR_FRESHENER, QUARANTINE_MARKER) emit boost_depleted when
## their capacity is exhausted; Arena removes them automatically in response.
##
## Arena-driven callbacks (all no-ops for non-applicable types):
##   absorb_infestation(amount, exit_pos) — called when an enemy reaches the exit
##   on_kill_near(kill_pos)               — called when an enemy dies
##   on_wave_started()                    — called when a new wave begins
##   on_enemy_died_near(death_pos)        — called when any enemy dies
##
## Usage: Arena instantiates this and calls initialize() before adding to the scene tree.

extends Node3D

const Grid = preload("res://arena/Grid.gd")


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

## Per-type stat table. All numeric values are placeholders — tuned via playtesting.
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


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when a perishable Boost exhausts its capacity.
## Arena connects here to remove the unit from the board automatically.
signal boost_depleted


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _boost_type:     BoostType = BoostType.PHEROMONE_DISPENSER
var _range:          float     = 0.0
var _cost:           int       = 0

# -1.0 means infinite capacity; perishable types start at their capacity stat value.
var _remaining_capacity: float = -1.0

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

var _base_color: Color = Color.WHITE


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Lightweight preview-only initializer used by the HUD icon SubViewport.
## Passes empty collections so no aura or callback logic runs.
func initialize_preview(boost_type: BoostType) -> void:
	initialize(boost_type, [], {})


## Configures the Boost for a given type and wires it to the live collections.
## Must be called by Arena before adding to the scene tree.
func initialize(boost_type: BoostType, active_enemies: Array, trap_nodes: Dictionary) -> void:
	_boost_type     = boost_type
	_active_enemies = active_enemies
	_trap_nodes     = trap_nodes

	var stats: Dictionary = STATS[boost_type]
	_range = stats["range"]
	_cost  = stats["cost"]

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
		BoostType.QUARANTINE_MARKER:
			_restore_per_kill    = stats["restore_per_kill"]
			_remaining_capacity  = stats["capacity"]

	_spawn_visual()


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
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

func get_cost() -> int:
	return _cost

func get_range_radius() -> float:
	return _range

func get_base_color() -> Color:
	return _base_color

## Returns remaining capacity fraction (1.0 = full, 0.0 = depleted).
## Returns 1.0 for infinite-capacity Boost types.
func get_capacity_fraction() -> float:
	if _remaining_capacity < 0.0:
		return 1.0
	var max_cap: float = STATS[_boost_type].get("capacity", 1.0)
	return _remaining_capacity / max_cap if max_cap > 0.0 else 0.0


# ---------------------------------------------------------------------------
# Aura management (PHEROMONE_DISPENSER + COMPRESSOR)
# ---------------------------------------------------------------------------

## Updates which traps are in aura range and applies / removes the boost effect.
## Two-pass pattern: clean up traps that left range, then apply to newly-in-range traps.
func _update_trap_aura() -> void:
	# Build the current set of in-range traps from Arena's live trap dictionary.
	var in_range: Array = []
	for trap in _trap_nodes.values():
		if is_instance_valid(trap) and _xz_distance(trap.global_position) <= _range:
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


## Spawns a colored placeholder visual until Phase 8 art migration.
## Color is chosen per type to be visually distinct from all trap types.
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

	# Background plate
	var fp     := Grid.CELL_SIZE * 1.9
	var bg_mi  := MeshInstance3D.new()
	var plane  := PlaneMesh.new()
	plane.size  = Vector2(fp * 1.85, fp * 1.85)
	bg_mi.mesh  = plane
	var bg_mat             := StandardMaterial3D.new()
	bg_mat.albedo_color     = Color(c.r * 0.55, c.g * 0.55, c.b * 0.55, 0.92)
	bg_mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mi.position.y        = 0.07 - 0.25
	bg_mi.material_override = bg_mat
	add_child(bg_mi)

	# Central cylinder body — visually distinct from the rectangular trap boxes.
	var cyl_mi   := MeshInstance3D.new()
	var cyl      := CylinderMesh.new()
	cyl.top_radius      = fp * 0.22
	cyl.bottom_radius   = fp * 0.22
	cyl.height          = fp * 0.28
	cyl.radial_segments = 12
	cyl_mi.mesh          = cyl
	cyl_mi.position.y    = fp * 0.14
	var cyl_mat             := StandardMaterial3D.new()
	cyl_mat.albedo_color     = c
	cyl_mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyl_mi.material_override = cyl_mat
	add_child(cyl_mi)
