class_name Shooter3D
extends Node3D

## 3D shooter: shows the loaded + next sphere meshes at the muzzle and emits
## `fired` on the fire action. Aim/trajectory is computed by LevelController3D
## (it owns the camera and the shot simulation), so this node is presentation +
## input only — mirroring the 2D Shooter.

signal fired

var enabled := true
var current_color := 0
var next_color := 1

var _mesh: Mesh
var _mats: Array          # Array[StandardMaterial3D]
var _loaded: MeshInstance3D
var _next: MeshInstance3D


func setup(p_mesh: Mesh, p_mats: Array, radius: float) -> void:
	_mesh = p_mesh
	_mats = p_mats
	_loaded = MeshInstance3D.new()
	_loaded.mesh = _mesh
	add_child(_loaded)
	_next = MeshInstance3D.new()
	_next.mesh = _mesh
	_next.scale = Vector3.ONE * 0.6
	_next.position = Vector3(radius * 2.4, 0.0, 0.0)
	add_child(_next)
	refresh_colors()


func refresh_colors() -> void:
	if _loaded:
		_loaded.material_override = _mats[current_color % _mats.size()]
	if _next:
		_next.material_override = _mats[next_color % _mats.size()]


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event.is_action_pressed("fire"):
		fired.emit()
