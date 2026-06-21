class_name NodeMarker
extends Area3D

## One glowing level point on the world map. A small sphere coloured by its unlock state
## (completed = dark green, available = orange + a wave pulse, locked = dim grey), pickable via
## the Area3D so a click opens its detail panel. Built fully in code (it's a runtime-spawned,
## data-driven thing): the marker owns its mesh, its state material, its pulse ring, and a fat
## click-collider. Reuses SphereAssets for the lacquered sphere look and DottedPath for the pulse.

signal clicked(id: int)

const S := WorldUnlock.State

const COL_COMPLETED := Color(0.10, 0.40, 0.14)  # dark green
const COL_AVAILABLE := Color(0.98, 0.46, 0.06)  # orange
const COL_LOCKED := Color(0.20, 0.20, 0.25)  # dim grey
const EMIT_COMPLETED := 1.3
const EMIT_AVAILABLE := 2.2  # throbs between PULSE_LO..PULSE_HI while available
const EMIT_LOCKED := 0.04

const PULSE_SPEED := 3.2  # rad/s, the danger_line CPU-phase idiom
const PULSE_LO := 1.5
const PULSE_HI := 2.8
const RING_SEGMENTS := 48
const RING_DOT := 0.22
const RING_GAP := 0.16
const STATE_TWEEN := 0.55  # completion transition: orange->green / grey->orange

var id: int = 0
var radius := 1.0
var _state: int = S.LOCKED
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _ring: MeshInstance3D
var _ring_mesh: ImmediateMesh
var _ring_mat: StandardMaterial3D
var _phase := 0.0


## node_id, where on the map (world space), its initial state, and the shared sphere assets
## (mesh + a base lacquered material to tint per state).
func setup(node_id: int, world_pos: Vector3, state: int, assets: SphereAssets) -> void:
	id = node_id
	position = world_pos
	monitoring = false
	monitorable = false
	input_ray_pickable = true

	_mat = assets.mats[0].duplicate()
	_mesh = MeshInstance3D.new()
	_mesh.mesh = assets.mesh
	radius = assets.mesh.radius
	_mesh.material_override = _mat
	add_child(_mesh)

	# A generous collider (1.5x the sphere) so the small markers are easy to click.
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius * 1.5
	col.shape = shape
	add_child(col)

	# The available-state wave pulse: a dotted ring that expands + fades each cycle.
	_ring_mesh = ImmediateMesh.new()
	_ring = MeshInstance3D.new()
	_ring.mesh = _ring_mesh
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_mat.albedo_color = Color(COL_AVAILABLE, 0.0)
	_ring.material_override = _ring_mat
	_ring.visible = false
	add_child(_ring)

	_apply_state(state)
	input_event.connect(_on_input_event)
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))


func _process(delta: float) -> void:
	if _state != S.AVAILABLE:
		return
	_phase = fmod(_phase + PULSE_SPEED * delta, TAU)
	_mat.emission_energy_multiplier = lerpf(PULSE_LO, PULSE_HI, 0.5 + 0.5 * sin(_phase))
	var frac := _phase / TAU
	var r := lerpf(radius * 1.1, radius * 2.6, frac)
	_ring_mat.albedo_color = Color(COL_AVAILABLE, (1.0 - frac) * 0.5)
	_ring_mesh.clear_surfaces()
	_ring_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	DottedPath.emit(
		_ring_mesh,
		DottedPath.ring_points(Vector2.ZERO, r, RING_SEGMENTS),
		RING_DOT,
		RING_GAP,
		_ring_map3d
	)
	_ring_mesh.surface_end()


## Change the marker's state. When `animate`, tween the albedo/emission (the completion
## transition the world map plays on return from a win); otherwise snap.
func set_state(state: int, animate: bool) -> void:
	if not animate:
		_apply_state(state)
		return
	var from_col := _mat.albedo_color
	var to_col := _color_for(state)
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(
		func(t: float) -> void: _mat.albedo_color = from_col.lerp(to_col, t), 0.0, 1.0, STATE_TWEEN
	)
	tw.parallel().tween_property(_mat, "emission_energy_multiplier", _emit_for(state), STATE_TWEEN)
	tw.tween_callback(func() -> void: _apply_state(state))


func _apply_state(state: int) -> void:
	_state = state
	var col := _color_for(state)
	_mat.albedo_color = col
	_mat.emission = col
	_mat.emission_energy_multiplier = _emit_for(state)
	_ring.visible = state == S.AVAILABLE
	if state != S.AVAILABLE:
		_ring_mesh.clear_surfaces()


func _color_for(state: int) -> Color:
	match state:
		S.COMPLETED:
			return COL_COMPLETED
		S.AVAILABLE:
			return COL_AVAILABLE
		_:
			return COL_LOCKED


func _emit_for(state: int) -> float:
	match state:
		S.COMPLETED:
			return EMIT_COMPLETED
		S.AVAILABLE:
			return EMIT_AVAILABLE
		_:
			return EMIT_LOCKED


func _ring_map3d(p: Vector2) -> Vector3:
	return Vector3(p.x, p.y, 0.0)


func _on_input_event(
	_cam: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape: int
) -> void:
	if _state == S.LOCKED:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		clicked.emit(id)
		get_viewport().set_input_as_handled()


func _on_hover(entered: bool) -> void:
	if _state == S.LOCKED:
		return
	var to := Vector3.ONE * (1.18 if entered else 1.0)
	create_tween().tween_property(_mesh, "scale", to, 0.12).set_trans(Tween.TRANS_QUAD)
