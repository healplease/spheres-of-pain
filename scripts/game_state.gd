extends Node

## Autoload (registered as GameState): owns scene flow, the currently selected
## level, and unlock progress. All navigation between menu / level select / play
## goes through here so no scene hardcodes another scene's path.

const LEVEL_COUNT := 10
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const LEVEL_SELECT_SCENE := "res://scenes/level_select.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"
const PLAY_SCENE := "res://scenes/level_3d.tscn"

var progress := ProgressStore.new()
var selected_index: int = -1            # -1 = free play (random board)
var selected_level: LevelResource = null
## False until the main menu has played its startup intro once. Lives here (not in
## the menu) because the menu scene is reloaded on every return — this autoload
## persists, so the title reveal fires only on the very first menu load per run.
var intro_played: bool = false


static func level_path(i: int) -> String:
	return "res://levels/level_%02d.tres" % i


## Load + validate a level file; null (with a pushed error) on any problem so a
## broken data file degrades to a disabled button, not a crash.
func load_level(i: int) -> LevelResource:
	var path := level_path(i)
	var lv := load(path) as LevelResource
	if lv == null:
		Log.error(Log.FLOW, "level load failed", {"index": i, "path": path})
		return null
	var problems := lv.validate()
	if not problems.is_empty():
		Log.error(Log.FLOW, "level invalid", {"index": i, "problems": "; ".join(problems)})
		return null
	return lv


func start_level(i: int) -> void:
	var lv := load_level(i)
	if lv == null:
		return
	selected_index = i
	selected_level = lv
	Log.info(Log.FLOW, "enter level", {"index": i, "title": lv.title})
	get_tree().change_scene_to_file(PLAY_SCENE)


func retry_level() -> void:
	if selected_index > 0:
		start_level(selected_index)


func has_next() -> bool:
	return selected_index > 0 and selected_index < LEVEL_COUNT


func start_next() -> void:
	if has_next():
		start_level(selected_index + 1)


## Called by the play controller on a win of the selected level.
func complete_current() -> void:
	if selected_index > 0:
		progress.mark_completed(selected_index)
		Log.info(Log.FLOW, "level completed", {
			"index": selected_index, "unlocked_through": progress.highest_unlocked})


func go_to_main_menu() -> void:
	selected_index = -1
	selected_level = null
	Log.info(Log.FLOW, "scene", {"to": "main_menu"})
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func go_to_level_select() -> void:
	selected_index = -1
	selected_level = null
	Log.info(Log.FLOW, "scene", {"to": "level_select"})
	get_tree().change_scene_to_file(LEVEL_SELECT_SCENE)


func go_to_settings() -> void:
	selected_index = -1
	selected_level = null
	Log.info(Log.FLOW, "scene", {"to": "settings"})
	get_tree().change_scene_to_file(SETTINGS_SCENE)
