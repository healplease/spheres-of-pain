class_name LevelController3D
extends Node3D

## 3D presentation of the SAME game. It owns the GridModel + ShotSimulator (the
## identical rules and ball-flight used by the 2D level) and renders them in 3D:
## sphere meshes on the board plane (XY, Z=0), a perspective camera, dim lighting,
## and a projectile flying on the plane. The simulation runs in logical 2D pixel
## space; `to3d`/`to2d` map that plane to/from 3D world space.

var _s := 1.0 / 56.0           # metres per logical pixel = 1/diameter; set in _ready
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
# Vertical stack below the danger (lose) line, in row-steps: the gun sits this far
# below the line, then the red miss-exit bar sits this far below the gun. A smaller
# MUZZLE_GAP lifts the whole gun+bar unit toward the field, so they sit closer to
# the spheres at the moment those reach the line and consume them.
const MUZZLE_GAP_ROWS := 0.3   # gun below the danger line (was 0.6 — hand-tuned 690)
const EXIT_GAP_ROWS := 0.6     # red miss-exit bar below the gun


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

# Danger visuals (bottom-line blink + red injury vignette) live in DangerView,
# which owns the tier logic and is driven via _update_heartbeat below.
const BANNER_PALE := Color(0.82, 0.78, 0.72, 1.0)   # intro / win verdict colour
const BANNER_RED := Color(0.86, 0.13, 0.12, 1.0)    # lose verdict colour

@export var diameter := 56.0
@export_range(1, 10) var num_colors := 5  # capped at BoardView3D.PALETTE.size()
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
# The trajectory only changes when the aim moves or the board changes, so we
# re-simulate on those events (mouse motion, shot resolution, ray shown) rather
# than every frame. simulate() is a heavy per-step loop; running it idle was waste.
var _aim_dirty := true
var game_over := false
var aim_ray_enabled := false   # trajectory preview hidden by default; [A] toggles
# Whether the ray should currently show, before the aim_ray_enabled / game_over gates.
# Always true in Click (ray shown whenever enabled); in Hold it's true only while the
# fire button is held, so the ray appears only during an aim. Seeded in _ready().
var _aim_active := true
var _shots_fired := 0          # HUD counter; bumped on every shot

# The danger subsystem (heartbeat audio + line/vignette shaders) lives in DangerView.
# _build_frame creates the bottom-bar material into _danger_line_mat; _ready hands it
# and the vignette material to the view, then set_tier() is driven via _update_heartbeat.
var _danger_view: DangerView
var _danger_line_mat: ShaderMaterial   # the bottom miss-exit bar (danger_line.gdshader)


func to3d(p: Vector2) -> Vector3:
	return Vector3((p.x - origin2d.x) * _s, -(p.y - origin2d.y) * _s, 0.0)

func to2d(w: Vector3) -> Vector2:
	return Vector2(w.x / _s + origin2d.x, -w.y / _s + origin2d.y)


func _ready() -> void:
	_s = 1.0 / diameter   # world scale follows the configured sphere size (one cell ≈ 1 m)
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
	# Control scheme is read once at build, like true_random (settings aren't reachable
	# mid-level). Hold: press aims, release fires, ray shows only while held. Click: fires
	# on press, ray always on (when enabled).
	shooter.hold_to_fire = Settings.control_scheme() == SettingsStore.ControlScheme.HOLD
	shooter.aim_active_changed.connect(_on_aim_active_changed)

	preview.mesh = _preview_mesh
	preview.material_override = _preview_mat
	aim_ray_enabled = Settings.aim_enabled()   # seed from the Gameplay setting; [A] still toggles in-session
	_aim_active = not shooter.hold_to_fire     # always-on in Click; off until a press in Hold
	_update_preview_visibility()

	_build_frame()
	_place_camera()
	_fit_embers()
	# Seed an initial aim + trajectory now that the camera is framed, so the gun can
	# fire and the ray can show before the first _process frame. Afterwards we only
	# re-simulate when the aim or board changes (see _aim_dirty / _input / _on_landed).
	_update_aim()
	_last_sim = sim.simulate(muzzle2d, _aim2d)
	_aim_dirty = false
	get_viewport().size_changed.connect(_place_camera)
	# Live-update glow/SSAO/shadows if the player changes Graphics settings while a level runs.
	Settings.graphics_changed.connect(_apply_graphics_settings)

	next_button.pressed.connect(GameState.start_next)
	retry_button.pressed.connect(GameState.retry_level)
	menu_button.pressed.connect(GameState.go_to_level_select)
	door_button.pressed.connect(GameState.go_to_level_select)

	# Danger subsystem: hand the bottom-line bar material (built in _build_frame) and
	# the red vignette material to a DangerView, which owns the heartbeat + shaders.
	_danger_view = DangerView.new()
	add_child(_danger_view)
	_danger_view.setup(_danger_line_mat, ($Dread/DangerVignette as ColorRect).material)
	level_name_label.text = _level.title if _level != null else "THE PIT"

	_update_status()
	_update_heartbeat()   # an authored level could start already close to the line

	Log.info(Log.PLAY, "level ready", {
		"mode": "authored" if _level != null else "free",
		"title": _level.title if _level != null else "THE PIT",
		"size": "%dx%d" % [columns, rows],
		"colors": num_colors,
		"danger_row": danger_row,
		"colored": model.count_colored(),
		"true_random": _bag.true_random,
		"aim": aim_ray_enabled,
		"hold": shooter.hold_to_fire,
	})

	if _level != null:
		_show_intro()

	if OS.has_environment("SOP_AUTOPLAY"):
		var t := Timer.new()
		t.wait_time = 0.6
		t.timeout.connect(_auto_step)
		add_child(t)
		t.start()
		Log.info(Log.PLAY, "autoplay enabled")


