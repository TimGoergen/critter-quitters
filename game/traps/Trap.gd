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

# SVG sprite frames — idle (index 0) and fire (index 1) for each trap type.
const SNAP_TRAP_FRAMES:    Array[Texture2D] = [preload("res://assets/snap_trap_idle.svg"),   preload("res://assets/snap_trap_fire.svg")]
const ZAPPER_FRAMES:       Array[Texture2D] = [preload("res://assets/zapper_idle.svg"),      preload("res://assets/zapper_fire.svg")]
const FOGGER_FRAMES:       Array[Texture2D] = [preload("res://assets/fogger_idle.svg"),      preload("res://assets/fogger_fire.svg")]
const GLUE_BOARD_FRAMES:   Array[Texture2D] = [preload("res://assets/glue_board_idle.svg"),  preload("res://assets/glue_board_fire.svg")]
const FLY_STRIP_FRAMES:    Array[Texture2D] = [preload("res://assets/fly_strip_idle.svg"),   preload("res://assets/fly_strip_fire.svg")]
const BAIT_STATION_FRAMES: Array[Texture2D] = [preload("res://assets/bait_station_idle.svg"), preload("res://assets/bait_station_fire.svg")]


# ---------------------------------------------------------------------------
# Trap type
# ---------------------------------------------------------------------------

enum TrapType { SNAP_TRAP, ZAPPER, FOGGER, GLUE_BOARD, FLY_STRIP_LAUNCHER, BAIT_STATION }

## Trap types that can target flying enemies.
## Snap Trap launches with enough vertical force to catch low-flying pests.
## Fly Strip Launcher is the dedicated anti-air option.
## Everything else is ground-only.
const ANTI_AIR_TYPES: Array[TrapType] = [TrapType.SNAP_TRAP, TrapType.FLY_STRIP_LAUNCHER]

## Trap types that deal direct HP damage to ground-based enemies.
## Glue Board is excluded — it applies a movement slow but deals no damage.
## Fly Strip Launcher is excluded — it targets flying enemies only.
const GROUND_DAMAGE_TYPES: Array[TrapType] = [
	TrapType.SNAP_TRAP, TrapType.ZAPPER, TrapType.FOGGER, TrapType.BAIT_STATION,
]

