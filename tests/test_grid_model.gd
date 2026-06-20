# gdlint:disable=max-public-methods
# ^ GUT: one public test_* method per case is the pattern
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
		assert_eq(
			Hex.world_to_cell(Hex.cell_to_world(cell, origin, d), origin, d),
			cell,
			"roundtrip %s" % cell
		)


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
	m.cells = {
		Vector2i(0, 0): GridModel.BLACK,
		Vector2i(1, 0): GridModel.BLACK,
		Vector2i(2, 0): GridModel.BLACK
	}
	assert_true(m.match_group(Vector2i(0, 0)).is_empty(), "black forms no match group")
	assert_eq(m.count_colored(), 0, "black spheres are not counted as colour")


# --- spin / bounce: indestructible, like black --------------------------------
# Both new types are sentinels < 0, so every "indestructible" rule (match, orphan,
# grow, randomize, win) must treat them exactly as it treats BLACK.


func test_specials_never_match_and_not_counted() -> void:
	for special in [GridModel.SPIN, GridModel.BOUNCE]:
		var m := _make_model()
		m.cells = {Vector2i(0, 0): special, Vector2i(1, 0): special, Vector2i(2, 0): special}
		assert_true(m.match_group(Vector2i(0, 0)).is_empty(), "special %d forms no match" % special)
		assert_eq(m.count_colored(), 0, "special %d not counted as colour" % special)
		assert_true(m.present_colors().is_empty(), "special %d not a queueable colour" % special)


func test_specials_never_orphaned_but_anchor_neighbours() -> void:
	for special in [GridModel.SPIN, GridModel.BOUNCE]:
		var m := _make_model()
		# Lone special stays; a breakable touching it is anchored; a far breakable is swept.
		m.cells = {Vector2i(0, 0): special, Vector2i(1, 0): 1, Vector2i(5, 5): 2}
		var orph := m.find_orphans()
		assert_does_not_have(orph, Vector2i(0, 0), "isolated special %d never orphaned" % special)
		assert_does_not_have(orph, Vector2i(1, 0), "sphere touching special %d anchored" % special)
		assert_has(orph, Vector2i(5, 5), "lone breakable still orphaned (special %d)" % special)


func test_specials_survive_randomize() -> void:
	for special in [GridModel.SPIN, GridModel.BOUNCE]:
		var m := _make_model()
		m.cells = {Vector2i(0, 0): 0, Vector2i(1, 0): special}
		m.randomize_colors()
		assert_eq(m.cells[Vector2i(1, 0)], special, "special %d survives randomize" % special)


func test_specials_not_seeded_by_growth() -> void:
	for special in [GridModel.SPIN, GridModel.BOUNCE]:
		var m := _make_model()
		m.cells = {Vector2i(2, 2): special}  # only a special on the board
		m.grow()
		assert_eq(m.cells.size(), 1, "a lone special %d seeds no growth" % special)


func test_won_when_only_specials_remain() -> void:
	var m := _make_model()
	m.cells = {
		Vector2i(0, 0): GridModel.SPIN,
		Vector2i(1, 0): GridModel.BOUNCE,
		Vector2i(2, 0): GridModel.BLACK
	}
	assert_true(m.is_won(), "no colour left -> won, even with spin/bounce/black standing")


func test_max_row_counts_specials() -> void:
	var m := _make_model()
	m.cells = {
		Vector2i(0, 4): 0, Vector2i(1, 10): GridModel.SPIN, Vector2i(2, 11): GridModel.BOUNCE
	}
	assert_eq(m.max_row(), 11, "specials sink toward the danger line like any sphere")


# --- spin rotation ------------------------------------------------------------


func _colour_multiset(m: GridModel) -> Array:
	# Sorted list of every breakable colour on the board, for order-independent compare.
	var out: Array = []
	for c in m.cells.values():
		if c >= 0:
			out.append(c)
	out.sort()
	return out


func _ring_contents(m: GridModel, spin: Vector2i, dirs: Array) -> Array:
	# Sorted contents (colour, or EMPTY for a gap) of the spin's six neighbour cells.
	var out: Array = []
	for d in dirs:
		out.append(m.cells.get(spin + d, GridModel.EMPTY))
	out.sort()
	return out


