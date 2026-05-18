## Trap.gd
## A player-placed trap that scans for enemies within its range and fires
## on a cooldown, dealing damage instantly on fire.
##
## Targeting model:
##   Each trap type has its own targeting priority:
##     SNAP_TRAP  — nearest enemy in range
##     ZAPPER     — farthest-along-path enemy in range (Phase 4)
##     FOGGER     — all enemies in range simultaneously (Phase 4)
##     GLUE_BOARD — passive AoE slow; cosmetic projectile fires when an enemy first enters range
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
##   Each trap instance tracks three independent upgrade levels — one per stat.
##   Active traps (Snap, Zapper, Fogger): Damage, Range, Fire Rate.
##   Glue Board: Adhesion, Range, Duration (seconds the slow persists after leaving range).
##   Each stat can be upgraded up to MAX_UPGRADE_LEVEL (3) times.
##   Costs per level are defined in UPGRADE_COSTS.
##
## Usage: instantiate via Arena, call initialize(), set position, then
## add to the scene tree.

extends Node3D

const Grid               = preload("res://arena/Grid.gd")
const Projectile         = preload("res://traps/Projectile.gd")
const FogCloud           = preload("res://traps/FogCloud.gd")
const UIFonts            = preload("res://ui/UIFonts.gd")
const SHADOW_OUTLINE_SHADER = preload("res://assets/shadow_outline.gdshader")
const BAIT_GLOW_SHADER      = preload("res://assets/bait_glow.gdshader")


# ---------------------------------------------------------------------------
# Trap type
# ---------------------------------------------------------------------------

enum TrapType { SNAP_TRAP, ZAPPER, FOGGER, GLUE_BOARD, FLY_STRIP_LAUNCHER, BAIT_STATION }

## Per-type stat table. All numeric values are placeholders — tuned via playtesting.
##   damage           — HP removed from each target per shot
##   range            — circular detection radius in world units (1 unit = 1 cell)
##   cooldown         — seconds between shots; 0.0 = passive (no shots fired)
##   cost             — Bug Bucks to place one trap of this type
##   color            — placeholder box colour (replaced by sprites in Phase 8)
##   cloud_duration   — FLY_STRIP_LAUNCHER only: seconds the sticky cloud persists
##   adhesion         — FLY_STRIP_LAUNCHER only: slow factor applied to flying enemies (0.0–1.0)
##   pulse_interval   — BAIT_STATION only: seconds between damage pulses
##   poison_*         — BAIT_STATION only: poison DoT applied after each pulse
const STATS := {
	TrapType.SNAP_TRAP:  { "damage": 5.0,  "range": 5.6, "cooldown": 1.0, "cost": 25, "color": Color(0.52, 0.27, 0.08) },
	TrapType.ZAPPER:     { "damage": 30.0, "range": 9.6, "cooldown": 2.5, "cost": 75, "color": Color(0.10, 0.50, 1.00) },
	TrapType.FOGGER:     { "damage": 3.0,  "range": 4.0, "cooldown": 2.2, "cost": 60, "color": Color(0.35, 0.88, 0.18) },
	TrapType.GLUE_BOARD: { "damage": 0.20, "range": 4.8, "cooldown": 0.0, "cost": 45, "color": Color(0.92, 0.89, 0.78) },
	TrapType.FLY_STRIP_LAUNCHER: {
		"damage": 2.0, "range": 5.0, "cooldown": 5.0, "cost": 65, "color": Color(0.85, 0.20, 0.65),
		"cloud_duration": 3.0, "adhesion": 0.30,
	},
	TrapType.BAIT_STATION: {
		"damage": 3.0, "range": 3.5, "cooldown": 0.0, "cost": 40, "color": Color(0.45, 0.25, 0.55),
		"pulse_interval": 4.0,
		"poison_damage_per_tick": 1.5, "poison_duration": 3.0, "poison_tick_rate": 0.5,
	},
}

## Each stat can be upgraded this many times independently.
const MAX_UPGRADE_LEVEL: int = 3

## Stat increment per upgrade level, as a fraction of the base value.
const UPGRADE_DAMAGE_FACTOR:    float = 0.20  # +20% of base damage per level
const UPGRADE_RANGE_FACTOR:     float = 0.10  # +10% of base range per level
const UPGRADE_FIRE_RATE_FACTOR: float = 0.08  # −8% of base cooldown per level (faster shots)

## Glue Board adhesion strength at each damage upgrade level (index = _damage_level).
## Values are slow factors: 0.0 = no slow, 1.0 = fully stopped.
## Defined as an explicit table because the intended values don't fit the shared
## UPGRADE_DAMAGE_FACTOR formula.
const GLUE_ADHESION_LEVELS: Array[float] = [0.20, 0.30, 0.40, 0.50]

## Glue Board slow duration (seconds) at each duration upgrade level (index = _duration_level).
## How long the slow persists on an enemy after it leaves the board's radius.
const GLUE_DURATION_LEVELS: Array[float] = [3.0, 4.5, 6.0, 8.0]

## Fly Strip Launcher adhesion strength at each third-stat upgrade level.
## Applied to flying enemies caught in the sticky cloud.
const FLY_STRIP_ADHESION_LEVELS: Array[float] = [0.30, 0.40, 0.55, 0.70]

## Bait Station poison duration (seconds) at each duration upgrade level.
## How long the DoT persists on an enemy after the pulse hits them.
const BAIT_POISON_DURATION_LEVELS: Array[float] = [3.0, 4.5, 6.0, 8.0]

## Bait Station glow plane appearance at rest (between pulses).
## The plane is always visible at this subdued level so the trap reads as dangerous.
## On each pulse it expands to full scale (1.0) and full opacity (1.0), then
## returns here.
const BAIT_GLOW_REST_OPACITY: float = 0.25   # dim persistent glow at zero stars
const BAIT_GLOW_REST_SCALE:   float = 0.50   # roughly footprint-sized at rest

## Resting glow opacity indexed by number of maxed stats (0–3).
## As the player upgrades the Bait Station, the persistent red glow brightens to
## signal increasing toxicity — 0 stars is faint, 3 stars is noticeably intense.
const BAIT_GLOW_OPACITY_BY_STARS: Array[float] = [0.25, 0.40, 0.55, 0.70]

## Bug Bucks cost for each upgrade level per trap type.
## Index 0 = first upgrade, 1 = second, 2 = third.
## All values are tuning placeholders — finalize via playtesting.
const UPGRADE_COSTS := {
	TrapType.SNAP_TRAP:          [20, 30,  50],
	TrapType.ZAPPER:             [50, 75, 120],
	TrapType.FOGGER:             [40, 60, 100],
	TrapType.GLUE_BOARD:         [30, 45,  70],
	TrapType.FLY_STRIP_LAUNCHER: [40, 65, 100],
	TrapType.BAIT_STATION:       [30, 45,  70],
}


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when a point-target trap fires (Snap Trap, Zapper). Arena spawns
## a Projectile in response so the trap does not need a scene tree reference.
signal fired(from_pos: Vector3, to_pos: Vector3, target: Node3D, damage: float, trap_type: TrapType)

## Emitted once per Fogger firing cycle. Arena spawns a FogCloud that persists
## for its full visual lifetime and ticks damage to any enemy in range on a
## fixed interval — including enemies that enter the area after the cloud forms.
signal aoe_fired(from_pos: Vector3, aoe_range: float, damage: float, active_enemies: Array)

## Emitted once per Fly Strip Launcher firing cycle. Arena spawns a FlyStripCloud
## that slows and damages flying enemies while they pass through it.
signal fly_strip_fired(from_pos: Vector3, aoe_range: float, damage: float, adhesion: float, cloud_duration: float, active_enemies: Array)

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

# All enemies currently under this board's slow effect.
#   key   = enemy node
#   value = -1.0 while the enemy is inside the range radius;
#           remaining countdown seconds after the enemy has left the radius.
var _glue_slowed_enemies: Dictionary = {}

# How long the slow lingers on an enemy after it exits the board's radius.
var _slow_duration:  float = 0.0
var _duration_level: int   = 0

# When true, this node is a visual-only placement preview: no combat, no hover area,
# no range indicator. Set by initialize_preview() before the node enters the tree.
var _is_preview: bool = false

# Range indicator shown on mouse hover.
var _is_hovered:      bool              = false
var _range_indicator: Node3D           = null
var _range_fill_mat:  StandardMaterial3D = null   # stored so color can be updated without rebuild
var _range_ring_mat:  StandardMaterial3D = null
var _hover_area:      Area3D = null
# When true, the indicator stays visible regardless of hover state (upgrade panel open).
var _indicator_pinned: bool  = false

# Star display — one Label3D per possible star (max 3).
# All three labels are pre-spawned; _update_star_display() shows/hides and repositions them.
var _star_labels: Array[Label3D] = []

