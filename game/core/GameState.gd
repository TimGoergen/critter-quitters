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


# ---------------------------------------------------------------------------
# Constants
#
# Numeric values marked TODO are placeholders — final values come from
# playtesting once the full game loop is in place.
# ---------------------------------------------------------------------------

## Starting currency given to the player at the beginning of every run.
## Increased by business upgrades purchased with Service Fees.
## TODO: tune via playtesting; increase via meta upgrades
const STARTING_BUG_BUCKS: int = 50


# ---------------------------------------------------------------------------
# Run state
#
# These values are reset at the start of each run by start_run().
# Read them freely; mutate them only through the methods below or through
# the systems that own each value (e.g. economy system owns bug_bucks).
# ---------------------------------------------------------------------------

## Current phase of the game. Setting this property emits phase_changed.
var current_phase: Phase = Phase.HUB:
	set(value):
		current_phase = value
		phase_changed.emit(value)

## The wave the player is currently on. Starts at 0; incremented to 1
## when the first wave begins.
var current_wave: int = 0

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
	current_phase = Phase.PLACING
	run_started.emit()


## Ends the current run and returns the game to the hub.
## Called when infestation_level reaches 1.0.
func end_run() -> void:
	current_phase = Phase.RUN_OVER
	run_ended.emit()
