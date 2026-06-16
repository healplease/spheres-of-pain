class_name StageView
extends Node

## The 3D staging around the play field: the perspective camera that frames the
## field head-on, the abyss backdrop quad behind it, the drifting ember particles,
## the world environment (fog/glow/grading), and the directional light. The
## controller owns the field geometry; it hands this node the scene nodes (setup)
## and the world-space field bounds (frame / fit_embers / apply_theme), and this
## node does the framing math, atmosphere, and live graphics-settings updates.

const MARGIN_TOP := 96.0  # reserved screen margin at the top (design px) — extra
# headroom so the HUD level name clears the field's top border
const MARGIN_BOTTOM := 50.0  # reserved screen margin at the bottom (design px)
const BACKDROP_OFFSET := 12.0  # metres the abyss backdrop sits behind the board plane

var _world_env: WorldEnvironment
var _light: DirectionalLight3D
var _camera: Camera3D
var _backdrop: MeshInstance3D
var _embers: GPUParticles3D
var _outer_bounds := Vector4.ZERO  # cached field-frame bounds, so a resize can reframe
var _view_center := Vector3.ZERO  # camera look target (field centre nudged down for the HUD)


func setup(
	world_env: WorldEnvironment,
	light: DirectionalLight3D,
	camera: Camera3D,
	backdrop: MeshInstance3D,
	embers: GPUParticles3D
) -> void:
	_world_env = world_env
	_light = light
	_camera = camera
	_backdrop = backdrop
	_embers = embers
	_setup_environment()
	# Reframe on viewport resize, and live-apply Graphics settings changes. Both
	# senders outlive the level scene, but this node frees with it (auto-disconnect).
	get_viewport().size_changed.connect(_place_camera)
	Settings.graphics_changed.connect(_apply_graphics_settings)


## Frame the field from its outer bounds; cache them so a resize can reframe without
## the controller recomputing geometry that hasn't changed.
func frame(outer_bounds: Vector4) -> void:
	_outer_bounds = outer_bounds
	_place_camera()


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.4, 0.5)
	env.ambient_light_energy = 0.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.025, 0.02, 0.045)
	env.fog_density = 0.015
	# Glow for the pulsing danger line and the embers (both peak above 1.0);
	# the abyss backdrop outputs plain ALBEDO so it can never bloom.
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.ssao_enabled = false  # overridden by _apply_graphics_settings() per the player's setting
	# Gentle grading toward the gothic-ink look: drained colour, a hair more bite.
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.88
	env.adjustment_contrast = 1.04
	_world_env.environment = env
	_light.rotation_degrees = Vector3(-50, -40, 0)
	_light.light_energy = 1.3
	_light.light_color = Color(0.92, 0.88, 0.98)
	# Glow / SSAO / shadow quality are player-controlled (Graphics settings); apply them now.
	_apply_graphics_settings()


## Apply the player's Graphics settings (glow / SSAO / shadow quality) onto the
## already-built environment + light. Called once during setup and again whenever
## the Settings autoload reports a change, so the look updates live.
func _apply_graphics_settings() -> void:
	var env := _world_env.environment
	if env == null:
		return
	env.glow_enabled = Settings.glow_enabled()
	env.ssao_enabled = Settings.ssao_enabled()
	match Settings.shadows():
		SettingsStore.Shadows.OFF:
			_light.shadow_enabled = false
		SettingsStore.Shadows.LOW:
			_light.shadow_enabled = true
			_light.directional_shadow_max_distance = 50.0
		SettingsStore.Shadows.HIGH:
			_light.shadow_enabled = true
			_light.directional_shadow_max_distance = 100.0


