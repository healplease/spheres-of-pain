# gdlint:disable=max-public-methods
# ^ GUT: one public test_* method per case is the pattern
extends GutTest

## Tests for LevelResource: layout parsing into GridModel, validation, and a
## data-integrity sweep over every shipped level file.


func _make_level() -> LevelResource:
	var lv := LevelResource.new()
	lv.id = 1
	lv.title = "Test Pit"
	lv.width = 5
	lv.num_colors = 3
	lv.danger_row = 10
	lv.layout = PackedStringArray(["012.X", "..120"])
	return lv


# --- parsing -------------------------------------------------------------------


func test_build_model_copies_config() -> void:
	var m := _make_level().build_model()
	assert_eq(m.width, 5, "width copied")
	assert_eq(m.num_colors, 3, "num_colors copied")
	assert_eq(m.danger_row, 10, "danger_row copied")


func test_build_model_parses_chars() -> void:
	var m := _make_level().build_model()
	assert_eq(m.cells.get(Vector2i(0, 0)), 0, "digit -> colour id")
	assert_eq(m.cells.get(Vector2i(2, 0)), 2, "digit -> colour id")
	assert_eq(m.cells.get(Vector2i(4, 0)), GridModel.BLACK, "X -> black obstacle")
	assert_false(m.cells.has(Vector2i(3, 0)), "dot -> empty (absent key)")
	assert_false(m.cells.has(Vector2i(0, 1)), "dot -> empty (absent key)")
	assert_eq(m.cells.get(Vector2i(3, 1)), 2, "second row parsed")


func test_build_model_counts() -> void:
	var m := _make_level().build_model()
	assert_eq(m.cells.size(), 7, "6 coloured + 1 black")
	assert_eq(m.count_colored(), 6, "black excluded from coloured count")
	assert_false(m.is_won(), "fresh level not won")
	assert_false(m.is_lost(), "fresh level not lost")


func test_lowercase_x_is_black() -> void:
	var lv := _make_level()
	lv.layout = PackedStringArray(["01x20"])
	assert_eq(lv.build_model().cells.get(Vector2i(2, 0)), GridModel.BLACK)


func test_s_is_spin_not_colour_zero() -> void:
	# "S".to_int() == 0, so the explicit branch must win or a spin would parse as red.
	var lv := _make_level()
	lv.layout = PackedStringArray(["01S20"])
	assert_eq(lv.build_model().cells.get(Vector2i(2, 0)), GridModel.SPIN, "S -> spin sentinel")


func test_b_is_bounce_not_colour_zero() -> void:
	var lv := _make_level()
	lv.layout = PackedStringArray(["01B20"])
	assert_eq(lv.build_model().cells.get(Vector2i(2, 0)), GridModel.BOUNCE, "B -> bounce sentinel")


func test_lowercase_s_and_b() -> void:
	var lv := _make_level()
	lv.layout = PackedStringArray(["0s1b2"])
	var m := lv.build_model()
	assert_eq(m.cells.get(Vector2i(1, 0)), GridModel.SPIN, "lowercase s -> spin")
	assert_eq(m.cells.get(Vector2i(3, 0)), GridModel.BOUNCE, "lowercase b -> bounce")


func test_specials_excluded_from_coloured_count() -> void:
	var lv := _make_level()
	lv.layout = PackedStringArray(["0S1B2"])  # 3 colours + 1 spin + 1 bounce
	var m := lv.build_model()
	assert_eq(m.count_colored(), 3, "spin and bounce don't count as colours")
	assert_eq(m.cells.size(), 5, "all five cells stored")


# --- validation ----------------------------------------------------------------


func test_valid_level_passes() -> void:
	assert_true(_make_level().validate().is_empty(), "fixture level is valid")


func test_validate_flags_ragged_row() -> void:
	var lv := _make_level()
	lv.layout = PackedStringArray(["012", "01210"])
	assert_false(lv.validate().is_empty(), "row shorter than width flagged")


func test_validate_flags_illegal_char() -> void:
	var lv := _make_level()
	lv.layout = PackedStringArray(["01?20", "00000"])
	assert_false(lv.validate().is_empty(), "non-digit non-X flagged")


func test_validate_flags_color_out_of_range() -> void:
	var lv := _make_level()
	lv.layout = PackedStringArray(["01920", "00000"])  # 9 >= num_colors 3
	assert_false(lv.validate().is_empty(), "colour id >= num_colors flagged")


func test_validate_flags_low_danger_row() -> void:
	var lv := _make_level()  # layout is 2 rows (indices 0,1)
	lv.danger_row = 1  # a row that authored spheres occupy -> on/over the line
	assert_false(lv.validate().is_empty(), "danger_row inside the layout flagged")


func test_validate_allows_danger_row_just_below_layout() -> void:
	var lv := _make_level()  # layout is 2 rows
	lv.danger_row = lv.layout.size()  # the first empty row below the layout: valid
	assert_true(lv.validate().is_empty(), "danger_row == rows is the tightest valid line")


func test_palette_covers_every_allowed_colour() -> void:
	# validate() allows num_colors up to 10; the renderer must have a distinct
	# material per colour or higher ids would alias via `% _mats.size()`.
	assert_true(BoardView3D.PALETTE.size() >= 10, "palette must cover all 10 allowed colours")


func test_validate_flags_no_breakables() -> void:
	var lv := _make_level()
	lv.layout = PackedStringArray(["XX.XX", "X.X.X"])
	assert_false(lv.validate().is_empty(), "all-black layout flagged")