## Per-type stat table. All numeric values are placeholders — tuned via playtesting.
##   damage           — HP removed from each target per shot
##   range            — circular detection radius in world units (1 unit = 1 cell)
##   cooldown         — seconds between shots; 0.0 = passive (no shots fired)
##   cost             — Bug Bucks to place one trap of this type
##   color            — placeholder box colour (replaced by sprites in Phase 8)
##   cloud_duration   — FLY_STRIP_LAUNCHER only: seconds the sticky cloud persists
##   adhesion         — FLY_STRIP_LAUNCHER only: slow factor applied to flying enemies (0.0—1.0)
##   pulse_interval   — BAIT_STATION only: seconds between damage pulses
##   poison_*         — BAIT_STATION only: poison DoT applied after each pulse
const STATS := {
	TrapType.SNAP_TRAP:  { "damage": 5.0,  "range": 5.6, "cooldown": 1.0, "cost": 25, "color": Color(0.78, 0.52, 0.22) },
	TrapType.ZAPPER:     { "damage": 30.0, "range": 9.6, "cooldown": 2.5, "cost": 75, "color": Color(0.10, 0.50, 1.00) },
	TrapType.FOGGER:     { "damage": 3.0,  "range": 4.0, "cooldown": 2.2, "cost": 60, "color": Color(0.35, 0.88, 0.18) },
	TrapType.GLUE_BOARD: { "damage": 0.20, "range": 4.8, "cooldown": 0.0, "cost": 45, "color": Color(1.00, 0.40, 0.00), "pulse_interval": 3.0 },
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

## Free upgrades (awarded by type-wide level-up cards) use a separate pool
## so each can be upgraded up to FREE_MAX_LEVEL times independently of Bug Bucks
## upgrades. A fully paid + fully free trap has noticeably higher stats than
## one upgraded through only one pool.
const FREE_MAX_LEVEL: int = 3

## Stat increment per upgrade level, as a fraction of the base value.
const UPGRADE_DAMAGE_FACTOR:    float = 0.20  # +20% of base damage per level
const UPGRADE_RANGE_FACTOR:     float = 0.10  # +10% of base range per level
const UPGRADE_FIRE_RATE_FACTOR: float = 0.08  # âˆ’8% of base cooldown per level (faster shots)

## Critical hit constants. Crit chance defaults to 0.0 (no crits) so the stats
## are present on every trap but dormant until the player upgrades them.
## On a successful crit roll the trap deals damage Ã— (1 + crit_damage_bonus).
const CRIT_CHANCE_BASE:           float = 0.00  # 0% — dormant by default
const CRIT_DAMAGE_BONUS_BASE:     float = 0.25  # 25% extra on a crit
const UPGRADE_CRIT_CHANCE_PER_LEVEL: float = 0.02   # +2% per level
const UPGRADE_CRIT_DAMAGE_PER_LEVEL: float = 0.25   # +25% per level

## Glue Board adhesion strength at each damage upgrade level (index = _damage_level).
## Values are slow factors: 0.0 = no slow, 1.0 = fully stopped.
## Defined as an explicit table because the intended values don't fit the shared
## UPGRADE_DAMAGE_FACTOR formula.
## Values start at 0.45 (45% speed reduction) so the slow is immediately noticeable.
const GLUE_ADHESION_LEVELS: Array[float] = [0.45, 0.55, 0.65, 0.75]

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
## On each pulse it expands to BAIT_GLOW_FIRE_SCALE and full opacity, then returns here.
##
## Scale math: glow plane mesh = _range * 2.0 = 7.0 units. Trap footprint ≈ 1.9 units.
##   Rest  → match footprint:      1.9 / 7.0 ≈ 0.27
##   Fire  → 150% of footprint:  2.85 / 7.0 ≈ 0.41
const BAIT_GLOW_REST_OPACITY: float = 0.25   # dim persistent glow at zero stars
const BAIT_GLOW_REST_SCALE:   float = 0.27   # matches trap footprint at rest
const BAIT_GLOW_FIRE_SCALE:   float = 0.41   # ~50% larger than footprint on pulse

## Resting glow opacity indexed by number of maxed stats (0—3).
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

# Upgrade state — each stat tracks its own level independently (0—MAX_UPGRADE_LEVEL).
var _damage_level: int = 0
var _range_level:  int = 0
var _rate_level:   int = 0   # always stays 0 for passive traps

# Critical hit upgrade state.
var _crit_chance:       float = 0.0
var _crit_damage_bonus: float = 0.25
var _crit_chance_level: int   = 0
var _crit_damage_level: int   = 0

# Free-upgrade counters — track level-up rewards separately from paid upgrades.
# Each pool caps at FREE_MAX_LEVEL (3) so the two pools are fully independent.
var _free_damage_level:      int = 0
var _free_range_level:       int = 0
var _free_rate_level:        int = 0
var _free_duration_level:    int = 0
var _free_crit_chance_level: int = 0
var _free_crit_dmg_level:    int = 0

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

# Glue Board pulse timing — how often it fires and the current countdown.
var _glue_pulse_interval: float = 0.0
var _glue_pulse_timer:    float = 0.0

# When true, this node is a visual-only placement preview: no combat, no hover area,
# no range indicator. Set by initialize_preview() before the node enters the tree.
var _is_preview: bool = false

# Range indicator shown on mouse hover.
var _is_hovered:      bool              = false
var _range_indicator: Node3D           = null
var _range_fill_mat:  StandardMaterial3D = null   # stored so color can be updated without rebuild
var _range_ring_mat:  StandardMaterial3D = null
var _range_ring_mi:   MeshInstance3D     = null   # stored so the mesh can be swapped for peek mode
var _hover_area:      Area3D = null
# When true, the indicator stays visible regardless of hover state (upgrade panel open).
var _indicator_pinned: bool  = false

# Progress bar display — background strip always visible, gold fill grows left-to-right
# as each stat category is maxed. Replaces the old floating star meshes.
var _bar_bg_mi:   MeshInstance3D = null   # always-visible dark background strip
var _bar_fill_mi: MeshInstance3D = null   # gold fill, scales left-to-right

# Boost indicator — small diamond shown in the trap's top-right corner whenever at
# least one boost aura is currently active on this trap.
var _boost_indicator: Label3D = null

# Upgrade tint — materials updated in _update_star_display() to lerp toward gold.
var _base_color:   Color                       = Color.WHITE
var _outline_mats: Array[StandardMaterial3D]   = []
var _shadow_mat:   ShaderMaterial              = null

# Arena-decorator nodes: the colored background plate, shadow halo, and footprint
# outline bars.  Populated by _spawn_background / _spawn_shadow / _spawn_footprint_outline
# so hide_decorators() can remove them for icon-only previews (e.g. HUD panel icons).
var _decorator_nodes: Array[Node3D] = []

# SVG sprite state — shared by all trap types.
var _trap_frames:    Array[Texture2D]    = []     # [idle, fire] set in _spawn_svg_trap_visual
var _visual_material: StandardMaterial3D = null   # albedo_texture swapped on each fire
var _bg_mat:          StandardMaterial3D = null   # colored background plate material; stored for dim/undim

# Per-type fire animation guard flags — prevent overlapping texture swaps.
var _snap_animating:      bool = false
var _fogger_animating:    bool = false
var _zapper_animating:    bool = false
var _fly_strip_animating: bool = false

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
const FOG_BATCH_CAP: int       = 2   # 2 batches Ã— 3—4 puffs each â‰ˆ 6 puffs max
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
var _damage_boost_sources:    Dictionary = {}   # BoostUnit node â†’ damage bonus factor
var _fire_rate_boost_sources: Dictionary = {}   # BoostUnit node â†’ fire-rate bonus factor
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

	_crit_chance      = CRIT_CHANCE_BASE
	_crit_damage_bonus = CRIT_DAMAGE_BONUS_BASE

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
	_spawn_boost_indicator()
	stats_changed.connect(_rebuild_range_indicator)
	stats_changed.connect(_update_star_display)
	if _trap_type == TrapType.GLUE_BOARD:
		_glue_pulse_interval = stats.get("pulse_interval", 3.0)
		_glue_pulse_timer    = 0.0   # fire immediately on the first pulse
		_slow_duration       = GLUE_DURATION_LEVELS[0]
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
	# Register with the global group so TrapUpgradePanel can query all placed
	# traps during peek mode without needing a direct Arena reference.
	add_to_group("placed_traps")


# ---------------------------------------------------------------------------
# Upgrade — cost
# ---------------------------------------------------------------------------

## Bug Bucks cost for the next upgrade to each stat. Returns 0 when already maxed.
## All costs pass through GameState.apply_upgrade_discount() so any active
## "Bulk Procurement" campaign buff is reflected in both the UI and the spend.
func get_damage_upgrade_cost() -> int:
	if _damage_level >= MAX_UPGRADE_LEVEL:
		return 0
	return GameState.apply_upgrade_discount(UPGRADE_COSTS[_trap_type][_damage_level])

func get_range_upgrade_cost() -> int:
	if _range_level >= MAX_UPGRADE_LEVEL:
		return 0
	return GameState.apply_upgrade_discount(UPGRADE_COSTS[_trap_type][_range_level])

func get_rate_upgrade_cost() -> int:
	if _rate_level >= MAX_UPGRADE_LEVEL or _base_cooldown == 0.0:
		return 0
	return GameState.apply_upgrade_discount(UPGRADE_COSTS[_trap_type][_rate_level])

func get_duration_upgrade_cost() -> int:
	if _duration_level >= MAX_UPGRADE_LEVEL:
		return 0
	return GameState.apply_upgrade_discount(UPGRADE_COSTS[_trap_type][_duration_level])

func get_crit_chance_upgrade_cost() -> int:
	if _crit_chance_level >= MAX_UPGRADE_LEVEL:
		return 0
	return GameState.apply_upgrade_discount(UPGRADE_COSTS[_trap_type][_crit_chance_level])

func get_crit_damage_upgrade_cost() -> int:
	if _crit_damage_level >= MAX_UPGRADE_LEVEL:
		return 0
	return GameState.apply_upgrade_discount(UPGRADE_COSTS[_trap_type][_crit_damage_level])


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

## Effective damage including all active boost multipliers.
## Use this in the upgrade panel's current-value column so the player sees the actual
## damage output, not the base value that excludes nearby Pheromone Dispensers.
func get_effective_damage() -> float:
	return _damage * _damage_multiplier

## Effective damage the trap would deal after the next damage upgrade, with boosts applied.
func get_effective_damage_after_upgrade() -> float:
	return get_damage_after_upgrade() * _damage_multiplier

## Effective fire rate including the fire-rate multiplier from Compressor boosts.
func get_effective_shots_per_sec() -> float:
	return (_fire_rate_multiplier / _cooldown) if _cooldown > 0.0 else 0.0

## Effective fire rate after the next fire-rate upgrade, with boosts applied.
func get_effective_shots_per_sec_after_upgrade() -> float:
	return _fire_rate_multiplier / maxf(_cooldown - _base_cooldown * UPGRADE_FIRE_RATE_FACTOR, 0.1)


## Glue Board / Bait Station — duration value after the next duration upgrade.
func get_duration_after_upgrade() -> float:
	if _trap_type == TrapType.BAIT_STATION:
		return BAIT_POISON_DURATION_LEVELS[mini(_duration_level + 1, MAX_UPGRADE_LEVEL)]
	return GLUE_DURATION_LEVELS[mini(_duration_level + 1, MAX_UPGRADE_LEVEL)]

## Crit chance value after the next crit chance upgrade.
func get_crit_chance_after_upgrade() -> float:
	return _crit_chance + UPGRADE_CRIT_CHANCE_PER_LEVEL

## Crit damage bonus after the next crit damage upgrade.
func get_crit_damage_after_upgrade() -> float:
	return _crit_damage_bonus + UPGRADE_CRIT_DAMAGE_PER_LEVEL


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

## Increases crit chance by UPGRADE_CRIT_CHANCE_PER_LEVEL. Only call when not maxed.
func apply_crit_chance_upgrade() -> void:
	_crit_chance += UPGRADE_CRIT_CHANCE_PER_LEVEL
	_crit_chance_level += 1
	_check_full_upgrade_bonus()
	stats_changed.emit()

## Increases crit damage bonus by UPGRADE_CRIT_DAMAGE_PER_LEVEL. Only call when not maxed.
func apply_crit_damage_upgrade() -> void:
	_crit_damage_bonus += UPGRADE_CRIT_DAMAGE_PER_LEVEL
	_crit_damage_level += 1
	_check_full_upgrade_bonus()
	stats_changed.emit()


# ---------------------------------------------------------------------------
# Free upgrades (type-wide, from level-up rewards)
#
# These use the same stat formulas as the paid upgrades but draw from a
# separate pool (_free_*_level caps at FREE_MAX_LEVEL = 3). Because they
# modify the same underlying stats (_damage, _range, _cooldown, etc.) the
# TrapUpgradePanel's "current value" display automatically reflects both
# paid and free contributions, and combat math picks them up with no extra
# code in the fire loops.
# ---------------------------------------------------------------------------

## Applies one free damage upgrade. Uses the same +20%-of-base formula as paid damage.
## For Glue Board this also adds the same fractional increment rather than the table
## lookup used by paid upgrades, so the two pools compose cleanly.
func apply_free_damage_upgrade() -> void:
	if _free_damage_level >= FREE_MAX_LEVEL:
		return
	_damage += _base_damage * UPGRADE_DAMAGE_FACTOR
	if _trap_type == TrapType.BAIT_STATION:
		_bait_poison_damage_per_tick += _bait_base_poison_damage * UPGRADE_DAMAGE_FACTOR
	_free_damage_level += 1
	stats_changed.emit()


## Applies one free range upgrade. Uses the same +10%-of-base formula as paid range.
func apply_free_range_upgrade() -> void:
	if _free_range_level >= FREE_MAX_LEVEL:
		return
	_range += _base_range * UPGRADE_RANGE_FACTOR
	_free_range_level += 1
	stats_changed.emit()


## Applies one free fire-rate upgrade. Reduces cooldown by 8% of base — same as paid rate.
## Passive traps (no cooldown) are skipped. Fly Strip Launcher's paid rate upgrade normally
## advances adhesion levels; free upgrades use the simpler cooldown reduction instead.
func apply_free_rate_upgrade() -> void:
	if _free_rate_level >= FREE_MAX_LEVEL or _base_cooldown == 0.0:
		return
	_cooldown = maxf(_cooldown - _base_cooldown * UPGRADE_FIRE_RATE_FACTOR, 0.1)
	_free_rate_level += 1
	stats_changed.emit()


## Applies one free duration upgrade. Adds 1.5 seconds to the slow/poison duration,
## matching the first paid-level increment in the duration tables.
## Only meaningful for Glue Board and Bait Station (other types have no duration stat).
func apply_free_duration_upgrade() -> void:
	if _free_duration_level >= FREE_MAX_LEVEL:
		return
	if _trap_type == TrapType.BAIT_STATION:
		_bait_poison_duration += BAIT_POISON_DURATION_LEVELS[1] - BAIT_POISON_DURATION_LEVELS[0]
	else:
		_slow_duration += GLUE_DURATION_LEVELS[1] - GLUE_DURATION_LEVELS[0]
	_free_duration_level += 1
	stats_changed.emit()


## Applies one free crit-chance upgrade. Same +2% per level as paid crit chance.
func apply_free_crit_chance_upgrade() -> void:
	if _free_crit_chance_level >= FREE_MAX_LEVEL:
		return
	_crit_chance += UPGRADE_CRIT_CHANCE_PER_LEVEL
	_free_crit_chance_level += 1
	stats_changed.emit()


## Applies one free crit-damage upgrade. Same +25% per level as paid crit damage.
func apply_free_crit_dmg_upgrade() -> void:
	if _free_crit_dmg_level >= FREE_MAX_LEVEL:
		return
	_crit_damage_bonus += UPGRADE_CRIT_DAMAGE_PER_LEVEL
	_free_crit_dmg_level += 1
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

func get_crit_chance() -> float:
	return _crit_chance

func get_crit_damage_bonus() -> float:
	return _crit_damage_bonus

func get_crit_chance_level() -> int:
	return _crit_chance_level

func get_crit_damage_level() -> int:
	return _crit_damage_level

func is_crit_chance_maxed() -> bool:
	return _crit_chance_level >= MAX_UPGRADE_LEVEL

func is_crit_damage_maxed() -> bool:
	return _crit_damage_level >= MAX_UPGRADE_LEVEL

## Glue Board — slow duration in seconds. Bait Station — poison duration in seconds.
func get_duration() -> float:
	if _trap_type == TrapType.BAIT_STATION:
		return _bait_poison_duration
	return _slow_duration

## True when every upgradeable stat is at MAX_UPGRADE_LEVEL.
## All traps now have 5 upgradeable stats: Damage, Range, Fire Rate / Duration, Crit Chance, Crit Damage.
func is_fully_upgraded() -> bool:
	if not (is_damage_maxed() and is_range_maxed() and is_crit_chance_maxed() and is_crit_damage_maxed()):
		return false
	match _trap_type:
		TrapType.GLUE_BOARD, TrapType.BAIT_STATION:
			return is_duration_maxed()
		_:
			return is_rate_maxed()

func get_damage() -> float:
	return _damage

func get_range_radius() -> float:
	# Returns effective range including any global campaign buff so the upgrade
	# panel displays the actual active radius, not the base stored value.
	return _effective_range()

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
			return "Pulses adhesive every few seconds, slowing every ground pest in range at the moment of each pulse. The slow lingers briefly after pests leave its range. Cannot hit flying pests."
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


## Returns all BoostUnit nodes currently applying a buff to this trap.
## Used by TrapUpgradePanel to show boost range circles during the peek gesture.
## A single Boost can appear in both source dictionaries if it buffs both stats,
## so duplicates are filtered before returning.
func get_boost_source_nodes() -> Array:
	var result: Array = []
	for source in _damage_boost_sources:
		if is_instance_valid(source) and not result.has(source):
			result.append(source)
	for source in _fire_rate_boost_sources:
		if is_instance_valid(source) and not result.has(source):
			result.append(source)
	return result


## Bug Bucks cost when placed_count units of this type are already on the grid.
## Formula: base_cost × (1 + 0.2 × placed_count), rounded to nearest integer.
## Called by Arena and HUD — keeps the formula in one place.
static func compute_placement_cost(trap_type: TrapType, placed_count: int) -> int:
	return roundi(float(STATS[trap_type]["cost"]) * (1.0 + 0.1 * float(placed_count)))


## Records the Bug Bucks actually paid at placement so get_sell_value() refunds
## the scaled cost rather than the base cost.
func set_placement_cost(cost: int) -> void:
	_cost = cost


## Returns the Bug Bucks cost that was paid to place this trap.
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
	if is_damage_maxed():      count += 1
	if is_range_maxed():       count += 1
	if is_crit_chance_maxed(): count += 1
	if is_crit_damage_maxed(): count += 1
	match _trap_type:
		TrapType.GLUE_BOARD, TrapType.BAIT_STATION:
			if is_duration_maxed(): count += 1
		_:
			if not is_passive() and is_rate_maxed(): count += 1
	return count

## Returns the total number of independently upgradeable stats for this trap.
## All trap types have 5: Damage, Range, Fire Rate / Duration, Crit Chance, Crit Damage.
func get_total_upgradeable_stats() -> int:
	return 5

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
	for lvl in range(_crit_chance_level):
		total_spent += UPGRADE_COSTS[_trap_type][lvl]
	for lvl in range(_crit_damage_level):
		total_spent += UPGRADE_COSTS[_trap_type][lvl]
	return int(total_spent * (SELL_REFUND_FRACTION + GameState.sell_value_bonus))


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

	_cooldown_remaining -= delta
	if _cooldown_remaining > 0.0:
		return

	var did_fire := false
	if _trap_type == TrapType.FOGGER:
		did_fire = _fire_fogger()
		if did_fire:
			# One crit roll per burst covers all pests caught in the cloud.
			aoe_fired.emit(global_position, _effective_range(), _roll_damage(_damage * _damage_multiplier), _active_enemies)
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
			# One crit roll per cloud launch so the entire cloud benefits or doesn't.
			fired.emit(global_position, fly_target.global_position, fly_target, 0.0, _trap_type)
			fly_strip_fired.emit(global_position, _effective_range(), _roll_damage(_damage * _damage_multiplier),
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
				_roll_damage(_damage * _damage_multiplier), _trap_type)
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


## Returns true if at least one non-flying enemy is in range and the batch cap has not been reached.
## Damage is NOT applied here — FogCloud ticks it on a fixed interval while alive.
## Flying enemies are excluded — the Fogger cannot hit airborne pests.
func _fire_fogger() -> bool:
	if _active_fog_batches >= FOG_BATCH_CAP:
		return false
	for enemy in _active_enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.get_is_flying():
			continue
		if _xz_distance(enemy.global_position) <= _effective_range():
			return true
	return false


## Pulses adhesive on a fixed interval. On each pulse, slows every ground enemy currently
## in range and starts a cosmetic projectile toward each. Between pulses the slow lingers
## on enemies that have already left range, counting down each frame until _slow_duration
## expires. Flying enemies are excluded — they never contact the adhesive surface.
func _update_glue_aoe(delta: float) -> void:
	# Every frame: tick duration countdowns for enemies that have left range.
	# Cannot erase from a Dictionary while iterating — collect targets first.
	var to_release: Array = []
	for enemy in _glue_slowed_enemies:
		if not is_instance_valid(enemy):
			to_release.append(enemy)
			continue
		if _xz_distance(enemy.global_position) <= _effective_range():
			_glue_slowed_enemies[enemy] = -1.0   # still in range — reset countdown sentinel
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

	# Tick the pulse timer.
	_glue_pulse_timer -= delta
	if _glue_pulse_timer > 0.0:
		return

	# Pulse fires: apply slow to all ground enemies currently in range.
	var hit_any := false
	for enemy in _active_enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.get_is_flying():
			continue
		if _xz_distance(enemy.global_position) <= _effective_range():
			enemy.add_slow_source(self, _damage)
			_glue_slowed_enemies[enemy] = -1.0
			fired.emit(global_position, enemy.global_position, enemy, 0.0, _trap_type)
			hit_any = true

	# Always start the next cooldown, whether or not any enemies were in range.
	_glue_pulse_timer = _glue_pulse_interval

	if hit_any:
		AudioManager.play_trap_fire(TrapType.GLUE_BOARD)
		_play_glue_board_animation()


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
		if enemy.get_is_flying() and _xz_distance(enemy.global_position) <= _effective_range():
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
		if _xz_distance(enemy.global_position) > _effective_range():
			continue
		# Crit roll applies to the burst damage only; poison tick rate is unaffected.
		enemy.take_damage(_roll_damage(_damage * _damage_multiplier), Color(0.72, 0.42, 0.08))
		enemy.apply_poison(_bait_poison_damage_per_tick, _bait_poison_duration, _bait_poison_tick_rate)
		hit_any = true
	if hit_any:
		_bait_pulse_timer = _bait_pulse_interval
		AudioManager.play_trap_fire(TrapType.BAIT_STATION)
		_play_bait_animation()
	else:
		# No enemies in range — stay ready; clamp to 0 so the timer does not
		# drift negative unboundedly while the range is empty.
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
## Also incorporates the global fire-rate campaign buff from GameState so that
## "Hair Trigger" stacks correctly with Compressor Boost auras.
func _recalculate_multipliers() -> void:
	var damage_bonus: float = 0.0
	for factor: float in _damage_boost_sources.values():
		damage_bonus += factor
	_damage_multiplier = 1.0 + damage_bonus

	# Start with the global campaign bonus, then add per-Boost aura contributions.
	var fire_rate_bonus: float = GameState.global_fire_rate_bonus
	for factor: float in _fire_rate_boost_sources.values():
		fire_rate_bonus += factor
	_fire_rate_multiplier = 1.0 + fire_rate_bonus

	_update_boost_indicator()


## Public wrapper called by Arena after a global fire-rate campaign buff is
## applied so that existing placed traps pick up the new value immediately.
## Also rebuilds the range indicator so the ring reflects the updated range.
func refresh_global_multipliers() -> void:
	_recalculate_multipliers()
	_rebuild_range_indicator()


## Returns the enemy in range closest to this trap (used by Snap Trap).
func _nearest_in_range() -> Node3D:
	var best: Node3D = null
	var best_dist    := INF
	for enemy in _active_enemies:
		if not is_instance_valid(enemy):
			continue
		var dist := _xz_distance(enemy.global_position)
		if dist <= _effective_range() and dist < best_dist:
			best_dist = dist
			best      = enemy
	return best


## Returns the enemy in range farthest along the path to the exit
## (used by Zapper — highest path index = closest to exit = biggest threat).
## Flying enemies are excluded — the Zapper cannot hit airborne pests.
func _farthest_in_range() -> Node3D:
	var best: Node3D = null
	var best_index   := -1
	for enemy in _active_enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.get_is_flying():
			continue
		if _xz_distance(enemy.global_position) <= _effective_range():
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


## Returns the trap's effective targeting range, including any global range
## campaign buff from GameState ("Extended Reach"). Used in all runtime
## distance comparisons so that the buff immediately affects all placed traps.
## The stored _range value is NOT modified — this is a read-only calculation.
func _effective_range() -> float:
	return _range * (1.0 + GameState.global_range_bonus)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Rolls a critical hit check and returns the appropriately scaled damage,
## including any active campaign buff bonuses from GameState.
##
## Crit chance and crit damage both combine the per-trap upgrade values with
## any global campaign bonus. The final result is multiplied by the global
## damage bonus so "Extermination Formula" affects every trap and damage type.
func _roll_damage(base_damage: float) -> float:
	var effective_crit_chance := _crit_chance + GameState.global_crit_chance_bonus
	var effective_crit_bonus  := _crit_damage_bonus + GameState.global_crit_dmg_bonus
	var result := base_damage
	if effective_crit_chance > 0.0 and randf() < effective_crit_chance:
		result = base_damage * (1.0 + effective_crit_bonus)
	return result * (1.0 + GameState.global_damage_bonus)


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


## Spawns the horizontal gold progress bar that shows how many stat categories are maxed.
## Called once from initialize() — not spawned for preview instances.
## Background bar is always visible; gold fill grows left-to-right as stats are maxed.
func _spawn_star_display() -> void:
	const BAR_W:      float = 1.70   # slightly less than the 2m footprint width
	const BAR_D:      float = 0.18   # depth (Z extent) for visibility from isometric camera
	const BAR_H:      float = 0.005  # essentially flat
	const BAR_LOCAL_Y: float = -0.065   # just above the SVG sprite (which is at local y=-0.08)
	const BAR_LOCAL_Z: float =  0.75    # front edge of trap footprint

	# Background bar — dark charcoal, always visible.
	var bg_box    := BoxMesh.new()
	bg_box.size    = Vector3(BAR_W, BAR_H, BAR_D)
	_bar_bg_mi     = MeshInstance3D.new()
	_bar_bg_mi.mesh = bg_box
	var bg_mat            := StandardMaterial3D.new()
	bg_mat.albedo_color    = Color(0.12, 0.12, 0.14, 0.90)
	bg_mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.no_depth_test   = true
	_bar_bg_mi.material_override = bg_mat
	_bar_bg_mi.position    = Vector3(0.0, BAR_LOCAL_Y, BAR_LOCAL_Z)
	add_child(_bar_bg_mi)

	# Gold fill bar — same size at full scale; scaled and offset left-to-right at update time.
	var fill_box    := BoxMesh.new()
	fill_box.size    = Vector3(BAR_W, BAR_H, BAR_D)
	_bar_fill_mi     = MeshInstance3D.new()
	_bar_fill_mi.mesh = fill_box
	var fill_mat            := StandardMaterial3D.new()
	fill_mat.albedo_color    = Color(1.0, 0.82, 0.18, 1.0)
	fill_mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.no_depth_test   = true
	_bar_fill_mi.material_override = fill_mat
	_bar_fill_mi.position    = Vector3(0.0, BAR_LOCAL_Y + 0.001, BAR_LOCAL_Z)   # tiny Y offset avoids Z-fight
	_bar_fill_mi.visible     = false
	add_child(_bar_fill_mi)


## Builds a flat five-pointed star as an ArrayMesh and returns it inside a
## MeshInstance3D. The star lies in the XY plane; BILLBOARD_ENABLED rotates
## it to face the camera at runtime. No fonts or textures required.
static func _make_star_mesh(outer_r: float, color: Color) -> MeshInstance3D:
	var inner_r := outer_r * 0.42
	var verts   := PackedVector3Array()

	# Fan triangulation: 10 triangles from origin to each adjacent boundary pair.
	# Angles start at PI/2 (top) and step clockwise by 36° each iteration.
	for i in 10:
		var a0 := PI / 2.0 - i * PI / 5.0
		var a1 := PI / 2.0 - (i + 1) * PI / 5.0
		var r0 := outer_r if (i % 2 == 0) else inner_r
		var r1 := outer_r if ((i + 1) % 2 == 0) else inner_r
		verts.append(Vector3.ZERO)
		verts.append(Vector3(cos(a0) * r0, sin(a0) * r0, 0.0))
		verts.append(Vector3(cos(a1) * r1, sin(a1) * r1, 0.0))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts

	var mesh                  := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat                    := StandardMaterial3D.new()
	mat.albedo_color            = color
	mat.shading_mode            = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode          = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test           = true
	mat.transparency            = BaseMaterial3D.TRANSPARENCY_ALPHA
	# CULL_DISABLED: winding order is irrelevant for a billboard polygon.
	mat.cull_mode               = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)

	var mi   := MeshInstance3D.new()
	mi.mesh   = mesh
	return mi


