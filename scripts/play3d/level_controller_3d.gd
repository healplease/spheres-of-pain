class_name LevelController3D
extends Node3D

## 3D presentation of the SAME game. It owns the GridModel + ShotSimulator (the
## identical rules and ball-flight used by the 2D level) and renders them in 3D:
## sphere meshes on the board plane (XY, Z=0), a perspective camera, dim lighting,
## and a projectile flying on the plane. The simulation runs in logical 2D pixel
## space; `to3d`/`to2d` map that plane to/from 3D world space.

const S := 1.0 / 56.0          # metres per logical pixel; one cell ≈ 1 m
const SPHERE_RADIUS := 0.46
const FRAME_THICK := 0.3       # frame bar cross-section (metres)
const FRAME_DEPTH := 0.6       # frame bar depth toward the camera (metres)
const MARGIN_PX := 50.0        # reserved screen margin, top and bottom (design px)
const FIELD_CENTER_X := 640.0  # logical x the field + muzzle are centred on
const TOP_Y := 80.0            # logical y of the row-0 sphere centres
const GROWTH_BUFFER := 7       # empty rows below the fill before the danger line
const BACKDROP_OFFSET := 12.0  # metres the abyss backdrop sits behind the board plane

const DANGER_SHADER := preload("res://shaders/danger_line.gdshader")

@export var diameter := 56.0
@export var num_colors := 5
## Field size is rolled randomly inside these inclusive ranges on each level.
@export var min_columns := 10
@export var max_columns := 50
@export var min_rows := 10
@export var max_rows := 50
@export_range(0.0, 0.3) var black_fraction := 0.06  # share of cells seeded black

# Derived from the rolled field size in _pick_field_dimensions(); the camera then
# reframes to whatever they produce, so any size in range is fully visible.
var columns := 11
var rows := 5
var danger_row := 12
var origin2d := Vector2(346, 80)   # logical board origin (cell 0,0)
var muzzle2d := Vector2(640, 690)  # logical muzzle
var _play_bottom := 720.0          # logical miss-exit line (below the muzzle)

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var light: DirectionalLight3D = $DirectionalLight3D
@onready var camera: Camera3D = $Camera3D
@onready var backdrop: MeshInstance3D = $Backdrop
@onready var embers: GPUParticles3D = $Embers
@onready var board: BoardView3D = $Board
@onready var shooter: Shooter3D = $Shooter
@onready var preview: MeshInstance3D = $Preview
@onready var status_label: Label = $Ui/Status
@onready var banner_label: Label = $Ui/Banner
@onready var lore_label: Label = $Ui/Lore
@onready var end_panel: VBoxContainer = $Ui/EndPanel
@onready var next_button: Button = $Ui/EndPanel/NextButton
@onready var retry_button: Button = $Ui/EndPanel/RetryButton
@onready var menu_button: Button = $Ui/EndPanel/MenuButton

var model: GridModel
var _level: LevelResource = null   # null = free play (random board)
var sim := ShotSimulator.new()
var _mesh: SphereMesh
var _mats: Array[StandardMaterial3D] = []
var _black_mat: StandardMaterial3D
var _preview_mesh := ImmediateMesh.new()
var _preview_mat: StandardMaterial3D
var _aim2d := Vector2(0, -1)
var _last_sim: Dictionary = {}
var game_over := false
var aim_ray_enabled := false   # trajectory preview hidden by default; [A] toggles
var _debug := false


func to3d(p: Vector2) -> Vector3:
	return Vector3((p.x - origin2d.x) * S, -(p.y - origin2d.y) * S, 0.0)

func to2d(w: Vector3) -> Vector2:
	return Vector2(w.x / S + origin2d.x, -w.y / S + origin2d.y)


