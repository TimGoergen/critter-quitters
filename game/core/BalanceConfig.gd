extends Node
## Mutable balance data for all game units. Read by Trap, BoostUnit, Enemy, and Arena
## instead of their hardcoded const values, so everything can be tweaked at runtime.
##
## Keys are plain integers matching each file's enum ordinals (0, 1, 2...) so this
## singleton never preloads Trap.gd or Enemy.gd (which pull shaders/textures and would
## create fragile autoload ordering).
##
## Each mutable var has a companion _DEFAULT_* const. reset_to_defaults() copies from
## those consts so the original values are always recoverable.

# ---------------------------------------------------------------------------
# Trap stats (0=SNAP_TRAP 1=ZAPPER 2=FOGGER 3=GLUE_BOARD 4=FLY_STRIP_LAUNCHER 5=BAIT_STATION)
# ---------------------------------------------------------------------------

const _DEFAULT_TRAP_STATS := {
	0: { "damage": 5.0,  "range": 5.6, "cooldown": 1.0, "cost": 25 },
	1: { "damage": 30.0, "range": 9.6, "cooldown": 2.5, "cost": 75 },
	2: { "damage": 3.0,  "range": 4.0, "cooldown": 2.2, "cost": 60 },
	3: { "damage": 0.20, "range": 4.8, "cooldown": 0.0, "cost": 45, "pulse_interval": 3.0 },
	4: { "damage": 2.0,  "range": 5.0, "cooldown": 5.0, "cost": 65,
		 "cloud_duration": 3.0, "adhesion": 0.30 },
	5: { "damage": 3.0,  "range": 3.5, "cooldown": 0.0, "cost": 40,
		 "pulse_interval": 4.0, "poison_damage_per_tick": 1.5,
		 "poison_duration": 3.0, "poison_tick_rate": 0.5 },
}
var _trap_stats: Dictionary = {}

const _DEFAULT_TRAP_UPGRADE_COSTS := {
	0: [20, 30,  50],
	1: [50, 75, 120],
	2: [40, 60, 100],
	3: [30, 45,  70],
	4: [40, 65, 100],
	5: [30, 45,  70],
}
var _trap_upgrade_costs: Dictionary = {}

## Global upgrade factors — the +% of base value gained per upgrade level.
const _DEFAULT_TRAP_UPGRADE_FACTORS := {
	"damage":              0.20,
	"range":               0.10,
	"fire_rate":           0.08,
	"crit_chance_per_level": 0.02,
	"crit_damage_per_level": 0.25,
}
var _trap_upgrade_factors: Dictionary = {}

## Per-level tables for traps whose upgrade math doesn't fit the shared factor formula.
const _DEFAULT_GLUE_ADHESION_LEVELS:       Array[float] = [0.35, 0.45, 0.55, 0.65]
const _DEFAULT_GLUE_DURATION_LEVELS:       Array[float] = [3.0,  4.5,  6.0,  8.0 ]
const _DEFAULT_FLY_STRIP_ADHESION_LEVELS:  Array[float] = [0.30, 0.40, 0.55, 0.70]
const _DEFAULT_BAIT_POISON_DURATION_LEVELS: Array[float] = [3.0,  4.5,  6.0,  8.0 ]
var _glue_adhesion_levels:        Array[float] = []
var _glue_duration_levels:        Array[float] = []
var _fly_strip_adhesion_levels:   Array[float] = []
var _bait_poison_duration_levels: Array[float] = []

# ---------------------------------------------------------------------------
# Boost stats (0=PHEROMONE_DISPENSER 1=COMPRESSOR 2=CASH_REGISTER 3=AIR_FRESHENER 4=QUARANTINE_MARKER)
# ---------------------------------------------------------------------------

