extends GutTest

## Smoke + wiring test for the 3D world map: instantiating the scene runs the whole controller
## _ready (env, camera/rig, 30 markers, roads, UI, the completion-transition setup), so reaching
## the asserts proves it builds without a runtime error. GameState.progress is swapped to a
## throwaway so marker states are deterministic.

const MAP_SCENE := preload("res://scenes/world_map.tscn")
const TEST_SAVE := "user://test_world_map.cfg"
const ST := WorldUnlock.State

var _saved_progress: WorldProgress


func before_each() -> void:
	_saved_progress = GameState.progress
	_wipe()
	GameState.progress = WorldProgress.new(TEST_SAVE)
	GameState.just_completed_id = -1


func after_each() -> void:
	GameState.progress = _saved_progress
	GameState.just_completed_id = -1
	_wipe()


func _wipe() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))


func _spawn() -> WorldMapController:
	var map: WorldMapController = MAP_SCENE.instantiate()
	add_child_autofree(map)
	return map


func test_map_builds_a_marker_per_node() -> void:
	var map := _spawn()
	await wait_frames(2)
	assert_eq(map._markers.size(), 30, "one marker per campaign node")
	assert_true(map._markers.has(1), "the start node has a marker")


func test_marker_states_reflect_a_fresh_save() -> void:
	var map := _spawn()
	await wait_frames(2)
	assert_eq(map._markers[1]._state, ST.AVAILABLE, "the start node is available on a fresh save")
	assert_eq(map._markers[2]._state, ST.LOCKED, "its successor is still locked")
	assert_eq(map._markers[25]._state, ST.LOCKED, "the final boss is locked")


func test_clicking_a_node_opens_the_detail_panel() -> void:
	var map := _spawn()
	await wait_frames(2)
	map._on_node_clicked(1)
	assert_eq(map._selected_id, 1, "the clicked node is selected")
	assert_true(map._detail.is_open(), "the detail panel opens")
	map._close_detail()
	await wait_frames(1)


func test_completion_transition_is_wired_on_return_from_a_win() -> void:
	# Pretend we just beat node 1: it forks to 2 and 9, both freshly available.
	GameState.progress.mark_completed(1)
	GameState.just_completed_id = 1
	var map := _spawn()
	await wait_frames(2)
	assert_eq(GameState.just_completed_id, -1, "the flag is consumed by the map")
	assert_eq(map._transition_node, 1, "the cleared node drives the transition")
	assert_true(2 in map._transition_newly, "the fork's spine child animates in")
	assert_true(9 in map._transition_newly, "the fork's branch child animates in too")
