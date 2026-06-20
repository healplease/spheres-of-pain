class_name Projectile3D
extends Node3D

## A fired sphere in 3D, animated along the pre-computed world-space path (the
## 2D shot path mapped onto the board plane by LevelController3D). Cosmetic — it
## emits `landed`/`missed` with the already-known result on arrival.

signal landed(cell: Vector2i, color: int)
signal missed

# Slow, heavy flight (E2.6): the orb reads as having mass, not zipping like an arcade pellet.
const FLIGHT_SPEED := 13.0  # m/s (was 18)
const ORB_EMISSION := 0.5  # the flying orb is the brightest thing on screen (board spheres ~0.06)
const TRAIL_COLOR := Color(0.5, 0.46, 0.52, 0.5)  # dim, desaturated contrail
const TRAIL_QUAD := 0.12  # contrail particle size (metres)

# Lazily-built soft round particle sprite, shared across every projectile's contrail so we
# don't rebuild the gradient per shot.
static var _dot: Texture2D

var path: Array[Vector3] = []
var cell := Vector2i.ZERO
var color := 0
var miss := false
var speed := FLIGHT_SPEED  # m/s

var _i := 0


func setup(mesh: Mesh, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	# The flying orb glows brighter than any board sphere so the eye tracks it. Duplicate the
	# shared palette material before bumping emission, or every sphere of that colour lights up.
	var m := mat
	if mat is StandardMaterial3D:
		m = mat.duplicate()
		m.emission_energy_multiplier = ORB_EMISSION
	mi.material_override = m
	add_child(mi)
	if Settings.fx_intensity() > 0.0:
		_add_contrail()


## A dim desaturated streak that trails the orb. Particles emit in WORLD space
## (local_coords = false) so they stay behind the moving projectile instead of riding with
## it; built only when Effects Intensity is above 0 (it's a particle effect).
func _add_contrail() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.spread = 8.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.2
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.5))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = TRAIL_COLOR
	mat.albedo_texture = _dot_texture()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2(TRAIL_QUAD, TRAIL_QUAD)
	quad.material = mat

	var trail := GPUParticles3D.new()
	trail.amount = 24
	trail.lifetime = 0.5
	trail.local_coords = false
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail.process_material = pm
	trail.draw_pass_1 = quad
	add_child(trail)


## A soft radial dot sprite for the contrail, built once and shared across all projectiles.
static func _dot_texture() -> Texture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = 24
		t.height = 24
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		_dot = t
	return _dot


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
