class_name LevelController3D
extends Node3D

## 3D presentation of the SAME game. It owns the GridModel + ShotSimulator (the
## identical rules and ball-flight used by the 2D level) and renders them in 3D:
## sphere meshes on the board plane (XY, Z=0), a perspective camera, dim lighting,
## and a projectile flying on the plane. The simulation runs in logical 2D pixel
## space; `to3d`/`to2d` map that plane to/from 3D world space.

const SPHERE_RADIUS := 0.46
const FRAME_THICK := 0.3  # frame bar cross-section (metres)
const FRAME_DEPTH := 0.6  # frame bar depth toward the camera (metres)
# The logical play geometry (field centre, top wall, muzzle + miss-exit gaps) is derived from
# the field size by the pure, unit-tested BoardGeometry helper. Camera framing margins +
# backdrop offset live in StageView, which owns the camera.

# Sentinel for _update_heartbeat's optional rows_left arg (see the danger section below).
const ROWS_TO_DANGER_UNSET := 0x7fffffff  # "not supplied" sentinel for _update_heartbeat

# Camera-shake trauma tiers (E2.2), fed to StageView.add_trauma (which squares trauma and
# scales by the Effects-Intensity slider). A dud lands with a thud; a pop scales with how
# many souls it freed, from a small twitch up to a catastrophe slam.
const FIRE_TRAUMA := 0.13  # tiny pitch-kick every shot — restraint, near-subliminal
const LAND_TRAUMA := 0.15  # a non-popping landing still thuds
const CLEAR_TRAUMA_BASE := 0.22  # floor a 3-match pop starts from
const CLEAR_TRAUMA_PER := 0.04  # added per freed sphere (matched + orphaned)
const CLEAR_TRAUMA_MIN := 0.30  # any pop registers at least this much
const CLEAR_TRAUMA_MAX := 0.95  # a catastrophe clear, capped shy of full trauma

# Big-clear crescendo (E2.4): a clear this large briefly drags time + all audio pitch down
# together, then eases back — the peak of the "build → peak → aftermath" sequence.
const BIG_CLEAR_AT := 20  # freed spheres at/above which the slow-mo fires
# Inward screen-pulse (E2.8): a medium-or-bigger clear throbs the dark inward, strength rising
# with magnitude. Lower threshold than the slow-mo so medium clears still register a throb.
const PULSE_CLEAR_AT := 6
const PULSE_STRENGTH_BASE := 0.22
const PULSE_STRENGTH_PER := 0.03
const PULSE_STRENGTH_MAX := 0.85
const SLOWMO_SCALE := 0.35  # how far the clock dips at the peak
const SLOWMO_HOLD := 0.12  # seconds held at the dip (real time)
const SLOWMO_RECOVER := 0.34  # seconds easing back to full speed (real time)

# End-state easing (E2.7). Win = relief: the gothic grading eases a few % toward calm.
# Lose = payoff: the vignette closes in (DangerView), the board drains toward grey, and a
# black fill wells up behind the verdict (which sits on the Ui layer above the Dread fill).
const WIN_SATURATION := 0.95
const WIN_CONTRAST := 1.0
const WIN_EASE_TIME := 1.6
const LOSE_BLACK_ALPHA := 0.72
const LOSE_SATURATION := 0.15
const LOSE_FADE_TIME := 1.4
const LOSE_DEAD_AIR := 0.15  # silence after the heartbeats stop before the defeat sting lands

# The grimdark veil shown while the field is built, and how many spheres to spawn per frame
# behind it. ~100/frame keeps each build frame a few ms even on weak machines while still
# finishing a full 2500-sphere board in well under a second.
const LOADING_OVERLAY_SCENE := preload("res://scenes/loading_overlay.tscn")
const BUILD_CHUNK := 100

# The intro/end overlay (banner, lore, choice panel, fades) lives in CenterBanner; the danger
# heartbeat/visuals live in DangerView; the narrator's bark cadence lives in NarratorDirector.
# All are driven from here.

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
var origin2d := Vector2(346, 80)  # logical board origin (cell 0,0)
var muzzle2d := Vector2(640, 690)  # logical muzzle
var model: GridModel
var sim := ShotSimulator.new()
var game_over := false