# Upgrade tint — materials updated in _update_star_display() to lerp toward gold.
var _base_color:   Color                       = Color.WHITE
var _outline_mats: Array[StandardMaterial3D]   = []
var _shadow_mat:   ShaderMaterial              = null

# Arena-decorator nodes: the colored background plate, shadow halo, and footprint
# outline bars.  Populated by _spawn_background / _spawn_shadow / _spawn_footprint_outline
# so hide_decorators() can remove them for icon-only previews (e.g. HUD panel icons).
var _decorator_nodes: Array[Node3D] = []

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

# Fly Strip Launcher animation nodes — null for all other trap types.
# _fly_strip_root bobs at idle; _fly_strip_barrel_pivot recoils on each shot.
var _fly_strip_root:          Node3D = null
var _fly_strip_barrel_pivot:  Node3D = null
var _fly_strip_barrel_base_y: float  = 0.0   # resting Y stored so recoil can return to origin
var _fly_strip_bob_time:      float  = 0.0
var _fly_strip_animating:     bool   = false

# Bait Station animation state — null for all other trap types.
# _bait_glow_mat is the radial glow shader material; at rest it holds
# BAIT_GLOW_REST_OPACITY and BAIT_GLOW_REST_SCALE, then pulses to full on each fire.
# _bait_glow_mi is the plane node so its scale can be tweened during the pulse.
var _bait_glow_mat:  ShaderMaterial  = null
var _bait_glow_mi:   MeshInstance3D  = null
var _bait_animating: bool            = false

# Tracks how many particle batches from this trap are still visually alive.
# Each fire increments the count; a timer decrements it after the particles expire.
# Firing is blocked when the count reaches the cap (~6 puffs on screen).
const FOG_BATCH_CAP: int       = 2   # 2 batches × 3–4 puffs each ≈ 6 puffs max
const FLY_STRIP_BATCH_CAP: int = 2   # same limit for fly strip clouds
var _active_fog_batches:       int = 0
var _active_fly_strip_batches: int = 0

# Fly Strip Launcher — extra stats that go beyond the base damage/range/cooldown tuple.
var _fly_strip_adhesion:       float = 0.0   # slow factor applied to flying enemies in the cloud
var _fly_strip_cloud_duration: float = 0.0   # how many seconds the cloud lingers

# Bait Station — pulse interval and poison parameters (stored separately because
# cooldown = 0.0 in STATS so the base fire loop treats it as passive).
var _bait_pulse_interval:          float = 0.0
var _bait_pulse_timer:             float = 0.0
var _bait_poison_damage_per_tick:  float = 0.0
var _bait_base_poison_damage:      float = 0.0   # base value stored so upgrades scale correctly
var _bait_poison_duration:         float = 0.0
var _bait_poison_tick_rate:        float = 0.0

# Damage and fire-rate multipliers applied by Boost auras.
# Stored per-source so the boost is removed cleanly when the Boost is sold or destroyed.
var _damage_boost_sources:    Dictionary = {}   # BoostUnit node → damage bonus factor
var _fire_rate_boost_sources: Dictionary = {}   # BoostUnit node → fire-rate bonus factor
var _damage_multiplier:    float = 1.0
var _fire_rate_multiplier: float = 1.0


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

	if _trap_type == TrapType.FLY_STRIP_LAUNCHER:
		_fly_strip_adhesion       = stats.get("adhesion", 0.30)
		_fly_strip_cloud_duration = stats.get("cloud_duration", 3.0)

	if _trap_type == TrapType.BAIT_STATION:
		_bait_pulse_interval         = stats.get("pulse_interval", 4.0)
		_bait_pulse_timer            = 0.0   # fire on the first frame an enemy is in range
		_bait_poison_damage_per_tick = stats.get("poison_damage_per_tick", 1.5)
		_bait_base_poison_damage     = _bait_poison_damage_per_tick
		_bait_poison_duration        = stats.get("poison_duration", 3.0)
		_bait_poison_tick_rate       = stats.get("poison_tick_rate", 0.5)

	_spawn_visual(stats["color"])
	_spawn_star_display()
	stats_changed.connect(_rebuild_range_indicator)
	stats_changed.connect(_update_star_display)
	if _trap_type == TrapType.GLUE_BOARD:
		_slow_duration = GLUE_DURATION_LEVELS[0]
		stats_changed.connect(_refresh_glue_slow)
	if _trap_type == TrapType.BAIT_STATION:
		_bait_poison_duration = BAIT_POISON_DURATION_LEVELS[0]


## Lightweight setup for placement preview ghosts.
## Builds the visual and range indicator — no combat state or hover area.
## Caller should set process_mode = DISABLED before adding to the tree.
func initialize_preview(trap_type: TrapType) -> void:
	_is_preview = true
	_trap_type  = trap_type
	_range      = STATS[trap_type]["range"]
	_spawn_visual(STATS[trap_type]["color"])


func _ready() -> void:
	if _is_preview:
		_spawn_range_indicator()
		if _range_indicator != null:
			_range_indicator.visible = true
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

func get_duration_upgrade_cost() -> int:
	if _duration_level >= MAX_UPGRADE_LEVEL:
		return 0
	return UPGRADE_COSTS[_trap_type][_duration_level]


# ---------------------------------------------------------------------------
# Upgrade — stat previews
# ---------------------------------------------------------------------------

## Damage this trap would have after one damage upgrade.
## For Glue Board, returns the next adhesion tier value from GLUE_ADHESION_LEVELS.
func get_damage_after_upgrade() -> float:
	match _trap_type:
		TrapType.GLUE_BOARD:
			return GLUE_ADHESION_LEVELS[mini(_damage_level + 1, MAX_UPGRADE_LEVEL)]
		_:
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

## Glue Board / Bait Station — duration value after the next duration upgrade.
func get_duration_after_upgrade() -> float:
	if _trap_type == TrapType.BAIT_STATION:
		return BAIT_POISON_DURATION_LEVELS[mini(_duration_level + 1, MAX_UPGRADE_LEVEL)]
	return GLUE_DURATION_LEVELS[mini(_duration_level + 1, MAX_UPGRADE_LEVEL)]


# ---------------------------------------------------------------------------
# Upgrade — apply
# ---------------------------------------------------------------------------

## Increases damage by 20% of base (or advances to the next adhesion tier for Glue Board).
## For Bait Station, poison tick damage scales with burst damage at the same rate.
## Only call when not maxed.
func apply_damage_upgrade() -> void:
	if _trap_type == TrapType.GLUE_BOARD:
		_damage_level += 1
		_damage = GLUE_ADHESION_LEVELS[_damage_level]
	else:
		_damage += _base_damage * UPGRADE_DAMAGE_FACTOR
		if _trap_type == TrapType.BAIT_STATION:
			_bait_poison_damage_per_tick += _bait_base_poison_damage * UPGRADE_DAMAGE_FACTOR
		_damage_level += 1
	_check_full_upgrade_bonus()
	stats_changed.emit()

## Increases range by 10% of base. Only call when not maxed.
func apply_range_upgrade() -> void:
	_range += _base_range * UPGRADE_RANGE_FACTOR
	_range_level += 1
	_check_full_upgrade_bonus()
	stats_changed.emit()

## Reduces cooldown by 8% of base (faster shots), or advances Fly Strip Launcher
## adhesion to the next tier. Only call when not maxed.
## Cooldown is clamped to 0.1 s minimum to prevent instant-fire edge cases.
func apply_fire_rate_upgrade() -> void:
	if _trap_type == TrapType.FLY_STRIP_LAUNCHER:
		_rate_level      += 1
		_fly_strip_adhesion = FLY_STRIP_ADHESION_LEVELS[_rate_level]
	else:
		_cooldown    = maxf(_cooldown - _base_cooldown * UPGRADE_FIRE_RATE_FACTOR, 0.1)
		_rate_level += 1
	_check_full_upgrade_bonus()
	stats_changed.emit()

## Advances the Glue Board slow duration or Bait Station poison duration to the next tier.
## Only call when not maxed.
func apply_duration_upgrade() -> void:
	_duration_level += 1
	if _trap_type == TrapType.BAIT_STATION:
		_bait_poison_duration = BAIT_POISON_DURATION_LEVELS[_duration_level]
	else:
		_slow_duration = GLUE_DURATION_LEVELS[_duration_level]
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

func get_duration_level() -> int:
	return _duration_level

func is_duration_maxed() -> bool:
	return _duration_level >= MAX_UPGRADE_LEVEL

## Glue Board — slow duration in seconds. Bait Station — poison duration in seconds.
func get_duration() -> float:
	if _trap_type == TrapType.BAIT_STATION:
		return _bait_poison_duration
	return _slow_duration

