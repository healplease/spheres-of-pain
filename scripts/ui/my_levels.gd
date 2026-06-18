class_name MyLevels
extends Control

## Paginated list of the player's own saved levels (user://levels/). Each row plays,
## edits, or deletes its level; a Create button jumps to the editor. Mirrors the
## level-select look, but the levels are discovered from disk via UserLevels and are
## always unlocked (no progression).

const ROWS_PER_PAGE := 6
const ROW_SCENE := preload("res://scenes/ui/level_row.tscn")

var _store := UserLevels.new()
var _entries: Array = []
var _page := 0
var _pending_delete := ""
var _confirm: ConfirmationDialog

@onready var list: VBoxContainer = $Center/VBox/List
@onready var empty_label: Label = $Center/VBox/Empty
@onready var page_nav: HBoxContainer = $Center/VBox/PageNav
@onready var prev_button: Button = $Center/VBox/PageNav/PrevButton
@onready var next_button: Button = $Center/VBox/PageNav/NextButton
@onready var page_label: Label = $Center/VBox/PageNav/PageLabel
@onready var create_button: Button = $Center/VBox/Footer/CreateButton
@onready var back_button: Button = $Center/VBox/Footer/BackButton


func _ready() -> void:
	prev_button.pressed.connect(_change_page.bind(-1))
	next_button.pressed.connect(_change_page.bind(1))
	create_button.pressed.connect(GameState.go_to_create_level)
	back_button.pressed.connect(GameState.go_to_level_select)
	_confirm = ConfirmationDialog.new()
	_confirm.dialog_text = "Delete this level? This cannot be undone."
	_confirm.confirmed.connect(_do_delete)
	add_child(_confirm)
	_reload()


func _pages() -> int:
	return maxi(1, ceili(float(_entries.size()) / ROWS_PER_PAGE))


func _reload() -> void:
	_entries = _store.list()
	_page = clampi(_page, 0, _pages() - 1)
	_show_page()


func _show_page() -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	empty_label.visible = _entries.is_empty()
	page_nav.visible = _entries.size() > ROWS_PER_PAGE
	var start := _page * ROWS_PER_PAGE
	for i in range(start, mini(start + ROWS_PER_PAGE, _entries.size())):
		var row := ROW_SCENE.instantiate()
		list.add_child(row)
		row.setup(_entries[i])
		row.play_requested.connect(GameState.play_user_level)
		row.edit_requested.connect(GameState.go_to_edit_level)
		row.delete_requested.connect(_ask_delete)
	page_label.text = "PAGE %d / %d" % [_page + 1, _pages()]
	prev_button.disabled = _page <= 0
	next_button.disabled = _page >= _pages() - 1
	if not _entries.is_empty():
		create_button.grab_focus()


func _change_page(delta: int) -> void:
	var target := clampi(_page + delta, 0, _pages() - 1)
	if target == _page:
		return
	_page = target
	_show_page()


func _ask_delete(path: String) -> void:
	_pending_delete = path
	_confirm.popup_centered()


func _do_delete() -> void:
	if _pending_delete == "":
		return
	Log.info(Log.FLOW, "level deleted", {"path": _pending_delete})
	_store.delete(_pending_delete)
	_pending_delete = ""
	_reload()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		GameState.go_to_level_select()