## Refreshes the progress bar, tints the footprint outline toward gold, and brightens the
## drop shadow as stats are maxed.  The background plate keeps its base color throughout —
## only the border and shadow shift, so the trap’s identity color is always visible.
func _update_star_display() -> void:
	if _bar_bg_mi == null:
		return
	var maxed: int = get_maxed_stat_count()

	# --- Gold progress bar ---
	const BAR_HALF_W: float = 0.85   # half of 1.70m bar width
	var frac: float = float(maxed) / float(get_total_upgradeable_stats())
	if _bar_fill_mi != null:
		_bar_fill_mi.visible   = frac > 0.001
		if frac > 0.001:
			_bar_fill_mi.scale.x   = frac
			# Shift left so the fill always starts at the left edge of the background bar.
			_bar_fill_mi.position.x = -BAR_HALF_W * (1.0 - frac)

	const GOLD: Color = Color(1.0, 0.82, 0.18)

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


## Spawns the small diamond Label3D that lights up when at least one boost aura is active.
## Floats centered above the trap at y=1.4 so it is clearly visible regardless of which
## direction the stars are facing. Uses BILLBOARD_ENABLED so it always faces the camera,
## matching the star label setup.
func _spawn_boost_indicator() -> void:
	_boost_indicator                     = Label3D.new()
	_boost_indicator.font                = UIFonts.symbols()
	_boost_indicator.font_size           = 72
	_boost_indicator.pixel_size          = 0.009
	_boost_indicator.modulate            = Color(1.0, 1.0, 1.0, 1.0)
	_boost_indicator.outline_size        = 8
	_boost_indicator.outline_modulate    = Color(0.0, 0.0, 0.0, 0.90)
	_boost_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boost_indicator.billboard           = BaseMaterial3D.BILLBOARD_ENABLED
	_boost_indicator.no_depth_test       = true
	_boost_indicator.text                = "\u2726"   # U+2726 BLACK FOUR-POINTED STAR
	_boost_indicator.position            = Vector3(0.75, 1.0, -0.75)
	_boost_indicator.visible             = false
	add_child(_boost_indicator)


