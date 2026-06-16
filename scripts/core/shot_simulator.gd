class_name ShotSimulator
extends RefCounted

## Pure-logic ball-flight simulation on the logical 2D play plane. No nodes, no
## rendering — shared by the 2D and 3D presentations: both run the SAME sim and
## map the resulting path into their own space (2D uses it directly; 3D maps each
## point onto the board plane). This keeps aim, wall bounces, and snapping
## identical across dimensions.
##
## Walls: top (row 0 line) and sides reflect; the bottom is the miss-exit.
## Returns {path: PackedVector2Array, cell: Vector2i, miss: false} for a hit, or
## {path, miss: true} for a shot that exits the bottom without attaching.

## How close (as a fraction of the cell spacing `diameter`) the moving sphere's
## centre must come to a settled sphere's centre to count as a hit. At 0.92 the two
## rendered spheres just touch (radius 0.46·diameter each); using less than that
## gives the *moving* sphere a smaller hitbox than it looks, so a precise shot can
## be threaded through a narrow gap between two field spheres — a skill play. Kept
## above ~0.5 so a shot can't pass straight through two touching spheres. Both the
## aim preview and the live shot run this same simulate(), so they stay identical.
const HIT_DISTANCE_SCALE := 0.78

var model: GridModel
var diameter := 56.0
var columns := 11
var origin := Vector2.ZERO
var play_left := 0.0
var play_right := 0.0
var play_bottom := 0.0


func simulate(start: Vector2, dir: Vector2) -> Dictionary:
	var pts := PackedVector2Array([start])
	var p := start
	var v := dir.normalized()
	var r := diameter * 0.5
	var collided = null
	for _i in range(6000):
		p += v * 6.0
		if p.x < play_left + r:
			p.x = play_left + r
			v.x = -v.x
			pts.append(p)
		elif p.x > play_right - r:
			p.x = play_right - r
			v.x = -v.x
			pts.append(p)
		if p.y <= origin.y:           # top wall: reflect downward
			p.y = origin.y
			v.y = -v.y
			pts.append(p)
		if p.y > play_bottom:         # exited the bottom -> miss
			pts.append(p)
			return {"path": pts, "miss": true}
		var hit = _nearest_occupied(p)
		if hit != null:
			pts.append(p)
			collided = hit
			break
	if collided == null:
		return {"path": pts, "miss": true}
	var cell: Vector2i = _snap_cell(p, collided)
	if cell.x < 0:                # no legal attach cell -> treat as a miss rather
		pts.append(p)             # than overwriting/floating a sphere (see _snap_cell)
		return {"path": pts, "miss": true}
	pts.append(Hex.cell_to_world(cell, origin, diameter))
	return {"path": pts, "cell": cell, "miss": false}


func _nearest_occupied(p: Vector2):
	var base := Hex.world_to_cell(p, origin, diameter)
	var best = null
	var bestd := diameter * HIT_DISTANCE_SCALE
	# Test base and its six neighbours without allocating an array each step (this
	# runs up to 6000 times per simulate()). i == 0 is base; 1..6 are the deltas.
	var dirs: Array = Hex.DIRS[base.y & 1]
	for i in range(7):
		var c: Vector2i = base if i == 0 else base + dirs[i - 1]
		if model.cells.has(c):
			var d := p.distance_to(Hex.cell_to_world(c, origin, diameter))
			if d < bestd:
				bestd = d
				best = c
	return best


func _snap_cell(p: Vector2, collided) -> Vector2i:
	var base := Hex.world_to_cell(p, origin, diameter)
	var cand := {base: true}
	for delta in Hex.DIRS[base.y & 1]:
		cand[base + delta] = true
	if collided != null:
		var cc: Vector2i = collided
		for delta in Hex.DIRS[cc.y & 1]:
			cand[cc + delta] = true
	var best = null
	var bestd := INF
	for c in cand.keys():
		if c.x < 0 or c.x >= columns or c.y < 0:
			continue
		if model.cells.has(c):
			continue
		if not model.has_neighbor(c):   # must touch the cluster to attach
			continue
		var d := p.distance_to(Hex.cell_to_world(c, origin, diameter))
		if d < bestd:
			bestd = d
			best = c
	if best == null:
		# Every candidate was occupied, out of bounds, or disconnected from the
		# cluster. There is no legal cell to attach to, so report failure with an
		# invalid sentinel (x < 0); simulate() turns this into a miss. Returning a
		# clamped base cell here would let attach() overwrite a settled sphere or
		# strand a neighbourless one (find_orphans only runs on a pop).
		return Vector2i(-1, -1)
	return best
