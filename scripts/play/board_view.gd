class_name BoardView
extends Node2D

## Renders the sphere field from a GridModel. A pure reflection of the model — it
## never mutates game state. This node is placed at the board origin in the
## scene, so it draws in local coordinates. M1 uses programmer-art circles; the
## gothic-ink art pass is M3.

## Placeholder palette. Distinct hues for now; final spheres get engraved sigils
## (the colorblind cue) in M3.
const PALETTE: Array[Color] = [
	Color("c0392b"),  # red
	Color("27ae60"),  # green
	Color("2980b9"),  # blue
	Color("d4ac0d"),  # yellow
	Color("8e44ad"),  # purple
	Color("16a085"),  # teal
	Color("d35400"),  # orange
]

var model: GridModel
var diameter := 56.0
var num_colors := 5
var columns := 11
var danger_row := 12

var _pops: Array = []  # [{pos: Vector2 (local), t: float}], t counts down


func setup(p_model: GridModel, p_diameter: float, p_num_colors: int, p_columns: int, p_danger_row: int) -> void:
	model = p_model
	diameter = p_diameter
	num_colors = p_num_colors
	columns = p_columns
	danger_row = p_danger_row
	queue_redraw()


## Spawn a transient vanish ring at a cell (pop or detach feedback).
func add_pop(cell: Vector2i) -> void:
	_pops.append({"pos": Hex.cell_to_world(cell, Vector2.ZERO, diameter), "t": 0.3})


func _process(delta: float) -> void:
	if not _pops.is_empty():
		for p in _pops:
			p.t -= delta
		_pops = _pops.filter(func(p): return p.t > 0.0)
	queue_redraw()  # prototype: cheap full redraw each frame


func _draw() -> void:
	if model == null:
		return
	var r := diameter * 0.5
	var dy := diameter * Hex.ROW_RATIO

	# Danger line — crossing it ends the level.
	var yline := danger_row * dy
	draw_line(Vector2(-diameter, yline), Vector2(columns * diameter, yline), Color(0.55, 0.05, 0.05, 0.85), 3.0)

	# Spheres.
	for cell in model.cells:
		var c: int = model.cells[cell]
		var pos := Hex.cell_to_world(cell, Vector2.ZERO, diameter)
		var col: Color = Color(0.08, 0.08, 0.09) if c == GridModel.BLACK else PALETTE[c % PALETTE.size()]
		draw_circle(pos, r - 2.0, col)
		draw_arc(pos, r - 2.0, 0.0, TAU, 24, Color(0, 0, 0, 0.55), 2.0)

	# Vanish rings.
	for p in _pops:
		var a: float = clampf(p.t / 0.3, 0.0, 1.0)
		draw_arc(p.pos, (1.0 - a) * r * 1.6 + 4.0, 0.0, TAU, 20, Color(1, 1, 1, a), 3.0)
