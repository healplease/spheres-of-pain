class_name MapDetailPanel
extends Control

## The right-half detail window that fades in when a node is selected: the level's name, region,
## lore, and an at-a-glance "what to expect" (objective + hazards + par, derived from the level
## data — or the node's authored summary), with a Descend button and a Back button. Built in code
## and parented to the world map's UI layer; it owns its own fade (the CenterBanner idiom).

signal descend_pressed(id: int)
signal back_pressed

const FADE := 0.4
const FRAMING := Color(0.62, 0.58, 0.62)

var _id := -1
var _title: Label
var _region: Label
var _desc: RichTextLabel
var _expect: Label
var _best: Label
var _descend: Button
var _back: Button


func _ready() -> void:
	# Right half of the screen, full height.
	anchor_left = 0.5
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.025, 0.04, 0.86)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 56)
	margin.add_theme_constant_override("margin_right", 56)
	margin.add_theme_constant_override("margin_top", 80)
	margin.add_theme_constant_override("margin_bottom", 64)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	_region = Label.new()
	_region.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_region)

	_title = Label.new()
	_title.theme_type_variation = &"TitleText"
	_title.add_theme_font_size_override("font_size", 44)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_title)

	_desc = RichTextLabel.new()
	_desc.fit_content = true
	_desc.scroll_active = false
	_desc.bbcode_enabled = false
	_desc.add_theme_color_override("default_color", Color(0.84, 0.82, 0.82))
	_desc.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	vbox.add_child(_desc)

	vbox.add_child(_gap(8))

	var expect_head := Label.new()
	expect_head.text = "WHAT TO EXPECT"
	expect_head.add_theme_font_size_override("font_size", 15)
	expect_head.add_theme_color_override("font_color", FRAMING)
	vbox.add_child(expect_head)

	_expect = Label.new()
	_expect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_expect.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_expect)

	_best = Label.new()
	_best.add_theme_font_size_override("font_size", 16)
	_best.add_theme_color_override("font_color", Color(0.55, 0.7, 0.5))
	vbox.add_child(_best)

	vbox.add_child(_gap(0, true))  # expands, pushing the buttons to the bottom

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	vbox.add_child(buttons)

	_descend = Button.new()
	_descend.text = "DESCEND"
	_descend.custom_minimum_size = Vector2(160, 52)
	_descend.pressed.connect(func() -> void: descend_pressed.emit(_id))
	buttons.add_child(_descend)

	_back = Button.new()
	_back.text = "BACK"
	_back.custom_minimum_size = Vector2(120, 52)
	_back.pressed.connect(func() -> void: back_pressed.emit())
	buttons.add_child(_back)

	visible = false
	modulate.a = 0.0


func is_open() -> bool:
	return visible


## Populate + fade the panel in for a node. `best` is "" unless the level has been beaten before.
func open(
	level: LevelResource, node: MapNodeResource, region: RegionResource, best: String
) -> void:
	_id = node.id
	_title.text = level.title
	if region != null:
		_region.text = region.title.to_upper()
		_region.add_theme_color_override("font_color", region.accent)
	else:
		_region.text = ""
	_desc.text = level.lore_fragment
	_expect.text = node.summary if not node.summary.is_empty() else _derive_expectation(level)
	_best.text = best
	_best.visible = not best.is_empty()
	visible = true
	_kill_fade()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, FADE)
	set_meta("fade", tw)
	_descend.grab_focus()


func close() -> void:
	_kill_fade()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, FADE)
	tw.tween_callback(func() -> void: visible = false)
	set_meta("fade", tw)


# --- helpers ------------------------------------------------------------------


## Build the at-a-glance "what to expect" line from the level's objective + modifiers + board.
func _derive_expectation(level: LevelResource) -> String:
	var parts := PackedStringArray()
	match level.objective_type:
		LevelResource.Objective.FREE_SOUL:
			parts.append("Free the caged soul.")
		LevelResource.Objective.CLEANSE:
			parts.append("Cleanse the cursed cell.")
		_:
			parts.append("Empty the wall.")
	parts.append("%d colours." % level.num_colors)
	if _has_char(level, "S"):
		parts.append("Spin-stones turn the colours as you land.")
	if _has_char(level, "B"):
		parts.append("Bounce-stones deflect your shot.")
	if level.tide_rows_per_shot > 0:
		parts.append("The dark tide rises with every shot.")
	if level.shot_budget > 0:
		parts.append("Only %d shots — make them count." % level.shot_budget)
	if level.par_shots > 0:
		parts.append("Par: %d shots." % level.par_shots)
	return " ".join(parts)


func _has_char(level: LevelResource, ch: String) -> bool:
	for row in level.layout:
		if ch in row or ch.to_lower() in row:
			return true
	return false


func _gap(h: int, expand := false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


func _kill_fade() -> void:
	if has_meta("fade"):
		var tw: Tween = get_meta("fade")
		if tw != null and tw.is_valid():
			tw.kill()
