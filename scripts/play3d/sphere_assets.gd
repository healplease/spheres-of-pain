class_name SphereAssets
extends RefCounted

## The shared visual resources for a level's spheres, built once and handed to the
## board, the shooter, and the projectile so they all draw from the same set:
##   - one SphereMesh template,
##   - one StandardMaterial3D per palette colour (BoardView3D.PALETTE),
##   - the obsidian shader material for black/unbreakable obstacles,
##   - the swirl/pulse shader materials for the spin/bounce obstacles,
##   - the unshaded translucent material for the aim-ray preview.
## Pure resource construction — no scene nodes — so it stays out of the controller.

const _OBSIDIAN := preload("res://shaders/obsidian_rim.gdshader")
const _SPIN := preload("res://shaders/spin_bubble.gdshader")
const _BOUNCE := preload("res://shaders/bounce_bubble.gdshader")

var mesh: SphereMesh
var mats: Array[StandardMaterial3D] = []
var black_mat: ShaderMaterial
var spin_mat: ShaderMaterial
var bounce_mat: ShaderMaterial
var preview_mat: StandardMaterial3D


func _init(radius: float) -> void:
	mesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	# Lacquered-glass look: clearcoat for a wet specular skin, a rim so spheres
	# keep a readable silhouette against the dark abyss, and a whisper of
	# self-emission (far below the bloom threshold) so they glow faintly in fog.
	for col in BoardView3D.PALETTE:
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.metallic = 0.35
		m.roughness = 0.3
		m.clearcoat_enabled = true
		m.clearcoat = 0.7
		m.clearcoat_roughness = 0.15
		m.rim_enabled = true
		m.rim = 0.4
		m.rim_tint = 0.35
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 0.06
		mats.append(m)
	# Black spheres are polished obsidian. A StandardMaterial3D rim needs scene light
	# to catch the edge, which the dark abyss doesn't provide — so these use a custom
	# shader that drives a self-lit fresnel edge into EMISSION instead. The glowing
	# silhouette reads against the near-black background (and blooms) while the face
	# stays dark and unbreakable-looking.
	black_mat = ShaderMaterial.new()
	black_mat.shader = _OBSIDIAN
	# Spin/bounce share the obsidian-family look (dark face, self-lit rim) but each adds
	# its own animated cue — a rotating swirl and an elastic pulse — keyed off the
	# shader's TIME uniform. Defaults are baked into the shaders; nothing to set here.
	spin_mat = ShaderMaterial.new()
	spin_mat.shader = _SPIN
	bounce_mat = ShaderMaterial.new()
	bounce_mat.shader = _BOUNCE
	preview_mat = StandardMaterial3D.new()
	preview_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	preview_mat.albedo_color = Color(0.9, 0.85, 0.85, 0.55)
	preview_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
