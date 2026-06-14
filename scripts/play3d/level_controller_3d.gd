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
const MARGIN_TOP := 96.0       # reserved screen margin at the top (design px) — extra
                               # headroom so the HUD level name clears the field's top border
const MARGIN_BOTTOM := 50.0    # reserved screen margin at the bottom (design px)
const FIELD_CENTER_X := 640.0  # logical x the field + muzzle are centred on
const TOP_Y := 80.0            # logical y of the row-0 sphere centres
const GROWTH_BUFFER := 9       # empty rows below the fill before the danger line
const BACKDROP_OFFSET := 12.0  # metres the abyss backdrop sits behind the board plane

const DANGER_SHADER := preload("res://shaders/danger_line.gdshader")
const FRAME_SHADER := preload("res://shaders/frame_veins.gdshader")

# Banner / lore / end-panel fade timings (seconds).
const FADE_IN_TIME := 0.45
const FADE_OUT_TIME := 0.7
# Soft black backdrop behind the centre text: the bar hugs each line's measured
# text height with this much vertical margin above and below, and fades out exactly
# over that margin (so the text sits on solid black, symmetric top and bottom). The
# big title font wants a much taller plate than the small tagline (kept as far as it
# can go without the title bar reaching down into the tagline's bar during the intro).
const TEXT_BG_PAD_Y := 16.0        # tagline (small font)
const TITLE_BG_PAD_Y := 54.0       # title / verdict (large font)

# Danger visuals (bottom-line blink + red injury vignette), driven off the same
# tier as the heartbeat audio and faded in/out over DANGER_FADE — in lock-step
# with the pulses. The line/vignette throb at the tier's BPM (rad/s = TAU*bpm/60).
const DANGER_BPM_SLOW := 67.0     # two rows from the line
const DANGER_BPM_FAST := 80.0     # one row from the line
const DANGER_LINE_AMBIENT := 1.7  # the line's resting pulse when safe (shader default)
const DANGER_FADE := 1.0
const VIG_SLIGHT := 0.45          # vignette intensity at two rows (rim only)
const VIG_INTENSE := 1.0          # vignette intensity at one row (heavy injury)
const VIG_EDGE_FAR := 0.62        # vignette confined to the screen rim
const VIG_EDGE_NEAR := 0.42       # reaches further in for the one-row injury look
const BANNER_PALE := Color(0.82, 0.78, 0.72, 1.0)   # intro / win verdict colour
const BANNER_RED := Color(0.86, 0.13, 0.12, 1.0)    # lose verdict colour

enum DangerTier { NONE, SLOW, FAST }

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
var _view_center := Vector3.ZERO   # camera look target (field centre nudged down for the HUD)

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var light: DirectionalLight3D = $DirectionalLight3D
@onready var camera: Camera3D = $Camera3D
@onready var backdrop: MeshInstance3D = $Backdrop
@onready var embers: GPUParticles3D = $Embers
@onready var board: BoardView3D = $Board
@onready var shooter: Shooter3D = $Shooter
@onready var preview: MeshInstance3D = $Preview
@onready var counter_label: Label = $Ui/Counter
@onready var level_name_label: Label = $Ui/LevelName
@onready var door_button: Button = $Ui/DoorButton
@onready var banner_bg: ColorRect = $Ui/BannerBg
@onready var lore_bg: ColorRect = $Ui/LoreBg
@onready var banner_label: Label = $Ui/Banner
@onready var lore_label: Label = $Ui/Lore
@onready var end_panel: VBoxContainer = $Ui/EndPanel
@onready var next_button: Button = $Ui/EndPanel/NextButton
@onready var retry_button: Button = $Ui/EndPanel/RetryButton
@onready var menu_button: Button = $Ui/EndPanel/MenuButton

var model: GridModel
var _level: LevelResource = null   # null = free play (random board)
var sim := ShotSimulator.new()
var _bag := ShotBag.new()          # decides the gun's next colour (true-random or bag mode)
var _mesh: SphereMesh
var _mats: Array[StandardMaterial3D] = []
var _black_mat: ShaderMaterial   # obsidian + self-lit fresnel rim (shaders/obsidian_rim.gdshader)
var _preview_mesh := ImmediateMesh.new()
var _preview_mat: StandardMaterial3D
var _aim2d := Vector2(0, -1)
var _last_sim: Dictionary = {}
var game_over := false
var aim_ray_enabled := false   # trajectory preview hidden by default; [A] toggles
var _debug := false
var _shots_fired := 0          # HUD counter; bumped on every shot

