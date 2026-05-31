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

## Emitted whenever service_fees changes (purchase or run-end award).
signal service_fees_changed(new_amount: int)

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

## Emitted once per run when TrapSelectionScreen confirms the player's choices.
signal unlocked_traps_set(types: Array[int])
signal unlocked_boosts_set(types: Array[int])


# ---------------------------------------------------------------------------
# Constants
#
# Numeric values marked TODO are placeholders — final values come from
# playtesting once the full game loop is in place.
# ---------------------------------------------------------------------------

## Starting currency given to the player at the beginning of every run.
## Increased by business upgrades purchased with Service Fees.
## 75 BB = exactly 3 Snap Traps — tight by design; forces immediate strategic decisions.
const STARTING_BUG_BUCKS: int = 100

## Total infestation points that fill the bar to 1.0.
## TODO: tune via playtesting
const INFESTATION_MAX: int = 20

## All permanent upgrades available for purchase with Service Fees.
## tier_costs: SF cost to buy tier 1, then tier 2 (independent, not cumulative).
## tier_effects: short label shown on each tier's purchase button.
const PERMANENT_UPGRADE_DEFS: Array = [
	# --- Equipment ---
	{
		"id": "reinforced_mechanisms", "category": "Equipment",
		"name": "Reinforced Mechanisms",
		"desc": "All traps start each run with bonus base damage.",
		"tier_costs": [4, 8], "tier_effects": ["+15% Damage", "+30% Damage"],
	},
	{
		"id": "extended_range", "category": "Equipment",
		"name": "Extended Range",
		"desc": "All traps start each run with a wider targeting radius.",
		"tier_costs": [3, 6], "tier_effects": ["+10% Range", "+20% Range"],
	},
	{
		"id": "tuned_triggers", "category": "Equipment",
		"name": "Tuned Triggers",
		"desc": "Active traps start each run firing more often.",
		"tier_costs": [3, 6], "tier_effects": ["+10% Fire Rate", "+20% Fire Rate"],
	},
	{
		"id": "wider_selection", "category": "Equipment",
		"name": "Wider Selection",
		"desc": "Gear selection at run start offers more options.",
		"tier_costs": [5, 10], "tier_effects": ["4 offered, pick 2", "4 offered, pick 3"],
	},
	# --- Business ---
	{
		"id": "starting_capital", "category": "Business",
		"name": "Starting Capital",
		"desc": "Begin each run with more Bug Bucks.",
		"tier_costs": [4, 8], "tier_effects": ["+25 Bug Bucks", "+50 Bug Bucks"],
	},
	{
		"id": "hazard_insurance", "category": "Business",
		"name": "Hazard Insurance",
		"desc": "The infestation threshold is higher before the run ends.",
		"tier_costs": [5, 10], "tier_effects": ["+10% Threshold", "+20% Threshold"],
	},
	{
		"id": "salvage_value", "category": "Business",
		"name": "Salvage Value",
		"desc": "Selling placed units returns a higher refund.",
		"tier_costs": [4, 8], "tier_effects": ["+5% Sell Value", "+10% Sell Value"],
	},
	{
		"id": "bulk_discount", "category": "Business",
		"name": "Bulk Discount",
		"desc": "All Bug Bucks upgrade costs are reduced.",
		"tier_costs": [5, 10], "tier_effects": ["−5% Upgrade Costs", "−10% Upgrade Costs"],
	},
	{
		"id": "field_experience", "category": "Business",
		"name": "Field Experience",
		"desc": "Earn more XP per kill, reaching level-ups faster.",
		"tier_costs": [4, 8], "tier_effects": ["+15% XP per Kill", "+30% XP per Kill"],
	},
]


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

## Set true by the "Start in Dev Mode" button on StartScreen so Arena knows to
## show the DebugStartDialog instead of bypassing it with default values.
var dev_mode: bool = false

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
var selected_trap_type: int = 0

## Trap types available for purchase this run. Set by TrapSelectionScreen at run start.
## Empty until the selection is confirmed — HUD hides all trap rows until then.
var unlocked_trap_types: Array[int] = []