func _process(_delta: float) -> void:
	# The danger pulse advances in DangerView's own _process (throbs through game over).
	if game_over:
		return
	if _aim_dirty:
		# Aim or board changed since last sim — refresh the cached trajectory. _on_fired
		# re-aims on the actual shot, so a stale path between events is harmless.
		_last_sim = sim.simulate(muzzle2d, _aim2d)
		_aim_dirty = false
		if preview.visible:   # in Hold the ray is hidden most of the time — skip the rebuild
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


## The single source of truth for the aim ray's visibility: the master "Enable aim"
## setting, AND whether an aim is currently active (always in Click, only while held in
## Hold), AND that the level is still live. Every place that changes any of these calls
## this, so the ray can never get stuck on or hidden.
func _update_preview_visibility() -> void:
	preview.visible = aim_ray_enabled and _aim_active and not game_over
	if preview.visible:
		_aim_dirty = true   # rebuild the ray mesh from a fresh sim now that it shows


## Hold scheme: the fire button went down (active) or up (inactive). Drives the ray so
## it appears only for the duration of the aim. Not emitted in Click mode.
func _on_aim_active_changed(active: bool) -> void:
	_aim_active = active
	_update_preview_visibility()


# --- setup helpers ------------------------------------------------------------

func _build_visual_assets() -> void:
	# Mesh + materials are pure resources; SphereAssets owns their construction.
	var assets := SphereAssets.new(SPHERE_RADIUS)
	_mesh = assets.mesh
	_mats = assets.mats
	_black_mat = assets.black_mat
	_preview_mat = assets.preview_mat


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


## Build the bounce/exit border via a FrameView node (under the controller, NOT under
## Board, which frees its children on every rebuild). The frame's red bottom bar
## material is handed to the DangerView to pulse; ember veins take the level's tint.
func _build_frame() -> void:
	var theme := _level if _level != null else LevelResource.new()
	var frame := FrameView.new()
	frame.name = "Frame"
	add_child(frame)
	frame.build(_frame_bounds(0.0), theme.ember_color, FRAME_THICK, FRAME_DEPTH)
	_danger_line_mat = frame.danger_line_mat


## Leaving the game screen (Esc to the menu, retry, next, any scene change) must cut
## the dread pulses instantly — they belong to this level, not the menus.
func _exit_tree() -> void:
	Sound.stop_heartbeats()


func _input(event: InputEvent) -> void:
	# Aim follows the pointer, so recompute it on motion (event-driven) rather than
	# polling every frame; the trajectory re-simulates next frame via _aim_dirty.
	if event is InputEventMouseMotion:
		_update_aim()
		_aim_dirty = true
		return
	# Fullscreen has no window chrome — Esc leaves to level select (same as the
	# HUD door button), so the two exits behave identically.
	if event.is_action_pressed("ui_cancel"):
		GameState.go_to_level_select()
	elif event.is_action_pressed("toggle_aim"):
		aim_ray_enabled = not aim_ray_enabled
		_update_preview_visibility()   # in Hold mode, still only shows while the button is held


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
## centred on FIELD_CENTER_X), the muzzle MUZZLE_GAP_ROWS below the danger line,
## and the bottom miss-exit line EXIT_GAP_ROWS below the muzzle.
func _layout_field() -> void:
	var row_step := diameter * Hex.ROW_RATIO
	# Centre the field horizontally: with this origin, (play_left + play_right) / 2
	# lands on FIELD_CENTER_X regardless of column count.
	origin2d = Vector2(FIELD_CENTER_X - diameter * (columns * 0.5 - 0.25), TOP_Y)
	var danger_y := origin2d.y + danger_row * row_step
	muzzle2d = Vector2(FIELD_CENTER_X, danger_y + row_step * MUZZLE_GAP_ROWS)
	_play_bottom = muzzle2d.y + row_step * EXIT_GAP_ROWS