func _ready() -> void:
	randomize()
	_build_visual_assets()
	_setup_environment()

	# An authored level (selected in the level-select menu) defines the board;
	# with no selection (running this scene directly) fall back to a random one.
	_level = GameState.selected_level
	if _level != null:
		model = _level.build_model()
		model.rng.randomize()
		columns = _level.width
		rows = _level.rows()
		num_colors = _level.num_colors
		danger_row = _level.danger_row
		_layout_field()
	else:
		_pick_field_dimensions()
		model = GridModel.new()
		model.width = columns
		model.num_colors = num_colors
		model.danger_row = danger_row
		model.rng.randomize()
		_build_board()

	_apply_theme()

	sim.model = model
	sim.diameter = diameter
	sim.columns = columns
	sim.origin = origin2d
	sim.play_left = origin2d.x - diameter * 0.5
	sim.play_right = origin2d.x + (columns - 1) * diameter + diameter
	sim.play_bottom = _play_bottom

	board.setup(model, _mesh, _mats, _black_mat, diameter)

	shooter.position = to3d(muzzle2d)
	# Pick the queued colours BEFORE setup() so its refresh_colors() shows the real
	# loaded colour — otherwise the muzzle paints colour 0 (red) on the first shot.
	shooter.current_color = _rand_color()
	shooter.next_color = _rand_color()
	shooter.setup(_mesh, _mats, SPHERE_RADIUS)
	shooter.fired.connect(_on_fired)

	preview.mesh = _preview_mesh
	preview.material_override = _preview_mat
	preview.visible = aim_ray_enabled

	_build_frame()
	_place_camera()
	_fit_embers()
	get_viewport().size_changed.connect(_place_camera)

	next_button.pressed.connect(GameState.start_next)
	retry_button.pressed.connect(GameState.retry_level)
	menu_button.pressed.connect(GameState.go_to_level_select)

	_update_status()
	if _level != null:
		_show_intro()

	if OS.has_environment("SOP_AUTOPLAY"):
		_debug = true
		var t := Timer.new()
		t.wait_time = 0.6
		t.timeout.connect(_auto_step)
		add_child(t)
		t.start()
		print("[AUTOPLAY] enabled")


func _process(_delta: float) -> void:
	if game_over:
		return
	_update_aim()
	_last_sim = sim.simulate(muzzle2d, _aim2d)
	_update_preview(_last_sim.path)


# --- aim / preview ------------------------------------------------------------

func _update_aim() -> void:
	# Cast the mouse ray onto the board plane (Z=0) and aim from the muzzle to it.
	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	if absf(dir.z) < 0.00001:
		return
	var t := -from.z / dir.z
	if t <= 0.0:
		return
	var hit := from + dir * t
	var d := to2d(hit) - muzzle2d
	if d.length() < 1.0:
		return
	var a := d.normalized()
	if a.y > -0.12:           # never aim sideways/down
		a.y = -0.12
		a = a.normalized()
	_aim2d = a


func _update_preview(path2d: PackedVector2Array) -> void:
	_preview_mesh.clear_surfaces()
	if path2d.size() < 2:
		return
	_preview_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in path2d:
		_preview_mesh.surface_add_vertex(to3d(p) + Vector3(0, 0, 0.05))  # nudge toward camera
	_preview_mesh.surface_end()


# --- setup helpers ------------------------------------------------------------

func _build_visual_assets() -> void:
	_mesh = SphereMesh.new()
	_mesh.radius = SPHERE_RADIUS
	_mesh.height = SPHERE_RADIUS * 2.0
	for col in BoardView3D.PALETTE:
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.metallic = 0.25
		m.roughness = 0.45
		_mats.append(m)
	_black_mat = StandardMaterial3D.new()
	_black_mat.albedo_color = Color(0.04, 0.04, 0.05)
	_black_mat.metallic = 0.1
	_black_mat.roughness = 0.8
	_preview_mat = StandardMaterial3D.new()
	_preview_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview_mat.albedo_color = Color(0.9, 0.85, 0.85, 0.55)
	_preview_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.4, 0.5)
	env.ambient_light_energy = 0.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.025, 0.02, 0.045)
	env.fog_density = 0.015
	# Glow for the pulsing danger line and the embers (both peak above 1.0);
	# the abyss backdrop outputs plain ALBEDO so it can never bloom.
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	# Gentle grading toward the gothic-ink look: drained colour, a hair more bite.
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.88
	env.adjustment_contrast = 1.04
	world_env.environment = env
	light.rotation_degrees = Vector3(-50, -40, 0)
	light.light_energy = 1.3
	light.light_color = Color(0.92, 0.88, 0.98)
	light.shadow_enabled = true