## Boost types available for purchase this run. Set alongside unlocked_trap_types.
## Empty until the selection is confirmed — HUD hides all boost rows until then.
var unlocked_boost_types: Array[int] = []

## Count of each trap/boost type currently placed on the grid.
## Key is the type int (matches Trap.TrapType / BoostUnit.BoostType).
## Used by supply pricing: each placed unit raises the cost of the next.
var trap_placed_counts:  Dictionary = {}
var boost_placed_counts: Dictionary = {}

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

## XP multiplier applied to every kill reward (Field Experience upgrade).
## e.g. 0.15 means each kill awards 15% more XP. Reset each run then set
## from permanent upgrades.
var global_xp_bonus: float = 0.0

## Fraction added to the effective infestation threshold (Hazard Insurance).
## e.g. 0.10 means the bar must fill 110% of INFESTATION_MAX to end the run.
var infestation_max_bonus: float = 0.0

## Additive bonus to the sell refund fraction (Salvage Value).
## Applied on top of each unit type's base sell fraction.
var sell_value_bonus: float = 0.0

## Wider Selection upgrade tier for the current session. 0 = 3 offered / pick 2.
## 1 = 4 offered / pick 2. 2 = 4 offered / pick 3.
var wider_selection_tier: int = 0


# ---------------------------------------------------------------------------
# Persistent state — survives across runs; loaded at startup, saved on change.
# ---------------------------------------------------------------------------

## Accumulated Service Fees across all runs. Spent on permanent upgrades.
var service_fees: int = 0

## Service Fees awarded for the most recent completed run (= XP level reached).
## Set by award_run_service_fees() so the hub screen can display it.
var service_fees_last_run: int = 0

## Purchased tier per permanent upgrade (0 = not purchased, 1 = tier 1, 2 = tier 2).
## Keys match the "id" field in PERMANENT_UPGRADE_DEFS.
var permanent_upgrades: Dictionary = {
	"reinforced_mechanisms": 0, "extended_range": 0, "tuned_triggers": 0,
	"wider_selection": 0, "starting_capital": 0, "hazard_insurance": 0,
	"salvage_value": 0, "bulk_discount": 0, "field_experience": 0,
}


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
	selected_trap_type    = 0
	unlocked_trap_types   = []
	unlocked_boost_types  = []
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
	global_xp_bonus = 0.0
	infestation_max_bonus = 0.0
	sell_value_bonus = 0.0
	wider_selection_tier = 0
	type_upgrade_queue  = {}
	trap_placed_counts  = {}
	boost_placed_counts = {}
	# Apply permanent upgrades on top of the clean slate. Starting Capital
	# bonus is added here after bug_bucks is already set to STARTING_BUG_BUCKS.
	_apply_permanent_upgrade_bonuses()
	current_phase = Phase.PLACING
	run_started.emit()
	bug_bucks_changed.emit(bug_bucks)
	infestation_changed.emit(infestation_level)
	xp_changed.emit(current_xp, exp_for_next_level())


## Ends the current run and returns the game to the hub.
## Called when infestation_level reaches 1.0.
func end_run() -> void:
	current_phase = Phase.RUN_OVER
	award_run_service_fees()
	run_ended.emit()


## Unlocks a single trap type mid-run (e.g. chosen from a level-up card).
## No-ops if already unlocked. Emits unlocked_traps_set so HUD updates.
func unlock_trap(trap_type: int) -> void:
	if trap_type not in unlocked_trap_types:
		unlocked_trap_types.append(trap_type)
		unlocked_traps_set.emit(unlocked_trap_types)


## Unlocks a single boost type mid-run (e.g. chosen from a level-up card).
## No-ops if already unlocked. Emits unlocked_boosts_set so HUD updates.
func unlock_boost(boost_type: int) -> void:
	if boost_type not in unlocked_boost_types:
		unlocked_boost_types.append(boost_type)
		unlocked_boosts_set.emit(unlocked_boost_types)


