# gdlint:disable=max-public-methods
# ^ a settings facade: one setter/read-through per option, by design
extends Node

## Autoload "Settings": owns a SettingsStore (the persisted model) and is the ONLY
## place that pushes those values into live engine state — window/display mode,
## vsync, the fps cap, the root viewport's antialiasing, and the audio bus volumes.
##
## Graphics options that live on the per-level Environment/light and the aim preview
## can't be set once globally (they're rebuilt every time the play scene loads), so
## the level READS them from here at build time and re-syncs live via `graphics_changed`.
## The dependency points level -> Settings; Settings never reaches into a level's nodes.

# past-tense: emitted after a graphics/gameplay change so a running level re-applies
signal graphics_changed

var store := SettingsStore.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	apply_all()


# --- apply (model -> engine) ------------------------------------------------


func apply_all() -> void:
	apply_video()
	apply_aa()
	apply_audio()
	apply_text_effects()
	apply_fx_intensity()
	graphics_changed.emit()  # sync any already-running level's env/aim
	(
		Log
		. info(
			Log.CONFIG,
			"settings applied",
			{
				"shadows": store.get_shadows(),
				"ssao": store.get_ssao(),
				"glow": store.get_glow(),
			}
		)
	)


func apply_video() -> void:
	var win := get_window()
	var mode: int = store.get_display_mode()
	win.mode = mode
	# Resolution only changes the window in Windowed mode; fullscreen uses the
	# monitor's native size. (Don't assume the requested mode succeeded — exclusive
	# fullscreen may silently fall back on some drivers; we persist the request anyway.)
	if mode == Window.MODE_WINDOWED:
		win.size = store.get_resolution()
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if store.get_vsync() else DisplayServer.VSYNC_DISABLED
	)
	Engine.max_fps = store.get_fps_limit()  # 0 = unlimited
	(
		Log
		. debug(
			Log.CONFIG,
			"video",
			{
				"display_mode": mode,
				"resolution": win.size,
				"vsync": store.get_vsync(),
				"fps_limit": store.get_fps_limit(),
			}
		)
	)


func apply_aa() -> void:
	# The 3D scene renders to the ROOT viewport (no SubViewport), so this is global
	# and survives scene changes. FXAA and MSAA are mutually exclusive here.
	var vp := get_viewport()
	match store.get_antialiasing():
		SettingsStore.AA.OFF:
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		SettingsStore.AA.FXAA:
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		SettingsStore.AA.MSAA_2X:
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.msaa_3d = Viewport.MSAA_2X
		SettingsStore.AA.MSAA_4X:
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.msaa_3d = Viewport.MSAA_4X
		SettingsStore.AA.MSAA_8X:
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			vp.msaa_3d = Viewport.MSAA_8X
	Log.debug(
		Log.CONFIG, "antialiasing", {"mode": SettingsStore.AA.keys()[store.get_antialiasing()]}
	)


func apply_audio() -> void:
	for ch in SettingsStore.VOLUME_CHANNELS:
		_apply_bus(_bus_name(ch), store.get_volume(ch))


## Graphics options are Environment-bound (rebuilt per level), so there's nothing
## global to push here — just notify the live level to re-read them.
func apply_graphics() -> void:
	graphics_changed.emit()


## The title-text shader reads this as a global shader param, so setting it once on
## the RenderingServer reaches every title in every scene at once (no per-node wiring,
## and the autoload never touches a level's nodes). 1 = effect on, 0 = off.
func apply_text_effects() -> void:
	RenderingServer.global_shader_parameter_set(
		&"text_glitch", 1.0 if store.get_text_glitch() else 0.0
	)


## The master juice multiplier. Pushed to the RenderingServer as a global shader param
## so shader-driven effects (e.g. the danger-vignette pulse) read it directly; code-driven
## effects (camera shake, particles, slow-mo, audio stings) read fx_intensity() instead.
func apply_fx_intensity() -> void:
	RenderingServer.global_shader_parameter_set(&"fx_intensity", store.get_fx_intensity())


