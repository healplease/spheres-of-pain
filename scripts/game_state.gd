extends Node

## Autoload (registered as GameState): owns scene flow, the currently selected
## level, and unlock progress. All navigation between menu / level select / play
## goes through here so no scene hardcodes another scene's path.

const LEVEL_COUNT := 15
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const LEVEL_SELECT_SCENE := "res://scenes/level_select.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"
const PLAY_SCENE := "res://scenes/level_3d.tscn"
const EDITOR_SCENE := "res://scenes/level_editor.tscn"
const MY_LEVELS_SCENE := "res://scenes/my_levels.tscn"

var progress := ProgressStore.new()
var selected_index: int = -1  # -1 = free play / draft / user level (no unlock progress)
var selected_level: LevelResource = null
## Where a play exit (Esc / door / end-panel "menu") returns to. Built-in levels go
## back to level select; an editor playtest to the editor; a My Levels play to My
## Levels. Set on every entry into the play scene so an exit always lands right.
var return_scene: String = LEVEL_SELECT_SCENE
## The level currently open in the editor, preserved across a playtest so exiting the
## test restores the in-progress draft. Also set when opening a saved level to edit;
## cleared when starting a fresh "Create level".
var editor_draft: LevelResource = null
## The user:// path the editor is editing ("" for a new, never-saved draft); a Save
## overwrites this path instead of creating a second file.
var editor_source_path: String = ""
## False until the main menu has played its startup intro once. Lives here (not in
## the menu) because the menu scene is reloaded on every return — this autoload
## persists, so the title reveal fires only on the very first menu load per run.
var intro_played: bool = false


static func level_path(i: int) -> String:
	return "res://levels/level_%02d.tres" % i


## Load + validate a built-in level file; null (with a pushed error) on any problem
## so a broken data file degrades to a disabled button, not a crash.
func load_level(i: int) -> LevelResource:
	return load_validated(level_path(i), str(i))


## Load + validate any LevelResource by path (built-in or user://). `label` is purely
## for the log line. Returns null on a missing file or any validation problem.
func load_validated(path: String, label: String) -> LevelResource:
	var lv := load(path) as LevelResource
	if lv == null:
		Log.error(Log.FLOW, "level load failed", {"id": label, "path": path})
		return null
	var problems := lv.validate()
	if not problems.is_empty():
		Log.error(Log.FLOW, "level invalid", {"id": label, "problems": "; ".join(problems)})
		return null
	return lv


func start_level(i: int) -> void:
	var lv := load_level(i)
	if lv == null:
		return
	selected_index = i
	selected_level = lv
	return_scene = LEVEL_SELECT_SCENE
	Log.info(Log.FLOW, "enter level", {"index": i, "title": lv.title})
	get_tree().change_scene_to_file(PLAY_SCENE)


## Replay the level currently loaded. Authored levels reload by index (re-validating
## from disk); a draft or user level (index <= 0) just reloads the play scene, whose
## _ready rebuilds from the still-set selected_level. selected_level + return_scene
## persist across the reload, so a retry also returns to the right place.
func retry_level() -> void:
	if selected_index > 0:
		start_level(selected_index)
	elif selected_level != null:
		Log.info(Log.FLOW, "retry", {"title": selected_level.title})
		get_tree().change_scene_to_file(PLAY_SCENE)


func has_next() -> bool:
	return selected_index > 0 and selected_index < LEVEL_COUNT


func start_next() -> void:
	if has_next():
		start_level(selected_index + 1)


## Called by the play controller on a win of the selected level.
func complete_current() -> void:
	if selected_index > 0:
		progress.mark_completed(selected_index)
		Log.info(
			Log.FLOW,
			"level completed",
			{"index": selected_index, "unlocked_through": progress.highest_unlocked}
		)


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


# --- editor / user levels -----------------------------------------------------


## The single exit from the play scene (Esc, the door button, the end-panel "menu").
## Returns to whatever launched the level. editor_draft is deliberately NOT cleared,
## so returning to the editor after a playtest restores the in-progress draft.
func go_back_from_play() -> void:
	selected_index = -1
	selected_level = null
	Log.info(Log.FLOW, "scene", {"to": return_scene})
	get_tree().change_scene_to_file(return_scene)


## Playtest an in-editor draft: run it like an authored level but with no progress
## side effects (index -1); exiting returns to the editor with the draft intact.
func play_draft(level: LevelResource) -> void:
	selected_index = -1
	selected_level = level
	editor_draft = level
	return_scene = EDITOR_SCENE
	Log.info(Log.FLOW, "enter level", {"mode": "draft", "title": level.title})
	get_tree().change_scene_to_file(PLAY_SCENE)


## Play a saved user level (free play — always unlocked, no progress); exiting returns
## to the My Levels list.
func play_user_level(path: String) -> void:
	var lv := load_validated(path, path.get_file())
	if lv == null:
		return
	selected_index = -1
	selected_level = lv
	return_scene = MY_LEVELS_SCENE
	Log.info(Log.FLOW, "enter level", {"mode": "user", "title": lv.title, "path": path})
	get_tree().change_scene_to_file(PLAY_SCENE)


func go_to_my_levels() -> void:
	Log.info(Log.FLOW, "scene", {"to": "my_levels"})
	get_tree().change_scene_to_file(MY_LEVELS_SCENE)


## Open the editor on a blank new level.
func go_to_create_level() -> void:
	editor_draft = null
	editor_source_path = ""
	Log.info(Log.FLOW, "scene", {"to": "level_editor", "mode": "create"})
	get_tree().change_scene_to_file(EDITOR_SCENE)


## Open the editor pre-filled with a saved user level; a Save overwrites that file.
func go_to_edit_level(path: String) -> void:
	var lv := load_validated(path, path.get_file())
	if lv == null:
		return
	editor_draft = lv
	editor_source_path = path
	Log.info(Log.FLOW, "scene", {"to": "level_editor", "mode": "edit", "path": path})
	get_tree().change_scene_to_file(EDITOR_SCENE)
