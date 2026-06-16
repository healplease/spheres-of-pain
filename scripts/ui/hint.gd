class_name Hint
extends PanelContainer

## A reusable tooltip that floats near the cursor and follows it. A host UI instances
## one as a top-level overlay (so it draws above everything and isn't laid out by a
## container) and calls show_hint()/hide_hint() — e.g. the Settings menu reveals a
## setting's description while its title is hovered. Mouse-transparent (set in the
## .tscn), so it never intercepts the controls it floats over, and clamped to the
## viewport so a long hint never spills off-screen.

const CURSOR_OFFSET := Vector2(18.0, 20.0)  # down-right of the pointer, clear of it
const EDGE_MARGIN := 8.0  # keep this far from the viewport edges

@onready var _label: Label = $Label


func _ready() -> void:
	top_level = true  # position in viewport space, ignoring the host's layout
	hide()


func _process(_delta: float) -> void:
	if not visible:
		return
	var view := get_viewport_rect().size
	var mouse := get_global_mouse_position()
	var pos := mouse + CURSOR_OFFSET
	# Flip to the other side of the cursor when the box would cross the far edge,
	# then clamp so it always stays fully on-screen.
	if pos.x + size.x + EDGE_MARGIN > view.x:
		pos.x = mouse.x - size.x - CURSOR_OFFSET.x
	if pos.y + size.y + EDGE_MARGIN > view.y:
		pos.y = mouse.y - size.y - CURSOR_OFFSET.y
	var lo := Vector2(EDGE_MARGIN, EDGE_MARGIN)
	global_position = pos.clamp(lo, (view - size - lo).max(lo))


func show_hint(text: String) -> void:
	if text.is_empty():
		hide()
		return
	_label.text = text
	reset_size()  # shrink to the new content so the follow math uses this frame's size
	show()


func hide_hint() -> void:
	hide()
