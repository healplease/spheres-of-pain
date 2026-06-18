class_name LevelSelect
extends Control

## Paged level grid: ten buttons authored in the scene form one reusable page,
## repopulated from the level files as the player flips pages. Page 1 is levels
## 1-10, page 2 is 11-20 (only 11-15 exist today; the rest render as empty slots).
## Locked levels are disabled (sequential unlock).

const LEVELS_PER_PAGE := 10

var _page := 0

@onready var grid: GridContainer = $Center/VBox/Grid
@onready var prev_button: Button = $Center/VBox/PageNav/PrevButton
@onready var next_button: Button = $Center/VBox/PageNav/NextButton
@onready var page_label: Label = $Center/VBox/PageNav/PageLabel
@onready var my_levels_button: Button = $Center/VBox/EditorNav/MyLevelsButton
@onready var create_button: Button = $Center/VBox/EditorNav/CreateButton


func _pages() -> int:
	return int(ceil(float(GameState.LEVEL_COUNT) / LEVELS_PER_PAGE))


func _ready() -> void:
	# Wire each slot once; the handler resolves the live level index from the page, so
	# flipping pages never restacks connections.
	for s in range(1, LEVELS_PER_PAGE + 1):
		var button := grid.get_node("Level%d" % s) as Button
		button.pressed.connect(_on_slot_pressed.bind(s))
	prev_button.pressed.connect(_change_page.bind(-1))
	next_button.pressed.connect(_change_page.bind(1))
	my_levels_button.pressed.connect(GameState.go_to_my_levels)
	create_button.pressed.connect(GameState.go_to_create_level)
	# Open on the page holding the player's furthest descent, so a return trip lands
	# near the next level rather than always at page 1.
	@warning_ignore("integer_division")
	var landing := (GameState.progress.highest_unlocked - 1) / LEVELS_PER_PAGE
	_page = clampi(landing, 0, _pages() - 1)
	_show_page()


## Populate the ten slots for the current page and refresh the nav controls. A focus
## target (the highest unlocked level on the page) grabs focus so the keyboard lands
## on the next level to play.
func _show_page() -> void:
	var focus_target: Button = null
	for s in range(1, LEVELS_PER_PAGE + 1):
		var button := grid.get_node("Level%d" % s) as Button
		var idx := _page * LEVELS_PER_PAGE + s
		if idx > GameState.LEVEL_COUNT:
			button.text = "—"
			button.disabled = true
			button.focus_mode = Control.FOCUS_NONE
			button.tooltip_text = ""
			continue
		var lv := GameState.load_level(idx)
		if lv == null:
			button.text = "%d\n—" % idx
			button.disabled = true
			button.focus_mode = Control.FOCUS_NONE
			continue
		button.text = "%d\n%s" % [idx, lv.title]
		var unlocked := GameState.progress.is_unlocked(idx)
		button.disabled = not unlocked
		# Locked levels drop out of the arrow-key focus chain entirely.
		button.focus_mode = Control.FOCUS_ALL if unlocked else Control.FOCUS_NONE
		button.tooltip_text = lv.lore_fragment if unlocked else "Locked. The way down is earned."
		if unlocked:
			focus_target = button  # highest unlocked on this page = the next to play
	page_label.text = "PAGE %d / %d" % [_page + 1, _pages()]
	prev_button.disabled = _page <= 0
	next_button.disabled = _page >= _pages() - 1
	if focus_target != null:
		focus_target.grab_focus()
	elif not prev_button.disabled:
		prev_button.grab_focus()
	elif not next_button.disabled:
		next_button.grab_focus()


func _change_page(delta: int) -> void:
	var target := clampi(_page + delta, 0, _pages() - 1)
	if target == _page:
		return
	_page = target
	_show_page()


func _on_slot_pressed(slot: int) -> void:
	var idx := _page * LEVELS_PER_PAGE + slot
	if idx <= GameState.LEVEL_COUNT:
		GameState.start_level(idx)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		GameState.go_to_main_menu()


func _on_back_pressed() -> void:
	GameState.go_to_main_menu()