## True when every upgradeable stat is at MAX_UPGRADE_LEVEL.
func is_fully_upgraded() -> bool:
	match _trap_type:
		TrapType.GLUE_BOARD, TrapType.BAIT_STATION:
			return is_damage_maxed() and is_range_maxed() and is_duration_maxed()
		_:
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

func get_type() -> TrapType:
	return _trap_type

func get_type_name() -> String:
	match _trap_type:
		TrapType.SNAP_TRAP:          return "Snap Trap"
		TrapType.ZAPPER:             return "Zapper"
		TrapType.FOGGER:             return "Fogger"
		TrapType.GLUE_BOARD:         return "Glue Board"
		TrapType.FLY_STRIP_LAUNCHER: return "Fly Strip Launcher"
		TrapType.BAIT_STATION:       return "Bait Station"
	return "Unknown"

## Short description shown in the upgrade panel.
func get_description() -> String:
	match _trap_type:
		TrapType.SNAP_TRAP:
			return "Targets the nearest pest in range. Fast fire rate, low damage. Can hit flying pests."
		TrapType.ZAPPER:
			return "Targets the pest farthest along the path. Slow rate, high damage. Cannot hit flying pests."
		TrapType.FOGGER:
			return "Fires an expanding cloud that hits all pests from closest to farthest. Cannot hit flying pests."
		TrapType.GLUE_BOARD:
			return "Continuously slows every pest inside its range. Passive — no firing."
		TrapType.FLY_STRIP_LAUNCHER:
			return "Targets flying pests only. Releases a sticky cloud on impact that slows and damages."
		TrapType.BAIT_STATION:
			return "Passable by enemies. Pulses poison onto every pest in range, dealing damage over time."
	return ""

## Returns a list of active boost effects currently amplifying this trap.
## Entries are aggregated by boost name so two Pheromone Dispensers appear
## as one entry with their combined bonus, not as two separate lines.
## Each entry is a Dictionary: { "name": String, "detail": String }
## Used by TrapUpgradePanel to display which boosts are in range.
func get_active_boost_display() -> Array:
	var result: Array = []

	var dmg_totals: Dictionary = {}
	for source in _damage_boost_sources:
		if is_instance_valid(source):
			var n: String = source.get_type_name()
			dmg_totals[n] = dmg_totals.get(n, 0.0) + _damage_boost_sources[source]
	for n: String in dmg_totals:
		result.append({ "name": n, "detail": "+%d%% damage" % int(dmg_totals[n] * 100) })

	var rate_totals: Dictionary = {}
	for source in _fire_rate_boost_sources:
		if is_instance_valid(source):
			var n: String = source.get_type_name()
			rate_totals[n] = rate_totals.get(n, 0.0) + _fire_rate_boost_sources[source]
	for n: String in rate_totals:
		result.append({ "name": n, "detail": "+%d%% fire rate" % int(rate_totals[n] * 100) })

	return result


## Returns the Bug Bucks cost to place this trap.
func get_cost() -> int:
	return _cost

## Returns the identity colour used for this trap's background plate, shadow, and footprint outline.
## The upgrade panel reads this to derive its per-trap colour theme.
func get_base_color() -> Color:
	return _base_color

## Glue Board only — adhesion strength as a percentage (e.g. 50.0 for 50% slow).
func get_adhesion_pct() -> float:
	return _damage * 100.0

## Glue Board only — adhesion after the next damage upgrade, as a percentage.
func get_adhesion_after_upgrade_pct() -> float:
	return get_damage_after_upgrade() * 100.0

## Returns how many stats are currently at MAX_UPGRADE_LEVEL.
func get_maxed_stat_count() -> int:
	var count := 0
	if is_damage_maxed(): count += 1
	if is_range_maxed():  count += 1
	match _trap_type:
		TrapType.GLUE_BOARD, TrapType.BAIT_STATION:
			if is_duration_maxed(): count += 1
		_:
			if not is_passive() and is_rate_maxed(): count += 1
	return count

## Returns the total number of independently upgradeable stats for this trap.
## All trap types have 3: active traps upgrade Fire Rate; Glue Board upgrades Duration.
func get_total_upgradeable_stats() -> int:
	return 3

## Fraction of total spending returned when the trap is sold.
const SELL_REFUND_FRACTION: float = 0.49

## Returns the Bug Bucks refunded when this trap is sold.
## Covers the placement cost plus every upgrade level purchased across all stats.
## Passive traps have no fire-rate level, so _rate_level stays 0 and its loop is a no-op.
func get_sell_value() -> int:
	var total_spent := _cost
	for lvl in range(_damage_level):
		total_spent += UPGRADE_COSTS[_trap_type][lvl]
	for lvl in range(_range_level):
		total_spent += UPGRADE_COSTS[_trap_type][lvl]
	for lvl in range(_rate_level):
		total_spent += UPGRADE_COSTS[_trap_type][lvl]
	for lvl in range(_duration_level):
		total_spent += UPGRADE_COSTS[_trap_type][lvl]
	return int(total_spent * SELL_REFUND_FRACTION)


# ---------------------------------------------------------------------------
# Combat loop
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _trap_type == TrapType.GLUE_BOARD:
		_update_glue_aoe(delta)
		return
	if _trap_type == TrapType.BAIT_STATION:
		_update_bait_station(delta)
		return

	# Fogger idle animation: gentle sine-wave float between shots.
	if _trap_type == TrapType.FOGGER and _fogger_root != null:
		_fogger_bob_time += delta
		_fogger_root.position.y = sin(_fogger_bob_time * 1.5) * Grid.CELL_SIZE * 0.035

	# Fly Strip Launcher idle animation: gentle bob matching the Fogger cadence.
	if _trap_type == TrapType.FLY_STRIP_LAUNCHER and _fly_strip_root != null:
		_fly_strip_bob_time += delta
		_fly_strip_root.position.y = sin(_fly_strip_bob_time * 1.3) * Grid.CELL_SIZE * 0.028

	_cooldown_remaining -= delta
	if _cooldown_remaining > 0.0:
		return

	var did_fire := false
	if _trap_type == TrapType.FOGGER:
		did_fire = _fire_fogger()
		if did_fire:
			aoe_fired.emit(global_position, _range, _damage * _damage_multiplier, _active_enemies)
			_play_fogger_animation()
			_active_fog_batches += 1
			var expire := FogCloud.PARTICLE_LIFETIME * 2.0 + 0.20
			get_tree().create_timer(expire).timeout.connect(
				func(): _active_fog_batches = maxi(0, _active_fog_batches - 1)
			)
	elif _trap_type == TrapType.FLY_STRIP_LAUNCHER:
		var fly_target := _fire_fly_strip()
		did_fire = fly_target != null
		if did_fire:
			# Cosmetic projectile toward the nearest flying enemy; cloud handles all damage.
			fired.emit(global_position, fly_target.global_position, fly_target, 0.0, _trap_type)
			fly_strip_fired.emit(global_position, _range, _damage * _damage_multiplier,
				_fly_strip_adhesion, _fly_strip_cloud_duration, _active_enemies)
			_play_fly_strip_animation()
			_active_fly_strip_batches += 1
			# Timer matches the cloud lifetime so the batch counter clears when it fades.
			get_tree().create_timer(_fly_strip_cloud_duration + 0.50).timeout.connect(
				func(): _active_fly_strip_batches = maxi(0, _active_fly_strip_batches - 1)
			)
	else:
		var target := _find_target()
		if target != null:
			fired.emit(global_position, target.global_position, target,
				_damage * _damage_multiplier, _trap_type)
			did_fire = true
			if _trap_type == TrapType.SNAP_TRAP:
				_play_snap_animation()
			if _trap_type == TrapType.ZAPPER:
				_play_zapper_animation()

	if did_fire:
		# Divide by fire-rate multiplier so a Compressor Boost speeds up all traps.
		_cooldown_remaining = _cooldown / _fire_rate_multiplier


func _exit_tree() -> void:
	# Release all slow sources so every affected enemy returns to normal speed
	# immediately when the trap is sold or overwritten.
	for enemy in _glue_slowed_enemies:
		if is_instance_valid(enemy):
			enemy.remove_slow_source(self)
	_glue_slowed_enemies.clear()


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
## Damage is NOT applied here — FogCloud ticks it on a fixed interval while alive.
func _fire_fogger() -> bool:
	if _active_fog_batches >= FOG_BATCH_CAP:
		return false
	for enemy in _active_enemies:
		if not is_instance_valid(enemy):
			continue
		if _xz_distance(enemy.global_position) <= _range:
			return true
	return false