var _s := 1.0 / 56.0  # metres per logical pixel = 1/diameter; set in _ready
var _play_bottom := 720.0  # logical miss-exit line (below the muzzle)
var _geom: BoardGeometry.Layout  # the derived play geometry; set in _layout_field
var _level: LevelResource = null  # null = free play (random board)
# Cells the objective watches ('@'/'*'), cached from the level in _ready; empty for CLEAR / free
# play. The win check (objective_met) waits for all of these to empty out.
var _objective_cells: Array[Vector2i] = []
var _bag := ShotBag.new()  # decides the gun's next colour (true-random or bag mode)
var _mesh: SphereMesh
var _mats: Array[StandardMaterial3D] = []
var _specials: Dictionary  # indestructible sentinel (< 0) -> Material (obsidian / swirl / pulse)
var _preview_mat: StandardMaterial3D  # handed to AimView; built in _build_visual_assets
var _aim_view: AimView  # owns the aim direction + dotted trajectory ray + its visibility
var _last_sim: Dictionary = {}
# The trajectory only changes when the aim moves or the board changes, so we
# re-simulate on those events (mouse motion, shot resolution, ray shown) rather
# than every frame. simulate() is a heavy per-step loop; running it idle was waste.
var _aim_dirty := true
var _shots_fired := 0  # HUD counter; bumped on every shot
# Cumulative souls unmade this level (matched pops + the orphans they sweep). Diegetically
# "souls freed"; fuels the grim end-screen epitaph. Never reset mid-level.
var _souls_freed := 0
# Skill score for this level: matched pops modestly, the isolation sweep super-linearly, plus
# an all-clear + economy bonus at the end (see Scoring). Never shown as a raw arcade number —
# it resolves into one verdict word at the end ("how cleanly you ended the suffering").
var _score := 0
# The danger subsystem (heartbeat audio + line/vignette shaders) lives in DangerView.
# _build_frame creates the bottom-bar material into _danger_line_mat; _ready hands it
# and the vignette material to the view, then set_tier() is driven via _update_heartbeat.
var _danger_view: DangerView
var _danger_line_mat: ShaderMaterial  # the bottom miss-exit bar (danger_line.gdshader)
var _center_banner: CenterBanner  # owns the intro/end overlay + its fades
var _stage_view: StageView  # owns the camera, backdrop, embers, environment
var _pop_burst: PopBurst  # pooled cluster-death particle bursts (embers/ash/shards/wisps)
var _narrator: NarratorDirector  # owns the narrator subtitle + when it speaks
# True while the field is being built behind the loading veil — gates firing so a click
# during load can't shoot into a half-built board. The veil itself lives here only while up.
var _loading := false
var _loading_overlay: LoadingOverlay

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
@onready var narrator_bg: ColorRect = $Ui/NarratorBg
@onready var narrator_line: Label = $Ui/NarratorLine


func to3d(p: Vector2) -> Vector3:
	return Vector3((p.x - origin2d.x) * _s, -(p.y - origin2d.y) * _s, 0.0)


func to2d(w: Vector3) -> Vector2:
	return Vector2(w.x / _s + origin2d.x, -w.y / _s + origin2d.y)


