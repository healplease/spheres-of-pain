class_name DescentMap
extends Control

## The campaign hub as a single vertical descent (there is only ever down): the regions
## stacked top→bottom, each a framing header + its levels + a named boss landmark. Replaces
## the old paged level grid. The column is built from data — GameState.regions() + the level
## files — so it always reflects the authored regions; the unlock + focus logic mirrors the
## old level select (sequential unlock, locked buttons drop out of the focus chain).

const LEVEL_MIN_HEIGHT := 60.0
const FRAMING_COLOR := Color(0.6, 0.56, 0.6, 1)  # dim region framing line

var _focus_target: Button = null  # furthest-unlocked level button — gets focus + is scrolled to

@onready var scroll: ScrollContainer = $Root/Scroll
@onready var column: VBoxContainer = $Root/Scroll/Column
@onready var back_button: Button = $Root/BackButton


func _ready() -> void:
	_build_column()
	back_button.pressed.connect(GameState.go_to_main_menu)
	# Land on the next level to play (the furthest unlocked) and scroll it into view, so a
	# return trip doesn't always dump you at the top of the descent.
	if _focus_target != null:
		_focus_target.grab_focus()
		scroll.ensure_control_visible.call_deferred(_focus_target)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		GameState.go_to_main_menu()


# --- column build -------------------------------------------------------------


func _build_column() -> void:
	for region in GameState.regions():
		_add_region(region)


func _add_region(region: RegionResource) -> void:
	if column.get_child_count() > 0:
		column.add_child(_spacer(18.0))  # breathing room between regions
	column.add_child(_region_name(region))
	column.add_child(_region_framing(region))
	for idx in range(region.first_level, region.last_level + 1):
		_add_level_button(idx)
	column.add_child(_boss_landmark(region))


func _region_name(region: RegionResource) -> Label:
	var l := Label.new()
	l.text = region.title
	l.theme_type_variation = &"TitleText"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 34)
	l.add_theme_color_override("font_color", region.accent)
	return l


func _region_framing(region: RegionResource) -> Label:
	var l := Label.new()
	l.text = region.framing_line
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", FRAMING_COLOR)
	return l


## The region's boss as a non-interactive landmark at the foot of its block — named, but its
## board is deferred (E1.5), so it reads as a sealed door, not a button.
func _boss_landmark(region: RegionResource) -> Label:
	var l := Label.new()
	l.text = "—  %s keeps the dark below  —" % region.boss_name
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", region.accent.lerp(Color(0.1, 0.1, 0.12, 1), 0.45))
	return l


func _add_level_button(idx: int) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, LEVEL_MIN_HEIGHT)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lv := GameState.load_level(idx)
	if lv == null:
		# A broken data file degrades to a disabled slot, not a crash (mirrors level select).
		b.text = "%d   —" % idx
		b.disabled = true
		b.focus_mode = Control.FOCUS_NONE
		column.add_child(b)
		return
	b.text = "%d   %s" % [idx, lv.title]
	var unlocked := GameState.progress.is_unlocked(idx)
	b.disabled = not unlocked
	# Locked levels drop out of the arrow-key focus chain entirely.
	b.focus_mode = Control.FOCUS_ALL if unlocked else Control.FOCUS_NONE
	b.tooltip_text = lv.lore_fragment if unlocked else "Locked. The way down is earned."
	if unlocked:
		b.pressed.connect(GameState.start_level.bind(idx))
		_focus_target = b  # ascending build → the last unlocked seen is the furthest down
	column.add_child(b)


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
