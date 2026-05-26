## GameState.gd
## Autoload singleton — the single source of truth for run state.
##
## Every other system reads from here rather than maintaining its own
## copy of shared state. Cross-system communication happens through the
## signals defined below, so systems stay decoupled from each other.
##
## Registered as an autoload in project.godot under the name "GameState".

extends Node


# ---------------------------------------------------------------------------
# Phase enum
#
# Describes what the player is currently doing. Other systems check this
# to know whether they should be active (e.g. the wave manager only runs
# during WAVE; the store only opens during STORE).
# ---------------------------------------------------------------------------

enum Phase {
	HUB,       # Between runs — player is at The Truck
	PLACING,   # Pre-wave countdown — player is placing traps
	WAVE,      # Wave in progress — pests are active on the arena
	STORE,     # Between waves — player is in the store
	RUN_OVER,  # Run has ended — Infestation Level reached maximum
}


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted whenever the game phase changes. Systems that depend on phase
## should connect here rather than polling current_phase each frame.
signal phase_changed(new_phase: Phase)

## Emitted once when a new run begins, after all run state is reset.
signal run_started

## Emitted once when a run ends, before transitioning back to the hub.
signal run_ended

## Emitted whenever bug_bucks changes. HUD connects here to stay current.
signal bug_bucks_changed(new_amount: int)

## Emitted whenever infestation_level changes. HUD connects here to stay current.
signal infestation_changed(new_level: float)

## Emitted when current_wave changes.
signal wave_changed(new_wave: int)

## Emitted each second during the between-wave countdown.
## seconds_remaining == 0 means the countdown ended (wave is launching).
signal wave_countdown_changed(seconds_remaining: int)

## Emitted when the player requests to skip the countdown and launch the next wave immediately.
signal wave_skip_requested

## Emitted when the player uses the multiplier toggle and wants to launch several waves at once.
## count is the number of waves to launch simultaneously (matches the ×1/×10/×100 setting).
signal wave_skip_multi_requested(count: int)

## Emitted when the player skips the countdown and receives a coin bonus for the remaining time.
signal early_wave_bonus_awarded(coins: int)

## Emitted whenever the "send next wave early" reward changes — at wave launch with
## the full amount, after each enemy spawns as it decreases, and at 0 once exhausted.
signal early_send_reward_changed(amount: int)

## Emitted at wave launch (spawned=0) and after each enemy spawns.
## HUD uses this to drive the timer-ring segment display.
signal wave_spawn_progress_changed(spawned: int, total: int)

## Emitted when the player picks a different trap type to place.
## type is an int matching the Trap.TrapType enum — stored as int here to
## avoid importing Trap.gd into GameState and creating a circular dependency.
signal trap_type_selected(type: int)

## Emitted by the HUD zoom button and by enemy-follow tap logic.
## Arena connects here to call _toggle_zoom().
signal zoom_toggle_requested

## Emitted by Arena after a zoom state change so HUD can update the button label.
signal zoom_state_changed(is_zoomed: bool)

## Emitted when the player changes grid line display preferences in Settings.
## show_when_overview: true draws lines in the zoomed-out (full-arena) view.
## show_when_zoomed:   true draws lines in the zoomed-in (2×) view.
signal grid_lines_changed(show_when_overview: bool, show_when_zoomed: bool)

## Emitted whenever current_xp or the required amount changes.
## new_xp is the player's current accumulated experience toward the next level.
## xp_needed is the total required to reach the next level from zero.
signal xp_changed(new_xp: int, xp_needed: int)

## Emitted when the player accumulates enough experience to advance a level.
## new_level is the level just reached (first level-up emits 2).
signal level_up(new_level: int)


# ---------------------------------------------------------------------------
# Constants
#
# Numeric values marked TODO are placeholders — final values come from
# playtesting once the full game loop is in place.
# ---------------------------------------------------------------------------

## Starting currency given to the player at the beginning of every run.
## Increased by business upgrades purchased with Service Fees.
## TODO: tune via playtesting; increase via meta upgrades
const STARTING_BUG_BUCKS: int = 1000

## Total infestation points that fill the bar to 1.0.
## TODO: tune via playtesting
const INFESTATION_MAX: int = 20


# ---------------------------------------------------------------------------
# Run state
#
# These values are reset at the start of each run by start_run().
# Read them freely; mutate them only through the methods below.
# ---------------------------------------------------------------------------

## Current phase of the game. Setting this property emits phase_changed.
var current_phase: Phase = Phase.HUB:
	set(value):
		current_phase = value
		phase_changed.emit(value)

## The wave the player is currently on. Starts at 0; incremented to 1
## when the first wave begins.
var current_wave: int = 0:
	set(value):
		current_wave = value
		wave_changed.emit(value)

