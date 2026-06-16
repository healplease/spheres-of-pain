class_name FocusSmoke
extends ColorRect

## A smoke-shader halo that slides behind whichever Button holds keyboard
## focus (see button_smoke.gdshader). Purely cosmetic: ignores the mouse,
## never takes focus, and hides itself when focus leaves all buttons.

const GROW_PX := 10.0  # how far the haze leaks past the button rect
const SLIDE_TIME := 0.18

var _tween: Tween


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


func _on_focus_changed(ctrl: Control) -> void:
	# Deferred so container layout has settled before we read the rect
	# (focus is often grabbed in _ready, one frame before layout).
	_follow.call_deferred(ctrl)


func _follow(ctrl: Control) -> void:
	if not is_instance_valid(ctrl) or not (ctrl is Button) or not ctrl.is_visible_in_tree():
		visible = false
		return
	var rect := ctrl.get_global_rect().grow(GROW_PX)
	if _tween != null:
		_tween.kill()
	if not visible:
		visible = true  # first focus: appear in place, no slide-in
		global_position = rect.position
		size = rect.size
		return
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "global_position", rect.position, SLIDE_TIME)
	_tween.parallel().tween_property(self, "size", rect.size, SLIDE_TIME)
