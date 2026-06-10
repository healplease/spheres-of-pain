extends GutTest

## Unit tests for the rules core (GridModel + Hex). Run via GUT:
##   Godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit


func _make_model() -> GridModel:
	var m := GridModel.new()
	m.num_colors = 5
	m.width = 6
	m.danger_row = 12
	m.rng.seed = 12345
	return m


# --- hex geometry -------------------------------------------------------------

func test_even_row_has_six_neighbors() -> void:
	assert_eq(Hex.neighbors(Vector2i(2, 0)).size(), 6)


func test_odd_row_has_six_neighbors() -> void:
	assert_eq(Hex.neighbors(Vector2i(2, 1)).size(), 6)


func test_horizontal_neighbors_present() -> void:
	var n := Hex.neighbors(Vector2i(2, 0))
	assert_true(n.has(Vector2i(1, 0)) and n.has(Vector2i(3, 0)), "left/right neighbours present")


func test_world_cell_roundtrip() -> void:
	var origin := Vector2(100, 80)
	var d := 64.0
	for cell in [Vector2i(0, 0), Vector2i(3, 4), Vector2i(5, 7), Vector2i(2, 11)]:
		assert_eq(Hex.world_to_cell(Hex.cell_to_world(cell, origin, d), origin, d), cell, "roundtrip %s" % cell)


# --- match / pop --------------------------------------------------------------

func test_match_pops_three() -> void:
	var m := _make_model()
	m.cells = {Vector2i(0, 0): 0, Vector2i(1, 0): 0}
	var res := m.attach(Vector2i(2, 0), 0)
	assert_true(res.did_pop, "3-in-a-row pops")
	assert_eq(res.popped.size(), 3, "three spheres removed")
	assert_true(m.cells.is_empty(), "field cleared after pop")


func test_dud_does_not_pop() -> void:
	var m := _make_model()
	m.cells = {Vector2i(0, 0): 0}
	var res := m.attach(Vector2i(1, 0), 0)
	assert_false(res.did_pop, "pair does not pop")
	assert_eq(m.cells.size(), 2, "both spheres remain on a dud")
	assert_true(res.orphaned.is_empty(), "no orphan sweep on a dud")


# --- orphans ------------------------------------------------------------------

func test_find_orphans_only_lone_sphere() -> void:
	var m := _make_model()
	m.cells = {Vector2i(0, 0): GridModel.BLACK, Vector2i(1, 0): 1, Vector2i(5, 5): 2}
	var orph := m.find_orphans()
	assert_eq(orph.size(), 1, "exactly one orphan")
	assert_has(orph, Vector2i(5, 5), "lone sphere is an orphan")
	assert_does_not_have(orph, Vector2i(1, 0), "sphere touching black is anchored")


func test_attach_sweeps_orphans_after_pop() -> void:
	var m := _make_model()
	m.cells = {Vector2i(0, 0): 0, Vector2i(1, 0): 0, Vector2i(0, 1): 1}
	var res := m.attach(Vector2i(2, 0), 0)  # completes the triple, which pops
	assert_true(res.did_pop, "triple pops")
	assert_has(res.orphaned, Vector2i(0, 1), "sphere orphaned by the pop is reported")
	assert_false(m.cells.has(Vector2i(0, 1)), "orphan swept from the field")
	assert_true(m.cells.is_empty(), "field cleared")


# --- black --------------------------------------------------------------------

func test_black_never_matches() -> void:
	var m := _make_model()
	m.cells = {Vector2i(0, 0): GridModel.BLACK, Vector2i(1, 0): GridModel.BLACK, Vector2i(2, 0): GridModel.BLACK}
	assert_true(m.match_group(Vector2i(0, 0)).is_empty(), "black forms no match group")
	assert_eq(m.count_colored(), 0, "black spheres are not counted as colour")


# --- growth -------------------------------------------------------------------

func test_grow_fills_fringe_with_neighbor_color() -> void:
	var m := _make_model()
	m.cells = {Vector2i(2, 2): 3}
	m.grow()
	for nb in Hex.neighbors(Vector2i(2, 2)):
		if nb.x >= 0 and nb.x < m.width and nb.y >= 0:
			assert_eq(m.cells.get(nb, -99), 3, "fringe cell %s filled with neighbour colour" % nb)
	assert_eq(m.cells[Vector2i(2, 2)], 3, "seed sphere unchanged (no downshift)")


func test_grow_protects_enclosed_pocket() -> void:
	var m := _make_model()
	var center := Vector2i(2, 2)
	for nb in Hex.neighbors(center):
		m.cells[nb] = 0
	m.grow()
	assert_false(m.cells.has(center), "fully-enclosed pocket (6 neighbours) stays empty")


# --- randomize ----------------------------------------------------------------

func test_randomize_keeps_black() -> void:
	var m := _make_model()
	m.cells = {Vector2i(0, 0): 0, Vector2i(1, 0): GridModel.BLACK}
	m.randomize_colors()
	assert_eq(m.cells[Vector2i(1, 0)], GridModel.BLACK, "black survives randomize")
	assert_between(m.cells[Vector2i(0, 0)], 0, m.num_colors - 1, "randomized colour within range")


# --- win / lose ---------------------------------------------------------------

func test_won_when_only_black_remains() -> void:
	var m := _make_model()
	m.cells = {Vector2i(0, 0): GridModel.BLACK}
	assert_true(m.is_won())


func test_not_won_while_colour_present() -> void:
	var m := _make_model()
	m.cells = {Vector2i(0, 0): 0}
	assert_false(m.is_won())


func test_lost_at_danger_row() -> void:
	var m := _make_model()
	m.cells = {Vector2i(0, 12): 0}
	assert_true(m.is_lost())


func test_safe_above_danger_row() -> void:
	var m := _make_model()
	m.cells = {Vector2i(0, 11): 0}
	assert_false(m.is_lost())
