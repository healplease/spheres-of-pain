class_name SettingsScene
extends Control

## The settings menu. Four tabs (Gameplay / Display / Graphics / Audio) whose rows are
## generated in code from the current SettingsStore values and wired straight to the
## Settings autoload's setters (live-apply + auto-save). The .tscn holds only the
## scaffold (background / tabs / back button); every row is built here so the inline
## "theme" (fonts, widths) lives in one factory — the project has no theme .tres,
## matching how LevelSelect/Sound populate nodes at runtime. A setting's description
## lives in the floating Hint, shown while its title (only) is hovered.

const TITLE_FONT := 22
const CONTROL_WIDTH := 280.0
const VALUE_WIDTH := 56.0   # fixed read-out width so the slider edge doesn't jiggle as digits change
const HintScene := preload("res://scenes/ui/hint.tscn")

@onready var tab_gameplay: VBoxContainer = $Center/VBox/Tabs/Gameplay
@onready var tab_display: VBoxContainer = $Center/VBox/Tabs/Display
@onready var tab_graphics: VBoxContainer = $Center/VBox/Tabs/Graphics
@onready var tab_audio: VBoxContainer = $Center/VBox/Tabs/Audio
@onready var back_button: Button = $Center/VBox/BackButton

var _resolution_option: OptionButton   # disabled unless display mode is Windowed
var _hint: Hint                        # floating tooltip, follows the cursor over a title


func _ready() -> void:
	# The hint is a top-level overlay added last so it draws above every tab and the
	# dread overlay; the row factory wires each title's hover to it.
	_hint = HintScene.instantiate()
	add_child(_hint)
	_build_gameplay_tab()
	_build_display_tab()
	_build_graphics_tab()
	_build_audio_tab()
	back_button.pressed.connect(GameState.go_to_main_menu)
	# Seed keyboard focus so arrows + Enter work without a first mouse click.
	back_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	# Fullscreen has no window chrome — Esc returns to the menu, like the play scene.
	if event.is_action_pressed("ui_cancel"):
		GameState.go_to_main_menu()


# --- row factory ------------------------------------------------------------

## Append a setting row (title + control on one line) to a tab. Hovering the title —
## not the control — reveals the description in the cursor-following Hint.
func _add_row(tab: VBoxContainer, title: String, control: Control, desc: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", TITLE_FONT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_STOP   # so the title receives hover events
	if not desc.is_empty():
		label.mouse_entered.connect(func() -> void: _hint.show_hint(desc))
		label.mouse_exited.connect(_hint.hide_hint)
	row.add_child(label)

	control.custom_minimum_size = Vector2(CONTROL_WIDTH, 0)
	control.size_flags_horizontal = Control.SIZE_SHRINK_END
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)

	tab.add_child(row)


func _make_check(pressed: bool, on_toggled: Callable) -> CheckButton:
	var cb := CheckButton.new()
	cb.button_pressed = pressed
	cb.toggled.connect(on_toggled)
	return cb


# --- Gameplay ---------------------------------------------------------------

func _build_gameplay_tab() -> void:
	# Shooting controls — id == the SettingsStore.ControlScheme value. Seed from the
	# resolved read-through (not store.get_*) so an unset value shows the platform default.
	var ctrl := OptionButton.new()
	ctrl.add_item("Click to shoot", SettingsStore.ControlScheme.CLICK)
	ctrl.add_item("Hold to aim, release to shoot", SettingsStore.ControlScheme.HOLD)
	ctrl.select(ctrl.get_item_index(Settings.control_scheme()))
	ctrl.item_selected.connect(func(i: int) -> void:
		Settings.set_control_scheme(ctrl.get_item_id(i)))
	_add_row(tab_gameplay, "Shooting controls", ctrl,
		"Click: tap to fire instantly. Hold: press to aim, release to shoot — better for touch and precise shots. In Hold, the aim beam shows only while you hold.")

	var aim := _make_check(Settings.aim_enabled(), Settings.set_aim_enabled)
	_add_row(tab_gameplay, "Enable aim", aim,
		"Show the trajectory beam that helps you aim the bubble shot. Toggle it in-game with [A].")

	var rnd := _make_check(Settings.true_random(), Settings.set_true_random)
	_add_row(tab_gameplay, "True random", rnd,
		"On: every bubble is independently random. Off: bubbles are dealt from a shuffled bag so colours come up evenly — a gentler, fairer distribution.")


# --- Display ----------------------------------------------------------------