func _ready() -> void:
	_s = 1.0 / diameter  # world scale follows the configured sphere size (one cell ≈ 1 m)
	randomize()
	_build_visual_assets()
	# StageView owns the camera, backdrop, embers and environment; it builds the
	# environment now and reframes/recolours on the calls below.
	_stage_view = StageView.new()
	add_child(_stage_view)
	_stage_view.setup(world_env, light, camera, backdrop, embers)

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
		# The objective cells ('@'/'*') are level metadata, not model state — cache the
		# coordinates once so the verdict check can watch them empty out (empty for CLEAR).
		_objective_cells = _level.objective_cells()
		_layout_field()
	else:
		_pick_field_dimensions()
		model = GridModel.new()
		model.width = columns
		model.num_colors = num_colors
		model.danger_row = danger_row
		model.rng.randomize()
		_build_board()

	_stage_view.apply_theme(_level if _level != null else LevelResource.new())

	sim.model = model
	sim.diameter = diameter
	sim.columns = columns
	sim.origin = origin2d
	sim.play_left = _geom.play_left
	sim.play_right = _geom.play_right
	sim.play_bottom = _geom.play_bottom

	# Configure the board but defer the sphere spawning to build_async (run behind the loading
	# veil below), so a large field never freezes the window on entry.
	board.setup(model, _mesh, _mats, _specials, diameter, false)

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

	# Aim direction + dotted trajectory ray live in AimView; hand it the Preview node, the
	# camera, the muzzle, and the logical<->world mapping. It seeds its own visibility from the
	# Gameplay "Enable aim" setting ([A] still toggles in-session) and emits ray_revealed
	# whenever the ray shows, which marks the trajectory dirty for the next _process.
	_aim_view = AimView.new()
	add_child(_aim_view)
	_aim_view.ray_revealed.connect(_on_ray_revealed)
	_aim_view.setup(
		preview,
		camera,
		muzzle2d,
		to3d,
		to2d,
		_preview_mat,
		diameter * SPHERE_RADIUS,
		Settings.aim_enabled(),
		shooter.hold_to_fire
	)
	shooter.aim_active_changed.connect(_aim_view.set_active)

	_build_frame()
	_stage_view.frame(_frame_bounds(FRAME_THICK))  # outer edge of the frame
	_stage_view.fit_embers(_frame_bounds(0.0))
	# Pooled cluster-death bursts, fired at the impact cell from _on_landed. A sibling of
	# the board (both at world origin), so a cell's board-local position is its world pos.
	_pop_burst = PopBurst.new()
	add_child(_pop_burst)
	# Seed an initial aim + trajectory now that the camera is framed, so the gun can
	# fire and the ray can show before the first _process frame. Afterwards we only
	# re-simulate when the aim or board changes (see _aim_dirty / _input / _on_landed).
	_aim_view.update_aim()
	_last_sim = sim.simulate(muzzle2d, _aim_view.aim2d)
	_aim_dirty = false

	door_button.pressed.connect(GameState.go_back_from_play)

	# Intro/end overlay: hand the banner/lore/panel nodes to CenterBanner, which owns
	# their fades and wires the choice buttons to GameState.
	_center_banner = CenterBanner.new()
	_center_banner.setup(
		banner_bg,
		lore_bg,
		banner_label,
		lore_label,
		end_panel,
		next_button,
		retry_button,
		menu_button
	)

	# The grim narrator owns its own subtitle low on the HUD, independent of the centre banner,
	# so a bark and the level lore can coexist. NarratorView fades whatever line it's handed;
	# NarratorDirector decides when to speak (line pools + never-repeat memory live in the
	# Narrator autoload). The director seeds its cooldown + danger tier from the opening board.
	var narrator_view := NarratorView.new()
	narrator_view.setup(narrator_line, narrator_bg)
	var region_id := (
		GameState.region_id_for_node(GameState.selected_index) if _level != null else -1
	)
	_narrator = NarratorDirector.new()
	add_child(_narrator)
	_narrator.setup(narrator_view, region_id, model.rows_to_danger())

	# Danger subsystem: hand the bottom-line bar material (built in _build_frame) and
	# the red vignette material to a DangerView, which owns the heartbeat + shaders.
	_danger_view = DangerView.new()
	add_child(_danger_view)
	_danger_view.setup(_danger_line_mat, ($Dread/DangerVignette as ColorRect).material)
	level_name_label.text = _level.title if _level != null else "THE PIT"

	_update_status()
	_update_heartbeat()  # an authored level could start already close to the line

	(
		Log
		. info(
			Log.PLAY,
			"level ready",
			{
				"mode": "authored" if _level != null else "free",
				"title": _level.title if _level != null else "THE PIT",
				"size": "%dx%d" % [columns, rows],
				"colors": num_colors,
				"danger_row": danger_row,
				"colored": model.count_colored(),
				"true_random": _bag.true_random,
				"aim": _aim_view.aim_ray_enabled,
				"hold": shooter.hold_to_fire,
			}
		)
	)

	# Build the field behind a loading veil. The veil (level title + lore + a progress bar)
	# doubles as the intro, so the CenterBanner intro is no longer shown here; the spheres are
	# spawned in time-sliced chunks so even a large board never freezes the window, and the
	# shaders are pre-warmed first so the first frame of play (and the first shot) don't hitch.
	_loading = true
	shooter.enabled = false
	_loading_overlay = LOADING_OVERLAY_SCENE.instantiate()
	add_child(_loading_overlay)
	_loading_overlay.begin(
		_level.title if _level != null else "THE PIT",
		_level.lore_fragment if _level != null else ""
	)
	_build_field_async()  # coroutine: prewarm -> chunked spawn -> reveal -> hand off to play


## Coroutine started at the end of _ready: pre-warm the shaders, spawn the field in chunks
## (driving the loading bar), then reveal the board and return control to the player. Runs
## entirely on the main thread — the work is time-sliced across frames, not threaded, because
## node creation isn't thread-safe.
func _build_field_async() -> void:
	var tree := get_tree()
	await tree.process_frame  # let the opaque veil paint before any heavy (masked) work
	await _prewarm_shaders()
	await board.build_async(BUILD_CHUNK, _on_build_progress)
	if not is_inside_tree():
		return  # left the level mid-build
	_loading = false
	if not game_over:
		shooter.enabled = true
	await _loading_overlay.dismiss()
	_loading_overlay = null
	if not is_inside_tree():
		return
	# The voice and (dev) autoplay only start once the board is revealed and play has begun.
	if _level != null:
		_narrator.say_descent_after_intro()
	_maybe_start_autoplay()