## The player's current in-run currency. Earned by killing pests;
## spent on traps, upgrades, and store rerolls.
var bug_bucks: int = 0

## How full the Infestation Level is, expressed as a value from 0.0 to 1.0.
## The run ends when this reaches 1.0.
var infestation_level: float = 0.0

## Grid coordinate of the pest entrance for the current run.
## Set at run start; does not change during the run.
var entrance_cell: Vector2i = Vector2i.ZERO

## Grid coordinate of the pest exit for the current run.
## Set at run start; does not change during the run.
var exit_cell: Vector2i = Vector2i.ZERO

## Which trap type the player currently has selected for placement.
## 0 = SNAP_TRAP, 1 = ZAPPER, 2 = FOGGER, 3 = GLUE_BOARD (Trap.TrapType enum order).
## All types are always available — Bug Bucks cost is the only gate.
var selected_trap_type: int = 0

## Bug Bucks awarded per second remaining when the player clicks Send Wave Early
## during the between-wave countdown.  Default 2; upgradeable between runs.
var early_wave_bonus_rate: int = 2

## Flat Bug Bucks bonus awarded per current-wave-number when the player sends
## the next wave while the current wave is still active.
## Final bonus = current_wave × WAVE_OVERLAP_BONUS_RATE.
## Larger than the countdown bonus because the player is taking on real risk.
const WAVE_OVERLAP_BONUS_RATE: int = 20

## Bug Bucks awarded per enemy that has NOT yet spawned when the player presses
## "Send Next Wave" during an active wave.  Small by design — the real reward
## is the extra kill bounties from tackling two waves at once.
const EARLY_SEND_PER_ENEMY: int = 3


# ---------------------------------------------------------------------------
# Experience & level state
#
# Reset at the start of each run. The level-up system is a mid-run progression
# layer: kills fill the XP bar; filling it pauses the game and offers three
# upgrade cards to choose from.
# ---------------------------------------------------------------------------

## How much XP the player has accumulated toward the next level this run.
var current_xp: int = 0

## The player's current level within this run. Starts at 0; the first
## level-up advances it to 1, the second to 2, and so on.
var current_player_level: int = 0


# ---------------------------------------------------------------------------
# Campaign buff state
#
# These are additive bonus magnitudes, e.g. 0.05 means +5%.
# Applied each time a Campaign-type upgrade card is selected at level-up.
# All reset to zero at run start.
# ---------------------------------------------------------------------------

## +X% multiplied into every trap's damage output on each shot.
var global_damage_bonus: float = 0.0

## +X% multiplied into every trap's effective targeting range.
var global_range_bonus: float = 0.0

## +X% added to the fire rate multiplier for every trap (more shots per second).
var global_fire_rate_bonus: float = 0.0

## +X% added to the crit chance roll for every trap.
var global_crit_chance_bonus: float = 0.0

## +X% added to the crit damage multiplier for every trap.
var global_crit_dmg_bonus: float = 0.0

## +X% multiplied into every kill bounty paid to the player.
var global_bucks_bonus: float = 0.0

## Each kill reduces the Infestation Level by this amount (Hazmat Protocol buff).
var infestation_heal_per_kill: float = 0.0

## Fraction by which all Bug Bucks upgrade costs are reduced (capped at 0.80).
## e.g. 0.10 means upgrades cost 10% less; 0.80 means they cost at most 80% less.
var upgrade_cost_discount: float = 0.0

## Tracks type-wide free upgrades awarded by level-up equipment cards.
## Structure: { trap_type_int: { stat_string: upgrade_count_int } }
## Arena applies these to all current and future traps of each type.
## Separate from Bug Bucks paid upgrades — each pool is capped at Trap.FREE_MAX_LEVEL.
var type_upgrade_queue: Dictionary = {}


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Resets all run state and begins a new run.
## Called by the hub screen when the player selects "Start New Job".
##
## entrance and exit are grid coordinates (column, row) assigned by the
## Arena when it is set up for the run.
func start_run(entrance: Vector2i, exit: Vector2i) -> void:
	entrance_cell = entrance
	exit_cell = exit
	current_wave = 0
	bug_bucks = STARTING_BUG_BUCKS
	infestation_level = 0.0
	selected_trap_type = 0
	early_wave_bonus_rate = 2
	# Reset experience and all campaign buffs so each run starts clean.
	current_xp = 0
	current_player_level = 0
	global_damage_bonus = 0.0
	global_range_bonus = 0.0
	global_fire_rate_bonus = 0.0
	global_crit_chance_bonus = 0.0
	global_crit_dmg_bonus = 0.0
	global_bucks_bonus = 0.0
	infestation_heal_per_kill = 0.0
	upgrade_cost_discount = 0.0
	type_upgrade_queue = {}
	current_phase = Phase.PLACING
	run_started.emit()
	bug_bucks_changed.emit(bug_bucks)
	infestation_changed.emit(infestation_level)
	xp_changed.emit(current_xp, exp_for_next_level())


