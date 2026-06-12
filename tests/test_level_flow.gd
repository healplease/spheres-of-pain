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
	assert_eq(scene.danger_row, 12, "level 1 danger row applied")
	assert_eq(scene.model.count_colored(), 36, "level 1 layout: 9x4 spheres")


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
	GameState.selected_index = GameState.LEVEL_COUNT  # pretend it was level 10
	scene._end("test win", true)
	assert_false(scene.next_button.visible, "no descend below the bottom")
