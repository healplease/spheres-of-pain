class_name Projectile
extends Node2D

## A fired sphere, animated along the pre-computed world-space path from the
## LevelController. Because the path (and its final cell) were already simulated
## for the aim preview, the projectile is purely cosmetic — it emits `landed`
## with the known cell when it arrives. Instanced from projectile.tscn at runtime.

signal landed(cell: Vector2i, color: int)
signal missed

var path := PackedVector2Array()
var cell := Vector2i.ZERO
var color := 0
var miss := false
var diameter := 56.0
var palette: Array[Color] = []
var speed := 1200.0

var _i := 0


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


func _draw() -> void:
	var r := diameter * 0.5
	var c: Color = palette[color % palette.size()] if not palette.is_empty() else Color.WHITE
	draw_circle(Vector2.ZERO, r - 2.0, c)
	draw_arc(Vector2.ZERO, r - 2.0, 0.0, TAU, 24, Color(0, 0, 0, 0.55), 2.0)