func test_spin_rotates_neighbours_counter_clockwise() -> void:
	var m := _make_model()
	m.num_colors = 6
	var spin := Vector2i(2, 2)  # even row
	# Fill all six neighbours (DIRS[0] order) with distinct colours, then rotate.
	var dirs: Array = Hex.DIRS[0]
	var cols := [0, 1, 2, 3, 4, 5]
	m.cells[spin] = GridModel.SPIN
	for i in range(6):
		m.cells[spin + dirs[i]] = cols[i]
	var moves := m.spin_step()
	# Each neighbour receives the colour of the previous slot: the sphere at slot i
	# physically moves forward to slot i+1, i.e. one step counter-clockwise on screen.
	for i in range(6):
		var expected: int = cols[(i - 1 + 6) % 6]
		assert_eq(m.cells[spin + dirs[i]], expected, "slot %d rotated CCW" % i)
	assert_eq(m.cells[spin], GridModel.SPIN, "the spin sphere itself is unchanged")
	# A clean permutation: six spheres, each leaving once and landing once.
	assert_eq(moves.size(), 6, "all six spheres relocate")
	var froms := {}
	var tos := {}
	for mv in moves:
		froms[mv["from"]] = true
		tos[mv["to"]] = true
	assert_eq(froms.size(), 6, "each source cell appears once")
	assert_eq(tos.size(), 6, "each destination cell appears once")


func test_spin_parity_consistent() -> void:
	# The same physical move (East content travels to the up-right neighbour) must hold
	# whether the spin sits on an even or an odd row.
	for spin in [Vector2i(2, 2), Vector2i(2, 3)]:
		var m := _make_model()
		m.num_colors = 6
		var dirs: Array = Hex.DIRS[spin.y & 1]
		m.cells[spin] = GridModel.SPIN
		for i in range(6):
			m.cells[spin + dirs[i]] = i  # slot index as colour
		m.spin_step()
		# dirs[0] is East, dirs[1] is up-right; East's colour (0) lands on up-right.
		assert_eq(m.cells[spin + dirs[1]], 0, "East colour moved to up-right (spin at %s)" % spin)


func test_spin_full_ring_matches_old_ccw() -> void:
	# Direction regression: a fully-occupied ring rotates exactly as the legacy colour
	# swap did — content at slot i lands on slot i+1 (counter-clockwise). Odd row also
	# guards parity.
	var m := _make_model()
	m.num_colors = 6
	var spin := Vector2i(2, 3)  # odd row
	var dirs: Array = Hex.DIRS[1]
	for i in range(6):
		m.cells[spin + dirs[i]] = i
	m.cells[spin] = GridModel.SPIN
	m.spin_step()
	for i in range(6):
		var prev: int = (i - 1 + 6) % 6
		assert_eq(m.cells[spin + dirs[i]], prev, "slot %d holds the previous slot's colour" % i)


func test_spin_only_rotates_coloured_neighbours() -> void:
	# Empty in-bounds neighbours are now track cells too, so they take part. With a black
	# neighbour excluded, the ring is [E, up-left, W, down-left, down-right] and the
	# contents (two colours + three gaps) rotate one slot anti-clockwise.
	var m := _make_model()
	var spin := Vector2i(2, 2)
	var dirs: Array = Hex.DIRS[0]
	m.cells[spin] = GridModel.SPIN
	m.cells[spin + dirs[0]] = 1  # E: colour
	m.cells[spin + dirs[1]] = GridModel.BLACK  # up-right: indestructible, excluded
	m.cells[spin + dirs[3]] = 2  # W: colour
	var moves := m.spin_step()
	assert_eq(m.cells[spin + dirs[1]], GridModel.BLACK, "black neighbour untouched")
	# E's colour jumps over the black to up-left; W's colour moves to down-left.
	assert_eq(m.cells.get(spin + dirs[2], GridModel.EMPTY), 1, "E colour travelled to up-left")
	assert_eq(m.cells.get(spin + dirs[4], GridModel.EMPTY), 2, "W colour travelled to down-left")
	# The source cells are now vacated (an empty slot rotated into them).
	assert_false(m.cells.has(spin + dirs[0]), "E source vacated")
	assert_false(m.cells.has(spin + dirs[3]), "W source vacated")
	assert_eq(moves.size(), 2, "two spheres relocated; the gaps moved no sphere")


