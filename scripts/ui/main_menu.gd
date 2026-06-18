class_name MainMenu
extends Control

## Title screen. The only place in the game that quits the application.
##
## On the very FIRST menu load of a run it plays a startup reveal: the words
## SPHERES / OF / PAIN surface one-by-one on a black void (scored by Sound's intro
## stinger), then rise and shrink into the title slot while the rest of the menu
## fades in. Returning here from a level or settings skips straight to the menu —
## GameState.intro_played (an autoload flag) remembers it already ran. The reveal is
## skippable with Space or a click.

const WORD_FADE := 0.35  # per-word fade-in
const HOLD := 0.5  # beat after the phrase assembles, before it moves
const MOVE_TIME := 0.9  # phrase travels + shrinks into the title slot
const CROSSFADE := 0.5  # word-overlay -> real title + abyss bloom
const UI_FADE := 0.6  # tagline + buttons rising in

## Gap (seconds) between each word surfacing. Tuned to the ~3.4s intro stinger;
## exported so it can be matched to the audio by eye.
@export var word_interval := 0.65

var _intro_running := false
var _intro_tween: Tween
var _intro_faded: Array[CanvasItem] = []

@onready var campaign_button: Button = $Center/VBox/CampaignButton
@onready var workshop_button: Button = $Center/VBox/WorkshopButton
@onready var settings_button: Button = $Center/VBox/SettingsButton
@onready var quit_button: Button = $Center/VBox/QuitButton
@onready var title: Label = $Center/VBox/Title
@onready var tagline: Label = $Center/VBox/Tagline
@onready var background: ColorRect = $Background
@onready var overlay: ColorRect = $Overlay
@onready var intro_overlay: Control = $IntroOverlay
@onready var word_group: HBoxContainer = $IntroOverlay/WordGroup
@onready var version_label: Label = $Version


func _ready() -> void:
	# Build stamp — CI rewrites application/config/version from the git tag at export;
	# locally it stays the "0.0.0-dev" placeholder from project.godot.
	version_label.text = "v" + str(ProjectSettings.get_setting("application/config/version", "dev"))
	if GameState.intro_played:
		# Already seen this run — show the menu as-is and drop the reveal scaffolding.
		intro_overlay.queue_free()
		campaign_button.grab_focus()
		return
	_intro_faded = [
		background,
		overlay,
		title,
		tagline,
		campaign_button,
		workshop_button,
		settings_button,
		quit_button
	]
	_run_intro()


## Build the whole reveal as ONE tween (so a skip is a single kill) after waiting a
## couple of frames for the containers to settle — the words need their laid-out
## size and the title needs its final on-screen rect to be the move target.
func _run_intro() -> void:
	for c in _intro_faded:
		c.modulate.a = 0.0  # present in layout (NOT visible=false), just invisible
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return

	# Centre the word phrase on the void, pivoting on its middle so it scales centrically.
	word_group.scale = Vector2.ONE
	word_group.pivot_offset = word_group.size * 0.5
	word_group.position = (intro_overlay.size - word_group.size) * 0.5

	# Where the real title ends up, and how far the (larger) phrase must shrink to match it.
	var target := title.get_global_rect()
	var target_scale: float = clampf(target.size.x / maxf(word_group.size.x, 1.0), 0.05, 1.0)
	var target_pos := target.get_center() - word_group.pivot_offset

	_intro_running = true
	var words := [
		$IntroOverlay/WordGroup/Word0, $IntroOverlay/WordGroup/Word1, $IntroOverlay/WordGroup/Word2
	]

	var t := create_tween()
	t.tween_callback(Sound.play_intro)
	for w: Label in words:
		t.tween_property(w, "modulate:a", 1.0, WORD_FADE)
		t.tween_interval(word_interval)
	t.tween_interval(HOLD)
	# Travel + shrink into the title slot (the two run together).
	(
		t
		. tween_property(word_group, "position", target_pos, MOVE_TIME)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_IN_OUT)
	)
	(
		t
		. parallel()
		. tween_property(word_group, "scale", Vector2(target_scale, target_scale), MOVE_TIME)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_IN_OUT)
	)
	# Hand off to the real title as the abyss blooms back in around it.
	t.chain().tween_property(intro_overlay, "modulate:a", 0.0, CROSSFADE)
	t.parallel().tween_property(title, "modulate:a", 1.0, CROSSFADE)
	t.parallel().tween_property(background, "modulate:a", 1.0, CROSSFADE)
	t.parallel().tween_property(overlay, "modulate:a", 1.0, CROSSFADE)
	# Then the menu options surface.
	t.chain().tween_property(tagline, "modulate:a", 1.0, UI_FADE)
	t.parallel().tween_property(campaign_button, "modulate:a", 1.0, UI_FADE)
	t.parallel().tween_property(workshop_button, "modulate:a", 1.0, UI_FADE)
	t.parallel().tween_property(settings_button, "modulate:a", 1.0, UI_FADE)
	t.parallel().tween_property(quit_button, "modulate:a", 1.0, UI_FADE)
	t.chain().tween_callback(_finalize_intro.bind(false))
	_intro_tween = t


## Space or any click during the reveal jumps straight to the finished menu. Runs in
## _input (not _unhandled_input) so it beats the full-screen CenterContainer to the
## event; consuming it stops the click from also pressing a button underneath.
func _input(event: InputEvent) -> void:
	if not _intro_running:
		return
	var skip: bool = (
		(
			event is InputEventKey
			and event.pressed
			and not event.echo
			and (event as InputEventKey).keycode == KEY_SPACE
		)
		or (event is InputEventMouseButton and event.pressed)
	)
	if skip:
		get_viewport().set_input_as_handled()
		_finalize_intro(true)


## End the reveal — naturally (skipped=false, alphas already animated to 1) or by a
## skip (kill the tween, cut the stinger, snap everything visible). Idempotent.
func _finalize_intro(skipped: bool) -> void:
	if not _intro_running:
		return
	_intro_running = false
	if skipped:
		if _intro_tween and _intro_tween.is_valid():
			_intro_tween.kill()
		Sound.stop_intro()
		for c in _intro_faded:
			c.modulate.a = 1.0
	if is_instance_valid(intro_overlay):
		intro_overlay.queue_free()
	GameState.intro_played = true
	# Seed keyboard focus only now, so arrows/Enter (and a button's wired hover sound)
	# can't fire mid-reveal.
	campaign_button.grab_focus()


func _on_campaign_pressed() -> void:
	GameState.go_to_level_select()


func _on_workshop_pressed() -> void:
	GameState.go_to_my_levels()


func _on_settings_pressed() -> void:
	GameState.go_to_settings()


func _on_quit_pressed() -> void:
	get_tree().quit()