# Danger-visual state: the materials we drive, the single tween that fades them,
# and the current tier (so re-calls at the same tier don't restart the 1 s fade).
var _danger_line_mat: ShaderMaterial   # the bottom miss-exit bar (danger_line.gdshader)
var _danger_vig_mat: ShaderMaterial    # the red injury vignette (danger_vignette.gdshader)
var _danger_tween: Tween
var _danger := DangerTier.NONE


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
	# Configure the colour source before the first draw: true-random or the fair bag,
	# per the Gameplay setting (read once — settings aren't reachable mid-level).
	_bag.rng.randomize()
	_bag.true_random = Settings.true_random()
	# Pick the queued colours BEFORE setup() so its refresh_colors() shows the real
	# loaded colour — otherwise the muzzle paints colour 0 (red) on the first shot.
	shooter.current_color = _rand_color()
	shooter.next_color = _rand_color()
	shooter.setup(_mesh, _mats, SPHERE_RADIUS)
	shooter.fired.connect(_on_fired)

	preview.mesh = _preview_mesh
	preview.material_override = _preview_mat
	aim_ray_enabled = Settings.aim_enabled()   # seed from the Gameplay setting; [A] still toggles in-session
	preview.visible = aim_ray_enabled

	_build_frame()
	_place_camera()
	_fit_embers()
	get_viewport().size_changed.connect(_place_camera)
	# Live-update glow/SSAO/shadows if the player changes Graphics settings while a level runs.
	Settings.graphics_changed.connect(_apply_graphics_settings)

	next_button.pressed.connect(GameState.start_next)
	retry_button.pressed.connect(GameState.retry_level)
	menu_button.pressed.connect(GameState.go_to_level_select)
	door_button.pressed.connect(GameState.go_to_level_select)

	# HUD: centre name (an authored title, or "THE PIT" in free play) + the red
	# vignette material the danger tier drives. Seed every uniform we tween so
	# get_shader_parameter() returns a real float for the fade's start value.
	_danger_vig_mat = ($Dread/DangerVignette as ColorRect).material
	_danger_vig_mat.set_shader_parameter("intensity", 0.0)
	_danger_vig_mat.set_shader_parameter("edge", VIG_EDGE_FAR)
	_danger_vig_mat.set_shader_parameter("pulse_speed", DANGER_LINE_AMBIENT)
	level_name_label.text = _level.title if _level != null else "THE PIT"

	_update_status()
	_update_heartbeat()   # an authored level could start already close to the line
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
	# Lacquered-glass look: clearcoat for a wet specular skin, a rim so spheres
	# keep a readable silhouette against the dark abyss, and a whisper of
	# self-emission (far below the bloom threshold) so they glow faintly in fog.
	for col in BoardView3D.PALETTE:
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.metallic = 0.35
		m.roughness = 0.3
		m.clearcoat_enabled = true
		m.clearcoat = 0.7
		m.clearcoat_roughness = 0.15
		m.rim_enabled = true
		m.rim = 0.4
		m.rim_tint = 0.35
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 0.06
		_mats.append(m)
	# Black spheres are polished obsidian. A StandardMaterial3D rim needs scene light
	# to catch the edge, which the dark abyss doesn't provide — so these use a custom
	# shader that drives a self-lit fresnel edge into EMISSION instead. The glowing
	# silhouette reads against the near-black background (and blooms) while the face
	# stays dark and unbreakable-looking.
	_black_mat = ShaderMaterial.new()
	_black_mat.shader = preload("res://shaders/obsidian_rim.gdshader")
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
	env.ssao_enabled = false   # overridden by _apply_graphics_settings() per the player's setting
	# Gentle grading toward the gothic-ink look: drained colour, a hair more bite.
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.88
	env.adjustment_contrast = 1.04
	world_env.environment = env
	light.rotation_degrees = Vector3(-50, -40, 0)
	light.light_energy = 1.3
	light.light_color = Color(0.92, 0.88, 0.98)
	# Glow / SSAO / shadow quality are player-controlled (Graphics settings); apply them now.
	_apply_graphics_settings()


