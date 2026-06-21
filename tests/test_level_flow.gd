extends GutTest

## Integration: the play scene driven by a selected campaign node — win/lose end flow, the
## completion side-effect (now a set-based WorldProgress mark + just_completed flag), and the
## level-loading + specials branches of the controller. GameState's progress is swapped to a
## throwaway file for the duration so the real save is never touched.

const TEST_SAVE := "user://test_world_flow.cfg"
const PLAY_SCENE := preload("res://scenes/level_3d.tscn")

var _saved_progress: WorldProgress


func before_each() -> void:
	_saved_progress = GameState.progress
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	GameState.progress = WorldProgress.new(TEST_SAVE)
	GameState.just_completed_id = -1


func after_each() -> void:
	GameState.progress = _saved_progress
	GameState.selected_index = -1
	GameState.selected_level = null
	GameState.just_completed_id = -1
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))


func _spawn_level(index: int) -> LevelController3D:
	GameState.selected_index = index
	GameState.selected_level = GameState.load_level(index)
	assert_not_null(GameState.selected_level, "level %d loads" % index)
	var scene: LevelController3D = PLAY_SCENE.instantiate()
	add_child_autofree(scene)
	return scene


func _count_value(model: GridModel, value: int) -> int:
	var n := 0
	for v in model.cells.values():
		if v == value:
			n += 1
	return n


## The play scene builds its board VIEW asynchronously behind a loading veil (chunked spawn over a
## few process frames), so a fixed wait races it. Poll until every model cell has a live sphere.
func _await_board_built(scene: LevelController3D) -> void:
	var guard := 0
	while scene.board._spheres.size() < scene.model.cells.size() and guard < 300:
		await wait_frames(1)
		guard += 1


func test_controller_builds_board_from_level() -> void:
	var scene := _spawn_level(1)
	await wait_physics_frames(2)
	assert_eq(scene.columns, 9, "level 1 width applied")
	assert_eq(scene.danger_row, 14, "level 1 danger row applied")
	assert_eq(scene.model.count_colored(), 36, "level 1 layout: 36 spheres in its top 4 rows")


func test_boss_levels_build_specials_without_error() -> void:
	# Boss boards carry spin/bounce spheres; building them runs the controller's specials wiring
	# (swirl/pulse materials). A missing dispatch key would crash here, so reaching the asserts
	# proves the wiring across all three bosses.
	for spec in [
		{"idx": 5, "spin": true, "bounce": false},  # The Tally-Keeper
		{"idx": 15, "spin": true, "bounce": true},  # The Choirmistress
		{"idx": 25, "spin": true, "bounce": true},  # The Last Warden
	]:
		var scene := _spawn_level(spec.idx)
		await _await_board_built(scene)
		assert_false(scene.model.is_won(), "boss %d not instantly won" % spec.idx)
		if spec.spin:
			assert_gt(_count_value(scene.model, GridModel.SPIN), 0, "boss %d has spin" % spec.idx)
		if spec.bounce:
			assert_gt(
				_count_value(scene.model, GridModel.BOUNCE), 0, "boss %d has bounce" % spec.idx
			)
		assert_eq(
			scene.board._spheres.size(),
			scene.model.cells.size(),
			"boss %d board built all spheres" % spec.idx
		)


func test_win_marks_completed_and_returns_to_map() -> void:
	var scene := _spawn_level(1)
	await wait_physics_frames(2)
	scene._end("test win", true)
	assert_true(GameState.progress.is_completed(1), "winning node 1 marks it completed")
	assert_eq(GameState.just_completed_id, 1, "the win flags the node for the map transition")
	assert_eq(GameState.node_state(2), WorldUnlock.State.AVAILABLE, "and unlocks its successor")
	assert_true(scene.end_panel.visible, "end panel shown")
	assert_false(scene.next_button.visible, "no auto-next — the branching map is the hub")
	assert_true(scene.retry_button.visible, "retry offered on a win (replay for a better verdict)")


func test_lose_offers_retry_without_completion() -> void:
	var scene := _spawn_level(1)
	await wait_physics_frames(2)
	scene._end("test loss", false)
	assert_false(GameState.progress.is_completed(1), "losing completes nothing")
	assert_eq(GameState.just_completed_id, -1, "a loss flags no completion")
	assert_true(scene.end_panel.visible, "end panel shown")
	assert_true(scene.retry_button.visible, "retry offered on a loss")
	assert_false(scene.next_button.visible, "no descend button at all now")


func test_final_boss_completes_the_descent() -> void:
	# Logic-only (no play scene): completing the region-3 boss is what ends the whole descent.
	assert_true(GameState.is_final_boss(25), "node 25 is the final boss")
	assert_false(GameState.is_final_boss(5), "an earlier boss is not the final one")
	assert_false(GameState.is_descent_complete(), "not complete on a fresh throwaway save")
	GameState.progress.mark_completed(25)
	assert_true(GameState.is_descent_complete(), "beating the final boss completes the descent")


# --- secondary objectives (E3.4) ----------------------------------------------
# Built in code (like test_level_resource's _make_level) and handed to the play scene via
# GameState.selected_level, so no campaign-node / region coupling is needed to prove them.


func _spawn_custom(level: LevelResource) -> LevelController3D:
	GameState.selected_index = -1  # not a campaign node — no completion side effects
	GameState.selected_level = level
	var scene: LevelController3D = PLAY_SCENE.instantiate()
	add_child_autofree(scene)
	return scene


func _headroom(top: PackedStringArray, total_rows: int, width: int) -> PackedStringArray:
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
	for i in range(4):
		scene.model.descend(scene._level.tide_rows_per_shot)
	assert_true(scene.model.is_lost(), "the tide eventually pushes the field across the line")
	assert_true(scene._is_failed(), "and that registers as a failure")
