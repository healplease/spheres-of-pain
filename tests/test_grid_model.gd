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


func test_find_orphans_never_sweeps_isolated_black() -> void:
	var m := _make_model()
	# A lone black sphere with no neighbours must stay; a lone breakable one goes.
	m.cells = {Vector2i(0, 0): GridModel.BLACK, Vector2i(5, 5): 2}
	var orph := m.find_orphans()
	assert_does_not_have(orph, Vector2i(0, 0), "isolated black is never an orphan")
	assert_has(orph, Vector2i(5, 5), "isolated breakable is still an orphan")


func test_attach_does_not_pop_orphaned_black() -> void:
	var m := _make_model()
	# Black bridges two breakable groups; popping the breakables strands the black.
	m.cells = {Vector2i(0, 0): 0, Vector2i(1, 0): 0, Vector2i(2, 0): GridModel.BLACK}
	var res := m.attach(Vector2i(0, 1), 0)  # completes a triple of 0s that pops
	assert_true(res.did_pop, "triple pops")
	assert_does_not_have(res.orphaned, Vector2i(2, 0), "orphaned black is not swept")
	assert_true(m.cells.has(Vector2i(2, 0)), "black survives on the field")


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


# --- present colours ----------------------------------------------------------

func test_present_colors_distinct_and_sorted() -> void:
	var m := _make_model()
	m.cells = {Vector2i(0, 0): 2, Vector2i(1, 0): 0, Vector2i(2, 0): 2, Vector2i(3, 0): 4}
	assert_eq(m.present_colors(), [0, 2, 4] as Array[int], "distinct breakable colours, ascending")


func test_present_colors_excludes_black() -> void:
	var m := _make_model()
	m.cells = {Vector2i(0, 0): GridModel.BLACK, Vector2i(1, 0): 3}
	assert_eq(m.present_colors(), [3] as Array[int], "black is not a queueable colour")


func test_present_colors_empty_on_clear_field() -> void:
	var m := _make_model()
	m.cells = {}
	assert_true(m.present_colors().is_empty(), "no colours on an empty field")


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


# --- danger proximity (drives the heartbeat audio) ----------------------------

func test_max_row_empty_field() -> void:
	var m := _make_model()
	m.cells = {}
	assert_eq(m.max_row(), -1, "empty field reports no occupied row")


func test_max_row_is_deepest_cell() -> void:
	var m := _make_model()
	m.cells = {Vector2i(0, 2): 0, Vector2i(3, 7): 1, Vector2i(1, 5): 2}
	assert_eq(m.max_row(), 7, "deepest occupied row")


func test_max_row_counts_black() -> void:
	var m := _make_model()
	# A black sphere sits deeper than any breakable; it still defines the deepest row.
	m.cells = {Vector2i(0, 4): 0, Vector2i(2, 11): GridModel.BLACK}
	assert_eq(m.max_row(), 11, "black counts toward the deepest row")


func test_rows_to_danger_two_rows_out() -> void:
	var m := _make_model()   # danger_row = 12
	m.cells = {Vector2i(0, 10): 0}
	assert_eq(m.rows_to_danger(), 2, "deepest at danger_row - 2 -> slow pulse")


func test_rows_to_danger_one_row_out() -> void:
	var m := _make_model()
	m.cells = {Vector2i(0, 11): 0}
	assert_eq(m.rows_to_danger(), 1, "deepest at danger_row - 1 -> fast pulse")


func test_rows_to_danger_empty_field_is_safe() -> void:
	var m := _make_model()
	m.cells = {}
	assert_eq(m.rows_to_danger(), 13, "empty field is far from the line (danger_row - (-1))")


# --- procedural free-play fill ------------------------------------------------

func test_fill_random_is_deterministic_for_a_seed() -> void:
	var a := GridModel.new(); a.width = 8; a.num_colors = 4; a.rng.seed = 999
	a.fill_random(6, 0.1)
	var b := GridModel.new(); b.width = 8; b.num_colors = 4; b.rng.seed = 999
	b.fill_random(6, 0.1)
	assert_eq(a.cells.size(), b.cells.size(), "same cell count for the same seed")
	var identical := true
	for k in a.cells:
		if b.cells.get(k, -999) != a.cells[k]:
			identical = false
			break
	assert_true(identical, "same seed -> identical board")


func test_fill_random_respects_num_colors() -> void:
	var m := GridModel.new(); m.width = 10; m.num_colors = 3; m.rng.seed = 1
	m.fill_random(5, 0.0)   # no black: a full rows*width breakable fill
	assert_eq(m.cells.size(), 50, "fraction 0 fills every cell")
	for c in m.cells.values():
		assert_true(c >= 0 and c < 3, "every breakable colour is in [0, num_colors)")


func test_fill_random_seeds_black_obstacles() -> void:
	var m := GridModel.new(); m.width = 10; m.num_colors = 3; m.rng.seed = 7
	m.fill_random(10, 0.1)   # ~10 black of 100 cells
	var black := 0
	for c in m.cells.values():
		if c == GridModel.BLACK:
			black += 1
	assert_gt(black, 0, "a positive black_fraction seeds some obstacles")
