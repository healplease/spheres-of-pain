# gdlint:disable=max-public-methods
extends Node

## This autoload is the project's navigation/state facade, so it legitimately exposes many
## small public methods (scene transitions + region/level lookups) — the metric is a false
## positive here; suppressed per the project's gdlint convention (directive must be line 1).

## Autoload (registered as GameState): owns scene flow, the currently selected
## level, and unlock progress. All navigation between menu / level select / play
## goes through here so no scene hardcodes another scene's path.

const LEVEL_COUNT := 30  # campaign nodes/levels, 1..30 (3 regions x 10); each maps to level_NN.tres
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
# The campaign hub is the 3D draggable world map (replaces the old vertical descent list).
# Repointing this const reroutes go_to_level_select(), the default return_scene, and the
# end-panel "menu" exit in one place.
const LEVEL_SELECT_SCENE := "res://scenes/world_map.tscn"
const WORLD_GRAPH_PATH := "res://world/world_graph.tres"
const SETTINGS_SCENE := "res://scenes/settings.tscn"
const PLAY_SCENE := "res://scenes/level_3d.tscn"
const EDITOR_SCENE := "res://scenes/level_editor.tscn"
const MY_LEVELS_SCENE := "res://scenes/my_levels.tscn"
const EPILOGUE_SCENE := "res://scenes/epilogue.tscn"

## The named regions of the descent, in order. Each groups a set of world-map nodes (see
## RegionResource); the world map tints them and the Narrator keys region sub-pools by their
## id. Loaded lazily + cached on first use.
const REGION_PATHS := [
	"res://regions/region_1_ossuary.tres",
	"res://regions/region_2_cloister.tres",
	"res://regions/region_3_vigil.tres",
]

var progress := WorldProgress.new()
# active campaign NODE id (== level index); -1 = free play / draft / user level
var selected_index: int = -1
var selected_level: LevelResource = null
## The node just won, for the world map's completion transition (orange->green + newly-unlocked
## successors grey->orange). Set by complete_current(); the map consumes + clears it on _ready.
var just_completed_id: int = -1
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

## Cached region resources (lazy — built on first regions() call so a broken region file
## degrades to "no grouping", not a boot crash).
var _regions: Array[RegionResource] = []
## Cached world graph (lazy, like regions()) — the branching node/edge map the world map renders
## and WorldUnlock derives availability from.
var _world_graph: WorldGraphResource = null
## True once a background threaded load of the play scene has been requested (and not yet
## consumed). Launch screens kick this off in their _ready so the (heavy-to-parse) play scene
## loads off the main thread while the player reads the menu; entering play then swaps to the
## ready PackedScene with no synchronous file load. Reset when the scene is taken.
var _play_scene_requested: bool = false


static func level_path(i: int) -> String:
	return "res://levels/level_%02d.tres" % i


## The descent's regions, in order. Loaded + cached once; a region file that fails to load
## is skipped (logged), so the map/narrator degrade gracefully rather than crash.
func regions() -> Array[RegionResource]:
	if _regions.is_empty():
		for p: String in REGION_PATHS:
			var r := load(p) as RegionResource
			if r == null:
				Log.error(Log.FLOW, "region load failed", {"path": p})
				continue
			_regions.append(r)
	return _regions


## The region a world-map node belongs to, or null if none claims it.
func region_for_node(node_id: int) -> RegionResource:
	for r in regions():
		if r.contains_node(node_id):
			return r
	return null


## The region id for a node (for Narrator region sub-pools); -1 when no region claims it.
func region_id_for_node(node_id: int) -> int:
	var r := region_for_node(node_id)
	return r.id if r != null else -1


# --- world graph --------------------------------------------------------------


## The branching descent graph, loaded + cached once (a missing/broken file logs and returns null,
## degrading the map to empty rather than crashing). Mirrors regions().
func world_graph() -> WorldGraphResource:
	if _world_graph == null:
		_world_graph = load(WORLD_GRAPH_PATH) as WorldGraphResource
		if _world_graph == null:
			Log.error(Log.FLOW, "world graph load failed", {"path": WORLD_GRAPH_PATH})
	return _world_graph


## Display state of one node (COMPLETED / AVAILABLE / LOCKED), derived from the graph + progress.
func node_state(id: int) -> WorldUnlock.State:
	return WorldUnlock.node_state(world_graph(), id, progress.completed_set())


## Whole-map id -> WorldUnlock.State; the world map colours its markers from this.
func node_states() -> Dictionary:
	return WorldUnlock.all_states(world_graph(), progress.completed_set())