const _DEFAULT_BOOST_STATS := {
	0: { "range": 4.0, "cost": 50, "damage_bonus":    0.25 },
	1: { "range": 4.0, "cost": 50, "fire_rate_bonus":  0.20 },
	2: { "range": 5.0, "cost": 45, "income_per_wave":  5,   "kill_bonus":       2    },
	3: { "range": 3.0, "cost": 35, "reduction":        0.50, "capacity":        50.0 },
	4: { "range": 4.0, "cost": 40, "restore_per_kill": 2.0,  "capacity":        80.0 },
}
var _boost_stats: Dictionary = {}

const _DEFAULT_BOOST_UPGRADE_COSTS := {
	0: [15, 25, 40],
	1: [15, 25, 40],
	2: [20, 35, 55],
	3: [15, 25, 40],
	4: [15, 25, 40],
}
var _boost_upgrade_costs: Dictionary = {}

## Primary-stat increment per upgrade level, keyed by boost type.
const _DEFAULT_BOOST_STAT_B_DELTA := {
	0: 0.08, 1: 0.07, 2: 3.0, 3: 0.10, 4: 1.0,
}
var _boost_stat_b_delta: Dictionary = {}

## Secondary-stat increment per upgrade level (only types 2, 3, 4 have a stat C).
const _DEFAULT_BOOST_STAT_C_DELTA := {
	2: 1.0, 3: 25.0, 4: 40.0,
}
var _boost_stat_c_delta: Dictionary = {}

## Range upgrade factor applied to _base_range per level (all boost types share this).
const _DEFAULT_BOOST_RANGE_FACTOR: float = 0.10
var _boost_range_factor: float = _DEFAULT_BOOST_RANGE_FACTOR

# ---------------------------------------------------------------------------
# Enemy stats (0=ANT 1=GNAT 2=CRICKET 3=BEETLE 4=COCKROACH 5=MOUSE 6=MOSQUITO 7=RAT_KING 8=RAT)
# ---------------------------------------------------------------------------

const _DEFAULT_ENEMY_STATS := {
	0: { "hp": 12,  "speed": 2.5,  "infestation":   8.0, "bounty":   6, "xp":  2 },
	1: { "hp":  6,  "speed": 5.6,  "infestation":   4.0, "bounty":   3, "xp":  1 },
	2: { "hp": 15,  "speed": 3.2,  "infestation":   8.0, "bounty":  10, "xp":  2 },
	3: { "hp": 33,  "speed": 1.5,  "infestation":  20.0, "bounty":  20, "xp":  5 },
	4: { "hp": 105, "speed": 1.0,  "infestation":  35.0, "bounty":  35, "xp":  8 },
	5: { "hp": 280, "speed": 0.6,  "infestation":  60.0, "bounty":  60, "xp": 20,
		 "bug_bucks_steal": 20 },
	6: { "hp":  18, "speed": 5.5,  "infestation":  18.0, "bounty":  10, "xp":  3,
		 "is_flying": true },
	7: { "hp": 900, "speed": 0.35, "infestation": 100.0, "bounty": 180, "xp": 40 },
	8: { "hp":  85, "speed": 1.3,  "infestation":  22.0, "bounty":  20, "xp":  6 },
}
var _enemy_stats: Dictionary = {}

## hp × (1 + wave_tier × this_value) where wave_tier = wave / 5.
const _DEFAULT_HP_SCALING_PER_TIER: float = 0.30
var _hp_scaling_per_tier: float = _DEFAULT_HP_SCALING_PER_TIER

# ---------------------------------------------------------------------------
# Wave config
# ---------------------------------------------------------------------------

const _DEFAULT_WAVE_CONFIG := {
	"wave_size":              15,
	"wave_size_step_waves":    5,
	"wave_size_step_amount":   2,
	"spawn_interval":          0.36,
	"spawn_gap_cells":         0.25,
	"boss_wave_interval":     10,
}
var _wave_config: Dictionary = {}

