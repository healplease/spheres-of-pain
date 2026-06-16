extends GutTest

## Smoke test for the reusable Hint tooltip. It's a view (needs the tree to size/show),
## so this just exercises the public contract headlessly: starts hidden, shows the text
## given to it, ignores empty text, and hides on request.


func _hint() -> Hint:
	var h: Hint = load("res://scenes/ui/hint.tscn").instantiate()
	add_child_autofree(h)
	return h


func test_starts_hidden() -> void:
	var h := _hint()
	await wait_frames(1)
	assert_false(h.visible, "hint is hidden until asked to show")


func test_show_sets_text_and_reveals() -> void:
	var h := _hint()
	await wait_frames(1)
	h.show_hint("a description")
	assert_true(h.visible, "shown after show_hint")
	assert_eq(h.get_node("Label").text, "a description", "label carries the hint text")


func test_empty_text_stays_hidden() -> void:
	var h := _hint()
	await wait_frames(1)
	h.show_hint("")
	assert_false(h.visible, "empty text never shows the hint")


func test_hide_hint() -> void:
	var h := _hint()
	await wait_frames(1)
	h.show_hint("x")
	h.hide_hint()
	assert_false(h.visible, "hidden after hide_hint")
