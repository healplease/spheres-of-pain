extends GutTest

## Tests for LevelAuthoring: packing an editor GridModel back into a LevelResource —
## layout strings, derived num_colors / danger_row, trailing-row trimming — and that
## the result round-trips back through LevelResource.build_model() to the same cells.


func _model(width: int) -> GridModel:
	var m := GridModel.new()
	m.width = width
	return m


# --- char mapping (inverse of build_model) ------------------------------------


func test_char_for_breakables_and_sentinels() -> void:
	assert_eq(LevelAuthoring.char_for(0), "0", "colour 0 -> '0'")
	assert_eq(LevelAuthoring.char_for(7), "7", "colour 7 -> '7'")
	assert_eq(LevelAuthoring.char_for(GridModel.BLACK), "X", "black -> 'X'")
	assert_eq(LevelAuthoring.char_for(GridModel.SPIN), "S", "spin -> 'S'")
	assert_eq(LevelAuthoring.char_for(GridModel.BOUNCE), "B", "bounce -> 'B'")


# --- num_colors derivation ----------------------------------------------------


func test_num_colors_is_highest_id_plus_one() -> void:
	var m := _model(5)
	m.cells[Vector2i(0, 0)] = 0
	m.cells[Vector2i(1, 0)] = 3  # highest breakable id
	m.cells[Vector2i(2, 0)] = GridModel.BLACK  # sentinels ignored
	assert_eq(LevelAuthoring.derive_num_colors(m), 4, "max id 3 -> num_colors 4")


func test_num_colors_clamped_to_one_when_no_breakables() -> void:
	var m := _model(5)
	m.cells[Vector2i(0, 0)] = GridModel.BLACK
	assert_eq(LevelAuthoring.derive_num_colors(m), 1, "no breakables -> clamped to 1")


# --- layout packing -----------------------------------------------------------


func test_layout_rows_padded_to_width() -> void:
	var m := _model(5)
	m.cells[Vector2i(0, 0)] = 0
	m.cells[Vector2i(2, 0)] = 2
	m.cells[Vector2i(4, 0)] = GridModel.BLACK
	var lv := LevelAuthoring.to_level(m, 8, "T", "L")
	assert_eq(lv.layout.size(), 8, "the whole field height is emitted, empty rows and all")
	assert_eq(lv.layout[0], "0.2.X", "gaps -> '.', sentinel -> 'X', padded to width")
	assert_eq(lv.layout[7], ".....", "trailing empty row kept as headroom")


func test_layout_keeps_all_rows_including_empty_headroom() -> void:
	var m := _model(3)
	m.cells[Vector2i(0, 0)] = 1
	m.cells[Vector2i(1, 2)] = 2  # leaves row 1 entirely empty between two occupied rows
	var lv := LevelAuthoring.to_level(m, 6, "T", "L")
	assert_eq(lv.layout.size(), 6, "all 6 field rows emitted; nothing trimmed")
	assert_eq(lv.layout[0], "1..", "row 0")
	assert_eq(lv.layout[1], "...", "internal empty row preserved")
	assert_eq(lv.layout[2], ".2.", "deepest sphere row")
	assert_eq(lv.layout[5], "...", "trailing empty row kept as headroom")


func test_danger_row_is_field_height() -> void:
	var m := _model(4)
	m.cells[Vector2i(0, 0)] = 0
	var lv := LevelAuthoring.to_level(m, 6, "T", "L")
	assert_eq(lv.danger_row, 6, "danger_row sits at the field's bottom edge (= height)")
	assert_eq(lv.danger_row, lv.layout.size(), "danger_row == layout.size()")


func test_metadata_copied() -> void:
	var m := _model(4)
	m.cells[Vector2i(0, 0)] = 0
	var lv := LevelAuthoring.to_level(m, 6, "My Pit", "a tagline")
	assert_eq(lv.title, "My Pit", "title copied")
	assert_eq(lv.lore_fragment, "a tagline", "tagline -> lore_fragment")
	assert_eq(lv.width, 4, "width copied from model")


# --- validity + round-trip ----------------------------------------------------


func test_authored_level_validates() -> void:
	var m := _model(5)
	m.cells[Vector2i(0, 0)] = 0
	m.cells[Vector2i(1, 0)] = 1
	m.cells[Vector2i(2, 0)] = GridModel.SPIN
	var lv := LevelAuthoring.to_level(m, 6, "T", "L")
	assert_eq(lv.validate(), PackedStringArray(), "a normal authored board is valid")


func test_empty_board_reports_no_breakables() -> void:
	var lv := LevelAuthoring.to_level(_model(5), 6, "T", "L")
	assert_false(
		lv.validate().is_empty(), "an empty board is rejected (no breakables / empty layout)"
	)


func test_round_trips_through_build_model() -> void:
	var m := _model(6)
	m.cells[Vector2i(0, 0)] = 0
	m.cells[Vector2i(3, 0)] = 5
	m.cells[Vector2i(2, 1)] = GridModel.BLACK
	m.cells[Vector2i(4, 1)] = GridModel.BOUNCE
	m.cells[Vector2i(1, 2)] = 2
	var rebuilt := LevelAuthoring.to_level(m, 7, "T", "L").build_model()
	assert_eq(rebuilt.cells, m.cells, "to_level -> build_model reproduces the exact cells")
	assert_eq(rebuilt.width, 6, "width survives the round-trip")