## Ends the current run and returns the game to the hub.
## Called when infestation_level reaches 1.0.
func end_run() -> void:
	current_phase = Phase.RUN_OVER
	run_ended.emit()


## Adds amount to bug_bucks and notifies listeners.
func add_bug_bucks(amount: int) -> void:
	bug_bucks += amount
	bug_bucks_changed.emit(bug_bucks)


## Deducts amount from bug_bucks if affordable. Returns true on success.
func spend_bug_bucks(amount: int) -> bool:
	if bug_bucks < amount:
		return false
	bug_bucks -= amount
	bug_bucks_changed.emit(bug_bucks)
	return true


## Sets the active trap type and notifies listeners.
## type must be a valid Trap.TrapType int value.
func select_trap_type(type: int) -> void:
	selected_trap_type = type
	trap_type_selected.emit(type)


## Broadcasts the current countdown value to HUD and other listeners.
## Called once per second by Arena during the between-wave countdown.
func set_countdown(seconds: int) -> void:
	wave_countdown_changed.emit(seconds)


## Increases infestation_level by points / INFESTATION_MAX.
## Calls end_run() if the level reaches 1.0.
func add_infestation(points: float) -> void:
	infestation_level = minf(infestation_level + points / float(INFESTATION_MAX), 1.0)
	infestation_changed.emit(infestation_level)
	if infestation_level >= 1.0:
		end_run()


## Reduces the Infestation Level by amount (Hazmat Protocol campaign buff).
## Clamped to 0.0 — cannot go negative. Does not trigger end_run.
func heal_infestation(amount: float) -> void:
	infestation_level = maxf(0.0, infestation_level - amount)
	infestation_changed.emit(infestation_level)


# ---------------------------------------------------------------------------
# Experience methods
# ---------------------------------------------------------------------------

## Returns the XP required to advance from the current level to the next.
## Level 0 → 1 costs 12 XP. Each subsequent level costs 3% more (geometric
## curve), so the bar fills at a pace that scales smoothly with wave progress.
func exp_for_next_level() -> int:
	return ceili(12.0 * pow(1.03, float(current_player_level)))


## Awards XP for a kill. Emits xp_changed each time; emits level_up whenever
## the bar fills. Handles multiple level-ups in a single call (rare but
## possible if a high-value enemy is killed early with a large infestation value).
func add_experience(amount: int) -> void:
	if amount <= 0:
		return
	current_xp += amount
	var needed := exp_for_next_level()
	while current_xp >= needed:
		current_xp -= needed
		current_player_level += 1
		level_up.emit(current_player_level)
		needed = exp_for_next_level()
	xp_changed.emit(current_xp, needed)


# ---------------------------------------------------------------------------
# Campaign buff methods
# ---------------------------------------------------------------------------

## Returns the Bug Bucks upgrade cost after applying any active upgrade discount.
## Pass the base cost from UPGRADE_COSTS; the result is always at least 1 Buck.
## Used by Trap.gd's get_X_upgrade_cost() methods so the discount is reflected
## in both the UI display and the actual spend.
func apply_upgrade_discount(base_cost: int) -> int:
	if upgrade_cost_discount <= 0.0:
		return base_cost
	return maxi(1, roundi(float(base_cost) * (1.0 - upgrade_cost_discount)))


## Applies a campaign buff identified by buff_id with the given magnitude.
## Called by LevelUpScreen when the player selects a Campaign-type upgrade card.
##
## All bonuses are additive — picking the same buff twice doubles the bonus.
## The upgrade_cost_discount is capped at 0.80 (max 80% cheaper) to prevent
## free upgrades.
func apply_campaign_buff(buff_id: String, magnitude: float) -> void:
	match buff_id:
		"dmg_all":          global_damage_bonus      += magnitude
		"range_all":        global_range_bonus        += magnitude
		"firerate_all":     global_fire_rate_bonus    += magnitude
		"crit_chance_all":  global_crit_chance_bonus  += magnitude
		"crit_dmg_all":     global_crit_dmg_bonus     += magnitude
		"bucks_all":        global_bucks_bonus         += magnitude
		"infestation_heal": infestation_heal_per_kill  += magnitude
		"upgrade_discount": upgrade_cost_discount = minf(
				upgrade_cost_discount + magnitude, 0.80)
