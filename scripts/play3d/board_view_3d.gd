class_name BoardView3D
extends Node3D

## 3D rendering of the sphere field — real SphereMesh instances placed on the
## board plane (XY, Z=0). A pure reflection of the GridModel, exactly like the 2D
## BoardView; only the presentation differs. Logical 2D cell positions are mapped
## to 3D via S (metres per logical pixel; one cell ≈ 1 m).

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
const SPAWN_TIME := 0.25  # grow-from-a-point duration for newly created spheres
const POP_TIME := 0.20  # expand-and-fade duration for cleared spheres
# A dying sphere swells as it fades, but unevenly — wider than it is tall — so the pop reads
# as a heavy collapse, not a clean balloon (E2.5's "deform little, settle slowly").
const POP_SQUASH := Vector3(1.4, 1.12, 1.4)
const POP_STAGGER := 0.1  # extra delay per unit of hex distance from the pop origin
# Emission flash on pop (E2.5): a dim blood-red glow from WITHIN as the soul is unmade —
# more sinister than albedo. Instant rise, slow ebb across the pop; gated by fx_intensity.
const POP_FLASH_COLOR := Color(0.7, 0.04, 0.05)
const POP_FLASH_ENERGY := 1.6  # peaks above the glow threshold (1.0) so it blooms briefly

# Spin rotation: spheres shrink, slide one slot anti-clockwise, then grow back.
const SPIN_SHRINK_TIME := 0.10  # contract before the slide
const SPIN_MOVE_TIME := 0.15  # glide to the next anti-clockwise cell
const SPIN_GROW_TIME := 0.10  # settle back to full size
const SPIN_SHRINK_SCALE := 0.8  # how small a sphere pulls in while travelling

var model: GridModel
var diameter := 56.0
var _s := 1.0 / 56.0  # metres per logical pixel = 1/diameter; set in setup()
var _mesh: Mesh
var _mats: Array  # Array[StandardMaterial3D], indexed by colour id
var _specials: Dictionary  # indestructible sentinel (< 0) -> Material
var _spheres: Dictionary = {}  # Vector2i -> MeshInstance3D (live spheres only)


## Store the model + shared assets and (by default) build the whole field at once. Pass
## `p_build = false` to skip the immediate build and drive it in time-sliced chunks via
## build_async() instead — the play scene does this so a large field never freezes the
## window; the editor uses the default synchronous build for its small authored boards.
func setup(
	p_model: GridModel,
	p_mesh: Mesh,
	p_mats: Array,
	p_specials: Dictionary,
	p_diameter: float,
	p_build := true
) -> void:
	model = p_model
	_mesh = p_mesh
	_mats = p_mats
	_specials = p_specials
	diameter = p_diameter
	_s = 1.0 / p_diameter  # world scale follows the configured sphere size
	if p_build:
		_build_all()


## Board-local 3D position of a cell (the node sits at the board origin).
func cell_local(cell: Vector2i) -> Vector3:
	var l := Hex.cell_to_world(cell, Vector2.ZERO, diameter)
	return Vector3(l.x * _s, -l.y * _s, 0.0)


## Initial field: every sphere created instantly at full size (no intro animation).
func _build_all() -> void:
	for cell in model.cells:
		_spawn(cell, model.cells[cell], true)


## Time-sliced version of _build_all: spawn the field in chunks of `chunk_size` spheres,
## yielding a frame between chunks so building a large board (up to ~2500 nodes) never
## blocks the main thread. `on_progress` (a Callable taking done:int, total:int) is invoked
## after each chunk so a loading bar can track the build. Awaitable — completes once every
## sphere exists. Creating many MeshInstance3D + add_child must stay on the main thread
## (the scene tree isn't thread-safe), so this cooperatively spreads the work, it doesn't
## thread it.
func build_async(chunk_size: int, on_progress: Callable) -> void:
	var tree := get_tree()  # cached so a scene change mid-build can't null-deref get_tree()
	var cells := model.cells.keys()
	var total := cells.size()
	var done := 0
	for cell in cells:
		_spawn(cell, model.cells[cell], true)
		done += 1
		if done % chunk_size == 0:
			if on_progress.is_valid():
				on_progress.call(done, total)
			await tree.process_frame
			if not is_inside_tree():
				return  # the level was left mid-build; stop touching the tree
	if on_progress.is_valid():
		on_progress.call(total, total)


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


