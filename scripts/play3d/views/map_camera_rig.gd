class_name MapCameraRig
extends Node

## Drives the world map's bird's-eye ORTHOGRAPHIC camera: drag to pan, wheel to zoom (toward the
## cursor), clamped to the map bounds. Orthographic keeps node spacing + road lengths uniform
## across the screen and makes screen->world a single constant, so panning and bounds are exact.
## A click that hits a node marker is consumed by the marker (Area3D), so a non-dragging press is
## left for the markers and only a moving press pans — they never fight.

signal panned

const CAM_Z := 40.0  # camera height above the Z=0 map plane (it looks straight down -Z)
const ZOOM_MIN := 14.0
const ZOOM_MAX := 120.0
const ZOOM_STEP := 1.12
const DRAG_THRESHOLD := 6.0  # px of motion before a press becomes a pan (vs a click)
const FOCUS_ZOOM := 26.0  # tight zoom when a node is selected
const FOCUS_TIME := 0.6

var _camera: Camera3D
var _bounds: Rect2
var _zoom := 60.0
var _center := Vector2.ZERO
var _dragging := false
var _drag_dist := 0.0
var _focused := false  # while a node detail panel is open: no pan/zoom, no bounds clamp
var _overview_zoom := 60.0
var _overview_center := Vector2.ZERO


func setup(camera: Camera3D, bounds: Rect2, start_center: Vector2, start_zoom: float) -> void:
	_camera = camera
	_bounds = bounds
	_zoom = clampf(start_zoom, ZOOM_MIN, ZOOM_MAX)
	_center = start_center
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.rotation = Vector3.ZERO
	_camera.near = 0.1
	_camera.far = CAM_Z * 2.0 + 10.0
	_clamp_center()
	_apply()


func world_center() -> Vector2:
	return _center


func consumed_drag() -> bool:
	return _drag_dist >= DRAG_THRESHOLD


func _unhandled_input(event: InputEvent) -> void:
	if _camera == null or _focused:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 1.0 / ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			if event.pressed:
				_drag_dist = 0.0
	elif event is InputEventMouseMotion and _dragging:
		_drag_dist += event.relative.length()
		if _drag_dist >= DRAG_THRESHOLD:
			_pan_by_screen_delta(event.relative)


# --- camera math --------------------------------------------------------------


func _world_per_px() -> float:
	var vp := get_viewport().get_visible_rect().size
	return _zoom / maxf(1.0, vp.y)


func _pan_by_screen_delta(px: Vector2) -> void:
	var wpp := _world_per_px()
	# Grab-and-drag: content follows the cursor, so the camera centre moves opposite on x and
	# (because screen-down is world-down here) with the drag on y.
	_center.x -= px.x * wpp
	_center.y += px.y * wpp
	_clamp_center()
	_apply()
	panned.emit()


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := _camera.project_position(screen_pos, CAM_Z)
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	_apply()
	var after := _camera.project_position(screen_pos, CAM_Z)
	_center += Vector2(before.x - after.x, before.y - after.y)
	_clamp_center()
	_apply()
	panned.emit()


func _aspect() -> float:
	var vp := get_viewport().get_visible_rect().size
	return vp.x / maxf(1.0, vp.y)


func _clamp_center() -> void:
	if _focused:
		return
	var half_h := _zoom * 0.5
	var half_w := half_h * _aspect()
	var b := _bounds
	if b.size.x <= 2.0 * half_w:
		_center.x = b.position.x + b.size.x * 0.5
	else:
		_center.x = clampf(_center.x, b.position.x + half_w, b.end.x - half_w)
	if b.size.y <= 2.0 * half_h:
		_center.y = b.position.y + b.size.y * 0.5
	else:
		_center.y = clampf(_center.y, b.position.y + half_h, b.end.y - half_h)


func _apply() -> void:
	_camera.size = _zoom
	_camera.position = Vector3(_center.x, _center.y, CAM_Z)


# --- focus (click a node -> frame it on the LEFT half) ------------------------


## Zoom in and bias the centre so `node_world` sits ~25% from the left edge, leaving the right
## half clear for the detail panel. Caches the overview so unfocus() can return there.
func focus_left(node_world: Vector3) -> void:
	_overview_zoom = _zoom
	_overview_center = _center
	_focused = true
	var half_w := FOCUS_ZOOM * 0.5 * _aspect()
	var target := Vector2(node_world.x + 0.5 * half_w, node_world.y)
	_tween_to(target, FOCUS_ZOOM)


func unfocus() -> void:
	_tween_to(_overview_center, _overview_zoom)
	# Re-enable pan/zoom once the camera is back (after the tween).
	get_tree().create_timer(FOCUS_TIME).timeout.connect(func() -> void: _focused = false)


## Ease the camera to center on a node (used by the completion transition) without opening a panel.
func ease_to(node_world: Vector3) -> void:
	_tween_to(Vector2(node_world.x, node_world.y), _zoom)


func _tween_to(center: Vector2, zoom: float) -> void:
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)
	tw.tween_method(_set_zoom, _zoom, zoom, FOCUS_TIME)
	tw.tween_method(_set_center, _center, center, FOCUS_TIME)


func _set_zoom(z: float) -> void:
	_zoom = z
	_apply()


func _set_center(c: Vector2) -> void:
	_center = c
	_apply()
	panned.emit()