## Shows the boost diamond when any boost source is active; hides it otherwise.
func _update_boost_indicator() -> void:
	if _boost_indicator == null:
		return
	var boosted := not _damage_boost_sources.is_empty() or not _fire_rate_boost_sources.is_empty()
	_boost_indicator.visible = boosted


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


## Shows the range indicator in peek mode: brighter fill/ring and a thicker ring border.
## Called from TrapUpgradePanel._on_peek_down() for the selected trap and its active boosts.
func show_range_indicator_peek() -> void:
	_indicator_pinned = true
	if _range_indicator != null:
		_range_indicator.visible = true
	_set_range_indicator_dimmed(false)
	_set_range_indicator_peek(true)


## Reverts the selected trap's indicator from peek mode back to normal pinned appearance.
## Does not hide the indicator — the panel keeps it visible until it closes.
func hide_range_indicator_peek() -> void:
	_set_range_indicator_peek(false)


## Sets the footprint outline bars to the given colour for the peek-gesture highlight.
## Defaults to white (the selected trap's ring colour in peek mode). Pass a specific
## colour when the caller wants the outline to match a different ring — e.g. passing
## get_base_color() for a buffing boost makes its outline match its identity-coloured ring.
func show_peek_outline(color: Color = Color.WHITE) -> void:
	for mat: StandardMaterial3D in _outline_mats:
		mat.albedo_color = color