## Physically animate a spin rotation: each move relocates the existing sphere node
## from its `from` cell to its `to` cell (no recolour — the colour travels with the
## node). The moves form a permutation of the participating cells, so the spheres are
## re-keyed in two passes (erase every source key, then insert every destination key)
## before animating — a single in-place pass would clobber a node whose destination is
## another move's source. Each node then runs a shrink -> slide -> grow tween. Returns
## the settle time (seconds) so the controller can hold firing until the field rests.
func animate_spin(moves: Array) -> float:
	if moves.is_empty():
		return 0.0
	# Pass 1: snapshot the live nodes by their source cell before touching _spheres.
	var hops: Array = []  # [{node: MeshInstance3D, to: Vector2i}]
	for move in moves:
		var from: Vector2i = move["from"]
		if not _spheres.has(from):
			continue  # defensive: model/view drift — skip rather than crash
		hops.append({"node": _spheres[from], "to": move["to"]})
	if hops.is_empty():
		return 0.0
	# Pass 2: re-key. Erase all sources first, then place every node at its destination.
	for move in moves:
		_spheres.erase(move["from"])
	for hop in hops:
		_spheres[hop["to"]] = hop["node"]
	# Pass 3: shrink -> slide -> grow on each node (independent tweens, same frame).
	for hop in hops:
		var mi: MeshInstance3D = hop["node"]
		var tw := mi.create_tween()
		(
			tw
			. tween_property(mi, "scale", Vector3.ONE * SPIN_SHRINK_SCALE, SPIN_SHRINK_TIME)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_IN)
		)
		(
			tw
			. tween_property(mi, "position", cell_local(hop["to"]), SPIN_MOVE_TIME)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_IN_OUT)
		)
		(
			tw
			. tween_property(mi, "scale", Vector3.ONE, SPIN_GROW_TIME)
			. set_trans(Tween.TRANS_BACK)
			. set_ease(Tween.EASE_OUT)
		)
	return SPIN_SHRINK_TIME + SPIN_MOVE_TIME + SPIN_GROW_TIME


## Single source of truth for the colour -> material map, shared by the board, the
## projectile, and the muzzle so they can never drift. Any indestructible sentinel
## (< 0: BLACK/SPIN/BOUNCE) looks its material up in `specials`; any breakable id
## wraps into the palette materials.
static func mat_for(mats: Array, specials: Dictionary, color: int) -> Material:
	return specials[color] if color < 0 else mats[color % mats.size()]


func _mat_for(color: int) -> Material:
	return BoardView3D.mat_for(_mats, _specials, color)


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
	(
		tw
		. tween_property(mi, "scale", Vector3.ONE, SPAWN_TIME)
		. from(Vector3.ZERO)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)


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
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", POP_SQUASH, POP_TIME).set_ease(Tween.EASE_OUT)
	# Alpha fade needs a per-instance StandardMaterial3D (shared across same-colour
	# spheres, so duplicate it). Black/obstacle spheres carry a ShaderMaterial, not a
	# StandardMaterial3D — only breakables pop today, but guard the cast so a future
	# rule that pops one can't null-deref; it just scales out without the fade.
	var m := mi.material_override.duplicate() as StandardMaterial3D
	if m != null:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = m
		tw.tween_property(m, "albedo_color:a", 0.0, POP_TIME).set_ease(Tween.EASE_OUT)
		# Glow from within as the soul is unmade: spike emission to a dim blood-red, then ebb
		# it fast-out across the pop (a quick flare with a lingering tail). Skipped at fx 0.
		var fx := Settings.fx_intensity()
		if fx > 0.0:
			m.emission = POP_FLASH_COLOR
			m.emission_energy_multiplier = POP_FLASH_ENERGY * fx
			(
				tw
				. tween_property(m, "emission_energy_multiplier", 0.0, POP_TIME)
				. set_trans(Tween.TRANS_EXPO)
				. set_ease(Tween.EASE_OUT)
			)
	tw.finished.connect(mi.queue_free)
