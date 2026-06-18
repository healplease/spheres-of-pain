class_name EditorSwatch
extends Control

## One bubble in the level editor's left palette: a coloured (or obstacle) disc the
## player drags onto the field or clicks to select as the active brush. The carried
## `value` is a GridModel cell value — a colour id (>= 0) or a BLACK/SPIN/BOUNCE
## sentinel — so the editor places it verbatim. Drag uses Godot's built-in
## _get_drag_data; EditorDropZone is the matching drop target over the board.

signal selected(value: int)

const SIZE := 50.0

var value: int = 0
var swatch_color: Color = Color.WHITE
var _is_selected := false


func setup(p_value: int, p_color: Color) -> void:
	value = p_value
	swatch_color = p_color
	custom_minimum_size = Vector2(SIZE, SIZE)
	tooltip_text = _label()
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func set_selected(on: bool) -> void:
	if on == _is_selected:
		return
	_is_selected = on
	queue_redraw()


func _label() -> String:
	match value:
		GridModel.BLACK:
			return "Black obstacle  (Shift+1)"
		GridModel.SPIN:
			return "Spin bubble  (Shift+2)"
		GridModel.BOUNCE:
			return "Bounce bubble  (Shift+3)"
		_:
			return "Colour %d  (%s)" % [value, "0" if value == 9 else str(value + 1)]


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 3.0
	if _is_selected:
		draw_circle(c, r + 3.0, Color(0.86, 0.13, 0.12, 0.9))  # red focus ring
	draw_circle(c, r, swatch_color)
	draw_arc(c, r, 0.0, TAU, 40, Color(0, 0, 0, 0.55), 2.0, true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected.emit(value)


## Begin a drag carrying this bubble; the editor's drop zone accepts it. Also selects
## this swatch so a drag and a click leave the same active brush behind.
func _get_drag_data(_at_position: Vector2) -> Variant:
	selected.emit(value)
	set_drag_preview(_make_ghost())
	return {"kind": "sphere", "value": value}


## A cursor-centred translucent disc shown under the pointer during the drag.
func _make_ghost() -> Control:
	var holder := Control.new()
	var ghost := EditorSwatch.new()
	ghost.setup(value, swatch_color)
	ghost.size = Vector2(40, 40)
	ghost.position = Vector2(-20, -20)
	ghost.modulate.a = 0.8
	holder.add_child(ghost)
	return holder