func test_validate_allows_spin_and_bounce() -> void:
	var lv := _make_level()
	lv.layout = PackedStringArray(["01S2B", "..120"])  # specials mixed with breakables
	assert_true(lv.validate().is_empty(), "spin/bounce are legal layout chars")


func test_validate_flags_only_indestructibles() -> void:
	var lv := _make_level()
	lv.layout = PackedStringArray(["SB.SB", "X.S.B"])  # no breakable sphere anywhere
	assert_false(lv.validate().is_empty(), "spin/bounce don't count as breakables")


# --- shipped data sweep ----------------------------------------------------------


func test_all_shipped_levels_are_valid() -> void:
	for i in range(1, GameState.LEVEL_COUNT + 1):
		var path := "res://levels/level_%02d.tres" % i
		var lv := load(path) as LevelResource
		assert_not_null(lv, "%s loads as LevelResource" % path)
		if lv == null:
			continue
		assert_eq(lv.id, i, "%s id matches filename" % path)
		assert_eq(lv.validate(), PackedStringArray(), "%s passes validation" % path)
		var m := lv.build_model()
		assert_false(m.is_won(), "%s not instantly won" % path)
		assert_false(m.is_lost(), "%s not instantly lost" % path)
		assert_false(lv.title.is_empty(), "%s has a title" % path)
		assert_false(lv.lore_fragment.is_empty(), "%s has lore" % path)


# --- par_shots -----------------------------------------------------------------


func test_par_shots_defaults_unset() -> void:
	assert_eq(LevelResource.new().par_shots, 0, "par defaults to unset (0)")


func test_validate_allows_zero_par() -> void:
	var lv := _make_level()
	lv.par_shots = 0
	assert_true(lv.validate().is_empty(), "0 par is valid (unset)")


func test_validate_flags_negative_par() -> void:
	var lv := _make_level()
	lv.par_shots = -1
	assert_false(lv.validate().is_empty(), "negative par flagged")


# --- objectives ----------------------------------------------------------------


func _make_free_soul_level() -> LevelResource:
	var lv := _make_level()  # width 5, num_colors 3, danger_row 10
	lv.objective_type = LevelResource.Objective.FREE_SOUL
	lv.objective_color = 1
	lv.layout = PackedStringArray(["0@120", "00120"])  # @ (a caged soul) at (1, 0)
	return lv


func test_tag_parses_to_objective_color() -> void:
	var m := _make_free_soul_level().build_model()
	assert_eq(
		m.cells.get(Vector2i(1, 0)), 1, "@ parses to objective_color as an ordinary breakable"
	)


func test_star_tag_parses_to_objective_color() -> void:
	var lv := _make_level()
	lv.objective_type = LevelResource.Objective.CLEANSE
	lv.objective_color = 2
	lv.layout = PackedStringArray(["0*120", "00120"])
	assert_eq(lv.build_model().cells.get(Vector2i(1, 0)), 2, "* parses to objective_color")
	assert_eq(lv.objective_cells(), [Vector2i(1, 0)] as Array[Vector2i], "* position reported")


func test_objective_cells_lists_tags() -> void:
	assert_eq(
		_make_free_soul_level().objective_cells(),
		[Vector2i(1, 0)] as Array[Vector2i],
		"@ position reported"
	)


func test_objective_cells_empty_for_clear() -> void:
	assert_true(_make_level().objective_cells().is_empty(), "a CLEAR level has no objective cells")


func test_free_soul_level_validates() -> void:
	assert_true(
		_make_free_soul_level().validate().is_empty(), "a well-formed FREE_SOUL level is valid"
	)


func test_validate_flags_tags_on_clear() -> void:
	var lv := _make_level()  # default objective_type CLEAR
	lv.layout = PackedStringArray(["0@120", "00120"])
	assert_false(lv.validate().is_empty(), "tags on a CLEAR level flagged")


func test_validate_flags_objective_without_tags() -> void:
	var lv := _make_level()
	lv.objective_type = LevelResource.Objective.FREE_SOUL  # but no @ anywhere
	assert_false(lv.validate().is_empty(), "an objective with no tagged cell flagged")


func test_validate_flags_objective_color_out_of_range() -> void:
	var lv := _make_free_soul_level()
	lv.objective_color = 9  # >= num_colors 3
	assert_false(lv.validate().is_empty(), "objective_color out of range flagged")


func test_validate_flags_negative_budget() -> void:
	var lv := _make_level()
	lv.shot_budget = -1
	assert_false(lv.validate().is_empty(), "negative shot_budget flagged")


func test_validate_flags_negative_tide() -> void:
	var lv := _make_level()
	lv.tide_rows_per_shot = -2
	assert_false(lv.validate().is_empty(), "negative tide flagged")


func test_objective_met_flips_when_tags_cleared() -> void:
	var lv := _make_free_soul_level()
	var m := lv.build_model()
	var cells := lv.objective_cells()
	assert_false(lv.objective_met(m, cells), "not met while the caged soul is on the board")
	m.cells.erase(Vector2i(1, 0))  # free the soul
	assert_true(lv.objective_met(m, cells), "met once every tagged cell is empty")


func test_objective_met_clear_uses_board_clear() -> void:
	var lv := _make_level()  # CLEAR objective
	var m := lv.build_model()
	assert_false(lv.objective_met(m, []), "CLEAR not met while spheres remain")
	m.cells.clear()
	assert_true(lv.objective_met(m, []), "CLEAR met on an empty board")
