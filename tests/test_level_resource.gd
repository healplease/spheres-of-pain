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
	var lv := _make_level()       # layout is 2 rows (indices 0,1)
	lv.danger_row = 1             # a row that authored spheres occupy -> on/over the line
	assert_false(lv.validate().is_empty(), "danger_row inside the layout flagged")


func test_validate_allows_danger_row_just_below_layout() -> void:
	var lv := _make_level()       # layout is 2 rows
	lv.danger_row = lv.layout.size()   # the first empty row below the layout: valid
	assert_true(lv.validate().is_empty(), "danger_row == rows is the tightest valid line")


func test_validate_flags_no_breakables() -> void:
	var lv := _make_level()
	lv.layout = PackedStringArray(["XX.XX", "X.X.X"])
	assert_false(lv.validate().is_empty(), "all-black layout flagged")


# --- shipped data sweep ----------------------------------------------------------

func test_all_shipped_levels_are_valid() -> void:
	for i in range(1, 11):
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
