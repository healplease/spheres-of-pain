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
## Note the hex grid: odd rows render shifted half a cell to the right, so a
## vertically aligned column in the text zig-zags on screen.
##
## The layout is the WHOLE playable field, including the empty headroom rows below the
## spheres: the lose line sits at the field's bottom edge (danger_row == layout.size()),
## so the trailing empty rows an author writes are the headroom before defeat — nothing
## is auto-added at play time. More empty rows = a gentler level.

@export var id: int = 1
@export var title: String = ""
@export_multiline var lore_fragment: String = ""
@export var width: int = 11  # columns; every layout row must be this long
@export var num_colors: int = 4
@export var danger_row: int = 12  # lose if any sphere reaches this row
@export var layout: PackedStringArray = []

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
			else:
				# Numeric only past here; non-numerics are rejected by validate(), and
				# "S".to_int() == 0 would otherwise silently become colour 0.
				model.cells[Vector2i(c, r)] = ch.to_int()
	return model


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
	var breakable := 0
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
	return problems
