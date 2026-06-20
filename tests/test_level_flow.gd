extends GutTest

## Integration: the play scene driven by a selected level — win/lose end flow,
## unlock side-effect, and the level-loading branch of the controller.
## GameState's progress is swapped to a throwaway file for the duration.

const TEST_SAVE := "user://test_progress_flow.cfg"
const PLAY_SCENE := preload("res://scenes/level_3d.tscn")

var _saved_progress: ProgressStore


func before_each() -> void:
	_saved_progress = GameState.progress
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	GameState.progress = ProgressStore.new(TEST_SAVE)


func after_each() -> void:
	GameState.progress = _saved_progress
	GameState.selected_index = -1
	GameState.selected_level = null
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))


func _spawn_level(index: int) -> LevelController3D:
	GameState.selected_index = index
	GameState.selected_level = GameState.load_level(index)
	assert_not_null(GameState.selected_level, "level %d loads" % index)
	var scene: LevelController3D = PLAY_SCENE.instantiate()
	add_child_autofree(scene)
	return scene


func test_controller_builds_board_from_level() -> void:
	var scene := _spawn_level(1)
	await wait_physics_frames(2)
	assert_eq(scene.columns, 9, "level 1 width applied")
	assert_eq(scene.danger_row, 14, "level 1 danger row applied")
	assert_eq(scene.model.count_colored(), 36, "level 1 layout: 36 spheres in its top 4 rows")


func _count_value(model: GridModel, value: int) -> int:
	var n := 0
	for v in model.cells.values():
		if v == value:
			n += 1
	return n


## The play scene builds its board VIEW asynchronously behind a loading veil (chunked spawn
## over a few process frames), so a fixed wait races it. Poll until every model cell has a
## live sphere (or a generous frame cap), then callers can assert on board._spheres.
func _await_board_built(scene: LevelController3D) -> void:
	var guard := 0
	while scene.board._spheres.size() < scene.model.cells.size() and guard < 300:
		await wait_frames(1)
		guard += 1


func test_special_levels_build_without_error() -> void:
	# Spawning the play scene runs the full controller: it builds the _specials map and
	# assigns the swirl/pulse materials to every spin/bounce sphere via board._build_all.
	# A missing dispatch key would crash here, so reaching the asserts proves the wiring.
	for spec in [
		{"idx": 11, "spin": 1, "bounce": 0, "colored": 35},
		{"idx": 12, "spin": 0, "bounce": 1, "colored": 35},
		{"idx": 15, "spin": 2, "bounce": 2, "colored": 68},
	]:
		var scene := _spawn_level(spec.idx)
		await _await_board_built(scene)
		assert_eq(
			_count_value(scene.model, GridModel.SPIN), spec.spin, "level %d spin count" % spec.idx
		)
		assert_eq(
			_count_value(scene.model, GridModel.BOUNCE),
			spec.bounce,
			"level %d bounce count" % spec.idx
		)
		assert_eq(scene.model.count_colored(), spec.colored, "level %d coloured count" % spec.idx)
		assert_false(scene.model.is_won(), "level %d not instantly won" % spec.idx)
		# Every model cell — colours and specials alike — got a live sphere built for it.
		assert_eq(
			scene.board._spheres.size(),
			scene.model.cells.size(),
			"level %d board built all spheres" % spec.idx
		)
		# _spawn_level registered the scene with add_child_autofree; it's freed at teardown.


func test_win_unlocks_next_and_shows_descend() -> void:
	var scene := _spawn_level(1)
	await wait_physics_frames(2)
	scene._end("test win", true)
	assert_true(GameState.progress.is_unlocked(2), "winning level 1 unlocks 2")
	assert_true(scene.end_panel.visible, "end panel shown")
	assert_true(scene.next_button.visible, "next offered on a win")
	assert_false(scene.retry_button.visible, "no retry on a win")


func test_lose_offers_retry_without_unlock() -> void:
	var scene := _spawn_level(1)
	await wait_physics_frames(2)
	scene._end("test loss", false)
	assert_false(GameState.progress.is_unlocked(2), "losing unlocks nothing")
	assert_true(scene.end_panel.visible, "end panel shown")
	assert_true(scene.retry_button.visible, "retry offered on a loss")
	assert_false(scene.next_button.visible, "no descend on a loss")


