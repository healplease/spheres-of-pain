class_name WorldMapController
extends Node3D

## The 3D draggable "hell planescape" world map — the campaign hub (LEVEL_SELECT_SCENE), replacing
## the old vertical list. One continuous bird's-eye surface holding all 30 level nodes as glowing
## points on a branching road network: completed = dark green, available = orange + a wave pulse,
## locked = dim grey. Drag to pan, wheel to zoom; click a node to zoom in on it (framed on the left
## half) while a detail window fades in on the right. On return from a win it plays the completion
## transition (the cleared node greens, newly-unlocked successors light up).
##
## The map is wholly data-driven (markers + roads come from GameState.world_graph()), so it builds
## its scene in code rather than a fixed .tscn. It owns the camera (via MapCameraRig), the markers
## (NodeMarker), the roads (RoadView), and the detail panel (MapDetailPanel); the pure model lives
## in WorldUnlock/WorldGraphResource and is only observed here.

const MAP_SCALE := 0.05  # logical map units -> world metres (one spine step ~ 10 m)
const MARKER_RADIUS := 1.0
const START_ZOOM := 56.0
const ST := WorldUnlock.State

var _graph: WorldGraphResource
var _states: Dictionary
var _regions: Array
var _assets: SphereAssets
var _camera: Camera3D
var _env: WorldEnvironment
var _rig: MapCameraRig
var _roads: RoadView
var _markers: Dictionary = {}  # id -> NodeMarker
var _detail: MapDetailPanel
var _ui: CanvasLayer
var _selected_id := -1
var _region_moods: Array = []  # [{y, bg}] for the per-region atmosphere blend

# Pending completion transition (the node just won + the successors it freshly unlocks).
var _transition_node := -1
var _transition_newly: Array = []


func _ready() -> void:
	GameState.preload_play_scene()  # warm the play scene off-thread while the player chooses
	get_viewport().physics_object_picking = true  # so Area3D markers receive clicks/hover
	_graph = GameState.world_graph()
	if _graph == null:
		Log.error(Log.FLOW, "world map: no graph", {})
		return
	_states = GameState.node_states()
	_regions = GameState.regions()
	_assets = SphereAssets.new(MARKER_RADIUS)

	var display := _display_states()  # pre-transition look, if returning from a win
	_build_environment()
	_build_roads(display)
	_build_markers(display)
	_build_camera_and_rig()
	_build_ui()
	_play_completion_transition()
	Log.info(Log.FLOW, "scene", {"to": "world_map", "nodes": _graph.nodes.size()})


func _process(delta: float) -> void:
	if _env == null or _rig == null:
		return
	var env := _env.environment
	env.background_color = env.background_color.lerp(_mood_for(_rig.world_center().y), delta * 1.5)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _detail != null and _detail.is_open():
			_close_detail()
		else:
			GameState.go_to_main_menu()
		get_viewport().set_input_as_handled()


# --- logical map space <-> world ----------------------------------------------


func to3d(p: Vector2) -> Vector3:
	return Vector3(p.x * MAP_SCALE, -p.y * MAP_SCALE, 0.0)


func to2d(w: Vector3) -> Vector2:
	return Vector2(w.x / MAP_SCALE, -w.y / MAP_SCALE)


# --- build --------------------------------------------------------------------


func _build_environment() -> void:
	_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.02, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.38, 0.42)
	env.ambient_light_energy = 0.55
	# Depth fog would wash a top-down ortho map (every point is the same distance from the camera),
	# so the mood comes from the dark, region-tinted background + glow instead.
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.92
	env.adjustment_contrast = 1.05
	_env.environment = env
	add_child(_env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-70, -28, 0)
	light.light_energy = 1.0
	light.light_color = Color(0.96, 0.86, 0.8)
	add_child(light)

	for r in _regions:
		_region_moods.append({"y": to3d(r.map_center).y, "bg": (r.fog_color * 1.4) as Color})


func _build_roads(states: Dictionary) -> void:
	_roads = RoadView.new()
	add_child(_roads)
	_roads.setup(_graph, to3d)
	_roads.rebuild(states)


func _build_markers(states: Dictionary) -> void:
	var container := Node3D.new()
	container.name = "Markers"
	add_child(container)
	for n in _graph.nodes:
		var m := NodeMarker.new()
		container.add_child(m)
		m.setup(n.id, to3d(n.map_position), states.get(n.id, ST.LOCKED), _assets)
		m.clicked.connect(_on_node_clicked)
		_markers[n.id] = m


