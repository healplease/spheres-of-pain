extends GutTest

## Smoke tests for the editor + My Levels scenes: they must instantiate and run
## _ready() without errors. This catches broken @onready node paths and scene wiring
## that compile-time class loading can't — the scripts parse fine but a renamed node
## would only blow up when _ready resolves it.

const EDITOR_SCENE := preload("res://scenes/level_editor.tscn")


func test_my_levels_scene_runs_ready() -> void:
	var scene := load("res://scenes/my_levels.tscn") as PackedScene
	assert_not_null(scene, "my_levels.tscn loads")
	var inst := scene.instantiate()
	add_child_autoqfree(inst)
	await get_tree().process_frame
	assert_true(is_instance_valid(inst), "my_levels survived _ready + a frame")


func test_level_row_scene_shows_title() -> void:
	var scene := load("res://scenes/ui/level_row.tscn") as PackedScene
	var row := scene.instantiate()
	add_child_autoqfree(row)
	row.setup({"path": "user://levels/x.tres", "title": "Test Row"})
	await get_tree().process_frame
	assert_eq(row.title_label.text, "Test Row", "row reflects its title")


func test_level_editor_scene_runs_ready_and_builds_palette() -> void:
	GameState.editor_draft = null
	GameState.editor_source_path = ""
	var inst := EDITOR_SCENE.instantiate()
	add_child_autoqfree(inst)
	await get_tree().process_frame
	assert_true(is_instance_valid(inst), "level editor survived _ready + a frame")
	var color_col := inst.get_node("Ui/Root/Palette/Columns/ColorColumn")
	var black_col := inst.get_node("Ui/Root/Palette/Columns/BlackColumn")
	assert_eq(color_col.get_child_count(), 10, "ten colour swatches built")
	assert_eq(black_col.get_child_count(), 3, "three indestructible swatches built")


func test_level_editor_restores_a_draft() -> void:
	# A draft set on GameState (a returning playtest or an opened saved level) should
	# repopulate the editor's fields + board.
	var draft := LevelResource.new()
	draft.title = "Restored"
	draft.lore_fragment = "tag"
	draft.width = 6
	draft.num_colors = 3
	draft.danger_row = 5  # lose line at the field's bottom edge -> height 5
	draft.layout = PackedStringArray(["012...", "......"])
	GameState.editor_draft = draft
	GameState.editor_source_path = ""
	var inst := EDITOR_SCENE.instantiate()
	add_child_autoqfree(inst)
	await get_tree().process_frame
	assert_eq(inst.name_edit.text, "Restored", "title restored into the name field")
	assert_eq(inst.width, 6, "width restored")
	assert_eq(inst.height, 5, "height recovered from danger_row")
	assert_eq(inst.model.cells.size(), 3, "board cells restored")
	GameState.editor_draft = null
