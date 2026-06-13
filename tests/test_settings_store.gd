extends GutTest

## Tests for SettingsStore defaults + persistence, on a throwaway INI file so the
## real user:// settings are never touched. The store is pure (no engine calls), so
## the engine-application layer (the Settings autoload) is intentionally not exercised
## here — that's why the model/applier split exists.

const TEST_PATH := "user://test_settings.ini"


func before_each() -> void:
	_wipe()


func after_all() -> void:
	_wipe()


func _wipe() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func test_defaults() -> void:
	var s := SettingsStore.new(TEST_PATH)
	assert_false(s.get_aim_enabled(), "aim off by default")
	assert_true(s.get_true_random(), "true random on by default")
	assert_eq(s.get_resolution(), Vector2i(1920, 1080), "default resolution")
	assert_eq(s.get_display_mode(), 3, "default mode = borderless fullscreen")
	assert_false(s.get_vsync(), "vsync off by default")
	assert_eq(s.get_fps_limit(), 60, "default fps limit")
	assert_eq(s.get_antialiasing(), SettingsStore.AA.MSAA_4X, "default AA = MSAA 4x")
	assert_eq(s.get_shadows(), SettingsStore.Shadows.HIGH, "default shadows = High")
	assert_false(s.get_ssao(), "ssao off by default")
	assert_true(s.get_glow(), "glow on by default")
	assert_true(s.get_text_glitch(), "text glitch on by default")
	assert_true(s.get_text_aberration(), "text aberration on by default")
	for ch in SettingsStore.VOLUME_CHANNELS:
		assert_eq(s.get_volume(ch), 1.0, "%s volume defaults to full" % ch)


func test_persistence_roundtrip() -> void:
	var s := SettingsStore.new(TEST_PATH)
	s.set_aim_enabled(true)
	s.set_true_random(false)
	s.set_resolution(Vector2i(2560, 1440))
	s.set_display_mode(0)
	s.set_vsync(true)
	s.set_fps_limit(144)
	s.set_antialiasing(SettingsStore.AA.FXAA)
	s.set_shadows(SettingsStore.Shadows.OFF)
	s.set_ssao(true)
	s.set_glow(false)
	s.set_text_glitch(false)
	s.set_text_aberration(false)
	s.set_volume(&"gameplay", 0.5)

	var t := SettingsStore.new(TEST_PATH)   # fresh instance, same path
	assert_true(t.get_aim_enabled(), "aim persisted")
	assert_false(t.get_true_random(), "true_random persisted")
	assert_eq(t.get_resolution(), Vector2i(2560, 1440), "resolution persisted")
	assert_eq(t.get_display_mode(), 0, "display mode persisted")
	assert_true(t.get_vsync(), "vsync persisted")
	assert_eq(t.get_fps_limit(), 144, "fps limit persisted")
	assert_eq(t.get_antialiasing(), SettingsStore.AA.FXAA, "AA persisted")
	assert_eq(t.get_shadows(), SettingsStore.Shadows.OFF, "shadows persisted")
	assert_true(t.get_ssao(), "ssao persisted")
	assert_false(t.get_glow(), "glow persisted")
	assert_false(t.get_text_glitch(), "text glitch persisted")
	assert_false(t.get_text_aberration(), "text aberration persisted")
	assert_almost_eq(t.get_volume(&"gameplay"), 0.5, 0.001, "gameplay volume persisted")


func test_volume_zero_roundtrips() -> void:
	var s := SettingsStore.new(TEST_PATH)
	s.set_volume(&"hud", 0.0)
	assert_eq(SettingsStore.new(TEST_PATH).get_volume(&"hud"), 0.0, "a muted channel persists as 0")


func test_channels_are_independent() -> void:
	var s := SettingsStore.new(TEST_PATH)
	s.set_volume(&"master", 0.2)
	s.set_volume(&"ambience", 0.8)
	var t := SettingsStore.new(TEST_PATH)
	assert_almost_eq(t.get_volume(&"master"), 0.2, 0.001)
	assert_almost_eq(t.get_volume(&"ambience"), 0.8, 0.001)
	assert_eq(t.get_volume(&"bgm"), 1.0, "untouched channel keeps its default")