func _on_build_progress(done: int, total: int) -> void:
	if _loading_overlay != null:
		_loading_overlay.set_progress(float(done) / float(maxi(total, 1)))


## Compile the pipelines for the materials that otherwise first appear during gameplay — the
## sphere material, the obsidian/spin/bounce obstacle shaders and the aim-ray preview — by
## drawing each once on a throwaway mesh in front of the camera, hidden behind the opaque
## veil. The frame/backdrop/HUD shaders already draw on frame 1 (also behind the veil), so
## they compile for free. Front-loading every compile here keeps both the chunked build and
## the first shot smooth. Best-effort: Forward+ compiles a pipeline when its draw is first
## submitted, so two frames give it time to land before the veil lifts.
func _prewarm_shaders() -> void:
	var mats: Array[Material] = [_mats[0], _preview_mat]
	mats.append_array(_specials.values())
	var holder := Node3D.new()
	holder.name = "ShaderPrewarm"
	add_child(holder)
	var base := camera.global_transform.origin - camera.global_transform.basis.z
	for i in mats.size():
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh
		mi.material_override = mats[i]
		mi.scale = Vector3.ONE * 0.1  # tiny; it's hidden by the veil anyway, just needs to draw
		mi.position = base + Vector3(float(i) * 0.05, 0.0, 0.0)
		holder.add_child(mi)
	await get_tree().process_frame
	await get_tree().process_frame
	holder.queue_free()


func _maybe_start_autoplay() -> void:
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
		_last_sim = sim.simulate(muzzle2d, _aim_view.aim2d)
		_aim_dirty = false
		if _aim_view.ray_visible():  # in Hold the ray is hidden most of the time — skip rebuild
			_aim_view.draw(_last_sim, shooter.current_color)


## AimView reshowed the ray (toggle, an aim press, or initial setup) — mark the trajectory
## dirty so the next _process re-simulates and redraws it.
func _on_ray_revealed() -> void:
	_aim_dirty = true


# --- setup helpers ------------------------------------------------------------


func _build_visual_assets() -> void:
	# Mesh + materials are pure resources; SphereAssets owns their construction.
	var assets := SphereAssets.new(SPHERE_RADIUS)
	_mesh = assets.mesh
	_mats = assets.mats
	_specials = assets.specials
	_preview_mat = assets.preview_mat


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
	# Safety: if we leave mid-crescendo, restore real time so the menus / next level don't
	# inherit a dragged-down clock or pitch (the slow-mo tween dies with this node).
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0


func _input(event: InputEvent) -> void:
	# Aim follows the pointer, so recompute it on motion (event-driven) rather than
	# polling every frame; the trajectory re-simulates next frame via _aim_dirty.
	if event is InputEventMouseMotion:
		_aim_view.update_aim()
		_aim_dirty = true
		return
	# Fullscreen has no window chrome — Esc leaves the level (same as the HUD door
	# button), returning to whatever launched it (level select, editor, My Levels).
	if event.is_action_pressed("ui_cancel"):
		GameState.go_back_from_play()
	elif event.is_action_pressed("toggle_aim"):
		_aim_view.toggle_enabled()  # in Hold mode, still only shows while the button is held


## Roll a random field size within the configured ranges and derive every logical
## coordinate from it: the board origin (so the field stays centred on
## FIELD_CENTER_X), the danger row (the bottom edge of the field — fill_random leaves
## its own empty headroom band there), the muzzle, and the bottom miss-exit line. The
## camera reframes to whatever this produces (see _place_camera), so any size in range
## is captured in full.
func _pick_field_dimensions() -> void:
	columns = randi_range(min_columns, max_columns)
	rows = randi_range(min_rows, max_rows)
	danger_row = rows
	_layout_field()


## Derive every logical coordinate from `columns` / `danger_row` (set either by the random
## roll above or by an authored level) via the shared BoardGeometry helper: the board origin
## (field centred), the muzzle below the danger line, the bottom miss-exit line, and the
## bounce bounds. Cached in `_geom` so the sim config below reads the identical values.
func _layout_field() -> void:
	_geom = BoardGeometry.compute(columns, danger_row, diameter)
	origin2d = _geom.origin2d
	muzzle2d = _geom.muzzle2d
	_play_bottom = _geom.play_bottom


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
	return BoardView3D.mat_for(_mats, _specials, color)


