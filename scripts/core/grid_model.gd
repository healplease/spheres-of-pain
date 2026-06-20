class_name GridModel
extends RefCounted

## Pure-logic model of the sphere field. No rendering, no Godot nodes — just the
## rules, so it can be unit-tested headlessly. Views reflect this; this is the
## single source of truth.
##
## Cells are stored sparsely: Dictionary[Vector2i] -> int colour id.
##   colour >= 0 : a breakable (poppable) coloured sphere
##   colour < 0  : an indestructible sphere (never matches, never orphaned, never
##                 grown/recoloured, excluded from the win count and the gun, yet
##                 still anchors neighbours and sinks toward the danger line). Three
##                 kinds, distinguished only by the view + a couple of rules:
##                   BLACK  (-1) : inert obstacle
##                   SPIN   (-2) : rotates its breakable neighbours' colours on a land
##                   BOUNCE (-3) : a fired sphere reflects off it (see ShotSimulator)
##   absent key   : empty cell
##
## Coordinate system: see Hex. The field is walled on top (row 0) and sides
## (columns [0, width)); the bottom is open. Bubbles only enter by colliding with
## the cluster — there is no top anchor and no row downshift.

const BLACK := -1
const SPIN := -2
const BOUNCE := -3

## Procedural free-play generation tuning (see fill_random). The bottom band of the
## field is always left empty as the descent's headroom, and a share of the fillable
## cells above it is left empty too, so a generated board has gaps rather than a
## solid slab.
const GEN_EMPTY_BOTTOM_MIN := 5  # fewest empty rows left at the bottom of the field
const GEN_EMPTY_BOTTOM_MAX := 7  # most empty rows left at the bottom of the field
const GEN_HOLE_CHANCE := 0.18  # per-cell chance a fillable cell is left empty (a hole)

## Sentinel for a vacant track slot during a spin rotation. Outside every real cell
## value (breakable >= 0, specials -1/-2/-3) so it can stand in for "empty" while the
## ring is permuted. NEVER stored in `cells` — spin_step() erases a cell instead.
const EMPTY := -100

var cells: Dictionary = {}  # Vector2i -> int
var width: int = 11  # columns [0, width)
var num_colors: int = 5
var danger_row: int = 12  # lose if any sphere occupies row >= this
var rng := RandomNumberGenerator.new()


## Any non-breakable sphere — the single invariant every rule keys off (never
## `== BLACK`), so SPIN/BOUNCE inherit black's match/orphan/grow/win behaviour.
static func is_indestructible(v: int) -> bool:
	return v < 0


## Result of resolving an attached sphere, returned to the controller so it can
## drive presentation (and decide whether to grow the field).
class AttachResult:
	var popped: Array[Vector2i] = []  # cells removed by the match
	var orphaned: Array[Vector2i] = []  # cells removed because they had no neighbours
	var did_pop: bool = false  # true if a 3+ match cleared


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
	# Iterate the direction deltas directly (Hex.neighbors would allocate an array
	# per call; this is on the orphan-sweep hot path).
	for delta in Hex.DIRS[cell.y & 1]:
		if cells.has(cell + delta):
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
		for delta in Hex.DIRS[cell.y & 1]:
			var nb: Vector2i = cell + delta
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
		for delta in Hex.DIRS[cell.y & 1]:
			var nb: Vector2i = cell + delta
			if not snapshot.has(nb) and nb.x >= 0 and nb.x < width and nb.y >= 0:
				candidates[nb] = true
	for cell in candidates:
		var colors: Array[int] = []
		for delta in Hex.DIRS[cell.y & 1]:
			var nb: Vector2i = cell + delta
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


## Rotate every SPIN sphere's ring of breakable/empty "track" neighbours one slot
## counter-clockwise (spheres physically move; the ring compacts over indestructibles/walls).
## Spins resolve one at a time in reading order, each ring read fully before it writes; returns
## the net hops ({from, to, color}) as a clean permutation for the view to animate.
## See docs/architecture/spin.md for the full rationale (track cells, ordering, CCW direction).
func spin_step() -> Array[Dictionary]:
	var spins: Array[Vector2i] = []
	for cell in cells:
		if cells[cell] == SPIN:
			spins.append(cell)
	# Reading order: top-to-bottom (row), then left-to-right (column) — deterministic,
	# and the natural order a player scans the board.
	spins.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	# origin[current cell] = the cell the sphere now there started in, so after several
	# overlapping rotations we can emit one net hop per sphere. Only touched cells appear.
	var origin := {}
	for spin in spins:
		var ring: Array[Vector2i] = []
		var contents: Array[int] = []
		var origins: Array = []  # parallel to ring; the origin of each slot's sphere, or null
		for delta in Hex.DIRS[spin.y & 1]:
			var nb: Vector2i = spin + delta
			if nb.x < 0 or nb.x >= width or nb.y < 0:
				continue  # out of bounds (walls) -> excluded; ring compacts over it
			var occupied := cells.has(nb)
			if occupied and cells[nb] < 0:
				continue  # indestructible -> excluded; ring compacts over it
			ring.append(nb)
			contents.append(cells[nb] if occupied else EMPTY)
			origins.append(origin.get(nb, nb) if occupied else null)
		var n := ring.size()
		if n < 2:
			continue  # 0 or 1 track cell -> rotation is a no-op
		# Rotate contents (and the origins riding with them) one slot CCW: slot i's
		# content moves to slot i+1. Read above is complete, so writing here is safe.
		for i in range(n):
			var dest: Vector2i = ring[i]
			var src := (i - 1 + n) % n
			if contents[src] == EMPTY:
				cells.erase(dest)
				origin.erase(dest)
			else:
				cells[dest] = contents[src]
				origin[dest] = origins[src]
	var moves: Array[Dictionary] = []
	for cur in origin:
		var org: Vector2i = origin[cur]
		if org != cur:
			moves.append({"from": org, "to": cur, "color": cells[cur]})
	return moves


## Procedurally fill a fresh free-play board of `rows` total rows. The bottom
## GEN_EMPTY_BOTTOM_MIN..MAX rows are always left empty as the descent's headroom
## (the lose line sits at the field's bottom edge); above that band every cell takes
## a random breakable colour in [0, num_colors) UNLESS it rolls a hole
## (GEN_HOLE_CHANCE), so empty cells are a viable outcome and the field has gaps. A
## fraction of the placed spheres are then turned into black obstacles. Uses this
## model's `rng`, so seeding `rng` reproduces the board (free play randomizes it;
## tests can pin a seed).
func fill_random(rows: int, black_fraction: float) -> void:
	var empty_bottom := rng.randi_range(GEN_EMPTY_BOTTOM_MIN, GEN_EMPTY_BOTTOM_MAX)
	var fill_rows := maxi(0, rows - empty_bottom)
	for r in range(fill_rows):
		for c in range(width):
			if rng.randf() < GEN_HOLE_CHANCE:
				continue  # leave this cell empty — a viable hole in the field
			cells[Vector2i(c, r)] = rng.randi() % num_colors
	# Blacken a share of the spheres actually placed (not raw grid area), so holes stay
	# holes rather than spawning floating obstacles. black_count is 0 on an empty fill,
	# so the indexing below only runs when `placed` is non-empty.
	var placed := cells.keys()
	var black_count := int(round(placed.size() * black_fraction))
	for _i in range(black_count):
		cells[placed[rng.randi() % placed.size()]] = BLACK


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
