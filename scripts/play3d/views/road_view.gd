class_name RoadView
extends Node3D

## The dotted roads between world-map nodes. Built from the graph's successor edges via DottedPath
## into a few child ImmediateMeshes, one per visual style (since a dotted surface carries no
## per-dot colour): spine roads read bright, optional branches dimmer, and roads out of a not-yet-
## cleared node stay a faint grey until that node is completed. Rebuilt whenever node states change.

const Z_LIFT := 0.04  # float the roads just in front of the map plane
const SPINE_DOT := 0.5
const SPINE_GAP := 0.32
const BRANCH_DOT := 0.34
const BRANCH_GAP := 0.46

const COL_SPINE := Color(0.92, 0.84, 0.72)  # warm bone — the main path, traversed/open
const COL_BRANCH := Color(0.62, 0.55, 0.62)  # dimmer side-path
const COL_LOCKED := Color(0.26, 0.26, 0.31, 0.7)  # not yet earned

var _graph: WorldGraphResource
var _to3d: Callable
var _spine: MeshInstance3D
var _branch: MeshInstance3D
var _locked: MeshInstance3D


func setup(graph: WorldGraphResource, to3d: Callable) -> void:
	_graph = graph
	_to3d = to3d
	_spine = _make_layer(COL_SPINE)
	_branch = _make_layer(COL_BRANCH)
	_locked = _make_layer(COL_LOCKED)


## Rebuild every road from the current id -> WorldUnlock.State map. A road is "open" (styled spine
## or branch) once its SOURCE node is completed; otherwise it reads locked-grey. The first
## successor of a node is its spine road, the rest are branches. Segments are grouped by layer
## first, so a layer with no edges (e.g. all spine roads still locked on a fresh save) is left
## empty rather than getting an empty ImmediateMesh surface (which the engine rejects).
func rebuild(states: Dictionary) -> void:
	var jobs := {_spine: [], _branch: [], _locked: []}  # layer -> Array of [pts, dot, gap]
	for n in _graph.nodes:
		var open: bool = states.get(n.id, WorldUnlock.State.LOCKED) == WorldUnlock.State.COMPLETED
		for i in range(n.successors.size()):
			var dst := _graph.node(n.successors[i])
			if dst == null:
				continue
			var spine := i == 0
			var layer := _locked
			var dot := BRANCH_DOT
			var gap := BRANCH_GAP
			if open:
				layer = _spine if spine else _branch
				dot = SPINE_DOT if spine else BRANCH_DOT
				gap = SPINE_GAP if spine else BRANCH_GAP
			# Walk the segment in WORLD/metre space (small magnitudes) so the dot/gap sizes are
			# metres and the emitter's step never falls below the float ULP (see DottedPath).
			var a := _to3d.call(n.map_position) as Vector3
			var b := _to3d.call(dst.map_position) as Vector3
			var pts := PackedVector2Array([Vector2(a.x, a.y), Vector2(b.x, b.y)])
			jobs[layer].append([pts, dot, gap])
	for layer in [_spine, _branch, _locked]:
		var mesh := layer.mesh as ImmediateMesh
		mesh.clear_surfaces()
		var list: Array = jobs[layer]
		if list.is_empty():
			continue
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for job in list:
			DottedPath.emit(mesh, job[0], job[1], job[2], _flat, Z_LIFT)
		mesh.surface_end()


## Maps an already-world-space 2D point straight to 3D (the road points are pre-converted to
## metres, so no further scaling — just drop onto the Z=0 plane; emit adds the z_lift).
func _flat(p: Vector2) -> Vector3:
	return Vector3(p.x, p.y, 0.0)


func _make_layer(col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	mi.material_override = mat
	add_child(mi)
	return mi
