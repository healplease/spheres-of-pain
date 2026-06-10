class_name LevelController3D
extends Node3D

## 3D presentation of the SAME game. It owns the GridModel + ShotSimulator (the
## identical rules and ball-flight used by the 2D level) and renders them in 3D:
## sphere meshes on the board plane (XY, Z=0), a perspective camera, dim lighting,
## and a projectile flying on the plane. The simulation runs in logical 2D pixel
## space; `to3d`/`to2d` map that plane to/from 3D world space.

const S := 1.0 / 56.0          # metres per logical pixel; one cell ≈ 1 m
const SPHERE_RADIUS := 0.46

@export var diameter := 56.0
@export var columns := 11
@export var num_colors := 5
@export var danger_row := 12
@export var origin2d := Vector2(346, 80)   # logical board origin (cell 0,0)
@export var muzzle2d := Vector2(640, 690)  # logical muzzle

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var light: DirectionalLight3D = $DirectionalLight3D
@onready var camera: Camera3D = $Camera3D
@onready var board: BoardView3D = $Board
@onready var shooter: Shooter3D = $Shooter
@onready var preview: MeshInstance3D = $Preview
@onready var status_label: Label = $Ui/Status
@onready var banner_label: Label = $Ui/Banner

var model: GridModel
var sim := ShotSimulator.new()
var _mesh: SphereMesh
var _mats: Array[StandardMaterial3D] = []
var _black_mat: StandardMaterial3D
var _preview_mesh := ImmediateMesh.new()
var _preview_mat: StandardMaterial3D
var _aim2d := Vector2(0, -1)
var _last_sim: Dictionary = {}
var game_over := false
var _debug := false


func to3d(p: Vector2) -> Vector3:
	return Vector3((p.x - origin2d.x) * S, -(p.y - origin2d.y) * S, 0.0)

func to2d(w: Vector3) -> Vector2:
	return Vector2(w.x / S + origin2d.x, -w.y / S + origin2d.y)


func _ready() -> void:
	randomize()
	_build_visual_assets()
	_setup_environment()

	model = GridModel.new()
	model.width = columns
	model.num_colors = num_colors
	model.danger_row = danger_row
	model.rng.randomize()
	_build_test_board()

	sim.model = model
	sim.diameter = diameter
	sim.columns = columns
	sim.origin = origin2d
	sim.play_left = origin2d.x - diameter * 0.5
	sim.play_right = origin2d.x + (columns - 1) * diameter + diameter
	sim.play_bottom = 720.0

	board.setup(model, _mesh, _mats, _black_mat, diameter)

	shooter.position = to3d(muzzle2d)
	shooter.setup(_mesh, _mats, SPHERE_RADIUS)
	shooter.current_color = _rand_color()
	shooter.next_color = _rand_color()
	shooter.fired.connect(_on_fired)

	preview.mesh = _preview_mesh
	preview.material_override = _preview_mat

	_place_camera()
	_update_status()

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
	for col in BoardView.PALETTE:
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
	env.fog_light_color = Color(0.03, 0.03, 0.05)
	env.fog_density = 0.015
	world_env.environment = env
	light.rotation_degrees = Vector3(-50, -40, 0)
	light.light_energy = 1.3
	light.light_color = Color(0.92, 0.88, 0.98)
	light.shadow_enabled = true


func _place_camera() -> void:
	var top := to3d(Vector2(muzzle2d.x, origin2d.y))
	var bot := to3d(Vector2(muzzle2d.x, sim.play_bottom))
	var center := (top + bot) * 0.5
	camera.position = center + Vector3(0.0, 1.5, 15.5)
	camera.look_at(center + Vector3(0.0, -1.0, 0.0), Vector3.UP)
	camera.fov = 52.0


func _build_test_board() -> void:
	for r in range(5):
		for c in range(columns):
			model.cells[Vector2i(c, r)] = randi() % num_colors
	model.cells[Vector2i(5, 2)] = GridModel.BLACK
	model.cells[Vector2i(3, 3)] = GridModel.BLACK
	model.cells[Vector2i(7, 3)] = GridModel.BLACK


func _rand_color() -> int:
	return randi() % num_colors


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
	board.rebuild()
	_advance_load()
	shooter.enabled = true
	_check_end()
	_update_status()


func _on_missed() -> void:
	if _debug:
		print("[MISS] reshuffle; coloured=", model.count_colored())
	model.randomize_colors()
	board.rebuild()
	_advance_load()
	shooter.enabled = true
	_update_status()


func _advance_load() -> void:
	shooter.current_color = shooter.next_color
	shooter.next_color = _rand_color()
	shooter.refresh_colors()


# --- end state ----------------------------------------------------------------

func _check_end() -> void:
	if model.is_won():
		_end("THE FIELD IS STILL.\nYou survive.")
	elif model.is_lost():
		_end("THE SPHERES CONSUME YOU.")


func _end(msg: String) -> void:
	game_over = true
	shooter.enabled = false
	_preview_mesh.clear_surfaces()
	banner_label.text = msg
	banner_label.visible = true


func _update_status() -> void:
	status_label.text = "Coloured spheres: %d     [LMB] fire  —  match 3+ to clear, miss out the bottom to reshuffle  (3D)" % model.count_colored()


# --- dev autoplay -------------------------------------------------------------

func _auto_step() -> void:
	if game_over or not shooter.enabled:
		return
	var dirs := [Vector2(0, -1), Vector2(0.45, -1).normalized(), Vector2(-0.5, -1).normalized()]
	_aim2d = dirs[randi() % dirs.size()]
	_last_sim = sim.simulate(muzzle2d, _aim2d)
	_on_fired()