func test_spin_single_bubble_moves_one_slot() -> void:
	# A lone sphere is no longer a no-op: the surrounding empty slots are track cells, so
	# the sphere travels one slot anti-clockwise (E -> up-right) and vacates its cell.
	var m := _make_model()
	var spin := Vector2i(2, 2)
	var dirs: Array = Hex.DIRS[0]
	m.cells = {spin: GridModel.SPIN, spin + dirs[0]: 3}
	var moves := m.spin_step()
	assert_false(m.cells.has(spin + dirs[0]), "the sphere left its source cell")
	assert_eq(m.cells.get(spin + dirs[1], GridModel.EMPTY), 3, "the sphere arrived up-right")
	assert_eq(moves.size(), 1, "exactly one sphere moved")
	assert_eq(moves[0]["from"], spin + dirs[0])
	assert_eq(moves[0]["to"], spin + dirs[1])
	assert_eq(moves[0]["color"], 3)


func test_spin_empty_travels_into_occupied() -> void:
	# A sphere rotates into a slot that was empty — the empty slot is a valid track cell.
	var m := _make_model()
	var spin := Vector2i(2, 2)
	var dirs: Array = Hex.DIRS[0]
	m.cells[spin] = GridModel.SPIN
	m.cells[spin + dirs[0]] = 1  # E occupied; up-right (dirs[1]) is empty
	m.spin_step()
	assert_eq(
		m.cells.get(spin + dirs[1], GridModel.EMPTY), 1, "sphere travelled into the empty slot"
	)
	assert_false(m.cells.has(spin + dirs[0]), "its source cell is now empty")


func test_spin_empty_replaces_bubble() -> void:
	# The dual: a lone empty slot travels anti-clockwise and vacates an occupied cell.
	var m := _make_model()
	var spin := Vector2i(2, 2)
	var dirs: Array = Hex.DIRS[0]
	m.cells[spin] = GridModel.SPIN
	# Occupy every neighbour except up-right (dirs[1]); that one gap rotates forward.
	for i in range(6):
		if i != 1:
			m.cells[spin + dirs[i]] = i
	m.spin_step()
	# The gap moves one slot forward (slot 1 -> slot 2), so the up-left cell, which
	# started occupied, is now vacated.
	assert_false(m.cells.has(spin + dirs[2]), "the gap rotated into up-left, vacating it")
	assert_eq(m.cells.get(spin + dirs[1], GridModel.EMPTY), 0, "up-right took East's colour")


func test_spin_permutation_conserves_multiset() -> void:
	# A ring of mixed colours and gaps: the sorted multiset of contents (colours AND
	# gaps) is unchanged — rotation only permutes them.
	var m := _make_model()
	m.num_colors = 6
	var spin := Vector2i(2, 2)
	var dirs: Array = Hex.DIRS[0]
	m.cells[spin] = GridModel.SPIN
	m.cells[spin + dirs[0]] = 0
	m.cells[spin + dirs[1]] = 4
	m.cells[spin + dirs[3]] = 2
	m.cells[spin + dirs[5]] = 2
	# dirs[2] and dirs[4] left empty.
	var before := _ring_contents(m, spin, dirs)
	m.spin_step()
	var after := _ring_contents(m, spin, dirs)
	assert_eq(after, before, "colours and gaps are both conserved by the rotation")


func test_spin_skips_indestructible_neighbour_jump_over() -> void:
	# A black neighbour is excluded from the ring, so a sphere jumps over it to the next
	# track slot, and the black sphere itself never moves.
	var m := _make_model()
	var spin := Vector2i(2, 2)
	var dirs: Array = Hex.DIRS[0]
	m.cells[spin] = GridModel.SPIN
	m.cells[spin + dirs[0]] = 1  # E: colour
	m.cells[spin + dirs[1]] = GridModel.BLACK  # up-right: excluded
	var moves := m.spin_step()
	assert_eq(m.cells[spin + dirs[1]], GridModel.BLACK, "black neighbour stayed put")
	assert_false(m.cells.has(spin + dirs[0]), "sphere left East")
	assert_eq(m.cells.get(spin + dirs[2], GridModel.EMPTY), 1, "sphere jumped the black to up-left")
	assert_eq(moves.size(), 1)
	assert_eq(moves[0]["from"], spin + dirs[0])
	assert_eq(moves[0]["to"], spin + dirs[2])