## Per-enemy wave pool config. weight=0 means the type never appears in the normal pool
## (used for boss types that are handled by special-case logic in Arena).
## phase_out_after=0 means no phase-out.
const _DEFAULT_ENEMY_WAVE_CONFIG := {
	0: { "first_wave":  1, "weight": 3, "phase_out_after": 0 },                         # ANT
	1: { "first_wave":  1, "weight": 3, "phase_out_after": 6 },                         # GNAT
	2: { "first_wave":  3, "weight": 2, "phase_out_after": 0 },                         # CRICKET
	3: { "first_wave":  5, "weight": 2, "phase_out_after": 0 },                         # BEETLE
	4: { "first_wave":  8, "weight": 3, "phase_out_after": 0 },                         # COCKROACH
	5: { "first_wave":  0, "weight": 0, "phase_out_after": 0 },                         # MOUSE (boss-only)
	6: { "first_wave":  3, "weight": 1, "phase_out_after": 0, "requires_anti_air": true }, # MOSQUITO
	7: { "first_wave":  0, "weight": 0, "phase_out_after": 0 },                         # RAT_KING (boss-only)
	8: { "first_wave": 15, "weight": 2, "phase_out_after": 0 },                         # RAT
}
var _enemy_wave_config: Dictionary = {}

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_copy_defaults()
	load_from_disk()


## Copies all _DEFAULT_* consts into the mutable var dicts.
## Called at startup and by reset_to_defaults().
func _copy_defaults() -> void:
	_trap_stats = _deep_copy_dict(_DEFAULT_TRAP_STATS)
	_trap_upgrade_costs = _deep_copy_dict(_DEFAULT_TRAP_UPGRADE_COSTS)
	_trap_upgrade_factors = _DEFAULT_TRAP_UPGRADE_FACTORS.duplicate()
	_glue_adhesion_levels = _DEFAULT_GLUE_ADHESION_LEVELS.duplicate()
	_glue_duration_levels = _DEFAULT_GLUE_DURATION_LEVELS.duplicate()
	_fly_strip_adhesion_levels = _DEFAULT_FLY_STRIP_ADHESION_LEVELS.duplicate()
	_bait_poison_duration_levels = _DEFAULT_BAIT_POISON_DURATION_LEVELS.duplicate()
	_boost_stats = _deep_copy_dict(_DEFAULT_BOOST_STATS)
	_boost_upgrade_costs = _deep_copy_dict(_DEFAULT_BOOST_UPGRADE_COSTS)
	_boost_stat_b_delta = _DEFAULT_BOOST_STAT_B_DELTA.duplicate()
	_boost_stat_c_delta = _DEFAULT_BOOST_STAT_C_DELTA.duplicate()
	_boost_range_factor = _DEFAULT_BOOST_RANGE_FACTOR
	_enemy_stats = _deep_copy_dict(_DEFAULT_ENEMY_STATS)
	_hp_scaling_per_tier = _DEFAULT_HP_SCALING_PER_TIER
	_wave_config = _DEFAULT_WAVE_CONFIG.duplicate()
	_enemy_wave_config = _deep_copy_dict(_DEFAULT_ENEMY_WAVE_CONFIG)