## Apply the player's Graphics settings (glow / SSAO / shadow quality) onto the
## already-built environment + light. Called once during setup and again whenever
## the Settings autoload reports a change, so the look updates live.
func _apply_graphics_settings() -> void:
	var env := world_env.environment
	if env == null:
		return
	env.glow_enabled = Settings.glow_enabled()
	env.ssao_enabled = Settings.ssao_enabled()
	match Settings.shadows():
		SettingsStore.Shadows.OFF:
			light.shadow_enabled = false
		SettingsStore.Shadows.LOW:
			light.shadow_enabled = true
			light.directional_shadow_max_distance = 50.0
		SettingsStore.Shadows.HIGH:
			light.shadow_enabled = true
			light.directional_shadow_max_distance = 100.0


func _place_camera() -> void:
	# Frame the whole play field (its outer frame) head-on, reserving MARGIN_TOP /
	# MARGIN_BOTTOM of screen. The top reserve is larger so the HUD (level name)
	# clears the field's top border: the field is centred in the band between them,
	# which sits below screen centre, so we aim the camera a touch higher to push
	# the field down into it. The viewport is the 1280x720 design space (canvas_items
	# stretch), so the margins are deterministic across resolutions.
	var b := _frame_bounds(FRAME_THICK)   # outer edge of the frame
	var center := Vector3((b.x + b.y) * 0.5, (b.z + b.w) * 0.5, 0.0)
	var field_h := absf(b.z - b.w)
	var field_w := absf(b.y - b.x)
	var vp := get_viewport().get_visible_rect().size
	if vp.y <= 0.0:
		return
	camera.fov = 52.0
	var tan_half := tan(deg_to_rad(camera.fov) * 0.5)
	var v_frac: float = maxf(0.2, (vp.y - (MARGIN_TOP + MARGIN_BOTTOM)) / vp.y)
	var aspect: float = vp.x / vp.y
	var d_fit_height := (field_h / v_frac) / (2.0 * tan_half)
	var d_fit_width := field_w / (2.0 * tan_half * aspect)
	var d: float = maxf(d_fit_height, d_fit_width)
	# Raise the look target by the band's downward shift, converted to world units
	# at the field plane (the full visible height there maps to vp.y pixels).
	var world_per_px := (2.0 * d * tan_half) / vp.y
	var look_shift := (MARGIN_TOP - MARGIN_BOTTOM) * 0.5 * world_per_px
	_view_center = center + Vector3(0.0, look_shift, 0.0)
	camera.position = _view_center + Vector3(0.0, 0.0, d)
	camera.look_at(_view_center, Vector3.UP)
	_fit_backdrop()


## Size the abyss backdrop quad to cover the camera frustum at its depth (with
## 15% margin), so no background_color slivers show at any field size. Centred on
## the camera's view axis (_view_center), not the field, so the look-target nudge
## can't reveal a sliver of background_color at the top.
func _fit_backdrop() -> void:
	backdrop.position = Vector3(_view_center.x, _view_center.y, -BACKDROP_OFFSET)
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

	# Obsidian bars with ember veins crawling through them, tinted to the level's
	# ember colour so the frame belongs to the same palette as the particles.
	var theme := _level if _level != null else LevelResource.new()
	var wall_mat := ShaderMaterial.new()
	wall_mat.shader = FRAME_SHADER
	wall_mat.set_shader_parameter("vein_color", theme.ember_color)

	var exit_mat := ShaderMaterial.new()
	exit_mat.shader = DANGER_SHADER
	exit_mat.set_shader_parameter("pulse_speed", DANGER_LINE_AMBIENT)   # seeded so the tween has a start value
	_danger_line_mat = exit_mat   # the danger tier drives its pulse_speed (blink rate)

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


## Leaving the game screen (Esc to the menu, retry, next, any scene change) must cut
## the dread pulses instantly — they belong to this level, not the menus.
func _exit_tree() -> void:
	Sound.stop_heartbeats()