## Restores the footprint outline bars to their normal upgrade-level tint.
func hide_peek_outline() -> void:
	_update_star_display()


## Fades this trap's visual materials so it recedes into the background while
## another trap's peek mode is active. Does not affect range indicators or stars.
func dim_for_peek() -> void:
	if _visual_material != null:
		_visual_material.albedo_color = Color(0.30, 0.30, 0.30, 0.30)
	if _bg_mat != null:
		_bg_mat.albedo_color = Color(0.06, 0.06, 0.06, 0.45)
	for mat: StandardMaterial3D in _outline_mats:
		mat.albedo_color = Color(0.15, 0.15, 0.15, 0.20)


## Restores materials changed by dim_for_peek() to their normal upgrade-level state.
func undim_for_peek() -> void:
	if _visual_material != null:
		_visual_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	if _bg_mat != null:
		_bg_mat.albedo_color = Color(_base_color.r * 0.65, _base_color.g * 0.65, _base_color.b * 0.65, 0.92)
	# _update_star_display() restores _outline_mats and _shadow_mat to their
	# correct upgrade-level tint, so we don't need to track those separately.
	_update_star_display()


## Applies or removes peek-mode style: brighter alpha and a thicker ring border.
## The white/gray tint is managed separately by _set_range_indicator_dimmed.
func _set_range_indicator_peek(peeking: bool) -> void:
	if _range_fill_mat == null or _range_ring_mat == null:
		return
	if peeking:
		_range_fill_mat.albedo_color.a = 0.25
		_range_ring_mat.albedo_color.a = 1.00
		if _range_ring_mi != null:
			_range_ring_mi.mesh = _make_ring_mesh(_effective_range(), 0.22)
	else:
		_range_fill_mat.albedo_color.a = 0.025
		_range_ring_mat.albedo_color.a = 0.55
		if _range_ring_mi != null:
			_range_ring_mi.mesh = _make_ring_mesh(_effective_range(), 0.10)


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
	# Local y offset from the trap root (world y = 0.25) to land at world y = 0.02 —
	# just above the arena floor and below all trap visual layers (shadow=0.05,
	# background=0.07, sprite=0.17). Transparent objects are depth-sorted back-to-front,
	# so placing the ring at the lowest world y ensures it renders behind everything.
	_range_indicator.position.y = 0.02 - 0.25
	_range_indicator.visible    = false

	var fill_alpha := 0.12 if _is_preview else 0.025
	var ring_alpha := 0.90 if _is_preview else 0.55

	# Use the effective range (including campaign buff) so the visual ring
	# matches the actual targeting range when "Extended Reach" is active.
	var eff_range := _effective_range()

	# Filled disc
	var fill_mi              := MeshInstance3D.new()
	var fill_mesh            := CylinderMesh.new()
	fill_mesh.top_radius      = eff_range
	fill_mesh.bottom_radius   = eff_range
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
	ring_mi.mesh              = _make_ring_mesh(eff_range, 0.10)
	_range_ring_mat             = StandardMaterial3D.new()
	_range_ring_mat.albedo_color = Color(1.0, 1.0, 1.0, ring_alpha)
	_range_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_range_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mi.material_override = _range_ring_mat
	_range_ring_mi = ring_mi
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