## Returns a shallow copy of each nested dict so mutations don't reach the const.
func _deep_copy_dict(src: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in src:
		var val = src[key]
		if val is Dictionary:
			result[key] = val.duplicate()
		elif val is Array:
			result[key] = val.duplicate()
		else:
			result[key] = val
	return result

# ---------------------------------------------------------------------------
# Public getters — Trap
# ---------------------------------------------------------------------------

func get_trap_stats(trap_type: int) -> Dictionary:
	return _trap_stats[trap_type]

func get_trap_upgrade_costs(trap_type: int) -> Array:
	return _trap_upgrade_costs[trap_type]

func get_trap_upgrade_factors() -> Dictionary:
	return _trap_upgrade_factors

func get_glue_adhesion_levels() -> Array:
	return _glue_adhesion_levels

func get_glue_duration_levels() -> Array:
	return _glue_duration_levels

func get_fly_strip_adhesion_levels() -> Array:
	return _fly_strip_adhesion_levels

func get_bait_poison_duration_levels() -> Array:
	return _bait_poison_duration_levels

# ---------------------------------------------------------------------------
# Public getters — Boost
# ---------------------------------------------------------------------------

func get_boost_stats(boost_type: int) -> Dictionary:
	return _boost_stats[boost_type]

func get_boost_upgrade_costs(boost_type: int) -> Array:
	return _boost_upgrade_costs[boost_type]

func get_boost_stat_b_delta(boost_type: int) -> float:
	return float(_boost_stat_b_delta[boost_type])

func get_boost_stat_c_delta(boost_type: int) -> float:
	return float(_boost_stat_c_delta[boost_type])

func get_boost_range_factor() -> float:
	return _boost_range_factor

# ---------------------------------------------------------------------------
# Public getters — Enemy / Wave
# ---------------------------------------------------------------------------

func get_enemy_stats(enemy_type: int) -> Dictionary:
	return _enemy_stats[enemy_type]

func get_hp_scaling_per_tier() -> float:
	return _hp_scaling_per_tier

func get_wave_config() -> Dictionary:
	return _wave_config

func get_enemy_wave_config(enemy_type: int) -> Dictionary:
	return _enemy_wave_config[enemy_type]

# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

const _SAVE_PATH := "user://balance.cfg"

func save() -> void:
	var cfg := ConfigFile.new()

	for t: int in _trap_stats:
		for field: String in _trap_stats[t]:
			cfg.set_value("trap_stats", "%d_%s" % [t, field], _trap_stats[t][field])

	for t: int in _trap_upgrade_costs:
		cfg.set_value("trap_upgrade_costs", str(t), _trap_upgrade_costs[t])

	for field: String in _trap_upgrade_factors:
		cfg.set_value("trap_upgrade_factors", field, _trap_upgrade_factors[field])

	cfg.set_value("trap_level_tables", "glue_adhesion",        _glue_adhesion_levels)
	cfg.set_value("trap_level_tables", "glue_duration",        _glue_duration_levels)
	cfg.set_value("trap_level_tables", "fly_strip_adhesion",   _fly_strip_adhesion_levels)
	cfg.set_value("trap_level_tables", "bait_poison_duration", _bait_poison_duration_levels)

	for b: int in _boost_stats:
		for field: String in _boost_stats[b]:
			cfg.set_value("boost_stats", "%d_%s" % [b, field], _boost_stats[b][field])

	for b: int in _boost_upgrade_costs:
		cfg.set_value("boost_upgrade_costs", str(b), _boost_upgrade_costs[b])

	for b: int in _boost_stat_b_delta:
		cfg.set_value("boost_stat_b_delta", str(b), _boost_stat_b_delta[b])

	for b: int in _boost_stat_c_delta:
		cfg.set_value("boost_stat_c_delta", str(b), _boost_stat_c_delta[b])

	cfg.set_value("boost_upgrade_factors", "range_factor", _boost_range_factor)

	for e: int in _enemy_stats:
		for field: String in _enemy_stats[e]:
			cfg.set_value("enemy_stats", "%d_%s" % [e, field], _enemy_stats[e][field])

	cfg.set_value("enemy_scaling", "hp_per_tier", _hp_scaling_per_tier)

	for field: String in _wave_config:
		cfg.set_value("wave_config", field, _wave_config[field])

	for e: int in _enemy_wave_config:
		for field: String in _enemy_wave_config[e]:
			cfg.set_value("enemy_wave_config", "%d_%s" % [e, field], _enemy_wave_config[e][field])

	cfg.save(_SAVE_PATH)


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_SAVE_PATH) != OK:
		return  # No saved file — defaults stand.

	for t: int in _trap_stats:
		for field: String in _trap_stats[t]:
			_trap_stats[t][field] = cfg.get_value("trap_stats", "%d_%s" % [t, field],
				_trap_stats[t][field])

	for t: int in _trap_upgrade_costs:
		_trap_upgrade_costs[t] = cfg.get_value("trap_upgrade_costs", str(t),
			_trap_upgrade_costs[t])

	for field: String in _trap_upgrade_factors:
		_trap_upgrade_factors[field] = cfg.get_value("trap_upgrade_factors", field,
			_trap_upgrade_factors[field])

	_glue_adhesion_levels        = cfg.get_value("trap_level_tables", "glue_adhesion",
		_glue_adhesion_levels)
	_glue_duration_levels        = cfg.get_value("trap_level_tables", "glue_duration",
		_glue_duration_levels)
	_fly_strip_adhesion_levels   = cfg.get_value("trap_level_tables", "fly_strip_adhesion",
		_fly_strip_adhesion_levels)
	_bait_poison_duration_levels = cfg.get_value("trap_level_tables", "bait_poison_duration",
		_bait_poison_duration_levels)

	for b: int in _boost_stats:
		for field: String in _boost_stats[b]:
			_boost_stats[b][field] = cfg.get_value("boost_stats", "%d_%s" % [b, field],
				_boost_stats[b][field])

	for b: int in _boost_upgrade_costs:
		_boost_upgrade_costs[b] = cfg.get_value("boost_upgrade_costs", str(b),
			_boost_upgrade_costs[b])

	for b: int in _boost_stat_b_delta:
		_boost_stat_b_delta[b] = cfg.get_value("boost_stat_b_delta", str(b),
			_boost_stat_b_delta[b])

	for b: int in _boost_stat_c_delta:
		_boost_stat_c_delta[b] = cfg.get_value("boost_stat_c_delta", str(b),
			_boost_stat_c_delta[b])

	_boost_range_factor = cfg.get_value("boost_upgrade_factors", "range_factor",
		_boost_range_factor)

	for e: int in _enemy_stats:
		for field: String in _enemy_stats[e]:
			_enemy_stats[e][field] = cfg.get_value("enemy_stats", "%d_%s" % [e, field],
				_enemy_stats[e][field])

	_hp_scaling_per_tier = cfg.get_value("enemy_scaling", "hp_per_tier", _hp_scaling_per_tier)

	for field: String in _wave_config:
		_wave_config[field] = cfg.get_value("wave_config", field, _wave_config[field])

	for e: int in _enemy_wave_config:
		for field: String in _enemy_wave_config[e]:
			_enemy_wave_config[e][field] = cfg.get_value("enemy_wave_config",
				"%d_%s" % [e, field], _enemy_wave_config[e][field])