func _input(event: InputEvent) -> void:
	# Fullscreen has no window chrome — Esc leaves to level select (same as the
	# HUD door button), so the two exits behave identically.
	if event.is_action_pressed("ui_cancel"):
		GameState.go_to_level_select()
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


## The gun's next colour, drawn only from those still present on the board so it
## never offers a colour that can no longer be matched. The ShotBag decides how
## (independent random, or the fair bag); it returns 0 when the board is cleared.
func _rand_color() -> int:
	return _bag.next(model.present_colors())


func _mat_for(color: int) -> Material:
	return _black_mat if color < 0 else _mats[color % _mats.size()]


# --- shot results -------------------------------------------------------------

func _on_fired() -> void:
	if game_over or not _last_sim.has("path"):
		return
	var is_miss: bool = _last_sim.get("miss", false)
	if _debug:
		print("[FIRE] color=", shooter.current_color, " -> ", "MISS" if is_miss else _last_sim.cell)
	_shots_fired += 1
	_update_status()   # the shots tally ticks the moment the gun fires
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
	# Reload immediately: the muzzle empties, the queued sphere slides in, a fresh
	# next grows beside it — the gun shows its true colour while the shot flies.
	shooter.reload(_rand_color())


func _on_landed(cell: Vector2i, color: int) -> void:
	var res := model.attach(cell, color)
	if _debug:
		print("[LAND] cell=", cell, " pop=", res.did_pop, " popped=", res.popped.size(),
			" orphaned=", res.orphaned.size(), " coloured=", model.count_colored())
	if res.did_pop:
		# One cluster-sized pop burst, not one sound per sphere — keeps big clears
		# (the matched group plus any spheres it orphans) from turning to noise.
		Sound.play_cluster_pop(res.popped.size() + res.orphaned.size())
	else:
		model.grow()
	# On a pop, ripple the clear outward from the impact cell; on a dud the grown
	# spheres just animate in (no removals, so pop_origin is irrelevant).
	var settle := board.sync([cell], cell)   # the landed sphere appears full-size
	_validate_load()
	_update_status()
	_update_heartbeat()   # a grow may have closed on the line; a pop may have backed off it
	# Hold the verdict until the board has visually settled — the win banner must
	# not appear while the last cluster is still popping.
	if model.is_won() or model.is_lost():
		await get_tree().create_timer(settle + 0.25).timeout
		if not is_inside_tree() or game_over:
			return
		_check_end()
		return
	shooter.enabled = true


func _on_missed() -> void:
	if _debug:
		print("[MISS] reshuffle; coloured=", model.count_colored())
	model.randomize_colors()
	board.sync()   # reshuffle only recolours; spheres stay, materials swap in place
	_validate_load()
	shooter.enabled = true
	_update_status()
	_update_heartbeat()


## The slots were already advanced at fire time, but the shot that just resolved
## may have wiped a slot's colour off the board (pop/sweep) or recoloured
## everything (reshuffle) — re-roll any slot whose colour is no longer present.
func _validate_load() -> void:
	var present := model.present_colors()
	if present.is_empty():
		return
	var changed := false
	if shooter.current_color not in present:
		shooter.current_color = _bag.next(present)
		changed = true
	if shooter.next_color not in present:
		shooter.next_color = _bag.next(present)
		changed = true
	if changed:
		shooter.refresh_colors()


# --- danger heartbeat ---------------------------------------------------------

## Map how close the field is to the lose line onto a danger tier, then route it to
## BOTH the audio (the two heartbeats) and the visuals (the bottom-line blink rate
## and the red injury vignette) so they stay locked together. SLOW at exactly two
## rows, FAST at one; anything else — safe, won, or lost (game_over) — is NONE.
## Called after every shot resolves and when the game ends.
func _update_heartbeat() -> void:
	var tier := DangerTier.NONE
	if not game_over:
		match model.rows_to_danger():
			2: tier = DangerTier.SLOW
			1: tier = DangerTier.FAST
	_set_danger(tier)