## Slows every enemy that enters range. The slow persists for _slow_duration seconds
## after the enemy leaves the radius before being removed. Runs every frame.
func _update_glue_aoe(delta: float) -> void:
	# First pass: tick duration countdowns and collect enemies whose slow has expired.
	# Cannot erase from a Dictionary while iterating — collect targets first.
	var to_release: Array = []
	for enemy in _glue_slowed_enemies:
		if not is_instance_valid(enemy):
			to_release.append(enemy)
			continue
		if _xz_distance(enemy.global_position) <= _range:
			_glue_slowed_enemies[enemy] = -1.0   # still in range — reset to "no countdown"
		else:
			var remaining: float = _glue_slowed_enemies[enemy]
			if remaining < 0.0:
				_glue_slowed_enemies[enemy] = _slow_duration  # just left range — start countdown
			else:
				remaining -= delta
				if remaining <= 0.0:
					to_release.append(enemy)
				else:
					_glue_slowed_enemies[enemy] = remaining

	for enemy in to_release:
		if is_instance_valid(enemy):
			enemy.remove_slow_source(self)
		_glue_slowed_enemies.erase(enemy)

	# Second pass: apply slow to newly-in-range enemies and fire a cosmetic projectile.
	var newly_caught := false
	for enemy in _active_enemies:
		if not is_instance_valid(enemy):
			continue
		if _xz_distance(enemy.global_position) <= _range and not _glue_slowed_enemies.has(enemy):
			enemy.add_slow_source(self, _damage)
			_glue_slowed_enemies[enemy] = -1.0
			fired.emit(global_position, enemy.global_position, enemy, 0.0, _trap_type)
			newly_caught = true
	if newly_caught:
		AudioManager.play_trap_fire(TrapType.GLUE_BOARD)


## Re-applies the current adhesion factor to all already-slowed enemies.
## Connected to stats_changed so an adhesion upgrade takes effect immediately
## on enemies that are already inside the board's radius.
func _refresh_glue_slow() -> void:
	for enemy in _glue_slowed_enemies:
		if is_instance_valid(enemy):
			enemy.add_slow_source(self, _damage)


## Returns the first in-range flying enemy, or null if the batch cap is reached or none qualify.
## Damage is NOT applied here — FlyStripCloud ticks it while alive.
## The returned node is used by the combat loop as the cosmetic projectile's visual target.
func _fire_fly_strip() -> Node3D:
	if _active_fly_strip_batches >= FLY_STRIP_BATCH_CAP:
		return null
	for enemy in _active_enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.get_is_flying() and _xz_distance(enemy.global_position) <= _range:
			return enemy
	return null


## Pulses damage + poison to all ground enemies in range on a fixed interval.
## Runs every frame in place of the standard fire loop.
func _update_bait_station(delta: float) -> void:
	_bait_pulse_timer -= delta
	if _bait_pulse_timer > 0.0:
		return

	var hit_any := false
	for enemy in _active_enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.get_is_flying():
			continue   # Bait Station only affects ground pests
		if _xz_distance(enemy.global_position) > _range:
			continue
		enemy.take_damage(_damage * _damage_multiplier, Color(0.72, 0.42, 0.08))
		enemy.apply_poison(_bait_poison_damage_per_tick, _bait_poison_duration, _bait_poison_tick_rate)
		hit_any = true
	if hit_any:
		# Only start the cooldown after a successful hit — keeps the trap "ready"
		# when no enemy was in range, so the first enemy to enter is hit immediately.
		_bait_pulse_timer = _bait_pulse_interval
		AudioManager.play_trap_fire(TrapType.BAIT_STATION)
		_play_bait_animation()
	else:
		_bait_pulse_timer = 0.0


# ---------------------------------------------------------------------------
# Boost aura system
# ---------------------------------------------------------------------------

## Called by a Pheromone Dispenser Boost when it enters or refreshes range of this trap.
## Stacks additively: two dispensers with factor 0.25 each give _damage_multiplier = 1.50.
func apply_damage_boost(source: Node3D, factor: float) -> void:
	_damage_boost_sources[source] = factor
	_recalculate_multipliers()


## Called by a Pheromone Dispenser Boost when it is sold, destroyed, or moves out of range.
func remove_damage_boost(source: Node3D) -> void:
	_damage_boost_sources.erase(source)
	_recalculate_multipliers()


## Called by a Compressor Boost when it enters or refreshes range of this trap.
func apply_fire_rate_boost(source: Node3D, factor: float) -> void:
	_fire_rate_boost_sources[source] = factor
	_recalculate_multipliers()


## Called by a Compressor Boost when it is sold, destroyed, or moves out of range.
func remove_fire_rate_boost(source: Node3D) -> void:
	_fire_rate_boost_sources.erase(source)
	_recalculate_multipliers()


## Recomputes multipliers from the current boost source dictionaries.
func _recalculate_multipliers() -> void:
	var damage_bonus: float = 0.0
	for factor: float in _damage_boost_sources.values():
		damage_bonus += factor
	_damage_multiplier = 1.0 + damage_bonus

	var fire_rate_bonus: float = 0.0
	for factor: float in _fire_rate_boost_sources.values():
		fire_rate_bonus += factor
	_fire_rate_multiplier = 1.0 + fire_rate_bonus


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
## yet been applied, boosts every stat by 7.5% as a reward for full investment.
## Fire rate boost reduces cooldown so shots-per-second increases by ~8%.
func _check_full_upgrade_bonus() -> void:
	if _bonus_applied or not is_fully_upgraded():
		return
	_damage  *= 1.075
	_range   *= 1.075
	if _base_cooldown > 0.0:
		_cooldown = maxf(_cooldown / 1.075, 0.1)
	_bonus_applied = true


## Spawns the star label and glow disc that reflect how many stats are maxed.
## Called once from initialize() — not spawned for preview instances.
## Spawns three Label3D nodes in fixed slots:
##   [0] = center (large)   always shown for the first maxed stat
##   [1] = left   (small)   shown for the second maxed stat
##   [2] = right  (small)   shown for the third maxed stat
func _spawn_star_display() -> void:
	# Center star is larger; side stars are smaller to signal hierarchy.
	# pixel_size=0.009 throughout so world-unit sizes scale directly with font_size.
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


## Refreshes star labels, tints the footprint outline toward gold, and brightens the
## drop shadow as stats are maxed.  The background plate keeps its base color throughout —
## only the border and shadow shift, so the trap's identity color is always visible.
func _update_star_display() -> void:
	if _star_labels.is_empty():
		return
	var maxed: int = get_maxed_stat_count()

	# --- Stars ---
	# Layout: [left-small]  [center-large]  [right-small]
	# center ★ is 88pt  → ~0.79 world units wide (half = 0.395)
	# side   ★ is 54pt  → ~0.49 world units wide (half = 0.243)
	# STAR_Z chosen so the center star's bottom edge (~z+0.395) clears the inner
	# edge of the outline bar (~z=0.874): 0.45 + 0.395 = 0.845, just inside the line.
	const STAR_Z:       float = 0.45
	const STAR_Y:       float = 0.65
	const SIDE_OFFSET:  float = 0.24

	# Slot 0 = center, 1 = left, 2 = right
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

	# --- Outline tint ---
	# Lerp from base color toward gold so the border signals upgrade progress
	# without washing out the trap's base color on the background plate.
	var tint := _base_color.lerp(GOLD, frac)
	for mat: StandardMaterial3D in _outline_mats:
		mat.albedo_color = tint

	# --- Shadow brightness + tint ---
	# At zero stars the shadow is dim (18% brightness, opacity 0.60).
	# As stars are earned it brightens (up to 50%) and shifts toward gold, echoing the outline.
	if _shadow_mat != null:
		var shadow_tint    := _base_color.lerp(GOLD, frac)
		var brightness     := lerpf(0.18, 0.50, frac)
		var shadow_opacity := lerpf(0.60, 0.90, frac)
		_shadow_mat.set_shader_parameter("shadow_color",
			Vector3(shadow_tint.r * brightness, shadow_tint.g * brightness, shadow_tint.b * brightness))
		_shadow_mat.set_shader_parameter("opacity", shadow_opacity)

	# --- Bait Station resting glow brightness ---
	# Skip update mid-pulse so the tween isn't interrupted; the corrected opacity
	# will take effect naturally when the next pulse finishes and fades back.
	if _bait_glow_mat != null and not _bait_animating:
		_bait_glow_mat.set_shader_parameter("opacity", _bait_current_rest_opacity())


## Shows the range indicator. Called by Arena when a placement preview overlaps this trap,
## or when the upgrade panel pins it open.
## Pass dimmed=true when shown because a new trap is being placed over this one — the gray
## tint signals "existing trap" vs. the full-white preview of the trap being placed.
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
	_set_range_indicator_dimmed(false)   # restore white for next time it appears


## Applies or removes the gray tint on the range indicator's materials.
func _set_range_indicator_dimmed(dimmed: bool) -> void:
	if _range_fill_mat == null or _range_ring_mat == null:
		return
	var tint := Color(0.50, 0.50, 0.50) if dimmed else Color(1.0, 1.0, 1.0)
	_range_fill_mat.albedo_color = Color(tint.r, tint.g, tint.b, _range_fill_mat.albedo_color.a)
	_range_ring_mat.albedo_color = Color(tint.r, tint.g, tint.b, _range_ring_mat.albedo_color.a)