func test_spin_excludes_out_of_bounds() -> void:
	# A spin against the left wall only rotates its in-bounds neighbours; no out-of-bounds
	# cell is ever written.
	var m := _make_model()
	var spin := Vector2i(0, 2)  # column 0 — three of its six neighbours are off-grid
	var dirs: Array = Hex.DIRS[0]
	m.cells[spin] = GridModel.SPIN
	m.cells[spin + dirs[0]] = 1  # E  (1,2)
	m.cells[spin + dirs[1]] = 2  # up-right (0,1)
	m.cells[spin + dirs[5]] = 3  # down-right (0,3)
	var moves := m.spin_step()
	# Three-cell ring rotates one CCW: E<-DR, UR<-E, DR<-UR.
	assert_eq(m.cells[spin + dirs[0]], 3, "E took down-right's colour")
	assert_eq(m.cells[spin + dirs[1]], 1, "up-right took E's colour")
	assert_eq(m.cells[spin + dirs[5]], 2, "down-right took up-right's colour")
	assert_eq(moves.size(), 3, "only the three in-bounds spheres moved")
	assert_false(m.cells.has(spin + dirs[2]), "no sphere written up-left (off-grid)")
	assert_false(m.cells.has(spin + dirs[3]), "no sphere written west (off-grid)")
	assert_false(m.cells.has(spin + dirs[4]), "no sphere written down-left (off-grid)")


func test_spin_preserves_colour_count() -> void:
	var m := _make_model()
	m.num_colors = 6
	var spin := Vector2i(2, 2)
	for i in range(6):
		m.cells[spin + Hex.DIRS[0][i]] = i % 4
	m.cells[spin] = GridModel.SPIN
	var before := m.count_colored()
	var before_multiset := _colour_multiset(m)
	m.spin_step()
	assert_eq(m.count_colored(), before, "spin only moves colours, never adds or removes")
	assert_eq(_colour_multiset(m), before_multiset, "the multiset of colours is conserved")


func test_spin_returns_moves_list() -> void:
	# The return value is a list of {from, to, color}; each from and to is unique, and
	# replaying the moves reproduces the resolved board.
	var m := _make_model()
	m.num_colors = 6
	var spin := Vector2i(2, 2)
	var dirs: Array = Hex.DIRS[0]
	for i in range(6):
		m.cells[spin + dirs[i]] = i
	m.cells[spin] = GridModel.SPIN
	var moves := m.spin_step()
	assert_eq(moves.size(), 6)
	var froms := {}
	var tos := {}
	var rebuilt := {spin: GridModel.SPIN}
	for mv in moves:
		assert_true(mv.has("from") and mv.has("to") and mv.has("color"), "move shape")
		froms[mv["from"]] = true
		tos[mv["to"]] = true
		rebuilt[mv["to"]] = mv["color"]
	assert_eq(froms.size(), 6, "every source unique")
	assert_eq(tos.size(), 6, "every destination unique")
	assert_eq(rebuilt, m.cells, "replaying the moves reproduces the board")


func test_spin_all_empty_ring_is_noop() -> void:
	var m := _make_model()
	var spin := Vector2i(2, 2)
	m.cells = {spin: GridModel.SPIN}
	var moves := m.spin_step()
	assert_true(moves.is_empty(), "no spheres to move")
	assert_eq(m.cells.size(), 1, "only the spin sphere remains; no empty was materialised")


