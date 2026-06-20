class_name DottedPath
extends RefCounted

## Shared dotted-polyline emitter for the 3D aim ray ([[AimView]]) and the editor's hover ring.
## Stateless geometry only — callers own the ImmediateMesh, its surface, and the colour.


## Walk a polyline in logical 2D space, emitting one short segment ("dot") per dot+gap cycle
## into an already-open ImmediateMesh LINES surface. `s` (arc length from the start) stays
## continuous across segments so the dot/gap rhythm never resets or skips a beat at a corner.
## `map3d` maps a logical Vector2 to world space; each dot is nudged `z_lift` toward the camera
## so it floats just in front of the board plane rather than z-fighting the spheres.
static func emit(
	mesh: ImmediateMesh,
	points: PackedVector2Array,
	dot: float,
	gap: float,
	map3d: Callable,
	z_lift := 0.05
) -> void:
	var cycle := dot + gap
	var s := 0.0
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var seg := b - a
		var seg_len := seg.length()
		if seg_len < 0.0001:
			continue
		var dir := seg / seg_len
		var local := 0.0  # distance walked within this segment
		while local < seg_len:
			var into := fmod(s + local, cycle)  # position within the current dot's cycle
			if into < dot:
				var run: float = minf(dot - into, seg_len - local)  # rest of this dot on this seg
				_add_dot(mesh, map3d, a + dir * local, a + dir * (local + run), z_lift)
				local += run
			else:
				local += cycle - into  # inside the gap: jump to the next dot
		s += seg_len


## A closed ring polyline (logical space) around `center`, fine enough that the dot walk renders
## evenly spaced dots around it.
static func ring_points(center: Vector2, radius: float, segments: int) -> PackedVector2Array:
	var ring := PackedVector2Array()
	ring.resize(segments + 1)
	for i in range(segments + 1):
		var ang := TAU * float(i) / float(segments)
		ring[i] = center + Vector2(cos(ang), sin(ang)) * radius
	return ring


static func _add_dot(
	mesh: ImmediateMesh, map3d: Callable, p0: Vector2, p1: Vector2, z_lift: float
) -> void:
	var w0: Vector3 = map3d.call(p0)
	var w1: Vector3 = map3d.call(p1)
	mesh.surface_add_vertex(w0 + Vector3(0, 0, z_lift))
	mesh.surface_add_vertex(w1 + Vector3(0, 0, z_lift))