## Procedurally fill the field: every cell in the first `rows` rows takes a random
## breakable colour, then a fraction are overwritten with unbreakable black
## obstacles.
func _build_board() -> void:
	# The rule lives in the model (pure, seedable, unit-tested); the view just asks
	# for a board. model.rng was seeded in _ready, so this honours that seed.
	model.fill_random(rows, black_fraction)


## The gun's next colour, drawn only from those still present on the board so it
## never offers a colour that can no longer be matched. The ShotBag decides how
## (independent random, or the fair bag); it returns 0 when the board is cleared.
func _rand_color() -> int:
	return _bag.next(model.present_colors())


func _mat_for(color: int) -> Material:
	return BoardView3D.mat_for(_mats, _black_mat, color)


# --- shot results -------------------------------------------------------------

## `reaim` recomputes the aim against the live pointer at the instant of firing. The
## `fired` signal carries no args, so a real shot uses the default (true): in Hold a fast
## press+release can land between _process frames, leaving _aim2d stale; in Click _process
## already aimed this frame, so it's a no-op. Autoplay passes false — it sets its own
## canned _aim2d and must not have it clobbered by the (absent) mouse.
func _on_fired(reaim := true) -> void:
	if game_over or not _last_sim.has("path"):
		return
	if reaim:
		_update_aim()
		_last_sim = sim.simulate(muzzle2d, _aim2d)
	var is_miss: bool = _last_sim.get("miss", false)
	Log.debug(Log.SHOT, "fire", {
		"n": _shots_fired + 1,
		"color": shooter.current_color,
		"aim": _aim2d,
		"result": "miss" if is_miss else "hit",
		"cell": null if is_miss else _last_sim.cell,
	})
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
	# Board is now in its final post-resolution state; scan it once and share the
	# counts with the log, the HUD, and the heartbeat instead of rescanning thrice.
	var colored := model.count_colored()
	var deepest := model.max_row()
	Log.debug(Log.MODEL, "attach", {
		"cell": cell,
		"color": color,
		"pop": res.did_pop,
		"popped": res.popped.size(),
		"orphaned": res.orphaned.size(),
		"colored": colored,
		"max_row": deepest,
	})
	_update_status(colored)
	_update_heartbeat(model.danger_row - deepest)   # a grow may have closed on the line; a pop may have backed off it
	# Hold the verdict until the board has visually settled — the win banner must
	# not appear while the last cluster is still popping.
	if model.is_won() or model.is_lost():
		await get_tree().create_timer(settle + 0.25).timeout
		if not is_inside_tree() or game_over:
			return
		_check_end()
		return
	_aim_dirty = true   # the board changed; the cached trajectory must be refreshed
	shooter.enabled = true


func _on_missed() -> void:
	Log.debug(Log.SHOT, "miss reshuffle", {"colored": model.count_colored()})
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

const ROWS_TO_DANGER_UNSET := 0x7fffffff   # "not supplied" sentinel for _update_heartbeat

## Forward the field's proximity to the lose line to the DangerView, which owns the
## tier logic + audio/visual escalation. Called after every shot and at game end.
## `rows_left` lets the caller pass an already-computed rows_to_danger() to avoid a
## redundant whole-board max_row() scan; omit it and we compute it here.
func _update_heartbeat(rows_left: int = ROWS_TO_DANGER_UNSET) -> void:
	if rows_left == ROWS_TO_DANGER_UNSET:
		rows_left = model.rows_to_danger()
	_danger_view.set_tier(rows_left, game_over)


# --- end state ----------------------------------------------------------------

func _check_end() -> void:
	if model.is_won():
		_end("THE FIELD IS STILL.\nYou survive.", true)
	elif model.is_lost():
		_end("THE SPHERES CONSUME YOU.", false)


func _end(msg: String, won: bool) -> void:
	game_over = true
	Log.info(Log.PLAY, "level end", {
		"won": won,
		"shots": _shots_fired,
		"colored": model.count_colored(),
		"max_row": model.max_row(),
	})
	shooter.enabled = false
	_update_heartbeat()   # game_over now true -> both pulses fade out (cleared or consumed)
	_preview_mesh.clear_surfaces()
	_update_preview_visibility()   # hide the ray at once, even if a finger is still down (Hold)
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
## `colored` lets the caller pass an already-computed count_colored() to avoid a
## redundant whole-board scan; omit it (-1) and we scan here.
func _update_status(colored: int = -1) -> void:
	if colored < 0:
		colored = model.count_colored()
	counter_label.text = "Spheres  %d\nShots  %d" % [colored, _shots_fired]


# --- dev autoplay -------------------------------------------------------------

func _auto_step() -> void:
	if game_over or not shooter.enabled:
		return
	var dirs := [Vector2(0, -1), Vector2(0.45, -1).normalized(), Vector2(-0.5, -1).normalized()]
	_aim2d = dirs[randi() % dirs.size()]
	_last_sim = sim.simulate(muzzle2d, _aim2d)
	_on_fired(false)   # keep the canned direction; don't re-aim to the (absent) mouse
