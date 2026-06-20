class_name Projectile3D
extends Node3D

## A fired sphere in 3D, animated along the pre-computed world-space path (the
## 2D shot path mapped onto the board plane by LevelController3D). Cosmetic — it
## emits `landed`/`missed` with the already-known result on arrival.

signal landed(cell: Vector2i, color: int)
signal missed

var path: Array[Vector3] = []
var cell := Vector2i.ZERO
var color := 0
var miss := false
var speed := 18.0  # m/s

var _i := 0


func setup(mesh: Mesh, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)


func _ready() -> void:
	if path.size() > 0:
		global_position = path[0]


func _physics_process(delta: float) -> void:
	if _i >= path.size() - 1:
		if miss:
			missed.emit()
		else:
			landed.emit(cell, color)
		queue_free()
		return
	var target := path[_i + 1]
	var to := target - global_position
	var move := speed * delta
	if move >= to.length():
		global_position = target
		_i += 1
	else:
		global_position += to.normalized() * move
