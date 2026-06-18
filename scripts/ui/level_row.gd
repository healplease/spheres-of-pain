class_name LevelRow
extends PanelContainer

## One entry in the My Levels list: the level's title plus Play / Edit / Delete.
## A runtime-instanced scene (one per saved level on the page); it carries the
## level's user:// path and signals the screen, which owns the navigation + the
## delete confirmation ("call down, signal up").

signal play_requested(path: String)
signal edit_requested(path: String)
signal delete_requested(path: String)

var _path := ""

@onready var title_label: Label = $HBox/TitleLabel
@onready var play_button: Button = $HBox/PlayButton
@onready var edit_button: Button = $HBox/EditButton
@onready var delete_button: Button = $HBox/DeleteButton


func setup(entry: Dictionary) -> void:
	_path = String(entry.get("path", ""))
	var title := String(entry.get("title", "")).strip_edges()
	title_label.text = title if not title.is_empty() else "(untitled)"
	play_button.pressed.connect(func() -> void: play_requested.emit(_path))
	edit_button.pressed.connect(func() -> void: edit_requested.emit(_path))
	delete_button.pressed.connect(func() -> void: delete_requested.emit(_path))