func reset_to_defaults() -> void:
	_copy_defaults()
	save()

# ---------------------------------------------------------------------------
# Markdown export
# ---------------------------------------------------------------------------

const _TRAP_NAMES  := ["Snap Trap", "Zapper", "Fogger", "Glue Board",
					   "Fly Strip Launcher", "Bait Station"]
const _BOOST_NAMES := ["Pheromone Dispenser", "Compressor", "Cash Register",
					   "Air Freshener", "Quarantine Marker"]
const _ENEMY_NAMES := ["Ant", "Gnat", "Cricket", "Beetle", "Cockroach",
					   "Mouse", "Mosquito", "Rat King", "Rat"]

## Returns a human-readable markdown string of the current balance configuration.
func export_to_markdown() -> String:
	var dt := Time.get_datetime_string_from_system()
	var lines: PackedStringArray = []

	lines.append("# Critter Quitters — Balance Config")
	lines.append("*Exported: %s*" % dt)
	lines.append("")
	lines.append("---")
	lines.append("")

	# --- TRAPS ---
	lines.append("## Traps")
	lines.append("")

	for t: int in range(6):
		var s := _trap_stats[t]
		lines.append("### %s" % _TRAP_NAMES[t])
		lines.append("| Stat | Value |")
		lines.append("|------|-------|")
		lines.append("| Damage | %s |" % _fmt(s["damage"]))
		lines.append("| Range | %s |" % _fmt(s["range"]))
		lines.append("| Cooldown | %s |" % _fmt(s["cooldown"]))
		lines.append("| Cost (BB) | %s |" % _fmt(s["cost"]))
		if s.has("pulse_interval"):
			lines.append("| Pulse Interval | %s |" % _fmt(s["pulse_interval"]))
		if s.has("cloud_duration"):
			lines.append("| Cloud Duration | %s |" % _fmt(s["cloud_duration"]))
		if s.has("adhesion"):
			lines.append("| Adhesion | %s |" % _fmt(s["adhesion"]))
		if s.has("poison_damage_per_tick"):
			lines.append("| Poison Dmg/Tick | %s |" % _fmt(s["poison_damage_per_tick"]))
		if s.has("poison_duration"):
			lines.append("| Poison Duration | %s |" % _fmt(s["poison_duration"]))
		if s.has("poison_tick_rate"):
			lines.append("| Poison Tick Rate | %s |" % _fmt(s["poison_tick_rate"]))
		var c := _trap_upgrade_costs[t]
		lines.append("")
		lines.append("**Upgrade Costs:** L1: %d BB · L2: %d BB · L3: %d BB" % [c[0], c[1], c[2]])
		lines.append("")

	lines.append("### Global Upgrade Factors")
	lines.append("| Factor | Value |")
	lines.append("|--------|-------|")
	var f := _trap_upgrade_factors
	lines.append("| Damage per Level | %s |" % _fmt(f["damage"]))
	lines.append("| Range per Level | %s |" % _fmt(f["range"]))
	lines.append("| Fire Rate per Level | %s |" % _fmt(f["fire_rate"]))
	lines.append("| Crit Chance per Level | %s |" % _fmt(f["crit_chance_per_level"]))
	lines.append("| Crit Damage per Level | %s |" % _fmt(f["crit_damage_per_level"]))
	lines.append("")

	lines.append("### Level Tables")
	lines.append("**Glue Adhesion:** %s" % " · ".join(PackedStringArray(_glue_adhesion_levels.map(_fmt))))
	lines.append("**Glue Duration:** %s" % " · ".join(PackedStringArray(_glue_duration_levels.map(_fmt))))
	lines.append("**Fly Strip Adhesion:** %s" % " · ".join(PackedStringArray(_fly_strip_adhesion_levels.map(_fmt))))
	lines.append("**Bait Poison Duration:** %s" % " · ".join(PackedStringArray(_bait_poison_duration_levels.map(_fmt))))
	lines.append("")
	lines.append("---")
	lines.append("")

	# --- BOOSTS ---
	lines.append("## Boosts")
	lines.append("")

	for b: int in range(5):
		var s := _boost_stats[b]
		lines.append("### %s" % _BOOST_NAMES[b])
		lines.append("| Stat | Value |")
		lines.append("|------|-------|")
		lines.append("| Range | %s |" % _fmt(s["range"]))
		lines.append("| Cost (BB) | %s |" % _fmt(s["cost"]))
		for key: String in ["damage_bonus", "fire_rate_bonus", "income_per_wave",
							"kill_bonus", "reduction", "capacity", "restore_per_kill"]:
			if s.has(key):
				lines.append("| %s | %s |" % [key.replace("_", " ").capitalize(), _fmt(s[key])])
		var c := _boost_upgrade_costs[b]
		lines.append("")
		lines.append("**Upgrade Costs:** L1: %d BB · L2: %d BB · L3: %d BB" % [c[0], c[1], c[2]])
		lines.append("**Stat B Delta:** %s · **Range Factor:** %s" % [
			_fmt(_boost_stat_b_delta[b]), _fmt(_boost_range_factor)])
		if _boost_stat_c_delta.has(b):
			lines.append("**Stat C Delta:** %s" % _fmt(_boost_stat_c_delta[b]))
		lines.append("")

	lines.append("---")
	lines.append("")

	# --- ENEMIES ---
	lines.append("## Enemies")
	lines.append("")

	for e: int in range(9):
		var s := _enemy_stats[e]
		lines.append("### %s" % _ENEMY_NAMES[e])
		lines.append("| Stat | Value |")
		lines.append("|------|-------|")
		lines.append("| HP | %s |" % _fmt(s["hp"]))
		lines.append("| Speed | %s |" % _fmt(s["speed"]))
		lines.append("| Infestation | %s |" % _fmt(s["infestation"]))
		lines.append("| Bounty (BB) | %s |" % _fmt(s["bounty"]))
		lines.append("| XP | %s |" % _fmt(s["xp"]))
		if s.has("bug_bucks_steal"):
			lines.append("| BB Steal on Exit | %s |" % _fmt(s["bug_bucks_steal"]))
		if s.get("is_flying", false):
			lines.append("| Flying | yes |")
		lines.append("")

	lines.append("**HP Scaling per Wave Tier:** %s  " % _fmt(_hp_scaling_per_tier))
	lines.append("*(formula: base_hp × (1 + wave_tier × this_value), where wave_tier = wave ÷ 5)*")
	lines.append("")
	lines.append("---")
	lines.append("")

	# --- WAVES ---
	lines.append("## Waves")
	lines.append("")

	var wc := _wave_config
	lines.append("### Wave Parameters")
	lines.append("| Parameter | Value |")
	lines.append("|-----------|-------|")
	lines.append("| Base Wave Size | %s |" % _fmt(wc["wave_size"]))
	lines.append("| Size Step Interval (waves) | %s |" % _fmt(wc["wave_size_step_waves"]))
	lines.append("| Size Step Amount | %s |" % _fmt(wc["wave_size_step_amount"]))
	lines.append("| Spawn Interval (sec) | %s |" % _fmt(wc["spawn_interval"]))
	lines.append("| Spawn Gap (cells) | %s |" % _fmt(wc["spawn_gap_cells"]))
	lines.append("| Boss Wave Interval | %s |" % _fmt(wc["boss_wave_interval"]))
	lines.append("")

	lines.append("### Enemy Wave Pool")
	lines.append("| Enemy | First Wave | Weight | Phase Out After |")
	lines.append("|-------|-----------|--------|----------------|")
	for e: int in range(9):
		var ewc := _enemy_wave_config[e]
		var po: String = "—" if ewc["phase_out_after"] == 0 else str(ewc["phase_out_after"])
		var note: String = " *(boss-only)*" if ewc["weight"] == 0 else ""
		var aa: String = " *(requires anti-air)*" if ewc.get("requires_anti_air", false) else ""
		lines.append("| %s | %d | %d | %s |%s%s" % [
			_ENEMY_NAMES[e], ewc["first_wave"], ewc["weight"], po, note, aa])
	lines.append("")

	return "\n".join(lines)


# ---------------------------------------------------------------------------
# Setters for scalar values — used by BalanceEditorScreen
# ---------------------------------------------------------------------------
# Dict and Array values can be mutated directly through their getter references,
# so only the standalone scalar fields need explicit setters.

func set_hp_scaling_per_tier(value: float) -> void:
	_hp_scaling_per_tier = value

func set_boost_stat_b_delta(boost_type: int, value: float) -> void:
	_boost_stat_b_delta[boost_type] = value

func set_boost_stat_c_delta(boost_type: int, value: float) -> void:
	_boost_stat_c_delta[boost_type] = value

func set_boost_range_factor(value: float) -> void:
	_boost_range_factor = value


# ---------------------------------------------------------------------------
# Markdown export
# ---------------------------------------------------------------------------

## Format a number: integer display if it's a whole number, 2 decimal places otherwise.
func _fmt(val) -> String:
	if val is bool:
		return "yes" if val else "no"
	var f := float(val)
	if f == floorf(f) and absf(f) < 1_000_000:
		return str(int(f))
	return "%.2f" % f
