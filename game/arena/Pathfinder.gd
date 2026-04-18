## Pathfinder.gd
## Calculates and maintains the shortest path from entrance to exit
## across the current grid layout using the A* algorithm.
##
## Recalculates automatically whenever the grid changes by listening to
## Grid's cell_changed signal. The result is stored as the current path
## and broadcast via path_updated so other systems (enemy movement, path
## visualisation) can react without polling.
##
## Also exposes can_place_at(), which simulates a placement and checks
## whether a valid path would still exist — used to reject placements
## that would completely block all routes.
##
## Movement is 4-directional (orthogonal only). Diagonal movement is
## excluded because it would allow pests to slip through diagonal trap
## gaps, undermining the maze-building strategy.
##
## Usage: instantiate as a child of Arena. Call initialize() with a
## reference to the Grid node before the first run begins.

extends Node

# Explicit dependency — preloading makes cross-script references visible
# at the top of the file rather than relying on the global class registry.
const Grid = preload("res://arena/Grid.gd")


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted after every path recalculation.
## new_path is an ordered Array[Vector2i] from entrance to exit.
## An empty array means no valid path currently exists.
signal path_updated(new_path: Array[Vector2i])


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _grid: Grid = null
var _current_path: Array[Vector2i] = []

# The four orthogonal directions used when evaluating neighbors.
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, -1),  # north
	Vector2i(0,  1),  # south
	Vector2i(-1, 0),  # west
	Vector2i( 1, 0),  # east
]


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Connects this Pathfinder to a Grid instance.
## Must be called by Arena before any run begins.
func initialize(grid: Grid) -> void:
	_grid = grid
	_grid.cell_changed.connect(_on_cell_changed)


# ---------------------------------------------------------------------------
# Public interface
# ---------------------------------------------------------------------------

## Returns a copy of the most recently calculated path.
## The path is ordered from entrance to exit as Vector2i grid coordinates.
## Returns an empty array if no valid path exists.
func get_current_path() -> Array[Vector2i]:
	return _current_path.duplicate()


## Finds the shortest path from start to end (defaults to GameState.exit_cell).
## Pass an explicit end to route an enemy toward a specific exit-gap row.
## Returns an empty array if no valid path exists from start.
func find_path_from(start: Vector2i, end: Vector2i = GameState.exit_cell) -> Array[Vector2i]:
	return _find_path(start, end)


## Returns true if blocking all cells in the given array would leave at least
## one valid path from entrance to exit.
##
## Call this before committing any trap or obstacle placement.
## Does not modify the grid — the check is purely hypothetical.
func can_place_at(cells: Array[Vector2i]) -> bool:
	var path := _find_path(
		GameState.entrance_cell,
		GameState.exit_cell,
		cells
	)
	return not path.is_empty()


## Returns true if a path exists from start to end with additional_blockers
## treated as impassable. Used by Arena to test entrance/exit cell pairs.
func can_reach(start: Vector2i, end: Vector2i, additional_blockers: Array[Vector2i] = []) -> bool:
	return not _find_path(start, end, additional_blockers).is_empty()


## Forces an immediate path recalculation.
## Normally triggered automatically via cell_changed, but can be called
## directly after entrance/exit positions are assigned at run start.
func recalculate() -> void:
	# Guard: do nothing if entrance and exit have not been set yet.
	# Vector2i.ZERO is the unset default — both being ZERO means setup
	# has not happened.
	if GameState.entrance_cell == Vector2i.ZERO \
			and GameState.exit_cell == Vector2i.ZERO:
		return

	_current_path = _find_path(GameState.entrance_cell, GameState.exit_cell)
	path_updated.emit(_current_path)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_cell_changed(_cell: Vector2i, _new_state: Grid.CellState) -> void:
	recalculate()


# ---------------------------------------------------------------------------
# A* implementation
# ---------------------------------------------------------------------------

## Finds the shortest path from start to end using A*.
##
## additional_blockers is a list of cells to treat as impassable for
## this search only — used by can_place_at() to simulate a hypothetical
## placement without modifying the grid.
##
## Returns an ordered Array[Vector2i] from start to end, or an empty
## array if no valid path exists.
func _find_path(
	start: Vector2i,
	end: Vector2i,
	additional_blockers: Array[Vector2i] = []
) -> Array[Vector2i]:

	# Open set: cells discovered but not yet fully evaluated.
	# Stored as an array; we scan for the lowest f_score each iteration.
	# For a 14x14 grid (196 cells max) this linear scan is fast enough.
	var open_set: Array[Vector2i] = [start]

	# Closed set: cells already fully evaluated. Stored as a Dictionary
	# for O(1) membership checks.
	var closed_set: Dictionary = {}

	# came_from[cell] = the cell we arrived from — used to reconstruct
	# the final path once we reach the end.
	var came_from: Dictionary = {}

	# g_score[cell] = cost of the cheapest known path from start to cell.
	# All moves cost 1 (uniform grid).
	var g_score: Dictionary = { start: 0.0 }

	# f_score[cell] = g_score[cell] + heuristic(cell, end).
	# This is the value A* uses to prioritise which cell to evaluate next.
	var f_score: Dictionary = { start: _heuristic(start, end) }

	while not open_set.is_empty():
		var current: Vector2i = _get_lowest_f_score(open_set, f_score)

		if current == end:
			return _reconstruct_path(came_from, end)

		open_set.erase(current)
		closed_set[current] = true

		for neighbor in _get_neighbors(current, additional_blockers):
			if closed_set.has(neighbor):
				continue

			# Every step costs 1, so tentative g is parent g + 1.
			var tentative_g: float = g_score.get(current, INF) + 1.0

			if tentative_g < g_score.get(neighbor, INF):
				# This is the best known route to neighbor — record it.
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + _heuristic(neighbor, end)

				if neighbor not in open_set:
					open_set.append(neighbor)

	# Open set exhausted with no path to end — no valid route exists.
	return []


## Returns passable orthogonal neighbors of cell that are not in
## additional_blockers and have not been removed by the closed set check
## in the caller. The closed set filter happens in the caller loop.
func _get_neighbors(
	cell: Vector2i,
	additional_blockers: Array[Vector2i]
) -> Array[Vector2i]:

	var neighbors: Array[Vector2i] = []
	for direction in DIRECTIONS:
		var neighbor := cell + direction
		if not _grid.is_in_bounds(neighbor):
			continue
		if not _grid.is_passable(neighbor):
			continue
		if neighbor in additional_blockers:
			continue
		neighbors.append(neighbor)
	return neighbors


## Manhattan distance heuristic — the minimum number of orthogonal steps
## from cell to target, ignoring all obstacles. This is admissible for
## 4-directional movement (never overestimates), which guarantees A*
## returns the shortest path.
func _heuristic(cell: Vector2i, target: Vector2i) -> float:
	return float(abs(cell.x - target.x) + abs(cell.y - target.y))


## Scans the open set and returns the cell with the lowest f_score.
## Ties are broken in favour of whichever cell appears first in the array.
func _get_lowest_f_score(
	open_set: Array[Vector2i],
	f_score: Dictionary
) -> Vector2i:

	var best_cell: Vector2i = open_set[0]
	var best_score: float = f_score.get(best_cell, INF)

	for cell in open_set:
		var score: float = f_score.get(cell, INF)
		if score < best_score:
			best_score = score
			best_cell = cell

	return best_cell


## Walks came_from backwards from end to start to build the ordered path.
func _reconstruct_path(came_from: Dictionary, end: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [end]
	var current: Vector2i = end

	while came_from.has(current):
		current = came_from[current]
		path.push_front(current)

	return path