## Every currently-reachable node id (for focus targeting on the map).
func available_ids() -> PackedInt32Array:
	return WorldUnlock.available_ids(world_graph(), progress.completed_set())


## The final region's boss node — beating it ends the whole descent.
func final_boss_node_id() -> int:
	var rs := regions()
	return rs.back().boss_node_id if not rs.is_empty() else 0


func is_final_boss(node_id: int) -> bool:
	return node_id > 0 and node_id == final_boss_node_id()


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


# --- play scene loading -------------------------------------------------------


## Begin loading the play scene off the main thread. Called from the launch screens'
## _ready (descent map, my levels, editor) so the scene parses while the player is still
## choosing — by the time they pick a level it's usually ready, and entering play is an
## instant in-memory swap instead of a synchronous file parse. Idempotent: a second call
## while a request is still outstanding is a no-op (the request is consumed on entry).
func preload_play_scene() -> void:
	if _play_scene_requested:
		return
	# use_sub_threads=true lets the worker pool parse sub-resources in parallel.
	if ResourceLoader.load_threaded_request(PLAY_SCENE, "", true) == OK:
		_play_scene_requested = true


## The preloaded play scene if the background load has finished, else null (caller then
## falls back to change_scene_to_file, which is still cache-warmed by the in-flight load).
## Only consumes the request once the load is fully done, so it never blocks.
func _take_play_scene() -> PackedScene:
	if not _play_scene_requested:
		return null
	if ResourceLoader.load_threaded_get_status(PLAY_SCENE) != ResourceLoader.THREAD_LOAD_LOADED:
		return null
	_play_scene_requested = false
	return ResourceLoader.load_threaded_get(PLAY_SCENE) as PackedScene


## Switch to the play scene, preferring the off-thread preloaded copy (instant) and
## falling back to a synchronous file load if it isn't ready yet.
func _enter_play_scene() -> void:
	var ps := _take_play_scene()
	if ps != null:
		get_tree().change_scene_to_packed(ps)
	else:
		get_tree().change_scene_to_file(PLAY_SCENE)


func start_level(i: int) -> void:
	var lv := load_level(i)
	if lv == null:
		return
	selected_index = i
	selected_level = lv
	return_scene = LEVEL_SELECT_SCENE
	Log.info(Log.FLOW, "enter level", {"index": i, "title": lv.title})
	_enter_play_scene()


## Enter a campaign node from the world map. Node id == campaign level index, so this loads
## levels/level_NN.tres; the graph lookup just guards against an unknown id. All nodes are playable
## (dead-ends are harder bonus levels), so there is no lore-only path here.
func start_node(id: int) -> void:
	if world_graph().node(id) == null:
		Log.error(Log.FLOW, "start_node: unknown node", {"id": id})
		return
	start_level(id)


## Replay the level currently loaded. Authored levels reload by index (re-validating
## from disk); a draft or user level (index <= 0) just reloads the play scene, whose
## _ready rebuilds from the still-set selected_level. selected_level + return_scene
## persist across the reload, so a retry also returns to the right place.
func retry_level() -> void:
	if selected_index > 0:
		start_level(selected_index)
	elif selected_level != null:
		Log.info(Log.FLOW, "retry", {"title": selected_level.title})
		_enter_play_scene()


func has_next() -> bool:
	return selected_index > 0 and selected_index < LEVEL_COUNT


## True once the whole descent has been cleared (the final region's boss beaten at least once).
func is_descent_complete() -> bool:
	return progress.is_completed(final_boss_node_id())


## The end-of-descent epilogue (shown after the final campaign level is won). Its own scene,
## not the in-level end panel; exits to the main menu like the other hub screens.
func go_to_epilogue() -> void:
	selected_index = -1
	selected_level = null
	Log.info(Log.FLOW, "scene", {"to": "epilogue"})
	get_tree().change_scene_to_file(EPILOGUE_SCENE)


func start_next() -> void:
	if has_next():
		start_level(selected_index + 1)


## Called by the play controller on a win of the selected campaign node. Records completion (with
## best score/tier) and flags the node so the world map can play its completion transition on
## return (the cleared node greens, newly-unlocked successors light up).
func complete_current(score: int = 0, tier: int = Scoring.Tier.FREED) -> void:
	if selected_index > 0:
		progress.mark_completed(selected_index, score, tier)
		just_completed_id = selected_index
		Log.info(
			Log.FLOW,
			"node completed",
			{
				"node": selected_index,
				"score": score,
				"completed_count": progress.completed_ids().size()
			}
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
	_enter_play_scene()


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
	_enter_play_scene()


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