## Hides the colored background plate, shadow halo, and footprint outline bars.
## Called on icon-only previews (HUD panel, drag overlay) so only the trap model shows.
func hide_decorators() -> void:
	for node: Node3D in _decorator_nodes:
		node.hide()


func _on_hover_enter() -> void:
	_is_hovered = true


func _on_hover_exit() -> void:
	_is_hovered = false


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
## Preview instances (trap being dragged for placement) use higher opacity so the
## circle reads clearly against the arena while the player is choosing a cell.
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


## Draws four thin flat bars forming a rectangular outline around the trap's
## full 1.9-cell footprint.  Positioned at local y=0.005 so the depth buffer
## hides the outline wherever the trap body overlaps it, while the border
## strips that extend beyond the body remain clearly visible from above.
func _spawn_footprint_outline(color: Color) -> void:
	var fp        := Grid.CELL_SIZE * 1.9
	var thickness := fp * 0.04   # thin enough to read as a border line
	var y         := 0.005       # just above floor, below all trap body elements

	# Each bar gets its own material so albedo_color updates in _update_star_display()
	# affect all four bars independently without material aliasing.
	var bar_h    := 0.008
	var inner_d  := fp - thickness * 2.0

	for sz: float in [-(fp * 0.5 - thickness * 0.5), fp * 0.5 - thickness * 0.5]:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline_mats.append(mat)
		var mi   := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size            = Vector3(fp, bar_h, thickness)
		mi.mesh              = mesh
		mi.position          = Vector3(0.0, y, sz)
		mi.material_override = mat
		add_child(mi)
		_decorator_nodes.append(mi)

	for sx: float in [-(fp * 0.5 - thickness * 0.5), fp * 0.5 - thickness * 0.5]:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline_mats.append(mat)
		var mi   := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size            = Vector3(thickness, bar_h, inner_d)
		mi.mesh              = mesh
		mi.position          = Vector3(sx, y, 0.0)
		mi.material_override = mat
		add_child(mi)
		_decorator_nodes.append(mi)


## Adds a rectangular outline shadow matching the footprint boundary.
## The shadow is transparent at the centre and peaks in opacity right at the
## boundary line, fading outward beyond it — like a soft halo around the outline.
## The shadow quad is wider than the footprint so the halo has room to breathe.
## Sits just above the floor (world y = 0.05); local Y offset is -0.20 because
## the trap root is at y = 0.25.
func _spawn_shadow(color: Color) -> void:
	# Plane is 2.4 cells wide, giving a halo of (2.4 - 1.9) / 2 = 0.25 cells on each
	# side of the boundary outline.  The shader normalises the gradient over that full
	# halo space, so the fade is always visible regardless of outer_spread tuning.
	# To widen or narrow the shadow, change plane_size here.
	var plane_size := Grid.CELL_SIZE * 2.4
	var shadow_mi  := MeshInstance3D.new()
	var plane      := PlaneMesh.new()
	plane.size      = Vector2(plane_size, plane_size)
	shadow_mi.mesh  = plane

	var mat := ShaderMaterial.new()
	mat.shader = SHADOW_OUTLINE_SHADER

	# boundary_half: UV-space half-extent of the footprint outline, measured from the
	# quad centre.  The shader uses this to find where the halo starts; the gap between
	# boundary_half and 0.5 (the quad edge) is the space the gradient fills.
	var boundary_half := (Grid.CELL_SIZE * 1.9 / plane_size) / 2.0
	mat.set_shader_parameter("boundary_half", boundary_half)
	mat.set_shader_parameter("opacity", 0.60)
	# Darken to ~18% brightness so the tinted halo reads as a shadow.
	mat.set_shader_parameter("shadow_color", Vector3(color.r * 0.18, color.g * 0.18, color.b * 0.18))
	shadow_mi.material_override = mat
	# Store so _update_star_display() can brighten and tint the shadow as stars are earned.
	_shadow_mat = mat

	shadow_mi.position.y = 0.05 - 0.25
	add_child(shadow_mi)
	_decorator_nodes.append(shadow_mi)


## Adds a dark, slightly transparent background plate that fills most of the cell.
## The shadow (larger) bleeds out softly beyond this plate's edges, giving a
## colored shadow-halo effect.  Sits above the shadow, below all trap geometry.
## Returns the material so callers that need to animate it (e.g. Bait Station) can hold a ref.
func _spawn_background(color: Color) -> StandardMaterial3D:
	var bg_mi  := MeshInstance3D.new()
	var plane  := PlaneMesh.new()
	plane.size  = Vector2(Grid.CELL_SIZE * 1.85, Grid.CELL_SIZE * 1.85)
	bg_mi.mesh  = plane

	var mat             := StandardMaterial3D.new()
	mat.albedo_color     = Color(color.r * 0.65, color.g * 0.65, color.b * 0.65, 0.92)
	mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mi.material_override = mat

	# Just above the shadow (world y = 0.07) so the shadow peeks out at the edges.
	bg_mi.position.y = 0.07 - 0.25
	add_child(bg_mi)
	_decorator_nodes.append(bg_mi)
	return mat


## Creates the trap's placeholder visual. All four trap types get multi-part
## procedural meshes matched to their real-world appearance.
func _spawn_visual(_color: Color) -> void:
	# Resolve the canonical per-type color once so shadow, background, and
	# footprint outline all stay in sync.
	var c: Color
	match _trap_type:
		TrapType.SNAP_TRAP:          c = Color(0.90, 0.70, 0.38)
		TrapType.ZAPPER:             c = Color(0.28, 0.62, 0.96)
		TrapType.FOGGER:             c = Color(0.46, 0.96, 0.38)
		TrapType.GLUE_BOARD:         c = Color(0.96, 0.82, 0.34)
		TrapType.FLY_STRIP_LAUNCHER: c = Color(0.92, 0.30, 0.78)
		TrapType.BAIT_STATION:       c = Color(0.52, 0.30, 0.65)
		_:                           c = Color(0.80, 0.80, 0.80)
	_base_color = c
	# Bait Station is a floor trap: it must be invisible at rest and never draw a
	# coloured background plate or shadow halo that would reveal its position.
	# It gets a dedicated radial glow plane instead, spawned by _spawn_bait_glow_plane().
	if _trap_type == TrapType.BAIT_STATION:
		_spawn_bait_glow_plane()
		_spawn_bait_station_visual()
		return
	_spawn_shadow(c)
	var bg_mat := _spawn_background(c)
	if _trap_type == TrapType.SNAP_TRAP:
		_spawn_footprint_outline(c)
		_spawn_snap_trap_visual()
		return
	if _trap_type == TrapType.ZAPPER:
		_spawn_footprint_outline(c)
		_spawn_zapper_visual()
		return
	if _trap_type == TrapType.FOGGER:
		_spawn_footprint_outline(c)
		_spawn_fogger_visual()
		return
	if _trap_type == TrapType.GLUE_BOARD:
		_spawn_footprint_outline(c)
		_spawn_glue_board_visual()
		return
	if _trap_type == TrapType.FLY_STRIP_LAUNCHER:
		_spawn_footprint_outline(c)
		_spawn_fly_strip_launcher_visual()
		return
	_spawn_footprint_outline(c)
	_spawn_placeholder_visual(c)


