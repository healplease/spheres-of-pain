class_name LevelResource
extends Resource

## An authored level: board layout plus the model parameters that shape its
## difficulty. Pure data — parsing into a GridModel lives here so it can be
## unit-tested headlessly; nothing in this class touches the scene tree.
##
## `layout` is ASCII art, one string per row, one character per column:
##   '.'        empty cell
##   '0'..'9'   breakable sphere of that colour id (must be < num_colors)
##   'X' / 'x'  indestructible black obstacle
##   'S' / 's'  indestructible spin sphere (rotates neighbour colours on a land)
##   'B' / 'b'  indestructible bounce sphere (a fired sphere reflects off it)
##   '@'        objective cell — a CAGED SOUL to free (FREE_SOUL objective)
##   '*'        objective cell — a CURSED cell to cleanse (CLEANSE objective)
## '@'/'*' parse to an ORDINARY breakable of `objective_color`, so they pop/orphan/grow/count
## like any sphere; they are only special in that the level is WON when those cells are empty
## (the model itself stays objective-agnostic — see objective_cells / objective_met). The two
## chars are interchangeable to the rules; the convention is '@' = soul, '*' = curse.
## Note the hex grid: odd rows render shifted half a cell to the right, so a
## vertically aligned column in the text zig-zags on screen.
##
## The layout is the WHOLE playable field, including the empty headroom rows below the
## spheres: the lose line sits at the field's bottom edge (danger_row == layout.size()),
## so the trailing empty rows an author writes are the headroom before defeat — nothing
## is auto-added at play time. More empty rows = a gentler level.

## The level's victory predicate. CLEAR = empty the whole board (the default, today's rule).
## FREE_SOUL / CLEANSE = empty the tagged objective cells ('@' / '*') — they share one check
## and differ only in tag char + fiction. Orthogonal MODIFIERS (shot_budget, tide) compose on
## top of any of these; they are not objective types (a fail-cap and a board mutation, not a
## win predicate). See objective_met() for the shared check.
enum Objective { CLEAR, FREE_SOUL, CLEANSE }

@export var id: int = 1
@export var title: String = ""
@export_multiline var lore_fragment: String = ""
@export var width: int = 11  # columns; every layout row must be this long
@export var num_colors: int = 4
@export var danger_row: int = 12  # lose if any sphere reaches this row
## Hand-tuned shot budget the efficiency tiers reckon against (clear within par = CLEANLY,
## within par+2 = FREED, slower = BARELY). 0 = unset, so the level offers no yardstick and
## always reads FREED with no economy bonus. Tuned per level by playtest.
@export var par_shots: int = 0
@export var layout: PackedStringArray = []

## Goal + constraints. objective_type picks the win predicate; objective_color is what the
## '@'/'*' tags parse to as ordinary breakables. shot_budget (0 = unlimited) is the "Sniper"
## lose-cap; tide_rows_per_shot (0 = off) drops the whole field that many rows after every
## shot — use EVEN values: a row is half-offset by parity, so an odd drop flips parity and
## scrambles hex adjacency, while an even drop is a rigid, adjacency-preserving descent.
@export_group("Objective")
@export var objective_type: Objective = Objective.CLEAR
@export var objective_color: int = 0
@export var shot_budget: int = 0
@export var tide_rows_per_shot: int = 0

## Per-level atmosphere. Defaults match the free-play look, so a level that
## sets nothing inherits the base violet/teal abyss.
@export_group("Theme")
@export var abyss_color_a: Color = Color(0.10, 0.05, 0.17)  # primary nebula accent
@export var abyss_color_b: Color = Color(0.03, 0.10, 0.11)  # secondary nebula accent
@export var ember_color: Color = Color(1.0, 0.62, 0.3)  # drifting particle tint
@export var fog_color: Color = Color(0.025, 0.02, 0.045)  # environment fog


func rows() -> int:
	return layout.size()


