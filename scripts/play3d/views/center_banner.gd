class_name CenterBanner
extends RefCounted

## The centre-screen text overlay: the level intro (title + lore fading in over the
## board, then dissolving) and the end verdict (the win/lose banner plus the choice
## panel). Owns the fade/size choreography and the UI nodes it animates; the
## controller hands it those nodes once (setup) and then only calls show_intro /
## show_end with the data + decisions it computed. Pure presentation — no game state.

const FADE_IN_TIME := 0.45
const FADE_OUT_TIME := 0.7
# Soft black backdrop behind the centre text: the bar hugs each line's measured text
# height with this much vertical margin above and below, and fades out over exactly
# that margin (so the text sits on solid black, symmetric top and bottom).
const TEXT_BG_PAD_Y := 16.0  # tagline (small font)
const TITLE_BG_PAD_Y := 54.0  # title / verdict (large font)
const BANNER_PALE := Color(0.82, 0.78, 0.72, 1.0)  # intro / win verdict colour
const BANNER_RED := Color(0.86, 0.13, 0.12, 1.0)  # lose verdict colour

var _banner_bg: ColorRect
var _lore_bg: ColorRect
var _banner_label: Label
var _lore_label: Label
var _end_panel: Control
var _next_button: Button
var _retry_button: Button
var _menu_button: Button
var _ended := false  # once the verdict shows, a late intro fade-out must not run


func setup(
	banner_bg: ColorRect,
	lore_bg: ColorRect,
	banner_label: Label,
	lore_label: Label,
	end_panel: Control,
	next_button: Button,
	retry_button: Button,
	menu_button: Button
) -> void:
	_banner_bg = banner_bg
	_lore_bg = lore_bg
	_banner_label = banner_label
	_lore_label = lore_label
	_end_panel = end_panel
	_next_button = next_button
	_retry_button = retry_button
	_menu_button = menu_button
	# The end-panel choices route straight to GameState (an autoload), so the banner
	# owns their wiring too.
	_next_button.pressed.connect(GameState.start_next)
	_retry_button.pressed.connect(GameState.retry_level)
	_menu_button.pressed.connect(GameState.go_back_from_play)


## Title + lore fade in over the board, hold for a few seconds, then dissolve —
## unless the game ended first (show_end sets _ended and the end banner wins).
func show_intro(title: String, lore: String) -> void:
	_banner_label.text = title
	_banner_label.add_theme_color_override("font_color", BANNER_PALE)
	_lore_label.text = lore
	# A separate soft bar hugs each line (title and tagline), centred on its own text;
	# the title gets a taller plate to match its bigger font.
	_size_text_backdrop(_banner_bg, _banner_label, TITLE_BG_PAD_Y)
	_size_text_backdrop(_lore_bg, _lore_label, TEXT_BG_PAD_Y)
	_fade_in(_banner_bg, FADE_IN_TIME)
	_fade_in(_banner_label, FADE_IN_TIME)
	_fade_in(_lore_bg, FADE_IN_TIME, 0.25)
	_fade_in(_lore_label, FADE_IN_TIME, 0.25)
	await _banner_label.get_tree().create_timer(3.0).timeout
	if not _banner_label.is_inside_tree() or _ended:
		return
	_fade_out(_banner_bg, FADE_OUT_TIME)
	_fade_out(_banner_label, FADE_OUT_TIME)
	_fade_out(_lore_bg, FADE_OUT_TIME)
	_fade_out(_lore_label, FADE_OUT_TIME)


