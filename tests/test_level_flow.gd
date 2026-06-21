extends GutTest

## Integration: the play scene driven by a selected level — win/lose end flow,
## unlock side-effect, and the level-loading branch of the controller.
## GameState's progress is swapped to a throwaway file for the duration.

const TEST_SAVE := "user://test_progress_flow.cfg"

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
	var scene: LevelController3D = load("res://scenes/level_3d.tscn").instantiate()
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
		await wait_physics_frames(2)
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