func _place_camera() -> void:
	# Frame the whole play field (its outer frame) head-on, reserving MARGIN_PX of
	# screen at the top and bottom. The viewport is the 1280x720 design space
	# (canvas_items stretch), so the margin is deterministic across resolutions.
	var b := _frame_bounds(FRAME_THICK)   # outer edge of the frame
	var center := Vector3((b.x + b.y) * 0.5, (b.z + b.w) * 0.5, 0.0)
	var field_h := absf(b.z - b.w)
	var field_w := absf(b.y - b.x)
	var vp := get_viewport().get_visible_rect().size
	if vp.y <= 0.0:
		return
	camera.fov = 52.0
	var tan_half := tan(deg_to_rad(camera.fov) * 0.5)
	var v_frac: float = maxf(0.2, (vp.y - 2.0 * MARGIN_PX) / vp.y)
	var aspect: float = vp.x / vp.y
	var d_fit_height := (field_h / v_frac) / (2.0 * tan_half)
	var d_fit_width := field_w / (2.0 * tan_half * aspect)
	var d: float = maxf(d_fit_height, d_fit_width)
	camera.position = center + Vector3(0.0, 0.0, d)
	camera.look_at(center, Vector3.UP)
	_fit_backdrop()


## Size the abyss backdrop quad to cover the camera frustum at its depth (with
## 15% margin), so no background_color slivers show at any field size.
func _fit_backdrop() -> void:
	var b := _frame_bounds(FRAME_THICK)
	backdrop.position = Vector3((b.x + b.y) * 0.5, (b.z + b.w) * 0.5, -BACKDROP_OFFSET)
	var dist := camera.position.z + BACKDROP_OFFSET
	var vp := get_viewport().get_visible_rect().size
	if vp.y <= 0.0:
		return
	var h := 2.0 * dist * tan(deg_to_rad(camera.fov) * 0.5) * 1.15
	var w := h * (vp.x / vp.y) * 1.15
	backdrop.scale = Vector3(w * 0.5, h * 0.5, 1.0)   # QuadMesh is 2x2


## Tint the abyss, embers and fog to the level's palette. The shader/particle
## materials are shared scene sub-resources that persist across scene reloads,
## so free play must reset them explicitly (via a defaults instance) rather
## than leaving whatever the last level set.
func _apply_theme() -> void:
	var theme := _level if _level != null else LevelResource.new()
	var mat := backdrop.material_override as ShaderMaterial
	mat.set_shader_parameter("violet", theme.abyss_color_a)
	mat.set_shader_parameter("teal", theme.abyss_color_b)
	world_env.environment.fog_light_color = theme.fog_color
	var ember_mat := (embers.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	ember_mat.albedo_color = Color(theme.ember_color, 0.55)


## Spread the ember particles across the whole play field (they float in a thin
## slab in front of the board plane), with density scaled to the field area.
func _fit_embers() -> void:
	var b := _frame_bounds(0.0)
	var span_x := b.y - b.x
	var span_y := b.z - b.w
	embers.position = Vector3((b.x + b.y) * 0.5, (b.z + b.w) * 0.5, 1.2)
	var pm := embers.process_material as ParticleProcessMaterial
	pm.emission_box_extents = Vector3(span_x * 0.5 + 1.0, span_y * 0.5 + 1.0, 1.5)
	embers.amount = clampi(int(span_x * span_y * 0.35), 60, 400)
	embers.restart()


## World-space bounce rectangle, padded outward by `pad`. Returns (left_x,
## right_x, top_y, bottom_y) as a Vector4. The inner faces (pad = 0) sit exactly
## on the surfaces the ball reflects off: sides, the row-0 top wall, and the
## bottom miss-exit line.
func _frame_bounds(pad: float) -> Vector4:
	var left_x := to3d(Vector2(sim.play_left, origin2d.y)).x - pad
	var right_x := to3d(Vector2(sim.play_right, origin2d.y)).x + pad
	var top_y := to3d(Vector2(origin2d.x, origin2d.y - diameter * 0.5)).y + pad
	var bot_y := to3d(Vector2(origin2d.x, sim.play_bottom)).y - pad
	return Vector4(left_x, right_x, top_y, bot_y)


## Build a raised border so the player can read where the ball bounces. Left,
## right and top are solid bounce walls; the bottom is a distinct red exit line
## (the ball falls out there — it does not bounce). Lives directly under the
## controller, NOT under Board (which frees its children on every rebuild).
func _build_frame() -> void:
	var b := _frame_bounds(0.0)
	var left_x := b.x
	var right_x := b.y
	var top_y := b.z
	var bot_y := b.w
	var cx := (left_x + right_x) * 0.5
	var cy := (top_y + bot_y) * 0.5
	var span_x := right_x - left_x
	var span_y := top_y - bot_y
	var t := FRAME_THICK

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.16, 0.15, 0.19)
	wall_mat.metallic = 0.3
	wall_mat.roughness = 0.6
	wall_mat.emission_enabled = true
	wall_mat.emission = Color(0.12, 0.11, 0.16)
	wall_mat.emission_energy_multiplier = 0.6

	var exit_mat := ShaderMaterial.new()
	exit_mat.shader = DANGER_SHADER

	var frame := Node3D.new()
	frame.name = "Frame"
	add_child(frame)

	# Bars are placed so their inner face aligns with the bounce surface (offset
	# outward by half the bar thickness); side/top bars overlap at the corners.
	_add_bar(frame, wall_mat, Vector3(t, span_y + t, FRAME_DEPTH), Vector3(left_x - t * 0.5, cy, 0.0))
	_add_bar(frame, wall_mat, Vector3(t, span_y + t, FRAME_DEPTH), Vector3(right_x + t * 0.5, cy, 0.0))
	_add_bar(frame, wall_mat, Vector3(span_x + t * 2.0, t, FRAME_DEPTH), Vector3(cx, top_y + t * 0.5, 0.0))
	_add_bar(frame, exit_mat, Vector3(span_x + t * 2.0, t, FRAME_DEPTH * 0.6), Vector3(cx, bot_y - t * 0.5, 0.0))


