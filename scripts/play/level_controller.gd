class_name LevelController
extends Node2D

## Orchestrates the 2D level: owns the GridModel + ShotSimulator, configures its
## scene children (Board, Shooter, UI) declared in level.tscn, resolves landings
## through the model, and drives win/lose. Geometry comes from @export tunables
## plus the child node positions (Board = board origin, Shooter = muzzle).
##
## Shot outcomes:
##   - hits the cluster, forms a 3+ match -> destroy cluster, sweep orphans, fire again
##   - hits the cluster, no match (dud)    -> field grows (cellular fill)
##   - misses, exits the bottom            -> field colours reshuffle

const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")

@export var diameter := 56.0
@export var columns := 11
@export var num_colors := 5
@export var danger_row := 12

@onready var board: BoardView = $Board
@onready var shooter: Shooter = $Shooter
@onready var status_label: Label = $Ui/Status
@onready var banner_label: Label = $Ui/Banner

var model: GridModel
var sim := ShotSimulator.new()
var game_over := false
var _last_sim: Dictionary = {}
var _debug := false  # verbose event logging; enabled by SOP_AUTOPLAY


func _ready() -> void:
	randomize()
	var origin := board.global_position

	model = GridModel.new()
	model.width = columns
	model.num_colors = num_colors
	model.danger_row = danger_row
	model.rng.randomize()
	_build_test_board()

	sim.model = model
	sim.diameter = diameter
	sim.columns = columns
	sim.origin = origin
	sim.play_left = origin.x - diameter * 0.5
	sim.play_right = origin.x + (columns - 1) * diameter + diameter
	sim.play_bottom = get_viewport_rect().size.y

	board.setup(model, diameter, num_colors, columns, danger_row)

	shooter.diameter = diameter
	shooter.palette = BoardView.PALETTE
	shooter.current_color = _rand_color()
	shooter.next_color = _rand_color()
	shooter.fired.connect(_on_fired)

	_update_status()

	# Dev-only self-driver: set SOP_AUTOPLAY=1 to fire scripted shots on a timer,
	# so the pipeline can be verified from stdout without OS mouse injection.
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
	_last_sim = sim.simulate(shooter.global_position, shooter.aim_dir)
	shooter.preview_path = _last_sim.path


# --- setup helpers ------------------------------------------------------------

func _build_test_board() -> void:
	for r in range(5):
		for c in range(columns):
			model.cells[Vector2i(c, r)] = randi() % num_colors
	# A few unbreakable obstacles to exercise black-sphere handling.
	model.cells[Vector2i(5, 2)] = GridModel.BLACK
	model.cells[Vector2i(3, 3)] = GridModel.BLACK
	model.cells[Vector2i(7, 3)] = GridModel.BLACK


func _rand_color() -> int:
	return randi() % num_colors


# --- shot results -------------------------------------------------------------

func _on_fired(_dir: Vector2) -> void:
	if game_over or not _last_sim.has("path"):
		return
	var is_miss: bool = _last_sim.get("miss", false)
	if _debug:
		print("[FIRE] color=", shooter.current_color, " -> ", "MISS" if is_miss else _last_sim.cell)
	shooter.enabled = false
	var proj := PROJECTILE_SCENE.instantiate() as Projectile
	proj.path = _last_sim.path
	proj.miss = is_miss
	if not is_miss:
		proj.cell = _last_sim.cell
	proj.color = shooter.current_color
	proj.diameter = diameter
	proj.palette = BoardView.PALETTE
	proj.landed.connect(_on_landed)
	proj.missed.connect(_on_missed)
	add_child(proj)


func _on_landed(cell: Vector2i, color: int) -> void:
	var res := model.attach(cell, color)
	if _debug:
		print("[LAND] cell=", cell, " pop=", res.did_pop, " popped=", res.popped.size(),
			" orphaned=", res.orphaned.size(), " coloured=", model.count_colored())
	for c in res.popped:
		board.add_pop(c)
	for c in res.orphaned:
		board.add_pop(c)
	if not res.did_pop:
		model.grow()
	board.queue_redraw()
	_advance_load()
	shooter.enabled = true
	_check_end()
	_update_status()


func _on_missed() -> void:
	if _debug:
		print("[MISS] reshuffle; coloured=", model.count_colored())
	model.randomize_colors()
	board.queue_redraw()
	_advance_load()
	shooter.enabled = true
	_update_status()


func _advance_load() -> void:
	shooter.current_color = shooter.next_color
	shooter.next_color = _rand_color()


# --- end state ----------------------------------------------------------------

func _check_end() -> void:
	if model.is_won():
		_end("THE FIELD IS STILL.\nYou survive.")
	elif model.is_lost():
		_end("THE SPHERES CONSUME YOU.")


func _end(msg: String) -> void:
	game_over = true
	shooter.enabled = false
	shooter.preview_path = PackedVector2Array()
	banner_label.text = msg
	banner_label.visible = true


func _update_status() -> void:
	status_label.text = "Coloured spheres: %d     [LMB] fire  —  match 3+ to clear, miss out the bottom to reshuffle" % model.count_colored()


# --- dev autoplay -------------------------------------------------------------

func _auto_step() -> void:
	if game_over or not shooter.enabled:
		return
	var dirs := [Vector2(0, -1), Vector2(0.45, -1).normalized(), Vector2(-0.5, -1).normalized()]
	var dir: Vector2 = dirs[randi() % dirs.size()]
	shooter.aim_dir = dir
	_last_sim = sim.simulate(shooter.global_position, dir)
	_on_fired(dir)
