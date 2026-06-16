class_name FrameView
extends Node3D

## The raised border around the play field. Left, right and top are solid obsidian
## bounce walls with ember veins crawling through them; the bottom is a distinct red
## miss-exit line (the ball falls out there — it does not bounce), whose material the
## DangerView pulses. Built once from world-space bounds. Lives directly under the
## controller, NOT under the board (which frees its children on every rebuild).

const FRAME_SHADER := preload("res://shaders/frame_veins.gdshader")
const DANGER_SHADER := preload("res://shaders/danger_line.gdshader")

var danger_line_mat: ShaderMaterial  # the bottom exit bar; DangerView drives its `phase`


## `bounds` = (left_x, right_x, top_y, bot_y) in world space; `thick`/`depth` are the
## bar cross-section and camera-ward depth in metres; `vein_color` tints the veins so
## the frame belongs to the same palette as the level's particles.
func build(bounds: Vector4, vein_color: Color, thick: float, depth: float) -> void:
	var left_x := bounds.x
	var right_x := bounds.y
	var top_y := bounds.z
	var bot_y := bounds.w
	var cx := (left_x + right_x) * 0.5
	var cy := (top_y + bot_y) * 0.5
	var span_x := right_x - left_x
	var span_y := top_y - bot_y
	var t := thick

	var wall_mat := ShaderMaterial.new()
	wall_mat.shader = FRAME_SHADER
	wall_mat.set_shader_parameter("vein_color", vein_color)

	danger_line_mat = ShaderMaterial.new()
	danger_line_mat.shader = DANGER_SHADER

	# Bars are placed so their inner face aligns with the bounce surface (offset
	# outward by half the bar thickness); side/top bars overlap at the corners.
	_add_bar(wall_mat, Vector3(t, span_y + t, depth), Vector3(left_x - t * 0.5, cy, 0.0))
	_add_bar(wall_mat, Vector3(t, span_y + t, depth), Vector3(right_x + t * 0.5, cy, 0.0))
	_add_bar(wall_mat, Vector3(span_x + t * 2.0, t, depth), Vector3(cx, top_y + t * 0.5, 0.0))
	_add_bar(
		danger_line_mat,
		Vector3(span_x + t * 2.0, t, depth * 0.6),
		Vector3(cx, bot_y - t * 0.5, 0.0)
	)


func _add_bar(mat: Material, size: Vector3, pos: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