func _add_bar(parent: Node3D, mat: Material, size: Vector3, pos: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _input(event: InputEvent) -> void:
	# Fullscreen has no window chrome — give the player a way back.
	if event.is_action_pressed("ui_cancel"):
		GameState.go_to_main_menu()
	elif event.is_action_pressed("toggle_aim"):
		aim_ray_enabled = not aim_ray_enabled
		preview.visible = aim_ray_enabled and not game_over


## Roll a random field size within the configured ranges and derive every logical
## coordinate from it: the board origin (so the field stays centred on
## FIELD_CENTER_X), the danger row (a fixed growth buffer below the fill), the
## muzzle, and the bottom miss-exit line. The camera reframes to whatever this
## produces (see _place_camera), so any size in range is captured in full.
func _pick_field_dimensions() -> void:
	columns = randi_range(min_columns, max_columns)
	rows = randi_range(min_rows, max_rows)
	danger_row = rows + GROWTH_BUFFER
	_layout_field()


## Derive every logical coordinate from `columns` / `danger_row` (set either by
## the random roll above or by an authored level): the board origin (field
## centred on FIELD_CENTER_X), the muzzle just below the danger line, and the
## bottom miss-exit line (≈0.6 of a row each, matching the original hand-tuned
## 12 / 690 / 720 layout).
func _layout_field() -> void:
	var row_step := diameter * Hex.ROW_RATIO
	# Centre the field horizontally: with this origin, (play_left + play_right) / 2
	# lands on FIELD_CENTER_X regardless of column count.
	origin2d = Vector2(FIELD_CENTER_X - diameter * (columns * 0.5 - 0.25), TOP_Y)
	var danger_y := origin2d.y + danger_row * row_step
	muzzle2d = Vector2(FIELD_CENTER_X, danger_y + row_step * 0.6)
	_play_bottom = muzzle2d.y + row_step * 0.6


## Procedurally fill the field: every cell in the first `rows` rows takes a random
## breakable colour, then a fraction are overwritten with unbreakable black
## obstacles.
func _build_board() -> void:
	for r in range(rows):
		for c in range(columns):
			model.cells[Vector2i(c, r)] = randi() % num_colors
	var black_count := int(round(rows * columns * black_fraction))
	for _i in range(black_count):
		var cell := Vector2i(randi() % columns, randi() % rows)
		model.cells[cell] = GridModel.BLACK


## A random colour drawn only from those still present on the board, so the gun
## never offers a colour that can no longer be matched. Falls back to colour 0 if
## the board has no breakable spheres left (game already won).
func _rand_color() -> int:
	var present := model.present_colors()
	if present.is_empty():
		return 0
	return present[randi() % present.size()]


func _mat_for(color: int) -> StandardMaterial3D:
	return _black_mat if color < 0 else _mats[color % _mats.size()]


# --- shot results -------------------------------------------------------------

func _on_fired() -> void:
	if game_over or not _last_sim.has("path"):
		return
	var is_miss: bool = _last_sim.get("miss", false)
	if _debug:
		print("[FIRE] color=", shooter.current_color, " -> ", "MISS" if is_miss else _last_sim.cell)
	shooter.enabled = false
	var proj := Projectile3D.new()
	proj.setup(_mesh, _mat_for(shooter.current_color))
	var p3d: Array[Vector3] = []
	for p in _last_sim.path:
		p3d.append(to3d(p))
	proj.path = p3d
	proj.miss = is_miss
	if not is_miss:
		proj.cell = _last_sim.cell
	proj.color = shooter.current_color
	proj.landed.connect(_on_landed)
	proj.missed.connect(_on_missed)
	add_child(proj)


func _on_landed(cell: Vector2i, color: int) -> void:
	var res := model.attach(cell, color)
	if _debug:
		print("[LAND] cell=", cell, " pop=", res.did_pop, " popped=", res.popped.size(),
			" orphaned=", res.orphaned.size(), " coloured=", model.count_colored())
	if not res.did_pop:
		model.grow()
	# On a pop, ripple the clear outward from the impact cell; on a dud the grown
	# spheres just animate in (no removals, so pop_origin is irrelevant).
	board.sync([cell], cell)   # the landed sphere appears full-size; grown spheres animate in
	_advance_load()
	shooter.enabled = true
	_check_end()
	_update_status()


func _on_missed() -> void:
	if _debug:
		print("[MISS] reshuffle; coloured=", model.count_colored())
	model.randomize_colors()
	board.sync()   # reshuffle only recolours; spheres stay, materials swap in place
	_advance_load()
	shooter.enabled = true
	_update_status()


func _advance_load() -> void:
	shooter.current_color = shooter.next_color
	shooter.next_color = _rand_color()
	# The promoted colour (the old `next`) may have just been wiped off the board by
	# the shot that resolved — if so, re-roll it from what's still present.
	var present := model.present_colors()
	if not present.is_empty() and shooter.current_color not in present:
		shooter.current_color = present[randi() % present.size()]
	shooter.refresh_colors()


# --- end state ----------------------------------------------------------------

func _check_end() -> void:
	if model.is_won():
		_end("THE FIELD IS STILL.\nYou survive.", true)
	elif model.is_lost():
		_end("THE SPHERES CONSUME YOU.", false)


func _end(msg: String, won: bool) -> void:
	game_over = true
	shooter.enabled = false
	_preview_mesh.clear_surfaces()
	banner_label.text = msg
	banner_label.visible = true
	lore_label.visible = false
	if won and _level != null:
		GameState.complete_current()
	next_button.visible = won and _level != null and GameState.has_next()
	retry_button.visible = not won and _level != null
	end_panel.visible = true
	# Hand keyboard focus to the most relevant choice so arrows + Enter work.
	if next_button.visible:
		next_button.grab_focus()
	elif retry_button.visible:
		retry_button.grab_focus()
	else:
		menu_button.grab_focus()


## Level intro: title + lore over the board for a few seconds, then fade out
## (unless the game somehow ended first — the end banner wins).
func _show_intro() -> void:
	banner_label.text = _level.title
	banner_label.visible = true
	lore_label.text = _level.lore_fragment
	lore_label.visible = true
	await get_tree().create_timer(3.0).timeout
	if not is_inside_tree() or game_over:
		return
	banner_label.visible = false
	lore_label.visible = false


func _update_status() -> void:
	var prefix := ""
	if _level != null:
		prefix = "L%d  %s  —  " % [_level.id, _level.title]
	status_label.text = prefix + "Coloured spheres: %d     [LMB] fire   [A] aim ray  —  match 3+ to clear, miss out the bottom to reshuffle" % model.count_colored()


# --- dev autoplay -------------------------------------------------------------

func _auto_step() -> void:
	if game_over or not shooter.enabled:
		return
	var dirs := [Vector2(0, -1), Vector2(0.45, -1).normalized(), Vector2(-0.5, -1).normalized()]
	_aim2d = dirs[randi() % dirs.size()]
	_last_sim = sim.simulate(muzzle2d, _aim2d)
	_on_fired()