## Records the trap and boost types chosen in TrapSelectionScreen.
## Selects the first unlocked trap as the active placement type and
## notifies listeners (primarily HUD) so they can show the right rows.
func set_unlocked_loadout(trap_types: Array[int], boost_types: Array[int]) -> void:
	unlocked_trap_types  = trap_types.duplicate()
	unlocked_boost_types = boost_types.duplicate()
	if not unlocked_trap_types.is_empty():
		selected_trap_type = unlocked_trap_types[0]
		trap_type_selected.emit(selected_trap_type)
	unlocked_traps_set.emit(unlocked_trap_types)
	unlocked_boosts_set.emit(unlocked_boost_types)


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


## Increases infestation_level by points / effective_max.
## The effective max is INFESTATION_MAX scaled by the Hazard Insurance bonus,
## so higher insurance tiers require more infestation to end the run.
## Calls end_run() if the level reaches 1.0.
func add_infestation(points: float) -> void:
	var effective_max := float(INFESTATION_MAX) * (1.0 + infestation_max_bonus)
	infestation_level = clampf(infestation_level + points / effective_max, 0.0, 1.0)
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
## Level 0 → 1 costs 20 XP — calibrated so the player levels up mid-wave 2
## with wave 1 = 10 Gnats × 1 XP each, satisfying the "every 2–4 waves" target.
## Each subsequent level costs 3% more (geometric curve).
func exp_for_next_level() -> int:
	return ceili(20.0 * pow(1.03, float(current_player_level)))


## Awards XP for a kill. Applies the Field Experience bonus before adding.
## Emits xp_changed each time; emits level_up whenever the bar fills.
func add_experience(amount: int) -> void:
	if amount <= 0:
		return
	var boosted := ceili(float(amount) * (1.0 + global_xp_bonus))
	current_xp += boosted
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
## Returns how many traps of the given type are currently placed on the grid.
func get_trap_placed_count(trap_type: int) -> int:
	return trap_placed_counts.get(trap_type, 0)


## Returns how many boosts of the given type are currently placed on the grid.
func get_boost_placed_count(boost_type: int) -> int:
	return boost_placed_counts.get(boost_type, 0)


## Called by Arena immediately after placing a trap. Increments the supply count.
func on_trap_placed(trap_type: int) -> void:
	trap_placed_counts[trap_type] = trap_placed_counts.get(trap_type, 0) + 1


## Called by Arena immediately after removing a trap. Decrements the supply count.
func on_trap_removed(trap_type: int) -> void:
	trap_placed_counts[trap_type] = maxi(0, trap_placed_counts.get(trap_type, 0) - 1)


## Called by Arena immediately after placing a boost.
func on_boost_placed(boost_type: int) -> void:
	boost_placed_counts[boost_type] = boost_placed_counts.get(boost_type, 0) + 1


## Called by Arena immediately after removing a boost.
func on_boost_removed(boost_type: int) -> void:
	boost_placed_counts[boost_type] = maxi(0, boost_placed_counts.get(boost_type, 0) - 1)


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


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_load_persistent()


# ---------------------------------------------------------------------------
# Service Fees & permanent upgrades
# ---------------------------------------------------------------------------

## Awards Service Fees at run end. The amount equals the XP level reached,
## so longer runs earn more. Persists immediately to the save file.
## Returns the number of fees awarded so the hub screen can display it.
func award_run_service_fees() -> int:
	service_fees_last_run = current_player_level
	service_fees += service_fees_last_run
	service_fees_changed.emit(service_fees)
	_save_persistent()
	return service_fees_last_run


## Returns the purchased tier (0, 1, or 2) for the given upgrade id.
func get_upgrade_tier(upgrade_id: String) -> int:
	return permanent_upgrades.get(upgrade_id, 0)


## Returns true if the player can afford the next tier of the given upgrade.
func can_purchase_upgrade(upgrade_id: String) -> bool:
	var tier := get_upgrade_tier(upgrade_id)
	if tier >= 2:
		return false
	for def: Dictionary in PERMANENT_UPGRADE_DEFS:
		if def["id"] == upgrade_id:
			return service_fees >= def["tier_costs"][tier]
	return false


## Purchases the next tier of the given upgrade, deducting the SF cost.
## Returns true on success, false if already maxed or unaffordable.
func purchase_upgrade(upgrade_id: String) -> bool:
	if not can_purchase_upgrade(upgrade_id):
		return false
	var tier := get_upgrade_tier(upgrade_id)
	for def: Dictionary in PERMANENT_UPGRADE_DEFS:
		if def["id"] == upgrade_id:
			service_fees -= def["tier_costs"][tier]
			permanent_upgrades[upgrade_id] = tier + 1
			service_fees_changed.emit(service_fees)
			_save_persistent()
			return true
	return false


