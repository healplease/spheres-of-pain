class_name SettingsStore
extends RefCounted

## Player settings persisted to an INI file (Godot's ConfigFile is natively INI).
## Pure model: typed getters/setters with defaults and NO engine calls (no
## DisplayServer / AudioServer / Engine / Viewport), so it's unit-testable headless
## exactly like ProgressStore. The Settings autoload owns one of these and is the
## only place that translates these values into live engine state. The save path is
## injectable so tests use a throwaway file instead of the real save.

const SECTION_GAMEPLAY := "gameplay"
const SECTION_VIDEO := "video"
const SECTION_GRAPHICS := "graphics"
const SECTION_AUDIO := "audio"

## Antialiasing options, stored as the enum's int value.
enum AA { OFF, FXAA, MSAA_2X, MSAA_4X, MSAA_8X }
## Directional-light shadow quality, stored as the enum's int value.
enum Shadows { OFF, LOW, HIGH }
## Shooting control scheme, stored as the enum's int value. CLICK fires on press
## (point-and-click); HOLD begins aiming on press and fires on release (touch/precision).
enum ControlScheme { CLICK, HOLD }

## FPS-limit choices the Video tab offers; 0 means Unlimited.
const FPS_CHOICES: Array[int] = [60, 75, 100, 120, 144, 240, 0]

## Resolution candidates across aspect ratios (16:9, 16:10, 4:3, 21:9). The Settings
## autoload filters these against the monitor size; the store only holds the list so
## the UI and the applier share one source of truth. ConfigFile round-trips Vector2i
## natively, so no string parsing is needed.
const RESOLUTION_CHOICES: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),  # 16:9
	Vector2i(1280, 800), Vector2i(1680, 1050), Vector2i(1920, 1200), Vector2i(2560, 1600),                       # 16:10
	Vector2i(1024, 768), Vector2i(1280, 960), Vector2i(1600, 1200),                                              # 4:3
	Vector2i(2560, 1080), Vector2i(3440, 1440),                                                                  # 21:9
]

## Audio channels (Master + four category sub-buses). Used as the suffix of the INI
## key (`vol_<channel>`) and mapped to a real bus name by the Settings autoload.
const VOLUME_CHANNELS: Array[StringName] = [&"master", &"bgm", &"ambience", &"hud", &"gameplay"]

# Defaults in one place — referenced by the getters and asserted by the test suite.
const DEF_AIM := false
const DEF_TRUE_RANDOM := true          # classic independent-random shot colours by default
const DEF_CONTROL_SCHEME := ControlScheme.CLICK   # neutral fallback; the autoload picks a platform-aware default when unset
const DEF_RESOLUTION := Vector2i(1920, 1080)
const DEF_DISPLAY_MODE := 3            # Window.MODE_FULLSCREEN (borderless) — matches launch behaviour
const DEF_VSYNC := false
const DEF_FPS_LIMIT := 60
const DEF_AA := AA.MSAA_4X
const DEF_SHADOWS := Shadows.HIGH
const DEF_SSAO := false
const DEF_GLOW := true
const DEF_TEXT_GLITCH := true           # title shiver on by default (accessibility opt-out)
const DEF_VOLUME := 1.0

var path: String
var _cf := ConfigFile.new()


func _init(save_path: String = "user://settings.ini") -> void:
	path = save_path
	_cf.load(path)   # a non-OK result (no file on first run) just leaves the defaults in place


# --- Gameplay ---------------------------------------------------------------

func get_aim_enabled() -> bool:
	return bool(_cf.get_value(SECTION_GAMEPLAY, "aim_enabled", DEF_AIM))

func set_aim_enabled(v: bool) -> void:
	_cf.set_value(SECTION_GAMEPLAY, "aim_enabled", v)
	_save()

func get_true_random() -> bool:
	return bool(_cf.get_value(SECTION_GAMEPLAY, "true_random", DEF_TRUE_RANDOM))

func set_true_random(v: bool) -> void:
	_cf.set_value(SECTION_GAMEPLAY, "true_random", v)
	_save()

func get_control_scheme() -> int:
	return int(_cf.get_value(SECTION_GAMEPLAY, "control_scheme", DEF_CONTROL_SCHEME))

func set_control_scheme(v: int) -> void:
	_cf.set_value(SECTION_GAMEPLAY, "control_scheme", v)
	_save()

## True once the player has explicitly chosen a scheme. The autoload uses this to tell
## "never set" from a real choice, so it can resolve a platform-aware default (touch ->
## HOLD) on first run without silently writing the INI here.
func has_control_scheme() -> bool:
	return _cf.has_section_key(SECTION_GAMEPLAY, "control_scheme")


# --- Video ------------------------------------------------------------------

func get_resolution() -> Vector2i:
	return _cf.get_value(SECTION_VIDEO, "resolution", DEF_RESOLUTION)

func set_resolution(v: Vector2i) -> void:
	_cf.set_value(SECTION_VIDEO, "resolution", v)
	_save()

func get_display_mode() -> int:
	return int(_cf.get_value(SECTION_VIDEO, "display_mode", DEF_DISPLAY_MODE))

func set_display_mode(v: int) -> void:
	_cf.set_value(SECTION_VIDEO, "display_mode", v)
	_save()

func get_vsync() -> bool:
	return bool(_cf.get_value(SECTION_VIDEO, "vsync", DEF_VSYNC))

func set_vsync(v: bool) -> void:
	_cf.set_value(SECTION_VIDEO, "vsync", v)
	_save()

func get_fps_limit() -> int:
	return int(_cf.get_value(SECTION_VIDEO, "fps_limit", DEF_FPS_LIMIT))

func set_fps_limit(v: int) -> void:
	_cf.set_value(SECTION_VIDEO, "fps_limit", v)
	_save()


# --- Graphics ---------------------------------------------------------------

func get_antialiasing() -> int:
	return int(_cf.get_value(SECTION_GRAPHICS, "antialiasing", DEF_AA))

func set_antialiasing(v: int) -> void:
	_cf.set_value(SECTION_GRAPHICS, "antialiasing", v)
	_save()

func get_shadows() -> int:
	return int(_cf.get_value(SECTION_GRAPHICS, "shadows", DEF_SHADOWS))

func set_shadows(v: int) -> void:
	_cf.set_value(SECTION_GRAPHICS, "shadows", v)
	_save()

func get_ssao() -> bool:
	return bool(_cf.get_value(SECTION_GRAPHICS, "ssao", DEF_SSAO))

func set_ssao(v: bool) -> void:
	_cf.set_value(SECTION_GRAPHICS, "ssao", v)
	_save()

func get_glow() -> bool:
	return bool(_cf.get_value(SECTION_GRAPHICS, "glow", DEF_GLOW))

func set_glow(v: bool) -> void:
	_cf.set_value(SECTION_GRAPHICS, "glow", v)
	_save()

func get_text_glitch() -> bool:
	return bool(_cf.get_value(SECTION_GRAPHICS, "text_glitch", DEF_TEXT_GLITCH))

func set_text_glitch(v: bool) -> void:
	_cf.set_value(SECTION_GRAPHICS, "text_glitch", v)
	_save()


# --- Audio (linear 0..1) ----------------------------------------------------

func get_volume(channel: StringName) -> float:
	return float(_cf.get_value(SECTION_AUDIO, _vol_key(channel), DEF_VOLUME))

func set_volume(channel: StringName, v: float) -> void:
	_cf.set_value(SECTION_AUDIO, _vol_key(channel), v)
	_save()


func _vol_key(channel: StringName) -> String:
	return "vol_" + String(channel)


func _save() -> void:
	_cf.save(path)
