class_name GridModel
extends RefCounted

## Pure-logic model of the sphere field. No rendering, no Godot nodes — just the
## rules, so it can be unit-tested headlessly. Views reflect this; this is the
## single source of truth.
##
## Cells are stored sparsely: Dictionary[Vector2i] -> int colour id.
##   colour >= 0 : a breakable (poppable) coloured sphere
##   colour == BLACK : an unbreakable obstacle (never matches; still counts as a
##                     neighbour, so it keeps adjacent spheres from being orphans)
##   absent key   : empty cell
##
## Coordinate system: see Hex. The field is walled on top (row 0) and sides
## (columns [0, width)); the bottom is open. Bubbles only enter by colliding with
## the cluster — there is no top anchor and no row downshift.

const BLACK := -1

var cells: Dictionary = {}        # Vector2i -> int
var width: int = 11               # columns [0, width)
var num_colors: int = 5
var danger_row: int = 12          # lose if any sphere occupies row >= this
var rng := RandomNumberGenerator.new()


## Result of resolving an attached sphere, returned to the controller so it can
## drive presentation (and decide whether to grow the field).
class AttachResult:
	var popped: Array[Vector2i] = []      # cells removed by the match
	var orphaned: Array[Vector2i] = []    # cells removed because they had no neighbours
	var did_pop: bool = false             # true if a 3+ match cleared


# --- queries ------------------------------------------------------------------

func is_occupied(cell: Vector2i) -> bool:
	return cells.has(cell)

func is_empty(cell: Vector2i) -> bool:
	return not cells.has(cell)

func count_colored() -> int:
	var n := 0
	for c in cells.values():
		if c >= 0:
			n += 1
	return n

func has_neighbor(cell: Vector2i) -> bool:
	for nb in Hex.neighbors(cell):
		if cells.has(nb):
			return true
	return false

## The distinct breakable colours currently on the board, ascending. The shooter
## uses this so it never queues a colour the player can no longer match — a colour
## eliminated from the field must drop out of the gun.
func present_colors() -> Array[int]:
	var seen := {}
	for c in cells.values():
		if c >= 0:
			seen[c] = true
	var out: Array[int] = []
	out.assign(seen.keys())
	out.sort()
	return out


# --- core rules ---------------------------------------------------------------

## Flood-fill the connected same-colour group containing `start`. Black/empty
## never match. Returns [] if start is not a breakable sphere.
func match_group(start: Vector2i) -> Array[Vector2i]:
	if not cells.has(start):
		return []
	var target: int = cells[start]
	if target < 0:
		return []
	var seen := {start: true}
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var cell: Vector2i = stack.pop_back()
		for nb in Hex.neighbors(cell):
			if seen.has(nb):
				continue
			if cells.get(nb, -999) == target:
				seen[nb] = true
				stack.append(nb)
	var group: Array[Vector2i] = []
	group.assign(seen.keys())
	return group

## Orphans = BREAKABLE cells with NO neighbour at all (any neighbour, breakable or
## unbreakable, keeps a sphere anchored). A lone sphere touching a black sphere is
## NOT an orphan. Black (unbreakable) spheres are never orphaned — they can and
## should stay on the field even when isolated. Removing a zero-neighbour sphere
## can't orphan anything else, so one pass is complete.
func find_orphans() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in cells:
		if cells[cell] < 0:
			continue  # black/unbreakable spheres are never swept
		if not has_neighbor(cell):
			out.append(cell)
	return out

## Place a sphere and resolve the match. A 3+ same-colour cluster is destroyed,
## then any orphans created by that destruction are swept. On a dud (no match)
## the caller grows the field instead.
func attach(cell: Vector2i, color: int) -> AttachResult:
	cells[cell] = color
	var res := AttachResult.new()
	var group := match_group(cell)
	if group.size() >= 3:
		res.did_pop = true
		res.popped = group
		for c in group:
			cells.erase(c)
		res.orphaned = find_orphans()
		for c in res.orphaned:
			cells.erase(c)
	return res

## Grow the field on a dud shot (cellular fill, no downshift): every empty cell
## inside the walls with 1-4 BREAKABLE neighbours spawns a sphere whose colour is
## copied from a random one of those neighbours. Cells with 5-6 breakable
## neighbours stay empty (protected pockets). Computed simultaneously from a
## pre-growth snapshot so new spheres don't cascade within one step.
func grow() -> void:
	var snapshot := cells.duplicate()
	var candidates := {}
	for cell in snapshot:
		if snapshot[cell] < 0:
			continue  # only breakable spheres seed growth
		for nb in Hex.neighbors(cell):
			if not snapshot.has(nb) and nb.x >= 0 and nb.x < width and nb.y >= 0:
				candidates[nb] = true
	for cell in candidates:
		var colors: Array[int] = []
		for nb in Hex.neighbors(cell):
			if snapshot.has(nb) and snapshot[nb] >= 0:
				colors.append(snapshot[nb])
		if colors.size() >= 1 and colors.size() <= 4:
			cells[cell] = colors[rng.randi_range(0, colors.size() - 1)]

## Field reshuffle: every breakable sphere takes a new random colour; black stays.
## Triggered when a shot misses entirely and exits the bottom of the field.
func randomize_colors() -> void:
	for cell in cells.keys():
		if cells[cell] >= 0:
			cells[cell] = rng.randi_range(0, num_colors - 1)

## Procedurally fill a fresh free-play board: every cell in the first `rows` rows
## takes a random breakable colour in [0, num_colors), then a fraction of cells are
## overwritten with black obstacles. Uses this model's `rng`, so seeding `rng`
## reproduces the board (free play randomizes it; tests can pin a seed).
func fill_random(rows: int, black_fraction: float) -> void:
	for r in range(rows):
		for c in range(width):
			cells[Vector2i(c, r)] = rng.randi() % num_colors
	var black_count := int(round(rows * width * black_fraction))
	for _i in range(black_count):
		cells[Vector2i(rng.randi() % width, rng.randi() % rows)] = BLACK


# --- win / lose ---------------------------------------------------------------

func is_won() -> bool:
	return count_colored() == 0

func is_lost() -> bool:
	for cell in cells.keys():
		if cell.y >= danger_row:
			return true
	return false

## The deepest occupied row (largest cell.y), or -1 on an empty board. Counts black
## (unbreakable) cells too, since they sink toward the lose line like any sphere and
## is_lost() reckons with them as well.
func max_row() -> int:
	var m := -1
	for cell in cells.keys():
		if cell.y > m:
			m = cell.y
	return m

## Rows of headroom before the field crosses the lose line: danger_row minus the
## deepest occupied row. 2 -> the slow heartbeat, 1 -> the fast one, <= 0 -> lost.
## A large value (empty/shallow board) means safe. Drives the danger audio.
func rows_to_danger() -> int:
	return danger_row - max_row()