func _build_display_tab() -> void:
	# Display mode — id == the Window.Mode value so we read it straight back.
	var mode := OptionButton.new()
	mode.add_item("Windowed", Window.MODE_WINDOWED)
	mode.add_item("Borderless fullscreen", Window.MODE_FULLSCREEN)
	mode.add_item("Exclusive fullscreen", Window.MODE_EXCLUSIVE_FULLSCREEN)
	mode.select(mode.get_item_index(Settings.store.get_display_mode()))
	mode.item_selected.connect(func(i: int) -> void:
		Settings.set_display_mode(mode.get_item_id(i))
		_refresh_resolution_enabled())
	_add_row(tab_display, "Display mode", mode,
		"Borderless is the default. Exclusive may flicker or revert on some drivers.")

	# Resolution — metadata holds the Vector2i; only meaningful in Windowed mode.
	var res := OptionButton.new()
	var current_res := Settings.store.get_resolution()
	for r in Settings.available_resolutions():
		res.add_item("%d x %d" % [r.x, r.y])
		res.set_item_metadata(res.item_count - 1, r)
		if r == current_res:
			res.select(res.item_count - 1)
	res.item_selected.connect(func(i: int) -> void:
		Settings.set_resolution(res.get_item_metadata(i)))
	_resolution_option = res
	_add_row(tab_display, "Resolution", res,
		"Applies in Windowed mode; fullscreen uses the monitor's native size.")
	_refresh_resolution_enabled()

	# V-sync
	var vsync := _make_check(Settings.store.get_vsync(), Settings.set_vsync)
	_add_row(tab_display, "V-sync", vsync,
		"Vertical synchronization — trades a little latency to remove tearing.")

	# FPS limit — id == the cap (0 = Unlimited).
	var fps := OptionButton.new()
	for v in SettingsStore.FPS_CHOICES:
		fps.add_item("Unlimited" if v == 0 else str(v), v)
	fps.select(fps.get_item_index(Settings.store.get_fps_limit()))
	fps.item_selected.connect(func(i: int) -> void:
		Settings.set_fps_limit(fps.get_item_id(i)))
	_add_row(tab_display, "FPS limit", fps, "The upper limit of frames per second.")


func _refresh_resolution_enabled() -> void:
	if _resolution_option != null:
		_resolution_option.disabled = Settings.store.get_display_mode() != Window.MODE_WINDOWED


# --- Graphics ---------------------------------------------------------------

func _build_graphics_tab() -> void:
	# Antialiasing — id == the SettingsStore.AA value.
	var aa := OptionButton.new()
	aa.add_item("Off", SettingsStore.AA.OFF)
	aa.add_item("FXAA", SettingsStore.AA.FXAA)
	aa.add_item("MSAA 2x", SettingsStore.AA.MSAA_2X)
	aa.add_item("MSAA 4x", SettingsStore.AA.MSAA_4X)
	aa.add_item("MSAA 8x", SettingsStore.AA.MSAA_8X)
	aa.select(aa.get_item_index(Settings.store.get_antialiasing()))
	aa.item_selected.connect(func(i: int) -> void:
		Settings.set_antialiasing(aa.get_item_id(i)))
	_add_row(tab_graphics, "Antialiasing", aa, "Makes the edges of objects smoother.")

	# Shadows — id == the SettingsStore.Shadows value.
	var sh := OptionButton.new()
	sh.add_item("Off", SettingsStore.Shadows.OFF)
	sh.add_item("Low", SettingsStore.Shadows.LOW)
	sh.add_item("High", SettingsStore.Shadows.HIGH)
	sh.select(sh.get_item_index(Settings.store.get_shadows()))
	sh.item_selected.connect(func(i: int) -> void:
		Settings.set_shadows(sh.get_item_id(i)))
	_add_row(tab_graphics, "Shadows", sh, "Quality of the directional light's shadows.")

	# SSAO
	var ssao := _make_check(Settings.store.get_ssao(), Settings.set_ssao)
	_add_row(tab_graphics, "Ambient occlusion", ssao,
		"Adds soft contact shadows in crevices (SSAO). Costs some performance.")

	# Glow / Bloom
	var glow := _make_check(Settings.store.get_glow(), Settings.set_glow)
	_add_row(tab_graphics, "Glow / Bloom", glow,
		"The danger line, embers, and obsidian rims bloom against the dark.")

	# Text glitch — the title shiver. Accessibility opt-out for motion sensitivity.
	var tglitch := _make_check(Settings.text_glitch(), Settings.set_text_glitch)
	_add_row(tab_graphics, "Text glitch", tglitch,
		"Titles occasionally shudder and jitter. Turn off to keep all on-screen text perfectly still.")


# --- Audio ------------------------------------------------------------------

func _build_audio_tab() -> void:
	_add_slider(tab_audio, "Master", &"master", "Overall volume.")
	_add_slider(tab_audio, "Music", &"bgm", "The title theme.")
	_add_slider(tab_audio, "Ambience", &"ambience", "The dungeon's breathing drone.")
	_add_slider(tab_audio, "HUD", &"hud", "Menu clicks and hovers.")
	_add_slider(tab_audio, "Gameplay", &"gameplay", "Sphere pops and the heartbeat of dread.")


func _add_slider(tab: VBoxContainer, title: String, channel: StringName, desc: String) -> void:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.01
	s.value = Settings.store.get_volume(channel)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Live 0–100 read-out to the right of the slider (stored 0–1, shown as a percentage).
	var pct := Label.new()
	pct.add_theme_font_size_override("font_size", TITLE_FONT)
	pct.custom_minimum_size = Vector2(VALUE_WIDTH, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.text = _percent(s.value)

	s.value_changed.connect(func(v: float) -> void:
		Settings.set_volume(channel, v)
		pct.text = _percent(v))

	# Wrap slider + read-out as one control so the row factory lays them out together.
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.add_child(s)
	box.add_child(pct)
	_add_row(tab, title, box, desc)


## Format a stored 0–1 volume as a whole-percent string (0 → "0%", 1 → "100%").
static func _percent(v: float) -> String:
	return "%d%%" % roundi(v * 100.0)