func test_winning_last_level_offers_no_next() -> void:
	var scene := _spawn_level(1)
	await wait_physics_frames(2)
	GameState.selected_index = GameState.LEVEL_COUNT  # pretend it was the last level
	scene._end("test win", true)
	assert_false(scene.next_button.visible, "no descend below the bottom")


# --- secondary objectives (E3.4) ----------------------------------------------
# Built in code (like test_level_resource's _make_level) and handed to the play scene via
# GameState.selected_level, so no campaign-level / region coupling is needed to prove them.


func _spawn_custom(level: LevelResource) -> LevelController3D:
	GameState.selected_index = -1  # not a campaign level — no unlock side effects
	GameState.selected_level = level
	var scene: LevelController3D = PLAY_SCENE.instantiate()
	add_child_autofree(scene)
	return scene


func _headroom(top: PackedStringArray, total_rows: int, width: int) -> PackedStringArray:
	# Pad a small authored top with empty rows so the board has descent headroom.
	var out := top.duplicate()
	while out.size() < total_rows:
		out.append(".".repeat(width))
	return out


func _free_soul_level() -> LevelResource:
	var lv := LevelResource.new()
	lv.id = 1
	lv.title = "Cage Test"
	lv.width = 5
	lv.num_colors = 3
	lv.danger_row = 8
	lv.objective_type = LevelResource.Objective.FREE_SOUL
	lv.objective_color = 0
	lv.layout = _headroom(PackedStringArray(["0@120", "00120"]), 8, 5)
	return lv


func test_free_soul_met_when_cage_cleared() -> void:
	var scene := _spawn_custom(_free_soul_level())
	await wait_physics_frames(2)
	assert_false(scene._is_objective_met(), "not yet — the caged soul is still on the board")
	for cell in scene._objective_cells:
		scene.model.cells.erase(cell)
	assert_true(scene._is_objective_met(), "freeing every tagged cell meets the objective")


func _sniper_level() -> LevelResource:
	var lv := LevelResource.new()
	lv.id = 1
	lv.title = "Sniper Test"
	lv.width = 5
	lv.num_colors = 3
	lv.danger_row = 8
	lv.shot_budget = 3
	lv.layout = _headroom(PackedStringArray(["01210", "21012"]), 8, 5)
	return lv


func test_sniper_fails_when_budget_spent_unmet() -> void:
	var scene := _spawn_custom(_sniper_level())
	await wait_physics_frames(2)
	scene._shots_fired = 3  # budget exhausted, board not cleared
	assert_true(scene._is_failed(), "a spent Sniper budget with the objective unmet is a loss")


func test_sniper_win_on_final_shot_is_not_a_fail() -> void:
	var scene := _spawn_custom(_sniper_level())
	await wait_physics_frames(2)
	scene._shots_fired = 3  # the last shot of the budget...
	scene.model.cells.clear()  # ...also cleared the board
	assert_true(scene._is_objective_met(), "the board is clear -> objective met")
	assert_false(scene._is_failed(), "met always beats failed, even at the budget limit")


func _tide_level() -> LevelResource:
	var lv := LevelResource.new()
	lv.id = 1
	lv.title = "Tide Test"
	lv.width = 5
	lv.num_colors = 3
	lv.danger_row = 6
	lv.tide_rows_per_shot = 2
	lv.layout = _headroom(PackedStringArray(["01210", "21012"]), 6, 5)
	return lv


func test_tide_eventually_drowns_the_board() -> void:
	var scene := _spawn_custom(_tide_level())
	await wait_physics_frames(2)
	assert_false(scene._is_failed(), "safe at the start")
	# Drive the tide directly (the controller does this once per shot via _apply_tide).
	for i in range(4):
		scene.model.descend(scene._level.tide_rows_per_shot)
	assert_true(scene.model.is_lost(), "the tide eventually pushes the field across the line")
	assert_true(scene._is_failed(), "and that registers as a failure")