func _build_camera_and_rig() -> void:
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.current = true
	_rig = MapCameraRig.new()
	add_child(_rig)
	var focus := to3d(_graph.node(_frontier_id()).map_position)
	_rig.setup(_camera, _world_bounds(), Vector2(focus.x, focus.y), START_ZOOM)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)

	var title := Label.new()
	title.text = "THE DESCENT"
	title.theme_type_variation = &"TitleText"
	title.add_theme_font_size_override("font_size", 40)
	title.position = Vector2(48, 32)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(title)

	var hint := Label.new()
	hint.text = "drag to wander  ·  scroll to zoom  ·  esc to leave"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.6, 0.56, 0.6))
	hint.position = Vector2(50, 84)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(hint)

	var back := Button.new()
	back.text = "BACK"
	back.anchor_top = 1.0
	back.anchor_bottom = 1.0
	back.offset_left = 36
	back.offset_right = 156
	back.offset_top = -68
	back.offset_bottom = -20
	back.pressed.connect(GameState.go_to_main_menu)
	_ui.add_child(back)

	_detail = MapDetailPanel.new()
	_ui.add_child(_detail)
	_detail.descend_pressed.connect(_on_descend)
	_detail.back_pressed.connect(_close_detail)


# --- interaction --------------------------------------------------------------


func _on_node_clicked(id: int) -> void:
	if _rig.consumed_drag():  # the press was a pan, not a click
		return
	if _detail.is_open():
		return
	var n := _graph.node(id)
	var lv := GameState.load_level(id)
	if lv == null:
		return
	_selected_id = id
	_rig.focus_left(to3d(n.map_position))
	_detail.open(lv, n, GameState.region_for_node(id), _best_text(id))
	Log.info(Log.FLOW, "map select", {"node": id})


func _on_descend(id: int) -> void:
	GameState.start_node(id)


func _close_detail() -> void:
	_detail.close()
	_rig.unfocus()
	_selected_id = -1


func _best_text(id: int) -> String:
	if not GameState.progress.is_completed(id):
		return ""
	var tier := GameState.progress.best_tier(id)
	return "Cleared — %s · best %d" % [Scoring.tier_word(tier), GameState.progress.best_score(id)]


# --- completion transition (return from a win) --------------------------------


## Build the id->state map the map first DISPLAYS. Normally the live states; but if we just won a
## node, show the pre-win look (cleared node still orange, its fresh successors still grey) so the
## transition can animate the change.
func _display_states() -> Dictionary:
	var display := _states.duplicate()
	var jc: int = GameState.just_completed_id
	GameState.just_completed_id = -1  # consume it
	if jc < 0 or not _graph.has_node(jc):
		return display
	_transition_node = jc
	display[jc] = ST.AVAILABLE
	for s in _graph.node(jc).successors:
		if _states.get(s, ST.LOCKED) == ST.AVAILABLE:
			display[s] = ST.LOCKED
			_transition_newly.append(s)
	return display


func _play_completion_transition() -> void:
	if _transition_node < 0:
		return
	var node := _graph.node(_transition_node)
	_rig.ease_to(to3d(node.map_position))  # bring the change on-screen
	await get_tree().create_timer(0.8).timeout
	if not is_inside_tree():
		return
	_markers[_transition_node].set_state(ST.COMPLETED, true)
	for s in _transition_newly:
		_markers[s].set_state(ST.AVAILABLE, true)
	_roads.rebuild(_states)
	Log.info(
		Log.FLOW, "map transition", {"completed": _transition_node, "unlocked": _transition_newly}
	)


# --- helpers ------------------------------------------------------------------


## The deepest available node id (the player's frontier) — the camera lands here, like the old
## descent map landing on the furthest-unlocked level. Falls back to the start node.
func _frontier_id() -> int:
	var best := _graph.start_node_id
	for id in GameState.available_ids():
		if id > best:
			best = id
	return best


func _world_bounds() -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for n in _graph.nodes:
		var w := to3d(n.map_position)
		lo = Vector2(minf(lo.x, w.x), minf(lo.y, w.y))
		hi = Vector2(maxf(hi.x, w.x), maxf(hi.y, w.y))
	var pad := Vector2(8.0, 8.0)
	return Rect2(lo - pad, (hi - lo) + pad * 2.0)


func _mood_for(world_y: float) -> Color:
	var best := Color(0.03, 0.02, 0.025)
	var nearest := INF
	for mood in _region_moods:
		var d: float = absf(world_y - mood.y)
		if d < nearest:
			nearest = d
			best = mood.bg
	return best