# --- shot results -------------------------------------------------------------


## `reaim` recomputes the aim against the live pointer at the instant of firing. The
## `fired` signal carries no args, so a real shot uses the default (true): in Hold a fast
## press+release can land between _process frames, leaving the aim stale; in Click _process
## already aimed this frame, so it's a no-op. Autoplay passes false — it sets its own
## canned aim and must not have it clobbered by the (absent) mouse.
func _on_fired(reaim := true) -> void:
	if _loading or game_over or not _last_sim.has("path"):
		return
	if reaim:
		_aim_view.update_aim()
		_last_sim = sim.simulate(muzzle2d, _aim_view.aim2d)
	var is_miss: bool = _last_sim.get("miss", false)
	(
		Log
		. debug(
			Log.SHOT,
			"fire",
			{
				"n": _shots_fired + 1,
				"color": shooter.current_color,
				"aim": _aim_view.aim2d,
				"result": "miss" if is_miss else "hit",
				"cell": null if is_miss else _last_sim.cell,
			}
		)
	)
	_shots_fired += 1
	_update_status()  # the shots tally ticks the moment the gun fires
	shooter.enabled = false
	_stage_view.add_trauma(FIRE_TRAUMA)  # a small kick as the orb leaves the muzzle
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


## Coroutine: the post-shot animations play in sequence (pop/grow, then spin), the gun stays
## locked until the board settles, and the verdict is read last (the spin can push a sphere
## across the line). See docs/architecture/level-flow.md for the full ordering rationale.
func _on_landed(cell: Vector2i, color: int) -> void:
	var res := model.attach(cell, color)
	if res.did_pop:
		var freed := res.popped.size() + res.orphaned.size()
		# One cluster-sized pop burst, not one sound per sphere — keeps big clears
		# (the matched group plus any spheres it orphans) from turning to noise.
		Sound.play_cluster_pop(freed)
		# Every removed sphere is a soul let go of the wall — tally them for the epitaph.
		_souls_freed += freed
		# Score the shot: the matched cluster modestly, the isolation sweep super-linearly.
		_score += Scoring.shot_score(res.popped.size(), res.orphaned.size())
		_narrator.narrate_clear(res.popped.size(), res.orphaned.size())
		# The board lurches in proportion to how much it just lost, and throws ash, embers,
		# bone shards and a few rising soul-wisps out of the impact cell.
		_stage_view.add_trauma(_clear_trauma(freed))
		_pop_burst.fire(board.cell_local(cell), freed)
		if freed >= PULSE_CLEAR_AT:
			_danger_view.pulse(
				clampf(PULSE_STRENGTH_BASE + freed * PULSE_STRENGTH_PER, 0.30, PULSE_STRENGTH_MAX)
			)
		if freed >= BIG_CLEAR_AT:
			_crescendo_slowmo()  # a big chain drags the whole moment down
			Sound.play_drone(clampf(float(freed) / 24.0, 0.4, 1.0))  # the sub-bass swell
	else:
		model.grow()
		_stage_view.add_trauma(LAND_TRAUMA)  # a dud still lands with a thud
	# On a pop, ripple the clear outward from the impact cell; on a dud the grown
	# spheres just animate in (no removals, so pop_origin is irrelevant).
	var settle := board.sync([cell], cell)  # the landed sphere appears full-size
	# Let the pop/grow finish before the spin reacts — the phases read sequentially.
	if settle > 0.0:
		await get_tree().create_timer(settle).timeout
		if not is_inside_tree() or game_over:
			return
	# Spin spheres now react to the settled board, physically rotating their breakable
	# neighbours one slot anti-clockwise. spin_step() brings the model to its final
	# state and returns the moves; animate_spin() relocates the existing nodes.
	var moves := model.spin_step()
	var spin_settle := board.animate_spin(moves)
	if spin_settle > 0.0:
		Log.debug(Log.PLAY, "spin", {"moves": moves.size(), "settle": spin_settle})
		await get_tree().create_timer(spin_settle).timeout
		if not is_inside_tree() or game_over:
			return
	# The tide (if any) drops the whole field one shot deeper — after the spin settles, before
	# the verdict is read, so a drop that crosses the line is reckoned with this same turn.
	if await _apply_tide():
		return  # left the level mid-descent
	_validate_load()
	# Board is now in its final post-resolution state; scan it once and share the
	# counts with the log, the HUD, and the heartbeat instead of rescanning thrice.
	# Read AFTER the spin — it can move a sphere into a deeper row.
	var colored := model.count_colored()
	var deepest := model.max_row()
	(
		Log
		. debug(
			Log.MODEL,
			"attach",
			{
				"cell": cell,
				"color": color,
				"pop": res.did_pop,
				"popped": res.popped.size(),
				"orphaned": res.orphaned.size(),
				"spin_moves": moves.size(),
				"colored": colored,
				"max_row": deepest,
			}
		)
	)
	_update_status(colored)
	# a grow may have closed on the line; a pop may have backed off it
	_update_heartbeat(model.danger_row - deepest)
	_narrator.narrate_danger(model.danger_row - deepest)
	# Hold the verdict a beat so the final state reads before the banner. Pop/grow, spin and
	# the tide have already settled above; any of them can end the level (the spin or the tide
	# can push a sphere across the line), so the verdict is read here, after them all.
	if _is_objective_met() or _is_failed():
		await get_tree().create_timer(0.25).timeout
		if not is_inside_tree() or game_over:
			return
		_check_end()
		return
	_aim_dirty = true  # the board changed; the cached trajectory must be refreshed
	shooter.enabled = true