## Builds the Glue Board visual: a flat rectangular glue board as seen from above.
## The camera is pure top-down, so all detail lives on the XZ plane.
##
## Layout from above (X axis, left to right):
##   [red end tab] → cardboard gap → amber adhesive surface → cardboard gap → [red end tab]
##   A centre crease line marks the fold used when placing real glue boards.
func _spawn_glue_board_visual() -> void:
	var fp  := Grid.CELL_SIZE * 1.9
	var bw  := fp * 0.70   # board width (X) — smaller footprint than the 2×2 cell
	var bd  := fp * 0.44   # board depth (Z)
	var y0  := fp * 0.008   # cardboard base
	var y1  := fp * 0.018   # red end-cap layer
	var y2  := fp * 0.024   # adhesive layer
	var y3  := fp * 0.032   # crease line

	# Cardboard base — warm tan, landscape orientation.
	var base_mi   := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size           = Vector3(bw, fp * 0.016, bd)
	base_mi.mesh             = base_mesh
	base_mi.position.y       = y0
	var base_mat             := StandardMaterial3D.new()
	base_mat.albedo_color     = Color(0.82, 0.66, 0.36)
	base_mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	base_mi.material_override = base_mat
	add_child(base_mi)

	# Red packaging end tabs — sit on the short ends of the cardboard and span
	# its full depth. Real commercial glue boards have distinct colored end pieces
	# (typically red) showing brand and instruction markings.
	var tab_w   := fp * 0.096
	var tab_mat := StandardMaterial3D.new()
	tab_mat.albedo_color = Color(0.92, 0.13, 0.08)
	tab_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for sx: float in [-(bw * 0.5 - tab_w * 0.5), bw * 0.5 - tab_w * 0.5]:
		var tab_mi   := MeshInstance3D.new()
		var tab_mesh := BoxMesh.new()
		tab_mesh.size           = Vector3(tab_w, fp * 0.010, bd)
		tab_mi.mesh             = tab_mesh
		tab_mi.position         = Vector3(sx, y1, 0.0)
		tab_mi.material_override = tab_mat
		add_child(tab_mi)

	# Adhesive surface — amber yellow, inset from the end tabs.
	# Slight transparency suggests the glossy sticky surface.
	var glue_w := bw - tab_w * 2.0 - fp * 0.012
	var glue_mi   := MeshInstance3D.new()
	var glue_mesh := BoxMesh.new()
	glue_mesh.size           = Vector3(glue_w, fp * 0.012, bd * 0.76)
	glue_mi.mesh             = glue_mesh
	glue_mi.position.y       = y2
	var glue_mat             := StandardMaterial3D.new()
	glue_mat.albedo_color     = Color(1.00, 0.82, 0.10, 0.92)
	glue_mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	glue_mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	glue_mi.material_override = glue_mat
	add_child(glue_mi)

	# Centre crease — thin dark line running the full glue width, marking the fold
	# typical of physical glue boards (folded tent-style for placement).
	var crease_mi   := MeshInstance3D.new()
	var crease_mesh := BoxMesh.new()
	crease_mesh.size           = Vector3(glue_w, fp * 0.008, fp * 0.018)
	crease_mi.mesh             = crease_mesh
	crease_mi.position.y       = y3
	var crease_mat             := StandardMaterial3D.new()
	crease_mat.albedo_color     = Color(0.48, 0.34, 0.10)
	crease_mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	crease_mi.material_override = crease_mat
	add_child(crease_mi)


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
	base_mat.albedo_color = Color(0.62, 0.40, 0.16)
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
	cheese_mat.albedo_color = Color(1.00, 0.90, 0.08)
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
	body_mat.albedo_color = Color(0.12, 0.76, 0.28)
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
	band_mat.albedo_color = Color(1.00, 0.95, 0.05)
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
	shoulder_mat.albedo_color = Color(0.10, 0.60, 0.22)
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
	tip_mat.albedo_color = Color(1.00, 0.38, 0.06)
	tip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tip_mi.material_override = tip_mat
	_fogger_nozzle.add_child(tip_mi)


## Builds the Zapper visual: a flat top-down silhouette of a bug zapper.
## The camera is a pure top-down orthographic view, so all detail must live
## on the XZ plane — upright geometry only shows its circular cross-section.
##
## Layout from above (X = right, Z = down):
##   +----|----|-[tube]-|----|-+    <- cage bars (gray) inside outer frame (dark)
##
## Parts: a dark charcoal outer rectangular frame, four evenly-spaced
## gray cage bars running front-to-back (Z), and a wide neon-blue UV tube
## strip running left-to-right (X) at the centre.
func _spawn_zapper_visual() -> void:
	var fp := Grid.CELL_SIZE * 1.9

	# Outer cage rectangle dimensions.
	var cw  := fp * 0.72   # total width  (X)
	var cd  := fp * 0.50   # total depth  (Z)
	var ft  := fp * 0.055  # outer frame bar thickness
	var y0  := fp * 0.012  # base Y — just above ground to avoid z-fighting
	var yhi := fp * 0.020  # Y for elements that sit on top of the frame

	var housing_mat := StandardMaterial3D.new()
	housing_mat.albedo_color = Color(0.14, 0.14, 0.20)
	housing_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var cage_mat := StandardMaterial3D.new()
	cage_mat.albedo_color = Color(0.52, 0.58, 0.68)
	cage_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Outer frame — four flat bars forming the rectangular border.
	var frame_h := fp * 0.022   # visual height of all flat boxes (invisible top-down, just avoids z-fight)

	# Top bar (−Z edge)
	var top_bar_mi   := MeshInstance3D.new()
	var top_bar_mesh := BoxMesh.new()
	top_bar_mesh.size           = Vector3(cw, frame_h, ft)
	top_bar_mi.mesh             = top_bar_mesh
	top_bar_mi.position         = Vector3(0.0, y0, -cd * 0.5 + ft * 0.5)
	top_bar_mi.material_override = housing_mat
	add_child(top_bar_mi)

	# Bottom bar (+Z edge)
	var bot_bar_mi   := MeshInstance3D.new()
	var bot_bar_mesh := BoxMesh.new()
	bot_bar_mesh.size           = Vector3(cw, frame_h, ft)
	bot_bar_mi.mesh             = bot_bar_mesh
	bot_bar_mi.position         = Vector3(0.0, y0, cd * 0.5 - ft * 0.5)
	bot_bar_mi.material_override = housing_mat
	add_child(bot_bar_mi)

	# Left bar (−X edge)
	var lft_bar_mi   := MeshInstance3D.new()
	var lft_bar_mesh := BoxMesh.new()
	lft_bar_mesh.size           = Vector3(ft, frame_h, cd)
	lft_bar_mi.mesh             = lft_bar_mesh
	lft_bar_mi.position         = Vector3(-cw * 0.5 + ft * 0.5, y0, 0.0)
	lft_bar_mi.material_override = housing_mat
	add_child(lft_bar_mi)

	# Right bar (+X edge)
	var rgt_bar_mi   := MeshInstance3D.new()
	var rgt_bar_mesh := BoxMesh.new()
	rgt_bar_mesh.size           = Vector3(ft, frame_h, cd)
	rgt_bar_mi.mesh             = rgt_bar_mesh
	rgt_bar_mi.position         = Vector3(cw * 0.5 - ft * 0.5, y0, 0.0)
	rgt_bar_mi.material_override = housing_mat
	add_child(rgt_bar_mi)

	# Interior cage bars — 4 thin strips running front-to-back (Z), evenly spaced.
	# Placed above the frame layer so they render on top.
	var inner_w  := cw - ft * 2
	var bar_w    := fp * 0.030
	var inner_cd := cd - ft * 2   # bar runs only inside the frame
	for i in range(4):
		var t    := float(i + 1) / 5.0   # positions at 0.20, 0.40, 0.60, 0.80
		var bx   := -inner_w * 0.5 + inner_w * t
		var cb_mi   := MeshInstance3D.new()
		var cb_mesh := BoxMesh.new()
		cb_mesh.size           = Vector3(bar_w, frame_h, inner_cd)
		cb_mi.mesh             = cb_mesh
		cb_mi.position         = Vector3(bx, yhi, 0.0)
		cb_mi.material_override = cage_mat
		add_child(cb_mi)

	# UV light assembly — container node scaled on discharge animation.
	# Positioned at the vertical centre of the cage.
	_zapper_uv_light          = Node3D.new()
	_zapper_uv_light.position = Vector3(0.0, yhi + fp * 0.010, 0.0)
	add_child(_zapper_uv_light)

	# Silver ring surrounding the central light assembly.  Sits inside the cage bars
	# and pulses outward with the UV light node during the discharge animation.
	var ring_mi   := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius    = fp * 0.12
	ring_mesh.outer_radius    = fp * 0.17
	ring_mi.mesh              = ring_mesh
	var ring_mat              := StandardMaterial3D.new()
	ring_mat.albedo_color      = Color(0.78, 0.78, 0.84)
	ring_mat.shading_mode      = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mi.material_override  = ring_mat
	_zapper_uv_light.add_child(ring_mi)

	# Soft circular glow — semi-transparent disc that replaces the rectangular
	# glow halo; the round shape reads better inside the ring.
	var glow_mi   := MeshInstance3D.new()
	var glow_mesh := CylinderMesh.new()
	glow_mesh.top_radius      = fp * 0.11
	glow_mesh.bottom_radius   = fp * 0.11
	glow_mesh.height          = fp * 0.004   # nearly flat; just enough to clear z-fighting
	glow_mesh.radial_segments = 16
	glow_mi.mesh              = glow_mesh
	var glow_mat              := StandardMaterial3D.new()
	glow_mat.albedo_color      = Color(0.00, 0.50, 1.00, 0.70)   # saturated neon blue
	glow_mat.shading_mode      = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.transparency      = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mi.material_override  = glow_mat
	_zapper_uv_light.add_child(glow_mi)

	# Lightning bolt — large flat polygon on the XZ plane, always rendered on top
	# of all other trap geometry via no_depth_test so it reads clearly from above.
	var bolt_mi              := MeshInstance3D.new()
	bolt_mi.mesh              = _build_bolt_mesh(fp * 0.42, Color(0.00, 0.50, 1.00))
	var bolt_mat             := StandardMaterial3D.new()
	bolt_mat.albedo_color     = Color.WHITE
	bolt_mat.vertex_color_use_as_albedo = true
	bolt_mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	bolt_mat.cull_mode        = BaseMaterial3D.CULL_DISABLED
	bolt_mat.no_depth_test    = true   # always draw on top of cage, ring, and floor
	bolt_mi.material_override  = bolt_mat
	_zapper_uv_light.add_child(bolt_mi)


