class_name Epilogue
extends Control

## Shown once the whole descent is complete (the final campaign level beaten) — a short,
## exhausted closing in the fiction's voice (§2.10): relief, never a fanfare. Exits to the
## main menu, like the other hub screens.

@onready var menu_button: Button = $Center/VBox/MenuButton


func _ready() -> void:
	menu_button.pressed.connect(GameState.go_to_main_menu)
	menu_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		GameState.go_to_main_menu()
