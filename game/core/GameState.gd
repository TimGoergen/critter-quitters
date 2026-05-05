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

## Emitted when the player skips the countdown and receives a coin bonus for the remaining time.
signal early_wave_bonus_awarded(coins: int)

## Emitted when the player picks a different trap type to place.
## type is an int matching the Trap.TrapType enum — stored as int here to
## avoid importing Trap.gd into GameState and creating a circular dependency.
signal trap_type_selected(type: int)


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

## Bug Bucks awarded per second remaining when the player clicks Send Wave Early.
## Default 2; future meta-upgrades can increase this between runs.
var early_wave_bonus_rate: int = 2


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
	current_phase = Phase.PLACING
	run_started.emit()
	bug_bucks_changed.emit(bug_bucks)
	infestation_changed.emit(infestation_level)


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
func add_infestation(points: int) -> void:
	infestation_level = minf(infestation_level + float(points) / float(INFESTATION_MAX), 1.0)
	infestation_changed.emit(infestation_level)
	if infestation_level >= 1.0:
		end_run()