## Builds a flat lightning bolt polygon on the XZ plane using ImmediateMesh.
## s is a scale factor — vertex coordinates range ±0.5*s in X and Z.
## The polygon has 6 vertices with the top-half shifted right and the bottom-half
## shifted left, creating a clear zigzag at the waist.
## The fan triangulation from v0 is valid because the interior diagonals all
## lie inside this particular concave hexagon.
func _build_bolt_mesh(s: float, color: Color) -> ImmediateMesh:
	var im  := ImmediateMesh.new()
	var pts := [
		Vector3(-0.10 * s, 0.0, -0.50 * s),  # v0 upper-left
		Vector3( 0.50 * s, 0.0, -0.50 * s),  # v1 upper-right (wide top)
		Vector3( 0.15 * s, 0.0,  0.00),       # v2 mid-right kink
		Vector3( 0.10 * s, 0.0,  0.50 * s),  # v3 lower-right
		Vector3(-0.50 * s, 0.0,  0.50 * s),  # v4 lower-left (wide bottom)
		Vector3(-0.15 * s, 0.0,  0.00),       # v5 mid-left kink
	]
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# Fan triangulation from v0.
	for tri in [[0,1,2], [0,2,3], [0,3,4], [0,4,5]]:
		for vi: int in tri:
			im.surface_set_color(color)
			im.surface_add_vertex(pts[vi])
	im.surface_end()
	return im


## Plays the fire animation: the UV light node scales outward sharply then
## eases back, simulating the electric discharge flash visible from above.
func _play_zapper_animation() -> void:
	if _zapper_uv_light == null or _zapper_animating:
		return
	_zapper_animating = true
	AudioManager.play_trap_fire(TrapType.ZAPPER)

	var burst := create_tween()
	burst.tween_property(_zapper_uv_light, "scale",
		Vector3(2.0, 1.0, 3.5), 0.06).set_ease(Tween.EASE_OUT)
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
	AudioManager.play_trap_fire(TrapType.FOGGER)

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
	AudioManager.play_trap_fire(TrapType.SNAP_TRAP)

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


## Simple flat box placeholder for trap types that don't have a dedicated visual yet.
func _spawn_placeholder_visual(color: Color) -> void:
	var fp      := Grid.CELL_SIZE * 1.9
	var box_mi  := MeshInstance3D.new()
	var box     := BoxMesh.new()
	box.size     = Vector3(fp * 0.60, fp * 0.20, fp * 0.60)
	box_mi.mesh  = box
	box_mi.position.y = fp * 0.10
	var mat             := StandardMaterial3D.new()
	mat.albedo_color     = color
	mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	box_mi.material_override = mat
	add_child(box_mi)


## Builds the Fly Strip Launcher visual: a compact mortar-style launcher seen from above.
##
## Layout from above (X = right, Z = down):
##   Flat circular base plate → cylindrical body → offset barrel tube + tape roll
##
## The whole assembly is parented to _fly_strip_root so the idle bob can move it as a unit.
## _fly_strip_barrel_pivot is offset so the recoil kicks the barrel inward on fire.
func _spawn_fly_strip_launcher_visual() -> void:
	var fp := Grid.CELL_SIZE * 1.9

	_fly_strip_root = Node3D.new()
	add_child(_fly_strip_root)

	# Base disc — dark magenta platform that the launcher sits on.
	var base_mi   := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.radial_segments = 20
	base_mesh.top_radius      = fp * 0.42
	base_mesh.bottom_radius   = fp * 0.42
	base_mesh.height          = fp * 0.028
	base_mi.mesh       = base_mesh
	base_mi.position.y = fp * 0.014   # half height above ground
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.80, 0.18, 0.65)
	base_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	base_mi.material_override = base_mat
	_fly_strip_root.add_child(base_mi)

	# Body cylinder — the main launcher housing, bright magenta.
	var body_mi   := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.radial_segments = 16
	body_mesh.top_radius      = fp * 0.22
	body_mesh.bottom_radius   = fp * 0.22
	body_mesh.height          = fp * 0.22
	body_mi.mesh       = body_mesh
	body_mi.position.y = fp * 0.028 + fp * 0.11   # sits on top of base disc
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.92, 0.30, 0.78)
	body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	body_mi.material_override = body_mat
	_fly_strip_root.add_child(body_mi)

	# Tape roll — a torus at the edge of the body representing coiled fly strip ammunition.
	# Pale gold-tan so it reads clearly against the magenta body from above.
	var roll_mi   := MeshInstance3D.new()
	var roll_mesh := TorusMesh.new()
	roll_mesh.inner_radius = fp * 0.04
	roll_mesh.outer_radius = fp * 0.12
	roll_mesh.rings        = 12
	roll_mesh.ring_segments = 8
	roll_mi.mesh       = roll_mesh
	roll_mi.position.x = fp * 0.28   # offset toward barrel side
	roll_mi.position.y = fp * 0.028 + fp * 0.22   # sits on top of body
	var roll_mat := StandardMaterial3D.new()
	roll_mat.albedo_color = Color(0.98, 0.85, 0.55)
	roll_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	roll_mi.material_override = roll_mat
	_fly_strip_root.add_child(roll_mi)

	# Barrel pivot — offset from centre so the barrel appears to jut out from the body.
	# On fire, this node is nudged down then back to simulate a recoil kick.
	_fly_strip_barrel_pivot = Node3D.new()
	_fly_strip_barrel_pivot.position.x = fp * 0.10
	_fly_strip_barrel_base_y = fp * 0.028 + fp * 0.22 + fp * 0.075
	_fly_strip_barrel_pivot.position.y = _fly_strip_barrel_base_y
	_fly_strip_root.add_child(_fly_strip_barrel_pivot)

	# Barrel tube — slightly tapered cylinder, darker magenta.
	var barrel_mi   := MeshInstance3D.new()
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.radial_segments = 10
	barrel_mesh.top_radius      = fp * 0.07
	barrel_mesh.bottom_radius   = fp * 0.09
	barrel_mesh.height          = fp * 0.15
	barrel_mi.mesh = barrel_mesh
	var barrel_mat := StandardMaterial3D.new()
	barrel_mat.albedo_color = Color(0.65, 0.18, 0.55)
	barrel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	barrel_mi.material_override = barrel_mat
	_fly_strip_barrel_pivot.add_child(barrel_mi)


## Creates the radial glow plane for the Bait Station.
##
## Two modes:
##   Placement preview — trap footprint size (fp), BAIT_GLOW_REST_OPACITY so the preview
##     matches the placed trap's at-rest appearance rather than a firing pulse.
##   Placed trap — range-based size (75% of range diameter), starts at BAIT_GLOW_REST_SCALE
##     and BAIT_GLOW_REST_OPACITY; _play_bait_animation() expands it to full on each pulse.
##
## hide_decorators() suppresses the plane entirely for HUD icon renders.
func _spawn_bait_glow_plane() -> void:
	var fp := Grid.CELL_SIZE * 1.9
	# Preview: match the trap footprint so the glow stays within the grate boundary.
	# Placed:  extend to 75% of the range diameter so the pulse radiates visibly outward.
	var glow_side := fp * 2.0 if _is_preview else _range * Grid.CELL_SIZE * 1.05
	var plane     := PlaneMesh.new()
	plane.size = Vector2(glow_side, glow_side)

	var mi  := MeshInstance3D.new()
	mi.mesh = plane
	# World y = 0.11 — above the grate bars (0.09) and below enemy sprites (0.25).
	# Expressed as a local offset: desired_world_y − trap_root_y = 0.11 − 0.25.
	mi.position.y = 0.11 - 0.25

	var mat := ShaderMaterial.new()
	mat.shader = BAIT_GLOW_SHADER
	mat.set_shader_parameter("opacity",    BAIT_GLOW_REST_OPACITY)
	mat.set_shader_parameter("glow_color", Vector3(0.90, 0.06, 0.06))
	mi.material_override = mat

	# Preview keeps scale 1.0 (footprint-sized).  Placed traps start at rest scale;
	# _play_bait_animation() grows them to 1.0 on each pulse then shrinks back.
	if not _is_preview:
		mi.scale = Vector3(BAIT_GLOW_REST_SCALE, 1.0, BAIT_GLOW_REST_SCALE)

	_bait_glow_mat = mat
	_bait_glow_mi  = mi
	add_child(mi)
	_decorator_nodes.append(mi)   # hide_decorators() will suppress it for icon previews


