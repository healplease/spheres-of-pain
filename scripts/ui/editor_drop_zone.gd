class_name EditorDropZone
extends Control

## A transparent Control over the editor's central board area. It is the drop target
## for palette bubbles dragged onto the field, and it routes clicks within the board
## region to the editor (left = paint with the active brush, right = erase). It only
## signals intent; the editor resolves the pointer to a hex cell and mutates the
## model — keeping all board logic in one place ("call down, signal up").

signal primary_pressed  # left click on the board: paint the active brush
signal secondary_pressed  # right click on the board: erase the cell
signal bubble_dropped(value: int)  # a palette bubble was dropped here
signal pointer_changed(over: bool)  # pointer entered / left the board region


func _ready() -> void:
	mouse_entered.connect(func() -> void: pointer_changed.emit(true))
	mouse_exited.connect(func() -> void: pointer_changed.emit(false))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			primary_pressed.emit()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			secondary_pressed.emit()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("kind") == "sphere"


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	bubble_dropped.emit(int(data["value"]))