## Spawns the radial glow plane that sits beneath the Bait Station grate.
## The plane mesh is sized to the full range diameter; it is held at BAIT_GLOW_REST_SCALE
## (≈ footprint size) at rest and expands to BAIT_GLOW_FIRE_SCALE (≈ 150% footprint) on each pulse.
## The shader's "opacity" parameter drives brightness so the radial gradient shape
## stays intact while only the intensity changes.
func _spawn_bait_glow_plane() -> void:
	var plane  := PlaneMesh.new()
	plane.size  = Vector2(_range * 2.0, _range * 2.0)
	var mi     := MeshInstance3D.new()
	mi.mesh     = plane
	# Same floor height as the shadow plane (world y=0.05); local offset from trap root at y=0.25.
	mi.position.y = 0.05 - 0.25
	mi.scale      = Vector3(BAIT_GLOW_REST_SCALE, 1.0, BAIT_GLOW_REST_SCALE)

	var mat    := ShaderMaterial.new()
	mat.shader  = BAIT_GLOW_SHADER
	mat.set_shader_parameter("opacity", BAIT_GLOW_REST_OPACITY)
	mi.material_override = mat

	_bait_glow_mat = mat
	_bait_glow_mi  = mi
	add_child(mi)


## Sets _base_color from the per-type identity colour, then builds the background
## plate, drop-shadow, and footprint outline that frame the SVG sprite quad.
func _spawn_visual(_color: Color) -> void:
	# Resolve the canonical per-type color so shadow, background, and outline stay in sync.
	var c: Color
	match _trap_type:
		TrapType.SNAP_TRAP:          c = Color(0.78, 0.52, 0.22)   # warm wood brown (#9E6628 family)
		TrapType.ZAPPER:             c = Color(0.28, 0.62, 0.96)   # electric blue (#1A5ACC elevated)
		TrapType.FOGGER:             c = Color(0.46, 0.96, 0.38)   # vivid green (#4ACC1E elevated)
		TrapType.GLUE_BOARD:         c = Color(1.00, 0.58, 0.14)   # orange-amber (#ff7a13 family)
		TrapType.FLY_STRIP_LAUNCHER: c = Color(0.92, 0.30, 0.78)   # bright magenta (#E040C0 family)
		TrapType.BAIT_STATION:       c = Color(0.52, 0.30, 0.65)   # purple glow (shows through transparent grate)
		_:                           c = Color(0.80, 0.80, 0.80)
	_base_color = c

	# Bait Station: no background plate or shadow — the glow plane is its only
	# ambient marker. The SVG grate is transparent so the glow shows through the holes.
	if _trap_type == TrapType.BAIT_STATION:
		_spawn_bait_glow_plane()
		_spawn_svg_trap_visual(BAIT_STATION_FRAMES)
		return

	_spawn_shadow(c)
	_bg_mat = _spawn_background(c)
	_spawn_footprint_outline(c)

	match _trap_type:
		TrapType.SNAP_TRAP:          _spawn_svg_trap_visual(SNAP_TRAP_FRAMES)
		TrapType.ZAPPER:             _spawn_svg_trap_visual(ZAPPER_FRAMES)
		TrapType.FOGGER:             _spawn_svg_trap_visual(FOGGER_FRAMES)
		TrapType.GLUE_BOARD:         _spawn_svg_trap_visual(GLUE_BOARD_FRAMES)
		TrapType.FLY_STRIP_LAUNCHER: _spawn_svg_trap_visual(FLY_STRIP_FRAMES)