## Apply a danger tier. No-op if unchanged, so the per-shot re-calls don't restart
## the 1 s fade. Audio toggles stay independent (escalation: the slow heartbeat
## fades out as the fast fades in). The visuals fade over DANGER_FADE on a single
## tween, killed and rebuilt on each change so a 2->1 escalation transitions cleanly.
func _set_danger(tier: DangerTier) -> void:
	if tier == _danger:
		return
	_danger = tier

	Sound.set_heartbeat_slow(tier == DangerTier.SLOW)
	Sound.set_heartbeat_fast(tier == DangerTier.FAST)

	# Per-tier targets: the vignette's intensity/reach, and the shared blink speed
	# (the bottom line and the vignette throb at the same BPM).
	var vig_intensity := 0.0
	var vig_edge := VIG_EDGE_FAR
	var line_speed := DANGER_LINE_AMBIENT
	match tier:
		DangerTier.SLOW:
			vig_intensity = VIG_SLIGHT
			line_speed = _bpm_to_speed(DANGER_BPM_SLOW)
		DangerTier.FAST:
			vig_intensity = VIG_INTENSE
			vig_edge = VIG_EDGE_NEAR
			line_speed = _bpm_to_speed(DANGER_BPM_FAST)

	if _danger_tween and _danger_tween.is_valid():
		_danger_tween.kill()
	var tw := create_tween().set_parallel(true)
	_tween_param(tw, _danger_vig_mat, "intensity", vig_intensity)
	_tween_param(tw, _danger_vig_mat, "edge", vig_edge)
	_tween_param(tw, _danger_vig_mat, "pulse_speed", line_speed)
	_tween_param(tw, _danger_line_mat, "pulse_speed", line_speed)
	_danger_tween = tw


## Tween one float shader uniform from its current value to `to` over DANGER_FADE,
## as a parallel leg of `tw`. The uniform must already be seeded (see _ready /
## _build_frame) so the start value reads back as a float.
func _tween_param(tw: Tween, mat: ShaderMaterial, param: String, to: float) -> void:
	var from: float = mat.get_shader_parameter(param)
	tw.tween_method(
		func(v: float) -> void: mat.set_shader_parameter(param, v),
		from, to, DANGER_FADE)


static func _bpm_to_speed(bpm: float) -> float:
	return TAU * bpm / 60.0


# --- end state ----------------------------------------------------------------

func _check_end() -> void:
	if model.is_won():
		_end("THE FIELD IS STILL.\nYou survive.", true)
	elif model.is_lost():
		_end("THE SPHERES CONSUME YOU.", false)


func _end(msg: String, won: bool) -> void:
	game_over = true
	shooter.enabled = false
	_update_heartbeat()   # game_over now true -> both pulses fade out (cleared or consumed)
	_preview_mesh.clear_surfaces()
	banner_label.text = msg
	# The verdict reads against the board on its own soft black bar (no tagline now);
	# the lose verdict turns red ("THE SPHERES CONSUME YOU"), the win stays pale.
	banner_label.add_theme_color_override("font_color", BANNER_PALE if won else BANNER_RED)
	_size_text_backdrop(banner_bg, banner_label, TITLE_BG_PAD_Y)
	_fade_in(banner_bg, FADE_IN_TIME)
	_fade_in(banner_label, FADE_IN_TIME)
	_kill_fade(lore_label)
	lore_label.visible = false
	lore_label.modulate.a = 1.0
	# The tagline (and its bar) belong to the intro only — make sure neither lingers
	# if the game ended mid-intro.
	_kill_fade(lore_bg)
	lore_bg.visible = false
	lore_bg.modulate.a = 1.0
	if won and _level != null:
		GameState.complete_current()
	next_button.visible = won and _level != null and GameState.has_next()
	retry_button.visible = not won and _level != null
	# The verdict lands first; the choices surface a beat later.
	_fade_in(end_panel, FADE_IN_TIME, 0.35)
	# Hand keyboard focus to the most relevant choice so arrows + Enter work.
	if next_button.visible:
		next_button.grab_focus()
	elif retry_button.visible:
		retry_button.grab_focus()
	else:
		menu_button.grab_focus()