## Map a clear's magnitude (matched + orphaned spheres) to a camera-shake trauma value:
## any pop registers at least CLEAR_TRAUMA_MIN, growing per freed sphere up to a capped
## catastrophe slam. StageView squares this and scales it by the Effects-Intensity slider.
func _clear_trauma(freed: int) -> float:
	return clampf(CLEAR_TRAUMA_BASE + freed * CLEAR_TRAUMA_PER, CLEAR_TRAUMA_MIN, CLEAR_TRAUMA_MAX)


## A big clear briefly drags the whole world down: the clock and all audio pitch dip
## together (AudioServer.playback_speed_scale transposes everything downward for free), then
## ease back. Gated on the Effects-Intensity slider — the dip is shallower as it lowers, and
## absent at 0. The restore tween ignores time_scale (or it would crawl and never finish);
## _exit_tree resets the globals if the level is torn down mid-dip.
func _crescendo_slowmo() -> void:
	var fx := Settings.fx_intensity()
	if fx <= 0.0:
		return
	var dip := lerpf(1.0, SLOWMO_SCALE, fx)
	_set_time_scale(dip)
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_interval(SLOWMO_HOLD)
	tw.tween_method(_set_time_scale, dip, 1.0, SLOWMO_RECOVER)


func _set_time_scale(s: float) -> void:
	Engine.time_scale = s
	AudioServer.playback_speed_scale = s


## Win = relief, not fanfare: heartbeats have already stopped and the vignette recedes; ease
## the drained gothic grading a few % toward calm — "a held breath let out in a cold room".
func _ease_env_calm() -> void:
	var env := world_env.environment
	if env == null:
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(env, "adjustment_saturation", WIN_SATURATION, WIN_EASE_TIME)
	tw.tween_property(env, "adjustment_contrast", WIN_CONTRAST, WIN_EASE_TIME)