## Places the SVG sprite quad for any trap type.
## The quad lies flat on the XZ plane (basis rotated so its normal points +Y)
## at world y = 0.17 — above the background plate (0.07) and below enemies (0.25).
## The trap root sits at world y = 0.25, so local y offset = 0.17 âˆ’ 0.25 = âˆ’0.08.
func _spawn_svg_trap_visual(frames: Array[Texture2D]) -> void:
	_trap_frames = frames
	var quad := QuadMesh.new()
	quad.size = Vector2(Grid.CELL_SIZE * 1.7, Grid.CELL_SIZE * 1.7)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	mat.albedo_texture = frames[0]
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	# Rotate so the quad lies flat on XZ rather than facing the camera along -Z.
	mi.basis = Basis(Vector3.LEFT, Vector3.FORWARD, Vector3.UP)
	mi.position.y = -0.08
	_visual_material = mat
	add_child(mi)


## Swaps to the fire frame, holds briefly, then resets to idle.
func _play_zapper_animation() -> void:
	if _visual_material == null or _zapper_animating:
		return
	_zapper_animating = true
	AudioManager.play_trap_fire(TrapType.ZAPPER)

	_visual_material.albedo_texture = _trap_frames[1]
	await get_tree().create_timer(0.35).timeout
	if not is_inside_tree():
		_zapper_animating = false
		return

	_visual_material.albedo_texture = _trap_frames[0]
	_zapper_animating = false


