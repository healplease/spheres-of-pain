class_name AimView
extends Node3D

## The trajectory preview: a dotted ray from the muzzle, tinted to the loaded sphere's colour,
## ending in a dotted ring at the predicted landing cell (or dotted all the way out on a miss).
## Owns the aim direction and the ray's visibility; the controller owns the simulation and feeds
## results in via draw(). See [[DottedPath]] for the dot walk.

signal ray_revealed  ## emitted whenever the ray ends up shown, so the controller re-simulates

# DOT and GAP are in logical pixels (the simulated path's own space) so they scale naturally with
# perspective. ALPHA is the dot opacity. Restyle the ray by tweaking these.
const PREVIEW_DOT := 6.0
const PREVIEW_GAP := 9.0
const PREVIEW_ALPHA := 0.85
# On a hit, the resting place gets a dotted ring instead of the final snap segment; radius is a
# multiple of the sphere radius (1.0 = bubble-sized).
const PREVIEW_LAND_SCALE := 1.0
const PREVIEW_RING_SEGMENTS := 48

var aim2d := Vector2(0, -1)  ## current aim direction (logical space); the controller reads this
var aim_ray_enabled := false  ## master "Enable aim" toggle ([A] flips it); read for logging

var _aim_active := true  # Click: always; Hold: only while the fire button is held
var _live := true  # cleared at game over so the ray can never reappear
var _preview: MeshInstance3D
var _preview_mat: StandardMaterial3D
var _camera: Camera3D
var _muzzle2d: Vector2
var _to3d: Callable
var _to2d: Callable
var _land_radius := 0.0  # landing-ring radius (logical px)
var _preview_mesh := ImmediateMesh.new()


func setup(
	preview_node: MeshInstance3D,
	camera: Camera3D,
	muzzle2d: Vector2,
	to3d: Callable,
	to2d: Callable,
	preview_mat: StandardMaterial3D,
	sphere_radius_logical: float,
	enabled: bool,
	hold_to_fire: bool
) -> void:
	_preview = preview_node
	_camera = camera
	_muzzle2d = muzzle2d
	_to3d = to3d
	_to2d = to2d
	_preview_mat = preview_mat
	_land_radius = sphere_radius_logical * PREVIEW_LAND_SCALE
	_preview.mesh = _preview_mesh
	_preview.material_override = _preview_mat
	aim_ray_enabled = enabled
	_aim_active = not hold_to_fire  # always-on in Click; off until a press in Hold
	_update_visibility()


## Cast the mouse ray onto the board plane (Z=0) and aim from the muzzle to it.
func update_aim() -> void:
	var mouse := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse)
	var dir := _camera.project_ray_normal(mouse)
	if absf(dir.z) < 0.00001:
		return
	var t := -from.z / dir.z
	if t <= 0.0:
		return
	var hit := from + dir * t
	var hit2d: Vector2 = _to2d.call(hit)
	var d := hit2d - _muzzle2d
	if d.length() < 1.0:
		return
	var a := d.normalized()
	if a.y > -0.12:  # never aim sideways/down
		a.y = -0.12
		a = a.normalized()
	aim2d = a


## Autoplay sets a canned direction directly (no mouse).
func set_aim(dir: Vector2) -> void:
	aim2d = dir


## Whether the ray is currently shown; the controller skips the mesh rebuild while it's hidden
## (e.g. in Hold between aims).
func ray_visible() -> bool:
	return _preview.visible


## Rebuild the ray mesh from a fresh simulation result, tinted to `color`.
func draw(sim_result: Dictionary, color: int) -> void:
	_preview_mesh.clear_surfaces()
	var path2d: PackedVector2Array = sim_result.get("path", PackedVector2Array())
	if path2d.size() < 2:
		return
	_preview_mat.albedo_color = _preview_color(color)
	_preview_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	if sim_result.get("miss", false):
		# A miss never settles — dot the whole flight out through the bottom.
		DottedPath.emit(_preview_mesh, path2d, PREVIEW_DOT, PREVIEW_GAP, _to3d)
	else:
		# A hit's path ends with the snap into the grid cell: drop that final bend and mark the
		# resting place with a dotted ring instead, so the preview reads as "it lands *here*".
		var flight := path2d.slice(0, path2d.size() - 1)
		DottedPath.emit(_preview_mesh, flight, PREVIEW_DOT, PREVIEW_GAP, _to3d)
		var ring := DottedPath.ring_points(
			path2d[path2d.size() - 1], _land_radius, PREVIEW_RING_SEGMENTS
		)
		DottedPath.emit(_preview_mesh, ring, PREVIEW_DOT, PREVIEW_GAP, _to3d)
	_preview_mesh.surface_end()


## Hold scheme: the fire button went down (active) or up (inactive). Shows the ray only for the
## duration of an aim. Connected to Shooter3D.aim_active_changed; not emitted in Click mode.
func set_active(active: bool) -> void:
	_aim_active = active
	_update_visibility()


## [A] toggles the master aim setting in-session.
func toggle_enabled() -> void:
	aim_ray_enabled = not aim_ray_enabled
	_update_visibility()


## Cut the ray at once (game over), even if a finger is still down in Hold, and keep it down.
func hide_ray() -> void:
	_live = false
	_preview_mesh.clear_surfaces()
	_update_visibility()


## The ray's colour: the loaded sphere's palette colour lifted toward white so the darker,
## saturated colours still read against the abyss, at the fixed dot opacity.
func _preview_color(color: int) -> Color:
	var pal := BoardView3D.PALETTE
	var c: Color = pal[color % pal.size()]
	c = c.lerp(Color.WHITE, 0.25)
	c.a = PREVIEW_ALPHA
	return c


## The single source of truth for ray visibility: master enabled AND an active aim AND still
## live. Emits ray_revealed whenever it ends up shown so the controller refreshes the trajectory.
func _update_visibility() -> void:
	_preview.visible = aim_ray_enabled and _aim_active and _live
	if _preview.visible:
		ray_revealed.emit()
