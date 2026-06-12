class_name MainMenu
extends Control

## Title screen. The only place in the game that quits the application.

@onready var select_level_button: Button = $Center/VBox/SelectLevelButton


func _ready() -> void:
	# Seed keyboard focus so arrows + Enter work without a first mouse click.
	select_level_button.grab_focus()


func _on_select_level_pressed() -> void:
	GameState.go_to_level_select()


func _on_quit_pressed() -> void:
	get_tree().quit()