## Swaps to the fire frame for the spray burst, then resets to idle.
func _play_fogger_animation() -> void:
	if _visual_material == null or _fogger_animating:
		return
	_fogger_animating = true
	AudioManager.play_trap_fire(TrapType.FOGGER)

	_visual_material.albedo_texture = _trap_frames[1]
	await get_tree().create_timer(0.30).timeout
	if not is_inside_tree():
		_fogger_animating = false
		return

	_visual_material.albedo_texture = _trap_frames[0]
	_fogger_animating = false


## Swaps to the fire frame (bar snapped flat) for half the cooldown, then resets.
## Guards against overlap so a fast trigger rate cannot stack multiple swaps.
func _play_snap_animation() -> void:
	if _visual_material == null or _snap_animating:
		return
	_snap_animating = true
	AudioManager.play_trap_fire(TrapType.SNAP_TRAP)

	_visual_material.albedo_texture = _trap_frames[1]
	await get_tree().create_timer(_cooldown * 0.50).timeout
	if not is_inside_tree():
		_snap_animating = false
		return

	_visual_material.albedo_texture = _trap_frames[0]
	_snap_animating = false


## Swaps to the fire frame (strip extending from barrel) for the launch, then resets.
func _play_fly_strip_animation() -> void:
	if _visual_material == null or _fly_strip_animating:
		return
	_fly_strip_animating = true
	AudioManager.play_trap_fire(TrapType.FLY_STRIP_LAUNCHER)

	_visual_material.albedo_texture = _trap_frames[1]
	await get_tree().create_timer(0.30).timeout
	if not is_inside_tree():
		_fly_strip_animating = false
		return

	_visual_material.albedo_texture = _trap_frames[0]
	_fly_strip_animating = false


## Swaps to the fire frame when the glue board first catches a new enemy, then resets.
## The fire frame shows a wider glue spread with ripple rings around newly-stuck victims.
func _play_glue_board_animation() -> void:
	if _visual_material == null:
		return
	_visual_material.albedo_texture = _trap_frames[1]
	await get_tree().create_timer(0.40).timeout
	if not is_inside_tree():
		return
	_visual_material.albedo_texture = _trap_frames[0]


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

	# Show the green fire-frame SVG (grate glowing) while the glow plane pulses.
	if _visual_material != null:
		_visual_material.albedo_texture = _trap_frames[1]

	# Expand from resting scale to fire scale and brighten simultaneously.
	# set_parallel(true) lets both tweens run at the same time on the same Tween object.
	var expand := create_tween().set_parallel(true)
	expand.tween_property(_bait_glow_mat, "shader_parameter/opacity",
		1.0, 0.12).set_ease(Tween.EASE_OUT)
	expand.tween_property(_bait_glow_mi, "scale",
		Vector3(BAIT_GLOW_FIRE_SCALE, 1.0, BAIT_GLOW_FIRE_SCALE), 0.12).set_ease(Tween.EASE_OUT)
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

	if _visual_material != null:
		_visual_material.albedo_texture = _trap_frames[0]
	_bait_animating = false