## The verdict banner + choice panel. `show_next`/`show_retry` decide which choices
## appear (the controller computes them from level + progress state). An optional
## `epitaph` (a grim souls-freed tally) rides the now-idle lore line beneath the verdict.
func show_end(msg: String, won: bool, show_next: bool, show_retry: bool, epitaph := "") -> void:
	_ended = true
	_banner_label.text = msg
	# The verdict reads against the board on its own soft black bar (no tagline now);
	# the lose verdict turns red, the win stays pale (relief, not fanfare).
	_banner_label.add_theme_color_override("font_color", BANNER_PALE if won else BANNER_RED)
	_size_text_backdrop(_banner_bg, _banner_label, TITLE_BG_PAD_Y)
	_fade_in(_banner_bg, FADE_IN_TIME)
	_fade_in(_banner_label, FADE_IN_TIME)
	# The intro tagline is gone now; the lore line is reused for the epitaph (if any),
	# fading in a beat after the verdict. With no epitaph it simply stays hidden.
	_kill_fade(_lore_label)
	_kill_fade(_lore_bg)
	if epitaph != "":
		_lore_label.text = epitaph
		_size_text_backdrop(_lore_bg, _lore_label, TEXT_BG_PAD_Y)
		_fade_in(_lore_bg, FADE_IN_TIME, 0.5)
		_fade_in(_lore_label, FADE_IN_TIME, 0.5)
	else:
		_lore_label.visible = false
		_lore_label.modulate.a = 1.0
		_lore_bg.visible = false
		_lore_bg.modulate.a = 1.0
	_next_button.visible = show_next
	_retry_button.visible = show_retry
	# The verdict lands first; the choices surface a beat later.
	_fade_in(_end_panel, FADE_IN_TIME, 0.35)
	# Hand keyboard focus to the most relevant choice so arrows + Enter work.
	if _next_button.visible:
		_next_button.grab_focus()
	elif _retry_button.visible:
		_retry_button.grab_focus()
	else:
		_menu_button.grab_focus()


# --- ui fades -----------------------------------------------------------------


## Show `ctrl` by fading its modulate alpha up from zero (after `delay`). Any fade
## already running on it is killed first, so rapid transitions (intro fade-out
## interrupted by the end banner) can't stack.
func _fade_in(ctrl: CanvasItem, dur: float, delay := 0.0) -> void:
	_kill_fade(ctrl)
	ctrl.modulate.a = 0.0
	ctrl.visible = true
	var tw := ctrl.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(ctrl, "modulate:a", 1.0, dur)
	ctrl.set_meta("fade_tween", tw)


## Fade `ctrl` out, then hide it and restore full alpha for the next show.
func _fade_out(ctrl: CanvasItem, dur: float) -> void:
	_kill_fade(ctrl)
	var tw := ctrl.create_tween()
	tw.tween_property(ctrl, "modulate:a", 0.0, dur)
	tw.tween_callback(
		func() -> void:
			ctrl.visible = false
			ctrl.modulate.a = 1.0
	)
	ctrl.set_meta("fade_tween", tw)


func _kill_fade(ctrl: CanvasItem) -> void:
	if ctrl.has_meta("fade_tween"):
		var tw: Tween = ctrl.get_meta("fade_tween")
		if tw != null and tw.is_valid():
			tw.kill()


## Fit a full-width soft backdrop to one centre-text label: centre it on the label's
## (centred) text and size it to the measured text height plus `pad_y` above and below,
## then fade the bar out over exactly that pad so the text rests on solid black with an
## equal margin top and bottom. Call after setting the label's text.
func _size_text_backdrop(bg: ColorRect, label: Label, pad_y: float) -> void:
	var font := label.get_theme_font("font")
	if font == null:
		return
	var fsize := label.get_theme_font_size("font")
	var ts := font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, fsize)
	# get_multiline_string_size ignores the Label's extra inter-line spacing; add it.
	var lines := label.text.count("\n") + 1
	if lines > 1:
		ts.y += float(lines - 1) * float(label.get_theme_constant("line_spacing"))
	var center_y := label.offset_top + (label.offset_bottom - label.offset_top) * 0.5
	var h := ts.y + pad_y * 2.0
	bg.offset_top = center_y - h * 0.5
	bg.offset_bottom = center_y + h * 0.5
	var mat := bg.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("soft_y", pad_y / h)  # fade out over the pad only