## Parse the layout into a fresh, configured GridModel. The caller seeds
## `model.rng` (tests want determinism, the game wants randomize()).
func build_model() -> GridModel:
	var model := GridModel.new()
	model.width = width
	model.num_colors = num_colors
	model.danger_row = danger_row
	for r in range(layout.size()):
		var row := layout[r]
		for c in range(row.length()):
			var ch := row[c]
			if ch == ".":
				continue
			elif ch == "X" or ch == "x":
				model.cells[Vector2i(c, r)] = GridModel.BLACK
			elif ch == "S" or ch == "s":
				model.cells[Vector2i(c, r)] = GridModel.SPIN
			elif ch == "B" or ch == "b":
				model.cells[Vector2i(c, r)] = GridModel.BOUNCE
			elif ch == "@" or ch == "*":
				# Objective tags are ORDINARY breakables of objective_color — the model never
				# learns they're special; objective_cells()/objective_met() track them by spot.
				model.cells[Vector2i(c, r)] = objective_color
			else:
				# Numeric only past here; non-numerics are rejected by validate(), and
				# "S".to_int() == 0 would otherwise silently become colour 0.
				model.cells[Vector2i(c, r)] = ch.to_int()
	return model


## The cells tagged as the objective ('@' or '*'), reparsed from the layout. The model does
## not store which cells are the goal (that's level metadata), so the controller asks here once
## and then watches those coordinates empty out. Empty for a CLEAR level.
func objective_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in range(layout.size()):
		var row := layout[r]
		for c in range(row.length()):
			var ch := row[c]
			if ch == "@" or ch == "*":
				out.append(Vector2i(c, r))
	return out


## The victory predicate, kept here (pure, with the level data it reads) so the controller has
## one place to ask. CLEAR wins on an empty board; an objective wins when every tagged cell is
## empty. `cells` is the result of objective_cells() (passed in so callers cache it once).
func objective_met(model: GridModel, cells: Array[Vector2i]) -> bool:
	if objective_type == Objective.CLEAR:
		return model.is_won()
	for cell in cells:
		if model.is_occupied(cell):
			return false
	return true


## Human-readable list of authoring problems; empty means the level is valid.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if width < 1:
		problems.append("width must be >= 1")
	if num_colors < 1 or num_colors > 10:
		problems.append("num_colors must be in [1, 10]")
	if layout.is_empty():
		problems.append("layout is empty")
	# Authored rows are indices 0..size-1; is_lost() triggers at cell.y >= danger_row.
	# So danger_row == layout.size() (the first empty row below the layout) is the
	# tightest valid line; only danger_row < size puts an authored sphere on/over it.
	if danger_row < layout.size():
		problems.append(
			"danger_row (%d) must be below the layout (%d rows)" % [danger_row, layout.size()]
		)
	if par_shots < 0:
		problems.append("par_shots (%d) must be >= 0 (0 = unset)" % par_shots)
	var breakable := 0
	var tags := 0  # '@'/'*' objective cells; they're breakables too
	for r in range(layout.size()):
		var row := layout[r]
		if row.length() != width:
			problems.append("row %d is %d chars, expected width %d" % [r, row.length(), width])
		for c in range(row.length()):
			var ch := row[c]
			# Empty + indestructibles (black/spin/bounce) are valid but not breakable.
			if (
				ch == "."
				or ch == "X"
				or ch == "x"
				or ch == "S"
				or ch == "s"
				or ch == "B"
				or ch == "b"
			):
				continue
			if ch == "@" or ch == "*":
				# Objective tags parse to a breakable of objective_color (checked below).
				tags += 1
				breakable += 1
				continue
			if ch < "0" or ch > "9":
				problems.append("row %d col %d: illegal char '%s'" % [r, c, ch])
			elif ch.to_int() >= num_colors:
				problems.append(
					"row %d col %d: colour %s >= num_colors %d" % [r, c, ch, num_colors]
				)
			else:
				breakable += 1
	if breakable == 0:
		problems.append("layout has no breakable spheres")
	# Objective wiring: tags and objective_type must agree, and the tag colour + the orthogonal
	# modifiers (Sniper budget, tide) must be in range.
	if objective_type == Objective.CLEAR and tags > 0:
		problems.append("objective tags ('@'/'*') present but objective_type is CLEAR")
	if objective_type != Objective.CLEAR and tags == 0:
		problems.append("objective_type %d needs at least one '@'/'*' tagged cell" % objective_type)
	if tags > 0 and (objective_color < 0 or objective_color >= num_colors):
		problems.append(
			"objective_color (%d) must be in [0, num_colors %d)" % [objective_color, num_colors]
		)
	if shot_budget < 0:
		problems.append("shot_budget (%d) must be >= 0 (0 = unlimited)" % shot_budget)
	if tide_rows_per_shot < 0:
		problems.append("tide_rows_per_shot (%d) must be >= 0 (0 = off)" % tide_rows_per_shot)
	return problems