## Lose = payoff: the red injury vignette closes inward (DangerView.close_out), the board
## drains toward grey, and black wells up behind the verdict. The black fill sits at the back
## of the Dread layer so the closing red stays vivid on top of it, and the verdict + choices
## (Ui layer, above Dread) stay legible — a loss must always show the player the fatal board.
func _close_out_lose() -> void:
	_danger_view.close_out()
	# Heartbeats were hard-stopped in _end; leave a beat of dead air, then the sub-bass sting
	# lands into the silence (E2.7). A timer, not an await, so it can't block the end flow.
	get_tree().create_timer(LOSE_DEAD_AIR).timeout.connect(Sound.play_lose_sting)
	var dread := $Dread as CanvasLayer
	var black := ColorRect.new()
	black.color = Color(0.0, 0.0, 0.0, 0.0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dread.add_child(black)
	dread.move_child(black, 0)  # behind the grain overlay + the closing red vignette
	var tw := create_tween().set_parallel(true)
	tw.tween_property(black, "color:a", LOSE_BLACK_ALPHA, LOSE_FADE_TIME)
	var env := world_env.environment
	if env != null:
		tw.tween_property(env, "adjustment_saturation", LOSE_SATURATION, LOSE_FADE_TIME)


func _on_missed() -> void:
	Log.debug(Log.SHOT, "miss reshuffle", {"colored": model.count_colored()})
	model.randomize_colors()
	board.sync()  # reshuffle only recolours; spheres stay, materials swap in place
	# Every shot drops the tide, a miss included — it can push the field across the line.
	if await _apply_tide():
		return  # left the level mid-descent
	_validate_load()
	_update_status()
	_update_heartbeat()
	# A miss can lose the level (the tide crossing the line, or the last shot of a spent budget)
	# but never win it — nothing was cleared. Read the verdict before re-arming the gun.
	if _is_failed() or _is_objective_met():
		await get_tree().create_timer(0.25).timeout
		if not is_inside_tree() or game_over:
			return
		_check_end()
		return
	shooter.enabled = true


## Drop the dark tide one shot deeper, if this level has one. Runs after the spin settles and
## before the verdict, so a drop that pushes the field across the line loses THIS turn. Returns
## true if the level was torn down mid-descent (the caller must then stop touching the tree).
func _apply_tide() -> bool:
	if _level == null or _level.tide_rows_per_shot <= 0:
		return false
	var moves := model.descend(_level.tide_rows_per_shot)
	var settle := board.animate_descend(moves)
	if settle > 0.0:
		Log.debug(Log.MODEL, "tide", {"rows": _level.tide_rows_per_shot, "moves": moves.size()})
		await get_tree().create_timer(settle).timeout
		if not is_inside_tree() or game_over:
			return true
	return false


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


## Forward the field's proximity to the lose line to the DangerView, which owns the
## tier logic + audio/visual escalation. Called after every shot and at game end.
## `rows_left` lets the caller pass an already-computed rows_to_danger() to avoid a
## redundant whole-board max_row() scan; omit it and we compute it here.
func _update_heartbeat(rows_left: int = ROWS_TO_DANGER_UNSET) -> void:
	if rows_left == ROWS_TO_DANGER_UNSET:
		rows_left = model.rows_to_danger()
	_danger_view.set_tier(rows_left, game_over)


# --- end state ----------------------------------------------------------------


## True when the level's victory condition is satisfied — delegates to the level's pure
## objective_met predicate, so the win rule has one home. Free play has no level, so it clears
## the board the old way.
func _is_objective_met() -> bool:
	if _level == null:
		return model.is_won()
	return _level.objective_met(model, _objective_cells)


## True when the level is lost: a sphere crossed the danger line, OR a Sniper shot-budget ran out
## before the objective was met. The objective is re-checked here so a winning final shot (which
## also spends the last of the budget) is never read as a failure — met always beats failed.
func _is_failed() -> bool:
	if model.is_lost():
		return true
	if _level != null and _level.shot_budget > 0:
		return _shots_fired >= _level.shot_budget and not _is_objective_met()
	return false


## The win banner per objective — short enough for the title font; the epitaph carries the
## grave-courtesy + souls tally beneath it.
func _win_verdict() -> String:
	if _level != null:
		match _level.objective_type:
			LevelResource.Objective.FREE_SOUL:
				return "THE CAGE IS OPEN.\nIt does not look back."
			LevelResource.Objective.CLEANSE:
				return "THE MARK IS LIFTED.\nThe stain remains in you."
	return "THE WALL IS QUIET.\nYou are not in it."


## The lose banner: a spent Sniper budget reads differently from being dragged under the line.
func _lose_verdict() -> String:
	if not model.is_lost() and _level != null and _level.shot_budget > 0:
		return "YOUR HANDS ARE EMPTY.\nThe work undone."
	return "THE DEAD RECLAIM YOU."


func _check_end() -> void:
	# Verdicts speak the fiction (§2.10): short lines to fit the banner; the grave-courtesy +
	# souls tally ride the epitaph beneath. Met is checked first so it always beats failed.
	if _is_objective_met():
		_end(_win_verdict(), true)
	elif _is_failed():
		_end(_lose_verdict(), false)


func _end(msg: String, won: bool) -> void:
	game_over = true
	_narrator.mark_ended()  # a pending descent/danger bark must not speak past the verdict
	# A win banks the marquee all-clear bonus plus any shots spared under par (the economy).
	if won:
		_score += Scoring.all_clear_bonus() + Scoring.economy_bonus(_par_shots(), _shots_fired)
	(
		Log
		. info(
			Log.PLAY,
			"level end",
			{
				"won": won,
				"shots": _shots_fired,
				"colored": model.count_colored(),
				"max_row": model.max_row(),
				"souls": _souls_freed,
				"score": _score,
			}
		)
	)
	shooter.enabled = false
	_update_heartbeat()  # game_over now true -> both pulses fade out (cleared or consumed)
	_aim_view.hide_ray()  # cut the ray at once, even if a finger is still down (Hold)
	# Win eases the room toward calm; a loss lets the dark close in over the fatal board.
	if won:
		_ease_env_calm()
	else:
		_close_out_lose()
	if won and _level != null:
		GameState.complete_current(_score, Scoring.tier(_par_shots(), _shots_fired))
	# Beating the final region's boss ends the whole descent: hold the verdict a beat, let
	# the voice land, then move to the epilogue (its own scene) instead of the ordinary end
	# panel. Esc still skips out to the hub during the pause.
	if won and GameState.is_final_boss(GameState.selected_index):
		_center_banner.show_end(msg, true, false, false, _epitaph(true))
		_narrator.say("victory", true)
		await get_tree().create_timer(3.5).timeout
		if is_inside_tree():
			GameState.go_to_epilogue()
		return
	# The visual verdict + choice panel are the CenterBanner's job; we just decide which choices
	# apply. The descent branches, so there is no single "next" — a win returns to the world map
	# (the menu button) to pick the next path. Retry is offered on any authored level (win or loss:
	# replay to better the score/tier, or try again after a fall); free play has neither.
	var show_next := false
	var show_retry := _level != null
	_center_banner.show_end(msg, won, show_next, show_retry, _epitaph(won))
	# The voice has the last word, on the HUD beneath the verdict (it interrupts any
	# clear/danger bark from the final shot). Forced — the end of a level always speaks.
	_narrator.say("victory" if won else "defeat", true)


## The level's shot budget for the efficiency tiers, or 0 (unset) for free play / a level that
## never set par — Scoring then reads the neutral FREED tier and grants no economy bonus.
func _par_shots() -> int:
	return _level.par_shots if _level != null else 0


## A one-breath tally beneath the verdict — the fiction's "grim epitaph", not a score. On a win
## it opens with the efficiency tier word (how cleanly the suffering ended); a loss carries no
## tier (you did not clear). Carries the grave-courtesy the title-size verdict has no room for.
func _epitaph(won: bool) -> String:
	if won:
		var t := Scoring.tier(_par_shots(), _shots_fired)
		return "%s. %d freed. Not one thanked you." % [Scoring.tier_word(t), _souls_freed]
	return "%d freed; and so you join the pattern you came to break." % _souls_freed


## The top-left HUD counter: coloured spheres still on the field (the clear target)
## and a running tally of shots fired. The level name and exits live in their own
## HUD nodes; the old one-line hint string is gone.
## `colored` lets the caller pass an already-computed count_colored() to avoid a
## redundant whole-board scan; omit it (-1) and we scan here.
func _update_status(colored: int = -1) -> void:
	if colored < 0:
		colored = model.count_colored()
	# Souls freed is understated, in fiction — not a flashing arcade score. The goal line names
	# what this level asks for (spheres / a caged soul / a cursed cell); the shots line shows the
	# Sniper budget when there is one.
	counter_label.text = (
		"%s\n%s\nSouls freed  %d" % [_goal_line(colored), _shots_line(), _souls_freed]
	)


## How many objective cells are still occupied (the FREE_SOUL / CLEANSE remaining count).
func _objective_remaining() -> int:
	var n := 0
	for cell in _objective_cells:
		if model.is_occupied(cell):
			n += 1
	return n


## The HUD goal line: the clear target for a CLEAR level, or the remaining tagged cells for an
## objective level.
func _goal_line(colored: int) -> String:
	if _level != null:
		match _level.objective_type:
			LevelResource.Objective.FREE_SOUL:
				return "Caged  %d" % _objective_remaining()
			LevelResource.Objective.CLEANSE:
				return "Cursed  %d" % _objective_remaining()
	return "Spheres  %d" % colored


## The HUD shots line: a bare tally, or fired / budget when a Sniper budget caps the level.
func _shots_line() -> String:
	if _level != null and _level.shot_budget > 0:
		return "Shots  %d / %d" % [_shots_fired, _level.shot_budget]
	return "Shots  %d" % _shots_fired


# --- dev autoplay -------------------------------------------------------------


func _auto_step() -> void:
	if game_over or not shooter.enabled:
		return
	var dirs := [Vector2(0, -1), Vector2(0.45, -1).normalized(), Vector2(-0.5, -1).normalized()]
	_aim_view.set_aim(dirs[randi() % dirs.size()])
	_last_sim = sim.simulate(muzzle2d, _aim_view.aim2d)
	_on_fired(false)  # keep the canned direction; don't re-aim to the (absent) mouse
