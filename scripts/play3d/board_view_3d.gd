class_name BoardView3D
extends Node3D

## 3D rendering of the sphere field — real SphereMesh instances placed on the
## board plane (XY, Z=0). A pure reflection of the GridModel, exactly like the 2D
## BoardView; only the presentation differs. Logical 2D cell positions are mapped
## to 3D via S (metres per logical pixel; one cell ≈ 1 m).

const S := 1.0 / 56.0

var model: GridModel
var diameter := 56.0
var _mesh: Mesh
var _mats: Array          # Array[StandardMaterial3D], indexed by colour id
var _black_mat: StandardMaterial3D


func setup(p_model: GridModel, p_mesh: Mesh, p_mats: Array, p_black: StandardMaterial3D, p_diameter: float) -> void:
	model = p_model
	_mesh = p_mesh
	_mats = p_mats
	_black_mat = p_black
	diameter = p_diameter
	rebuild()


## Board-local 3D position of a cell (the node sits at the board origin).
func cell_local(cell: Vector2i) -> Vector3:
	var l := Hex.cell_to_world(cell, Vector2.ZERO, diameter)
	return Vector3(l.x * S, -l.y * S, 0.0)


## Rebuild all sphere instances from the model. Called after every field change.
## The cluster is ~50-150 spheres, so a full rebuild per shot is cheap.
func rebuild() -> void:
	for child in get_children():
		child.free()
	for cell in model.cells:
		var c: int = model.cells[cell]
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh
		mi.material_override = _black_mat if c == GridModel.BLACK else _mats[c % _mats.size()]
		mi.position = cell_local(cell)
		add_child(mi)
