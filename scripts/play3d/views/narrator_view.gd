class_name NarratorView
extends RefCounted

## The grim narrator's subtitle: a single fading line low on the play HUD, independent of the
## centre intro/verdict banner (CenterBanner) so a narrator bark and the level lore can show at
## once. Owns the fade choreography + the two nodes it animates (a label and its soft backdrop);
## the controller hands them over once (setup) and calls show_line() on real events. Pure
## presentation — it neither holds game state nor picks lines (that's the Narrator autoload).
##
## The fade helpers mirror CenterBanner's so the two overlays read identically; kept local to
## keep this view self-contained.

const FADE_IN_TIME := 0.5
const FADE_OUT_TIME := 0.8
const HOLD_TIME := 3.2  # how long a line lingers fully lit before fading
# Soft backdrop margin above/below the line. Kept slim so the bar sits in the top HUD band
# (just under the level title) without crowding it or reaching down into the playfield.
const BG_PAD_Y := 10.0

var _label: Label
var _bg: ColorRect


func setup(label: Label, bg: ColorRect) -> void:
	_label = label
	_bg = bg
	_label.visible = false
	_bg.visible = false


## Fade a line in low on screen, hold, then fade out. A newer line interrupts the old — its
## tweens are killed and restarted, and the stale fade-out bows out (it checks the text is
## still its own). Empty text is a no-op, so the controller can pass Narrator.line_for(...)
## straight through even when nothing is authored for the event.
func show_line(text: String) -> void:
	if text == "" or _label == null:
		return
	_label.text = text
	_size_backdrop()
	_fade_in(_bg, FADE_IN_TIME)
	_fade_in(_label, FADE_IN_TIME)
	await _label.get_tree().create_timer(FADE_IN_TIME + HOLD_TIME).timeout
	# A newer line (or a torn-down scene) means this fade-out is no longer ours to run.
	if not _label.is_inside_tree() or _label.text != text:
		return
	_fade_out(_bg, FADE_OUT_TIME)
	_fade_out(_label, FADE_OUT_TIME)


# --- ui fades (mirror CenterBanner) -------------------------------------------


func _fade_in(ctrl: CanvasItem, dur: float) -> void:
	_kill_fade(ctrl)
	ctrl.modulate.a = 0.0
	ctrl.visible = true
	var tw := ctrl.create_tween()
	tw.tween_property(ctrl, "modulate:a", 1.0, dur)
	ctrl.set_meta("fade_tween", tw)


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


## Fit the soft backdrop to the (centred) line: centre it on the label and size it to the
## measured text height plus BG_PAD_Y above/below, fading the bar out over exactly that pad so
## the line rests on solid black with an equal margin. Call after setting the label's text.
func _size_backdrop() -> void:
	var font := _label.get_theme_font("font")
	if font == null:
		return
	var fsize := _label.get_theme_font_size("font")
	var ts := font.get_multiline_string_size(_label.text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, fsize)
	var center_y := _label.offset_top + (_label.offset_bottom - _label.offset_top) * 0.5
	var h := ts.y + BG_PAD_Y * 2.0
	_bg.offset_top = center_y - h * 0.5
	_bg.offset_bottom = center_y + h * 0.5
	var mat := _bg.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("soft_y", BG_PAD_Y / h)