func _place_camera() -> void:
	# Frame the whole play field (its outer frame) head-on, reserving MARGIN_TOP /
	# MARGIN_BOTTOM of screen. The top reserve is larger so the HUD (level name)
	# clears the field's top border: the field is centred in the band between them,
	# which sits below screen centre, so we aim the camera a touch higher to push
	# the field down into it. The viewport is the 1280x720 design space (canvas_items
	# stretch), so the margins are deterministic across resolutions.
	var b := _outer_bounds
	if b == Vector4.ZERO:
		return  # a resize fired before frame() supplied the field bounds
	var center := Vector3((b.x + b.y) * 0.5, (b.z + b.w) * 0.5, 0.0)
	var field_h := absf(b.z - b.w)
	var field_w := absf(b.y - b.x)
	var vp := get_viewport().get_visible_rect().size
	if vp.y <= 0.0:
		return
	_camera.fov = 52.0
	var tan_half := tan(deg_to_rad(_camera.fov) * 0.5)
	var v_frac: float = maxf(0.2, (vp.y - (MARGIN_TOP + MARGIN_BOTTOM)) / vp.y)
	var aspect: float = vp.x / vp.y
	var d_fit_height := (field_h / v_frac) / (2.0 * tan_half)
	var d_fit_width := field_w / (2.0 * tan_half * aspect)
	var d: float = maxf(d_fit_height, d_fit_width)
	# Raise the look target by the band's downward shift, converted to world units
	# at the field plane (the full visible height there maps to vp.y pixels).
	var world_per_px := (2.0 * d * tan_half) / vp.y
	var look_shift := (MARGIN_TOP - MARGIN_BOTTOM) * 0.5 * world_per_px
	_view_center = center + Vector3(0.0, look_shift, 0.0)
	_camera.position = _view_center + Vector3(0.0, 0.0, d)
	_camera.look_at(_view_center, Vector3.UP)
	_fit_backdrop()


## Size the abyss backdrop quad to cover the camera frustum at its depth (with
## 15% margin), so no background_color slivers show at any field size. Centred on
## the camera's view axis (_view_center), not the field, so the look-target nudge
## can't reveal a sliver of background_color at the top.
func _fit_backdrop() -> void:
	_backdrop.position = Vector3(_view_center.x, _view_center.y, -BACKDROP_OFFSET)
	var dist := _camera.position.z + BACKDROP_OFFSET
	var vp := get_viewport().get_visible_rect().size
	if vp.y <= 0.0:
		return
	var h := 2.0 * dist * tan(deg_to_rad(_camera.fov) * 0.5) * 1.15
	var w := h * (vp.x / vp.y) * 1.15
	_backdrop.scale = Vector3(w * 0.5, h * 0.5, 1.0)  # QuadMesh is 2x2


## Tint the abyss, embers and fog to the level's palette. The shader/particle
## materials are shared scene sub-resources that persist across scene reloads,
## so free play must reset them explicitly (via a defaults instance) rather
## than leaving whatever the last level set.
func apply_theme(theme: LevelResource) -> void:
	var mat := _backdrop.material_override as ShaderMaterial
	mat.set_shader_parameter("violet", theme.abyss_color_a)
	mat.set_shader_parameter("teal", theme.abyss_color_b)
	_world_env.environment.fog_light_color = theme.fog_color
	var ember_mat := (_embers.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	ember_mat.albedo_color = Color(theme.ember_color, 0.55)


## Spread the ember particles across the whole play field (they float in a thin
## slab in front of the board plane), with density scaled to the field area.
func fit_embers(inner_bounds: Vector4) -> void:
	var b := inner_bounds
	var span_x := b.y - b.x
	var span_y := b.z - b.w
	_embers.position = Vector3((b.x + b.y) * 0.5, (b.z + b.w) * 0.5, 1.2)
	var pm := _embers.process_material as ParticleProcessMaterial
	pm.emission_box_extents = Vector3(span_x * 0.5 + 1.0, span_y * 0.5 + 1.0, 1.5)
	_embers.amount = clampi(int(span_x * span_y * 0.35), 60, 400)
	_embers.restart()
