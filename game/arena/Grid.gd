## Grid.gd
## Represents the 14x14 arena grid.
##
## Owns the state of every cell — what occupies it and whether it can be
## traversed by pests or built on by the player. Grid state is the single
## source of truth for the arena layout.
##
## Does not handle pathfinding — that belongs to Pathfinder.gd.
## Does not handle rendering — that belongs to Arena.gd.
##
## Usage: instantiate as a child of Arena. Call setup_run() at the start
## of each run to reset the grid and assign entrance/exit positions.

extends Node


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## The number of cells along each side of the square grid.
## Subject to change via playtesting — adjust here and everything scales.
const GRID_SIZE: int = 30

## World-space size of one grid cell in metres.
## Changing this scales the entire arena uniformly.
const CELL_SIZE: float = 1.0


# ---------------------------------------------------------------------------
# Cell state enum
#
# Each cell holds exactly one of these states. Passability and buildability
# are derived from state — see is_passable() and is_buildable() below.
# ---------------------------------------------------------------------------

enum CellState {
	EMPTY,     # Nothing here — passable by pests, available for trap placement
	TRAP,      # Player-placed trap — impassable, can be sold or upgraded
	OBSTACLE,  # Arena Evolution obstacle — impassable, cannot be removed by player
	WALL,      # Permanent arena border wall — impassable, never buildable or removable
	ENTRANCE,  # Pest entry point (gap in left wall) — passable, buildable with path check
	EXIT,      # Pest destination (gap in right wall) — passable, buildable with path check
}


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted whenever a cell's state changes.
## The Pathfinder connects here to know when to recalculate the path.
signal cell_changed(cell: Vector2i, new_state: CellState)


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

# Internal storage indexed as _cells[row][col].
# Row 0 is the top of the grid; col 0 is the left.
var _cells: Array = []


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_initialize_cells()


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Resets the entire grid to EMPTY and assigns entrance and exit cells.
## Call this at the start of every run before spawning anything.
func setup_run(entrance: Vector2i, exit: Vector2i) -> void:
	_initialize_cells()
	set_cell(entrance, CellState.ENTRANCE)
	set_cell(exit, CellState.EXIT)


# ---------------------------------------------------------------------------
# Cell queries
# ---------------------------------------------------------------------------

## Returns the current state of a cell.
## Assumes the cell is in bounds — call is_in_bounds() first if unsure.
func get_cell(cell: Vector2i) -> CellState:
	return _cells[cell.y][cell.x] as CellState


## Returns true if the cell is within the grid boundaries.
func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GRID_SIZE \
		and cell.y >= 0 and cell.y < GRID_SIZE


## Returns true if pests can move through this cell.
## EMPTY, ENTRANCE, and EXIT are passable. TRAP and OBSTACLE are not.
func is_passable(cell: Vector2i) -> bool:
	var state: CellState = get_cell(cell)
	return state == CellState.EMPTY \
		or state == CellState.ENTRANCE \
		or state == CellState.EXIT


## Returns true if the player is allowed to place a trap on this cell.
## ENTRANCE and EXIT cells are buildable so traps can narrow the gap,
## but Arena enforces that at least one opening row must remain clear.
func is_buildable(cell: Vector2i) -> bool:
	var state := get_cell(cell)
	return state == CellState.EMPTY \
		or state == CellState.ENTRANCE \
		or state == CellState.EXIT


# ---------------------------------------------------------------------------
# Cell mutation
# ---------------------------------------------------------------------------

## Sets a cell to the given state and emits cell_changed.
## This is the only way state should be written — do not access _cells directly.
func set_cell(cell: Vector2i, state: CellState) -> void:
	_cells[cell.y][cell.x] = state
	cell_changed.emit(cell, state)


## Places a player trap on the given cell.
## Assumes the cell is buildable — call is_buildable() before calling this.
func place_trap(cell: Vector2i) -> void:
	set_cell(cell, CellState.TRAP)


## Removes a player trap and returns the cell to EMPTY.
## Assumes the cell currently holds a TRAP.
func remove_trap(cell: Vector2i) -> void:
	set_cell(cell, CellState.EMPTY)


## Places an Arena Evolution obstacle on the given cell.
## If the cell holds a TRAP, the trap is destroyed with no refund —
## that responsibility belongs to the caller (ArenaEvolution).
func place_obstacle(cell: Vector2i) -> void:
	set_cell(cell, CellState.OBSTACLE)


## Removes an Arena Evolution obstacle — used by the rare removal roll.
## Assumes the cell currently holds an OBSTACLE.
func remove_obstacle(cell: Vector2i) -> void:
	set_cell(cell, CellState.EMPTY)


# ---------------------------------------------------------------------------
# Bulk queries — used by Pathfinder and Arena Evolution
# ---------------------------------------------------------------------------

## Returns all cells currently holding an OBSTACLE.
## Used by Arena Evolution when selecting a random obstacle to remove.
func get_obstacle_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			if _cells[row][col] == CellState.OBSTACLE:
				result.append(Vector2i(col, row))
	return result


## Returns all cells that pests can currently move through.
## Used by Pathfinder to build the navigation graph.
func get_passable_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			var cell := Vector2i(col, row)
			if is_passable(cell):
				result.append(cell)
	return result


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Fills the entire grid with EMPTY cells.
## Called at startup and at the beginning of each run.
func _initialize_cells() -> void:
	_cells.clear()
	for row in range(GRID_SIZE):
		var row_data: Array[int] = []
		row_data.resize(GRID_SIZE)
		row_data.fill(CellState.EMPTY)
		_cells.append(row_data)
