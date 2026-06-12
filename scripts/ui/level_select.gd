class_name LevelSelect
extends Control

## Level grid: ten buttons authored in the scene, populated from the level
## files at runtime. Locked levels are disabled (sequential unlock).

@onready var grid: GridContainer = $Center/VBox/Grid


func _ready() -> void:
	var focus_target: Button = null
	for i in range(1, GameState.LEVEL_COUNT + 1):
		var button := grid.get_node("Level%d" % i) as Button
		var lv := GameState.load_level(i)
		if lv == null:
			button.text = "%d\n—" % i
			button.disabled = true
			button.focus_mode = Control.FOCUS_NONE
			continue
		button.text = "%d\n%s" % [i, lv.title]
		var unlocked := GameState.progress.is_unlocked(i)
		button.disabled = not unlocked
		# Locked levels drop out of the arrow-key focus chain entirely.
		button.focus_mode = Control.FOCUS_ALL if unlocked else Control.FOCUS_NONE
		button.tooltip_text = lv.lore_fragment if unlocked else "Locked. The way down is earned."
		button.pressed.connect(GameState.start_level.bind(i))
		if unlocked:
			focus_target = button   # highest unlocked = the next level to play
	if focus_target != null:
		focus_target.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		GameState.go_to_main_menu()


func _on_back_pressed() -> void:
	GameState.go_to_main_menu()