## Applies all purchased permanent upgrade effects to run-scoped state.
## Called at the end of start_run() after all vars are reset to zero, so
## permanent bonuses form the baseline that campaign cards then stack on top of.
func _apply_permanent_upgrade_bonuses() -> void:
	var t: int

	t = permanent_upgrades.get("reinforced_mechanisms", 0)
	global_damage_bonus    = ([0.0, 0.15, 0.30] as Array)[t]

	t = permanent_upgrades.get("extended_range", 0)
	global_range_bonus     = ([0.0, 0.10, 0.20] as Array)[t]

	t = permanent_upgrades.get("tuned_triggers", 0)
	global_fire_rate_bonus = ([0.0, 0.10, 0.20] as Array)[t]

	wider_selection_tier   = permanent_upgrades.get("wider_selection", 0)

	t = permanent_upgrades.get("starting_capital", 0)
	bug_bucks             += ([0, 25, 50] as Array)[t]

	t = permanent_upgrades.get("hazard_insurance", 0)
	infestation_max_bonus  = ([0.0, 0.10, 0.20] as Array)[t]

	t = permanent_upgrades.get("salvage_value", 0)
	sell_value_bonus       = ([0.0, 0.05, 0.10] as Array)[t]

	t = permanent_upgrades.get("bulk_discount", 0)
	upgrade_cost_discount  = ([0.0, 0.05, 0.10] as Array)[t]

	t = permanent_upgrades.get("field_experience", 0)
	global_xp_bonus        = ([0.0, 0.15, 0.30] as Array)[t]


func _save_persistent() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "service_fees", service_fees)
	for upgrade_id: String in permanent_upgrades.keys():
		cfg.set_value("upgrades", upgrade_id, permanent_upgrades[upgrade_id])
	cfg.save("user://save.cfg")


func _load_persistent() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://save.cfg") != OK:
		return
	service_fees = cfg.get_value("meta", "service_fees", 0)
	for upgrade_id: String in permanent_upgrades.keys():
		permanent_upgrades[upgrade_id] = cfg.get_value("upgrades", upgrade_id, 0)


# ---------------------------------------------------------------------------
# Display formatting
# ---------------------------------------------------------------------------

## Formats a Bug Bucks integer into a compact, human-readable string.
##
## Below 10,000  — exact integer, no suffix:  "1", "115", "9995"
## At 10,000+    — one decimal place with a unit suffix, decimal dropped when .0:
##                 "10K", "39.2K", "1.5M", "2.3B", "1.2T", "9.1Q"
##
## All UI code should call this function rather than formatting amounts
## directly, so the display rule is defined in exactly one place.
static func format_bucks(amount: int) -> String:
	# Below the compaction threshold — exact display.
	if amount < 10_000:
		return str(amount)

	# Suffix table: [divisor, suffix letter].
	# Checked largest-first so we always select the correct unit without
	# having to re-examine boundaries after the match.
	const THRESHOLDS := [
		[1_000_000_000_000_000, "Q"],  # quadrillion
		[1_000_000_000_000,     "T"],  # trillion
		[1_000_000_000,         "B"],  # billion
		[1_000_000,             "M"],  # million
		[1_000,                 "K"],  # thousand
	]

	for entry in THRESHOLDS:
		var divisor: int   = entry[0]
		var suffix: String = entry[1]
		if amount >= divisor:
			# Compute via integer math to avoid floating-point rounding artefacts.
			# Example: 39176 → round(39.176 × 10) = 392 → whole=39, decimal=2 → "39.2k"
			var tenths: int  = roundi(float(amount) / float(divisor) * 10.0)
			var whole: int   = tenths / 10
			var decimal: int = tenths % 10
			if decimal == 0:
				return "%d%s" % [whole, suffix]
			return "%d.%d%s" % [whole, decimal, suffix]

	# Unreachable: every integer >= 10,000 matches the "k" threshold above.
	return str(amount)