## Builds the Bait Station visual: a low-profile black metal grate sitting flush at ground level.
##
## Layout from above: a rectangular outer frame with two families of diagonal bars at ±45°
## intersecting to create a diamond grid pattern.  Each interior bar is clipped to the
## inner frame area so no bar end protrudes past the border.
##
## Positioned at world y = 0.09 — above the background plate (0.07) but well below enemy
## sprites (0.25), so the opaque grate bars never depth-occlude an enemy overhead.
##
## No footprint outline or shadow is spawned — the trap blends into the floor.
## The glow plane sits at a persistent dim red; _play_bait_animation() strobes it on each pulse.
func _spawn_bait_station_visual() -> void:
	var fp := Grid.CELL_SIZE * 1.9
	# World y = 0.09; local offset = desired_world_y − trap_root_y = 0.09 − 0.25.
	var y      := 0.09 - 0.25
	var bar_h  := fp * 0.030   # grate depth — slightly taller than before for wrought-iron mass
	var bar_t  := fp * 0.065   # bar cross-section — substantially thicker for a heavy iron look

	# Square frame at 90% of the standard trap footprint.
	var frame_s := fp * 0.8
	var frame_w := frame_s
	var frame_d := frame_s

	# Wrought iron colours: dark charcoal with a slight warm (brownish) undertone,
	# not pure black.  Frame is slightly darker than the interior bars to read as a border.
	var grate_mat := StandardMaterial3D.new()
	grate_mat.albedo_color = Color(0.20, 0.18, 0.15)
	grate_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var bar_mat := StandardMaterial3D.new()
	bar_mat.albedo_color = Color(0.30, 0.27, 0.23)
	bar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Outer frame: four axis-aligned border bars.
	# Raised one bar_h above the interior diagonal bars so the frame visually masks any
	# diagonal bar end that reaches the frame boundary, keeping the border clean.
	var frame_y := y + bar_h
	for sign_z: float in [-1.0, 1.0]:
		var mi   := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size     = Vector3(frame_w, bar_h, bar_t)
		mi.mesh       = mesh
		mi.position.y = frame_y
		mi.position.z = sign_z * (frame_d * 0.5 - bar_t * 0.5)
		mi.material_override = grate_mat
		add_child(mi)
	for sign_x: float in [-1.0, 1.0]:
		var mi   := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size     = Vector3(bar_t, bar_h, frame_d - bar_t * 2.0)
		mi.mesh       = mesh
		mi.position.y = frame_y
		mi.position.x = sign_x * (frame_w * 0.5 - bar_t * 0.5)
		mi.material_override = grate_mat
		add_child(mi)

	# Interior diamond bars: two families of parallel bars at +45° and −45°.
	# Bars in each family are evenly spaced along their perpendicular direction.
	# The clipping logic trims each bar to fit exactly inside the inner frame area —
	# bars that don't intersect the inner rectangle at all are skipped entirely.
	var inner_w := frame_w - bar_t * 2.0
	var inner_d := frame_d - bar_t * 2.0
	var hw      := inner_w * 0.5   # half-width of the clip rectangle
	var hd      := inner_d * 0.5   # half-depth of the clip rectangle
	# Spacing scaled with the larger frame: still 5 visible bars per family (k = −2 … +2),
	# giving ~8 visible diamond cells inside the full-footprint frame.
	var spacing := fp * 0.22

	var bar_count := int(ceil((hw + hd) / spacing))

	for angle: float in [PI / 4.0, -PI / 4.0]:
		# In Godot, rotation.y = angle maps local +Z to world direction (sin(angle), 0, cos(angle)).
		# That is the bar's running direction.  The perpendicular (CCW 90° in XZ) is (−cos, 0, sin).
		var dx := sin(angle)     # running direction X
		var dz := cos(angle)     # running direction Z
		var px := -cos(angle)    # perpendicular direction X (used to offset parallel bars)
		var pz :=  sin(angle)    # perpendicular direction Z

		for k in range(-bar_count, bar_count + 1):
			var cx := k * spacing * px   # bar centre X before clipping
			var cz := k * spacing * pz   # bar centre Z before clipping

			# Parametric clip: find t range where (cx + t·dx, cz + t·dz) ∈ [−hw, hw] × [−hd, hd].
			var t_min := -1e9
			var t_max :=  1e9
			if abs(dx) > 1e-6:
				var t0 := (-hw - cx) / dx
				var t1 := ( hw - cx) / dx
				t_min = maxf(t_min, minf(t0, t1))
				t_max = minf(t_max, maxf(t0, t1))
			if abs(dz) > 1e-6:
				var t0 := (-hd - cz) / dz
				var t1 := ( hd - cz) / dz
				t_min = maxf(t_min, minf(t0, t1))
				t_max = minf(t_max, maxf(t0, t1))
			if t_min >= t_max:
				continue   # this bar does not intersect the inner frame rectangle

			var t_mid   := (t_min + t_max) * 0.5
			var bar_len := t_max - t_min
			var mi   := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size       = Vector3(bar_t, bar_h, bar_len)
			mi.mesh         = mesh
			mi.position.x   = cx + t_mid * dx
			mi.position.y   = y
			mi.position.z   = cz + t_mid * dz
			mi.rotation.y   = angle
			mi.material_override = bar_mat
			add_child(mi)


## Plays the launch animation: squishes the root outward on XZ and kicks the barrel
## down, then springs both back to rest. Guards against overlap.
func _play_fly_strip_animation() -> void:
	if _fly_strip_root == null or _fly_strip_animating:
		return
	_fly_strip_animating = true
	AudioManager.play_trap_fire(TrapType.FLY_STRIP_LAUNCHER)

	var fp       := Grid.CELL_SIZE * 1.9
	var kick_y   := _fly_strip_barrel_base_y - fp * 0.06   # push barrel down on fire

	var squish := create_tween()
	squish.tween_property(_fly_strip_root, "scale",
		Vector3(1.25, 0.65, 1.25), 0.07).set_ease(Tween.EASE_OUT)
	if _fly_strip_barrel_pivot != null:
		var kick := create_tween()
		kick.tween_property(_fly_strip_barrel_pivot, "position:y",
			kick_y, 0.06).set_ease(Tween.EASE_OUT)

	await squish.finished
	if not is_inside_tree():
		_fly_strip_animating = false
		return

	var spring := create_tween()
	spring.tween_property(_fly_strip_root, "scale",
		Vector3(1.0, 1.0, 1.0), 0.25).set_ease(Tween.EASE_OUT)
	if _fly_strip_barrel_pivot != null:
		var reset := create_tween()
		reset.tween_property(_fly_strip_barrel_pivot, "position:y",
			_fly_strip_barrel_base_y, 0.20).set_ease(Tween.EASE_OUT)

	await spring.finished
	_fly_strip_animating = false


## Returns the resting glow opacity for the current star count.
## Used both when updating stars and when fading back after a pulse.
func _bait_current_rest_opacity() -> float:
	return BAIT_GLOW_OPACITY_BY_STARS[mini(get_maxed_stat_count(), BAIT_GLOW_OPACITY_BY_STARS.size() - 1)]


## Plays the Bait Station fire animation: the radial glow plane snaps to full opacity
## then fades back to invisible, simulating a toxic pulse seen through the grate.
## The grate itself does not move.  Opacity is a shader parameter so the radial gradient
## stays intact throughout — only its overall intensity changes.
func _play_bait_animation() -> void:
	if _bait_glow_mat == null or _bait_glow_mi == null or _bait_animating:
		return
	_bait_animating = true

	# Expand from resting scale to full range coverage and brighten simultaneously.
	# set_parallel(true) lets both tweens run at the same time on the same Tween object.
	var expand := create_tween().set_parallel(true)
	expand.tween_property(_bait_glow_mat, "shader_parameter/opacity",
		1.0, 0.12).set_ease(Tween.EASE_OUT)
	expand.tween_property(_bait_glow_mi, "scale",
		Vector3.ONE, 0.12).set_ease(Tween.EASE_OUT)
	await expand.finished

	if not is_inside_tree():
		_bait_animating = false
		return

	await get_tree().create_timer(0.05).timeout
	if not is_inside_tree():
		_bait_animating = false
		return

	# Shrink and fade back to the current star-level resting glow (not fully invisible).
	var fade := create_tween().set_parallel(true)
	fade.tween_property(_bait_glow_mat, "shader_parameter/opacity",
		_bait_current_rest_opacity(), 0.55).set_ease(Tween.EASE_IN)
	fade.tween_property(_bait_glow_mi, "scale",
		Vector3(BAIT_GLOW_REST_SCALE, 1.0, BAIT_GLOW_REST_SCALE), 0.55).set_ease(Tween.EASE_IN)
	await fade.finished

	_bait_animating = false