func test_spin_ring_size_one_is_noop() -> void:
	# With only a single track cell (others off-grid or indestructible) there is nothing
	# to rotate against, so the spin does nothing.
	var m := _make_model()
	var spin := Vector2i(0, 0)  # top-left corner: four neighbours are off-grid
	var dirs: Array = Hex.DIRS[0]
	m.cells[spin] = GridModel.SPIN
	m.cells[spin + dirs[0]] = 1  # E: the lone in-bounds breakable neighbour
	m.cells[spin + dirs[5]] = GridModel.BLACK  # down-right: in-bounds but excluded
	var moves := m.spin_step()
	assert_true(moves.is_empty(), "a one-cell ring cannot rotate")
	assert_eq(m.cells[spin + dirs[0]], 1, "the lone neighbour is unchanged")
	assert_eq(m.cells[spin + dirs[5]], GridModel.BLACK, "the black neighbour is unchanged")


func _spin_conflict_board() -> GridModel:
	# Two spins that share the neighbour (3, 2), plus a colour around each.
	var m := _make_model()
	m.num_colors = 6
	m.cells = {
		Vector2i(2, 2): GridModel.SPIN,
		Vector2i(4, 2): GridModel.SPIN,
		Vector2i(3, 2): 0,
		Vector2i(2, 1): 1,
		Vector2i(1, 2): 2,
		Vector2i(5, 2): 3,
		Vector2i(4, 1): 4,
		Vector2i(4, 3): 5,
	}
	return m


func test_spin_multi_is_deterministic() -> void:
	var a := _spin_conflict_board()
	a.spin_step()
	var b := _spin_conflict_board()
	b.spin_step()
	for k in a.cells:
		assert_eq(
			b.cells.get(k, -999), a.cells[k], "shared-neighbour spin is deterministic at %s" % k
		)


func test_spin_multi_overlap_cascades() -> void:
	# The two spins share neighbours. They resolve one at a time in reading order — (2,2)
	# first, then (4,2) on the board (2,2) left behind — so BOTH take effect; neither is
	# skipped (the old behaviour dropped the second spin).
	var m := _spin_conflict_board()
	m.spin_step()
	# (2,2) acted first: its up-right took the shared cell's colour.
	assert_eq(m.cells[Vector2i(2, 1)], 0, "(2,2) rotated — up-right took the shared colour")
	# (4,2) then acted on the result: its own exclusive neighbours changed too.
	assert_eq(m.cells[Vector2i(5, 2)], 5, "(4,2) east changed — the second spin triggered")
	assert_eq(m.cells[Vector2i(4, 1)], 3, "(4,2) up-right changed — the second spin triggered")
	assert_eq(m.cells.get(Vector2i(3, 1), GridModel.EMPTY), 4, "(4,2) filled its up-left slot")
	assert_false(m.cells.has(Vector2i(4, 3)), "(4,2) vacated its down-right slot")


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
	var m := _make_model()  # danger_row = 12
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
	var a := GridModel.new()
	a.width = 8
	a.num_colors = 4
	a.rng.seed = 999
	a.fill_random(6, 0.1)
	var b := GridModel.new()
	b.width = 8
	b.num_colors = 4
	b.rng.seed = 999
	b.fill_random(6, 0.1)
	assert_eq(a.cells.size(), b.cells.size(), "same cell count for the same seed")
	var identical := true
	for k in a.cells:
		if b.cells.get(k, -999) != a.cells[k]:
			identical = false
			break
	assert_true(identical, "same seed -> identical board")


func test_fill_random_respects_num_colors() -> void:
	var m := GridModel.new()
	m.width = 10
	m.num_colors = 3
	m.rng.seed = 1
	m.fill_random(5, 0.0)  # no black: a full rows*width breakable fill
	assert_eq(m.cells.size(), 50, "fraction 0 fills every cell")
	for c in m.cells.values():
		assert_true(c >= 0 and c < 3, "every breakable colour is in [0, num_colors)")


func test_fill_random_seeds_black_obstacles() -> void:
	var m := GridModel.new()
	m.width = 10
	m.num_colors = 3
	m.rng.seed = 7
	m.fill_random(10, 0.1)  # ~10 black of 100 cells
	var black := 0
	for c in m.cells.values():
		if c == GridModel.BLACK:
			black += 1
	assert_gt(black, 0, "a positive black_fraction seeds some obstacles")