## Level intro: title + lore fade in over the board, hold for a few seconds,
## then dissolve (unless the game somehow ended first — the end banner wins).
func _show_intro() -> void:
	banner_label.text = _level.title
	banner_label.add_theme_color_override("font_color", BANNER_PALE)
	lore_label.text = _level.lore_fragment
	# A separate soft bar hugs each line (title and tagline), centred on its own text;
	# the title gets a taller plate to match its bigger font.
	_size_text_backdrop(banner_bg, banner_label, TITLE_BG_PAD_Y)
	_size_text_backdrop(lore_bg, lore_label, TEXT_BG_PAD_Y)
	_fade_in(banner_bg, FADE_IN_TIME)
	_fade_in(banner_label, FADE_IN_TIME)
	_fade_in(lore_bg, FADE_IN_TIME, 0.25)
	_fade_in(lore_label, FADE_IN_TIME, 0.25)
	await get_tree().create_timer(3.0).timeout
	if not is_inside_tree() or game_over:
		return
	_fade_out(banner_bg, FADE_OUT_TIME)
	_fade_out(banner_label, FADE_OUT_TIME)
	_fade_out(lore_bg, FADE_OUT_TIME)
	_fade_out(lore_label, FADE_OUT_TIME)


# --- ui fades -------------------------------------------------------------

## Show `ctrl` by fading its modulate alpha up from zero (after `delay`).
## Any fade already running on it is killed first, so rapid transitions
## (intro fade-out interrupted by the end banner) can't stack.
func _fade_in(ctrl: CanvasItem, dur: float, delay := 0.0) -> void:
	_kill_fade(ctrl)
	ctrl.modulate.a = 0.0
	ctrl.visible = true
	var tw := ctrl.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(ctrl, "modulate:a", 1.0, dur)
	ctrl.set_meta("fade_tween", tw)


## Fade `ctrl` out, then hide it and restore full alpha for the next show.
func _fade_out(ctrl: CanvasItem, dur: float) -> void:
	_kill_fade(ctrl)
	var tw := ctrl.create_tween()
	tw.tween_property(ctrl, "modulate:a", 0.0, dur)
	tw.tween_callback(func () -> void:
		ctrl.visible = false
		ctrl.modulate.a = 1.0)
	ctrl.set_meta("fade_tween", tw)


func _kill_fade(ctrl: CanvasItem) -> void:
	if ctrl.has_meta("fade_tween"):
		var tw: Tween = ctrl.get_meta("fade_tween")
		if tw != null and tw.is_valid():
			tw.kill()


## Fit a full-width soft backdrop to one centre-text label: centre it on the label's
## (centred) text and size it to the measured text height plus `pad_y` above and below,
## then fade the bar out over exactly that pad so the text rests on solid black with an
## equal margin top and bottom. Call after setting the label's text.
func _size_text_backdrop(bg: ColorRect, label: Label, pad_y: float) -> void:
	var font := label.get_theme_font("font")
	if font == null:
		return
	var fsize := label.get_theme_font_size("font")
	var ts := font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, fsize)
	# get_multiline_string_size ignores the Label's extra inter-line spacing; add it.
	var lines := label.text.count("\n") + 1
	if lines > 1:
		ts.y += float(lines - 1) * float(label.get_theme_constant("line_spacing"))
	var center_y := label.offset_top + (label.offset_bottom - label.offset_top) * 0.5
	var h := ts.y + pad_y * 2.0
	bg.offset_top = center_y - h * 0.5
	bg.offset_bottom = center_y + h * 0.5
	var mat := bg.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("soft_y", pad_y / h)   # fade out over the pad only


## The top-left HUD counter: coloured spheres still on the field (the clear target)
## and a running tally of shots fired. The level name and exits live in their own
## HUD nodes; the old one-line hint string is gone.
func _update_status() -> void:
	counter_label.text = "Spheres  %d\nShots  %d" % [model.count_colored(), _shots_fired]


# --- dev autoplay -------------------------------------------------------------

func _auto_step() -> void:
	if game_over or not shooter.enabled:
		return
	var dirs := [Vector2(0, -1), Vector2(0.45, -1).normalized(), Vector2(-0.5, -1).normalized()]
	_aim2d = dirs[randi() % dirs.size()]
	_last_sim = sim.simulate(muzzle2d, _aim2d)
	_on_fired()
