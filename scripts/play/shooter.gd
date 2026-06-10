class_name Shooter
extends Node2D

## Aiming + firing. This node is placed at the muzzle in the scene, so it draws
## in local coordinates (loaded sphere at the origin). It tracks the mouse to aim
## (clamped to the upward hemisphere), draws the loaded/next sphere and a dotted
## trajectory preview, and emits `fired` / `dropped`. The preview path is supplied
## by the LevelController in world space so it exactly matches where the shot will
## land (fair, readable — pillar 3).

signal fired(direction: Vector2)

var aim_dir := Vector2(0, -1)
var current_color := 0
var next_color := 1
var preview_path := PackedVector2Array()   # world-space points from the controller
var diameter := 56.0
var palette: Array[Color] = []
var enabled := true


func _process(_delta: float) -> void:
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length() < 1.0:
		to_mouse = Vector2(0, -1)
	var d := to_mouse.normalized()
	if d.y > -0.12:           # never aim sideways/down
		d.y = -0.12
		d = d.normalized()
	aim_dir = d
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event.is_action_pressed("fire"):
		fired.emit(aim_dir)


func _draw() -> void:
	var r := diameter * 0.5

	# Dotted trajectory preview (world points -> local for drawing).
	if enabled and preview_path.size() >= 2:
		for i in range(preview_path.size() - 1):
			_draw_dotted(to_local(preview_path[i]), to_local(preview_path[i + 1]))

	# Loaded sphere at the muzzle (local origin).
	draw_circle(Vector2.ZERO, r - 2.0, _col(current_color))
	draw_arc(Vector2.ZERO, r - 2.0, 0.0, TAU, 24, Color(0, 0, 0, 0.55), 2.0)

	# Next sphere, smaller, to the side.
	var np := Vector2(r + 18.0, 6.0)
	draw_circle(np, r * 0.5, _col(next_color))
	draw_arc(np, r * 0.5, 0.0, TAU, 18, Color(0, 0, 0, 0.5), 1.5)


func _col(i: int) -> Color:
	if palette.is_empty():
		return Color.WHITE
	return palette[i % palette.size()]


func _draw_dotted(a: Vector2, b: Vector2) -> void:
	var dist := a.distance_to(b)
	var dir := (b - a).normalized()
	var t := 0.0
	while t < dist:
		var p1 := a + dir * t
		var p2 := a + dir * minf(t + 6.0, dist)
		draw_line(p1, p2, Color(0.9, 0.85, 0.85, 0.45), 2.0)
		t += 14.0