# --- setters the Settings UI calls (mutate store -> auto-save -> apply) -------


func set_aim_enabled(v: bool) -> void:
	store.set_aim_enabled(v)
	# no global effect; a live level (e.g. a future pause overlay) can pick it up
	graphics_changed.emit()


func set_true_random(v: bool) -> void:
	store.set_true_random(v)  # read by the next level at build; settings aren't reachable mid-level


func set_control_scheme(v: int) -> void:
	store.set_control_scheme(v)  # read by the next level at build; settings aren't reachable mid-level


func set_resolution(v: Vector2i) -> void:
	store.set_resolution(v)
	apply_video()


func set_display_mode(v: int) -> void:
	store.set_display_mode(v)
	apply_video()


func set_vsync(v: bool) -> void:
	store.set_vsync(v)
	apply_video()


func set_fps_limit(v: int) -> void:
	store.set_fps_limit(v)
	apply_video()


func set_antialiasing(v: int) -> void:
	store.set_antialiasing(v)
	apply_aa()


func set_shadows(v: int) -> void:
	store.set_shadows(v)
	apply_graphics()


func set_ssao(v: bool) -> void:
	store.set_ssao(v)
	apply_graphics()


func set_glow(v: bool) -> void:
	store.set_glow(v)
	apply_graphics()


func set_text_glitch(v: bool) -> void:
	store.set_text_glitch(v)
	apply_text_effects()


func set_fx_intensity(v: float) -> void:
	store.set_fx_intensity(v)
	apply_fx_intensity()


func set_volume(channel: StringName, v: float) -> void:
	store.set_volume(channel, v)
	apply_audio()


# --- read-throughs the level/UI use (so callers don't reach into .store) -----


func aim_enabled() -> bool:
	return store.get_aim_enabled()


func true_random() -> bool:
	return store.get_true_random()


## The shooting control scheme. When the player has never chosen one, resolve a
## platform-aware default here (the store stays engine-free): HOLD on native mobile
## apps and on phones playing the web build, CLICK everywhere else. This is computed
## fresh each read rather than persisted, so the same user:// profile picks the right
## default if it's opened on a different device class.
func control_scheme() -> int:
	if store.has_control_scheme():
		return store.get_control_scheme()
	return (
		SettingsStore.ControlScheme.HOLD
		if _default_is_hold()
		else SettingsStore.ControlScheme.CLICK
	)


func _default_is_hold() -> bool:
	return (
		OS.has_feature("mobile")
		or (OS.has_feature("web") and DisplayServer.is_touchscreen_available())
	)


func glow_enabled() -> bool:
	return store.get_glow()


func ssao_enabled() -> bool:
	return store.get_ssao()


func shadows() -> int:
	return store.get_shadows()


func text_glitch() -> bool:
	return store.get_text_glitch()


## Master juice multiplier (0..1) for code-driven game-feel effects. Shaders read the
## `fx_intensity` global param instead (see apply_fx_intensity).
func fx_intensity() -> float:
	return store.get_fx_intensity()


## Resolution candidates that fit the current monitor, plus the saved choice,
## smallest-area first. Used to populate the Video tab's dropdown.
func available_resolutions() -> Array[Vector2i]:
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var out: Array[Vector2i] = []
	for r in SettingsStore.RESOLUTION_CHOICES:
		if r.x <= screen.x and r.y <= screen.y:
			out.append(r)
	var current := store.get_resolution()
	if not out.has(current):
		out.append(current)  # never hide the saved choice, even if it exceeds the monitor
	out.sort_custom(func(a, b): return a.x * a.y < b.x * b.y)
	return out


# --- helpers ----------------------------------------------------------------


func _apply_bus(bus_name: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.0)  # 0 mutes (linear_to_db(0) is -inf)
	if linear > 0.0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))


func _bus_name(channel: StringName) -> StringName:
	match channel:
		&"master":
			return &"Master"
		&"bgm":
			return &"BGM"
		&"ambience":
			return &"Ambience"
		&"hud":
			return &"HUD"
		&"gameplay":
			return &"Gameplay"
	return &"Master"
