extends GutTest

## Smoke test for the Settings scene: instantiating it must run every tab builder
## in scripts/ui/settings.gd without error and produce the expected rows. This covers
## the one path the store/flow tests don't — the data-driven UI generation (OptionButton
## population, slider seeding, signal wiring) — so a broken builder fails headless here
## instead of only when a player opens the menu.


func _open() -> SettingsScene:
	var scene: SettingsScene = load("res://scenes/settings.tscn").instantiate()
	add_child_autofree(scene)
	return scene


func _tab(scene: SettingsScene, name: String) -> VBoxContainer:
	return scene.get_node("Center/VBox/Tabs/" + name)


func test_scene_builds_all_tab_rows() -> void:
	var scene := _open()
	await wait_frames(1)
	assert_eq(
		_tab(scene, "Gameplay").get_child_count(),
		3,
		"Gameplay: shooting controls + aim + true random rows"
	)
	assert_eq(_tab(scene, "Display").get_child_count(), 4, "Display: mode/resolution/vsync/fps")
	assert_eq(
		_tab(scene, "Graphics").get_child_count(),
		6,
		"Graphics: aa/shadows/ssao/glow + text glitch + effects intensity"
	)
	assert_eq(_tab(scene, "Audio").get_child_count(), 5, "Audio: master + 4 channels")


func test_volume_percent_formatting() -> void:
	# The audio sliders store 0–1 but read out as whole percents.
	assert_eq(SettingsScene._percent(0.0), "0%", "muted reads 0%")
	assert_eq(SettingsScene._percent(0.5), "50%", "half reads 50%")
	assert_eq(SettingsScene._percent(1.0), "100%", "full reads 100%")
	assert_eq(SettingsScene._percent(0.07), "7%", "rounds to the nearest whole percent")


func test_resolution_dropdown_has_entries() -> void:
	var scene := _open()
	await wait_frames(1)
	# Each row is an HBox(label, control); the control is its second child. Resolution
	# is the 2nd Display row.
	var res_row: HBoxContainer = _tab(scene, "Display").get_child(1)
	var control: Control = res_row.get_child(1)
	assert_true(control is OptionButton, "resolution control is an OptionButton")
	assert_gt((control as OptionButton).item_count, 0, "resolution list is never empty")
