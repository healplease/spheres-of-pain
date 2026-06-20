extends GutTest

## Tests for BoardGeometry — the pure derivation of the board's logical play geometry from the
## field size. These guard that the extraction from the controller reproduces the shipped
## geometry and stays centred regardless of column count.


func test_centre_independent_of_columns() -> void:
	# The field is centred on FIELD_CENTER_X regardless of column count, so the muzzle (which
	# fires from the centre) always sits over the middle of the play area.
	for cols in [9, 11, 50]:
		var g := BoardGeometry.compute(cols, 12, 56.0)
		assert_almost_eq(
			(g.play_left + g.play_right) * 0.5,
			BoardGeometry.FIELD_CENTER_X,
			0.001,
			"columns %d: play area is centred on FIELD_CENTER_X" % cols
		)
		assert_almost_eq(g.muzzle2d.x, BoardGeometry.FIELD_CENTER_X, 0.001, "muzzle x centred")


func test_muzzle_and_exit_below_danger_line() -> void:
	# The gun hangs below the danger (lose) line, and the miss-exit bar below the gun.
	var g := BoardGeometry.compute(11, 12, 56.0)
	var danger_y := g.origin2d.y + 12 * 56.0 * Hex.ROW_RATIO
	assert_gt(g.muzzle2d.y, danger_y, "muzzle sits below the danger line")
	assert_gt(g.play_bottom, g.muzzle2d.y, "miss-exit sits below the muzzle")


func test_matches_legacy_values() -> void:
	# The column-derived coordinates must reproduce the values the game shipped with before the
	# geometry was extracted (and that test_shot.gd::_make_sim still hard-codes).
	var g := BoardGeometry.compute(11, 12, 56.0)
	assert_almost_eq(g.origin2d.x, 346.0, 0.001, "origin x for 11 columns")
	assert_almost_eq(g.origin2d.y, 80.0, 0.001, "origin y is the top wall")
	assert_almost_eq(g.play_left, 318.0, 0.001, "left bounce wall")
	assert_almost_eq(g.play_right, 962.0, 0.001, "right bounce wall")
