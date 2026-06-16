class_name BoardView3D
extends Node3D

## 3D rendering of the sphere field — real SphereMesh instances placed on the
## board plane (XY, Z=0). A pure reflection of the GridModel, exactly like the 2D
## BoardView; only the presentation differs. Logical 2D cell positions are mapped
## to 3D via S (metres per logical pixel; one cell ≈ 1 m).

const S := 1.0 / 56.0

## Sphere colour palette (colour id -> hue). The controller builds one
## StandardMaterial3D per entry. Final spheres get engraved sigils (the
## colorblind cue) in M3.
# Must hold at least as many entries as the model's max colour count
# (LevelResource.validate allows num_colors up to 10), or higher ids would alias
# onto lower ones via `% _mats.size()`. Hues are chosen to stay distinguishable.
const PALETTE: Array[Color] = [
	Color("c0392b"),  # red
	Color("2ec24a"),  # green  — pulled toward pure green, brighter
	Color("1f5ea8"),  # blue   — deeper, more saturated
	Color("d4ac0d"),  # yellow
	Color("8e44ad"),  # purple
	Color("1ec3e0"),  # cyan   — lighter and bluer, no longer reads as green
	Color("d35400"),  # orange
	Color("e84393"),  # magenta — hot pink, distinct from red and purple
	Color("8d5a2b"),  # brown   — warm, low-chroma, distinct from orange
	Color("cfd8dc"),  # bone    — pale grey-white, the colourless sphere
]

# Animation tuning.
const SPAWN_TIME := 0.25   # grow-from-a-point duration for newly created spheres
const POP_TIME := 0.20     # expand-and-fade duration for cleared spheres
const POP_SCALE := 1.3     # how far a dying sphere swells before vanishing
const POP_STAGGER := 0.1   # extra delay per unit of hex distance from the pop origin

var model: GridModel
var diameter := 56.0
var _mesh: Mesh
var _mats: Array          # Array[StandardMaterial3D], indexed by colour id
var _black_mat: ShaderMaterial
var _spheres: Dictionary = {}   # Vector2i -> MeshInstance3D (live spheres only)


func setup(p_model: GridModel, p_mesh: Mesh, p_mats: Array, p_black: ShaderMaterial, p_diameter: float) -> void:
	model = p_model
	_mesh = p_mesh
	_mats = p_mats
	_black_mat = p_black
	diameter = p_diameter
	_build_all()


## Board-local 3D position of a cell (the node sits at the board origin).
func cell_local(cell: Vector2i) -> Vector3:
	var l := Hex.cell_to_world(cell, Vector2.ZERO, diameter)
	return Vector3(l.x * S, -l.y * S, 0.0)


## Initial field: every sphere created instantly at full size (no intro animation).
func _build_all() -> void:
	for cell in model.cells:
		_spawn(cell, model.cells[cell], true)


## Reconcile the view with the model after a field change, diffing against the
## spheres we already hold so we only touch what actually changed:
##   added     -> grow in (or appear instantly if listed in `instant_cells`)
##   recoloured-> swap material in place (no animation; happens on reshuffle)
##   removed   -> expand-and-fade pop
## `instant_cells` are cells that should appear full-size — e.g. the just-landed
## sphere, whose arrival the projectile already animated.
## When `pop_origin` is given (the cell the shot landed on), removed spheres pop in
## a ripple: each waits POP_STAGGER per unit of hex distance from that origin, so
## the cluster clears outward from the impact. Without it, all pops fire at once.
## Returns the time (seconds) until the last started animation finishes, so the
## controller can hold the end-of-level banner until the field has visually settled.
func sync(instant_cells: Array = [], pop_origin = null) -> float:
	var settle := 0.0
	# Added + recoloured.
	for cell in model.cells:
		var c: int = model.cells[cell]
		if not _spheres.has(cell):
			var instant: bool = cell in instant_cells
			_spawn(cell, c, instant)
			if not instant:
				settle = maxf(settle, SPAWN_TIME)
		elif int(_spheres[cell].get_meta("color")) != c:
			var mi: MeshInstance3D = _spheres[cell]
			mi.material_override = _mat_for(c)
			mi.set_meta("color", c)
	# Removed (collect first; we mutate _spheres while popping).
	var gone: Array = []
	for cell in _spheres:
		if not model.cells.has(cell):
			gone.append(cell)
	for cell in gone:
		var delay := 0.0
		if pop_origin != null:
			delay = Hex.distance(pop_origin, cell) * POP_STAGGER
		_pop(cell, delay)
		settle = maxf(settle, delay + POP_TIME)
	return settle


func _mat_for(color: int) -> Material:
	return _black_mat if color == GridModel.BLACK else _mats[color % _mats.size()]


func _make_sphere(color: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.material_override = _mat_for(color)
	mi.set_meta("color", color)
	return mi


## Create a sphere at `cell`. Unless `instant`, it grows from a point to full size
## over SPAWN_TIME with a slight overshoot.
func _spawn(cell: Vector2i, color: int, instant: bool) -> void:
	var mi := _make_sphere(color)
	mi.position = cell_local(cell)
	if not instant:
		mi.scale = Vector3.ZERO
	add_child(mi)
	_spheres[cell] = mi
	if instant:
		return
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, SPAWN_TIME) \
		.from(Vector3.ZERO).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Clear a sphere with an expand-and-fade pop, then free it. Removed from the
## tracking dict up front so a fast follow-up shot can refill the cell with a
## fresh instance (the dying one keeps animating independently). `delay` defers the
## start of the animation (the sphere sits full-size until its turn in the ripple).
func _pop(cell: Vector2i, delay := 0.0) -> void:
	var mi: MeshInstance3D = _spheres[cell]
	_spheres.erase(cell)
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(_play_pop.bind(mi))
	else:
		_play_pop(mi)


## Run the expand-and-fade on an already-detached sphere, then free it.
func _play_pop(mi: MeshInstance3D) -> void:
	if not is_instance_valid(mi):
		return
	# Sound is driven once per cluster by the controller (Sound.play_cluster_pop),
	# not per sphere — a big clear would otherwise machine-gun the pop sample.
	# Materials are shared across same-colour spheres; duplicate so fading this
	# one doesn't fade the others.
	var m := mi.material_override.duplicate() as StandardMaterial3D
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * POP_SCALE, POP_TIME).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, POP_TIME).set_ease(Tween.EASE_OUT)
	tw.finished.connect(mi.queue_free)
