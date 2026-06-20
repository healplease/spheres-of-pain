class_name LevelEditor3D
extends Node3D

## In-game level editor. Renders an empty hex field in the SAME 3D presentation as
## play (BoardView3D for the spheres, StageView for the camera/atmosphere, FrameView
## for the border) and lets the player fill it by dragging palette bubbles, clicking,
## or pressing number keys over a cell. The board is packed into a LevelResource to
## Play (a no-progress playtest) or Save (to user://levels/). No shooter, projectile,
## or danger system lives here — only authoring.
##
## Coordinate mapping and the dotted hover ring mirror LevelController3D; the working
## board is a GridModel (the same cells dict the game plays), converted via
## LevelAuthoring. The model stays Log-free; this controller observes + logs.

const SPHERE_RADIUS := 0.46
const FRAME_THICK := 0.3
const FRAME_DEPTH := 0.6
const FIELD_CENTER_X := 640.0
const TOP_Y := 80.0

# The editable grid the player fills. The whole field is the playable area — the lose
# line sits at its bottom edge (danger_row = height), so the empty rows an author
# leaves at the bottom ARE the level's headroom (nothing is auto-added). The default
# is a tall 10x12 so there is room to fill the top and leave headroom below.
const MIN_WIDTH := 3
const MAX_WIDTH := 16
const MIN_HEIGHT := 2
const MAX_HEIGHT := 20
const DEFAULT_WIDTH := 10
const DEFAULT_HEIGHT := 12

# Screen margins (design px) kept clear of the camera frame so the board sits
# centred with equal gaps on both sides: the palette lives in the left gap, the
# inspector drawer in the right one. The field clears the drawer's open width.
const RESERVE_LEFT := 346.0
const RESERVE_RIGHT := 346.0

# The inspector drawer slides horizontally between these x positions (design px):
# open shows the whole panel in the right margin; closed parks it off-screen with
# only its handle peeking at the screen edge.
const DRAWER_OPEN_X := 934.0
const DRAWER_CLOSED_X := 1250.0
const DRAWER_SLIDE := 0.22

const BLACK_SWATCH := Color(0.08, 0.08, 0.1)  # all indestructibles share one disc

# Dotted hover-ring styling (logical px), matching the play aim-ray ring.
const RING_DOT := 6.0
const RING_GAP := 9.0
const RING_SEGMENTS := 48

const NO_TOOL := 0x7fffffff  # "no brush for this key" / dict-miss sentinel

@export var diameter := 56.0

var width := DEFAULT_WIDTH
var height := DEFAULT_HEIGHT
var model := GridModel.new()
var origin2d := Vector2(FIELD_CENTER_X, TOP_Y)

var _s := 1.0 / 56.0
var _store := UserLevels.new()
var _selected_tool := 0  # active brush: a colour id (>= 0) or BLACK/SPIN/BOUNCE
var _hover_cell := Vector2i(-999, -999)
var _has_hover := false
var _pointer_on_board := false
var _drawer_open := true
var _source_path := ""  # user:// path being edited ("" = a new, unsaved level)

var _mesh: SphereMesh
var _mats: Array[StandardMaterial3D] = []
var _specials: Dictionary
var _ring_mesh := ImmediateMesh.new()
var _ring_mat: StandardMaterial3D
var _stage_view: StageView
var _frame: FrameView
var _swatches: Array[EditorSwatch] = []

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var light: DirectionalLight3D = $DirectionalLight3D
@onready var camera: Camera3D = $Camera3D
@onready var backdrop: MeshInstance3D = $Backdrop
@onready var embers: GPUParticles3D = $Embers
@onready var board: BoardView3D = $Board
@onready var preview: MeshInstance3D = $Preview
@onready var drop_zone: EditorDropZone = $Ui/Root/DropZone
@onready var color_column: VBoxContainer = $Ui/Root/Palette/Columns/ColorColumn
@onready var black_column: VBoxContainer = $Ui/Root/Palette/Columns/BlackColumn
@onready var drawer: Control = $Ui/Root/Drawer
@onready var handle: Button = $Ui/Root/Drawer/Handle
@onready var width_spin: SpinBox = $Ui/Root/Drawer/Inspector/VBox/WidthRow/WidthSpin
@onready var height_spin: SpinBox = $Ui/Root/Drawer/Inspector/VBox/HeightRow/HeightSpin
@onready var name_edit: LineEdit = $Ui/Root/Drawer/Inspector/VBox/NameEdit
@onready var tagline_edit: LineEdit = $Ui/Root/Drawer/Inspector/VBox/TaglineEdit
@onready var status_label: Label = $Ui/Root/Drawer/Inspector/VBox/Status
@onready var play_button: Button = $Ui/Root/Drawer/Inspector/VBox/PlayButton
@onready var save_button: Button = $Ui/Root/Drawer/Inspector/VBox/SaveButton
@onready var back_button: Button = $Ui/Root/Drawer/Inspector/VBox/BackButton


func to3d(p: Vector2) -> Vector3:
	return Vector3((p.x - origin2d.x) * _s, -(p.y - origin2d.y) * _s, 0.0)


func to2d(w: Vector3) -> Vector2:
	return Vector2(w.x / _s + origin2d.x, -w.y / _s + origin2d.y)


func _ready() -> void:
	_s = 1.0 / diameter
	# Preload the play scene off-thread so a playtest (play_draft) swaps in instantly.
	GameState.preload_play_scene()
	_build_visual_assets()

	_stage_view = StageView.new()
	add_child(_stage_view)
	_stage_view.reserve_left = RESERVE_LEFT
	_stage_view.reserve_right = RESERVE_RIGHT
	_stage_view.setup(world_env, light, camera, backdrop, embers)

	_restore_or_blank()
	model.num_colors = 10  # every palette colour is placeable while authoring
	model.danger_row = height  # lose line at the field's bottom edge (see LevelAuthoring)
	board.setup(model, _mesh, _mats, _specials, diameter)

	preview.mesh = _ring_mesh
	preview.material_override = _ring_mat

	_build_palette()
	_wire_inspector()
	drop_zone.focus_mode = Control.FOCUS_CLICK  # clicking the board steals focus from text fields
	drop_zone.primary_pressed.connect(_paint_at_pointer)
	drop_zone.secondary_pressed.connect(_erase_at_pointer)
	drop_zone.bubble_dropped.connect(_drop_at_pointer)
	drop_zone.pointer_changed.connect(_on_pointer_changed)

	_reframe()
	_stage_view.apply_theme(LevelResource.new())
	_select_tool(0)
	drop_zone.grab_focus()  # so number keys place bubbles before any click
	_refresh_status()
	Log.info(
		Log.FLOW,
		"editor ready",
		{"mode": "edit" if _source_path != "" else "create", "size": "%dx%d" % [width, height]}
	)


# --- setup --------------------------------------------------------------------


func _build_visual_assets() -> void:
	var assets := SphereAssets.new(SPHERE_RADIUS)
	_mesh = assets.mesh
	_mats = assets.mats
	_specials = assets.specials
	_ring_mat = assets.preview_mat


## Start from the editor draft (a returning playtest, or a saved level opened to edit)
## or, with no draft, a blank minimal field. Height is the draft's danger_row, which
## LevelAuthoring stores at the field's bottom edge (danger_row = height).
func _restore_or_blank() -> void:
	_source_path = GameState.editor_source_path
	var draft := GameState.editor_draft
	if draft != null:
		width = clampi(draft.width, MIN_WIDTH, MAX_WIDTH)
		height = clampi(draft.danger_row, MIN_HEIGHT, MAX_HEIGHT)
		model = draft.build_model()
		model.width = width
		name_edit.text = draft.title
		tagline_edit.text = draft.lore_fragment
	else:
		width = DEFAULT_WIDTH
		height = DEFAULT_HEIGHT
		model = GridModel.new()
		model.width = width
	_prune_out_of_bounds()


func _build_palette() -> void:
	for i in range(BoardView3D.PALETTE.size()):
		_add_swatch(color_column, i, BoardView3D.PALETTE[i])
	# The "black bubbles" column: every indestructible shares the black disc; the
	# swatch draws an S / B glyph to mark Spin / Bounce.
	_add_swatch(black_column, GridModel.BLACK, BLACK_SWATCH)
	_add_swatch(black_column, GridModel.SPIN, BLACK_SWATCH)
	_add_swatch(black_column, GridModel.BOUNCE, BLACK_SWATCH)


func _add_swatch(column: VBoxContainer, value: int, color: Color) -> void:
	var sw := EditorSwatch.new()
	column.add_child(sw)
	sw.setup(value, color)
	sw.selected.connect(_select_tool)
	_swatches.append(sw)


func _wire_inspector() -> void:
	width_spin.min_value = MIN_WIDTH
	width_spin.max_value = MAX_WIDTH
	width_spin.value = width
	height_spin.min_value = MIN_HEIGHT
	height_spin.max_value = MAX_HEIGHT
	height_spin.value = height
	# Set values BEFORE connecting so the seed values don't fire a spurious rebuild.
	width_spin.value_changed.connect(_on_dimension_changed)
	height_spin.value_changed.connect(_on_dimension_changed)
	name_edit.text_changed.connect(func(_t: String) -> void: _refresh_status())
	play_button.pressed.connect(_on_play)
	save_button.pressed.connect(_on_save)
	back_button.pressed.connect(GameState.go_to_my_levels)
	handle.pressed.connect(_toggle_drawer)


## Slide the inspector in/out. The field is framed clear of the open drawer, so this
## is purely to declutter the view — the handle stays reachable at the screen edge.
func _toggle_drawer() -> void:
	_drawer_open = not _drawer_open
	handle.text = "›" if _drawer_open else "‹"
	var target_x := DRAWER_OPEN_X if _drawer_open else DRAWER_CLOSED_X
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(drawer, "position:x", target_x, DRAWER_SLIDE)


# --- field geometry -----------------------------------------------------------


func _layout_field() -> void:
	# Centre the field on FIELD_CENTER_X, exactly like the play controller.
	origin2d = Vector2(FIELD_CENTER_X - diameter * (width * 0.5 - 0.25), TOP_Y)


## World-space bounds (left_x, right_x, top_y, bot_y) of the editable grid, padded
## outward by `pad`. Mirrors LevelController3D._frame_bounds but spans the authored
## rows (0..height-1) rather than a play danger line.
func _frame_bounds(pad: float) -> Vector4:
	var row_step := diameter * Hex.ROW_RATIO
	var play_left := origin2d.x - diameter * 0.5
	var play_right := origin2d.x + (width - 1) * diameter + diameter
	var top_logical := origin2d.y - diameter * 0.5
	var bot_logical := origin2d.y + (height - 1) * row_step + diameter * 0.5
	var left_x := to3d(Vector2(play_left, origin2d.y)).x - pad
	var right_x := to3d(Vector2(play_right, origin2d.y)).x + pad
	var top_y := to3d(Vector2(origin2d.x, top_logical)).y + pad
	var bot_y := to3d(Vector2(origin2d.x, bot_logical)).y - pad
	return Vector4(left_x, right_x, top_y, bot_y)


## Recompute the origin, rebuild the border, and reframe the camera/embers for the
## current width/height. Called on load and after every size change.
func _reframe() -> void:
	_layout_field()
	if _frame != null:
		_frame.queue_free()
	_frame = FrameView.new()
	_frame.name = "Frame"
	add_child(_frame)
	_frame.build(_frame_bounds(0.0), LevelResource.new().ember_color, FRAME_THICK, FRAME_DEPTH)
	_stage_view.frame(_frame_bounds(FRAME_THICK))
	_stage_view.fit_embers(_frame_bounds(0.0))


func _on_dimension_changed(_value: float) -> void:
	width = int(width_spin.value)
	height = int(height_spin.value)
	model.width = width
	model.danger_row = height
	_prune_out_of_bounds()
	board.sync()
	_reframe()
	_redraw_ring()
	_refresh_status()


func _prune_out_of_bounds() -> void:
	for cell in model.cells.keys():
		if cell.x < 0 or cell.x >= width or cell.y < 0 or cell.y >= height:
			model.cells.erase(cell)


# --- brushes / placement ------------------------------------------------------


func _select_tool(value: int) -> void:
	_selected_tool = value
	for sw in _swatches:
		sw.set_selected(sw.value == value)


func _in_grid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < height


## The grid cell under the current mouse pointer (ray cast onto the board plane,
## Z=0), or an off-grid sentinel when the ray misses.
func _cell_under_mouse() -> Vector2i:
	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	if absf(dir.z) < 0.00001:
		return Vector2i(-999, -999)
	var t := -from.z / dir.z
	if t <= 0.0:
		return Vector2i(-999, -999)
	var hit := from + dir * t
	return Hex.world_to_cell(to2d(hit), origin2d, diameter)


func _paint_at_pointer() -> void:
	_place(_selected_tool)


func _drop_at_pointer(value: int) -> void:
	_select_tool(value)
	_place(value)


## Place `value` at the cell under the pointer (no-op off-grid or when unchanged).
## Placement deliberately does NOT depend on the hover-ring gate, so a drop that lands
## on the board always takes — even if the drag suppressed enter/exit events.
func _place(value: int) -> void:
	var cell := _cell_under_mouse()
	if not _in_grid(cell):
		return
	if model.cells.get(cell, NO_TOOL) == value:
		return
	model.cells[cell] = value
	board.sync()
	_refresh_status()


func _erase_at_pointer() -> void:
	var cell := _cell_under_mouse()
	if _in_grid(cell) and model.cells.has(cell):
		model.cells.erase(cell)
		board.sync()
		_refresh_status()


# --- input --------------------------------------------------------------------


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover()


func _on_pointer_changed(over: bool) -> void:
	_pointer_on_board = over
	if over:
		_update_hover()
	else:
		_has_hover = false
		_redraw_ring()


## Number keys place at the hovered cell; Shift+1/2/3 place the indestructibles;
## Delete/Backspace erase; Esc leaves. Only reaches here when no LineEdit consumed
## the key, so typing a level name never drops bubbles.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	if key.keycode == KEY_ESCAPE:
		GameState.go_to_my_levels()
		return
	if key.keycode == KEY_DELETE or key.keycode == KEY_BACKSPACE:
		_erase_at_pointer()
		return
	var tool := _tool_for_key(key.keycode, key.shift_pressed)
	if tool == NO_TOOL:
		return
	_select_tool(tool)
	_place(tool)


## Map a key to a brush: 1-9 -> colours 0-8, 0 -> colour 9; with Shift, 1/2/3 ->
## Black/Spin/Bounce. NO_TOOL for anything else.
func _tool_for_key(keycode: int, shift: bool) -> int:
	var tool := NO_TOOL
	if shift:
		match keycode:
			KEY_1:
				tool = GridModel.BLACK
			KEY_2:
				tool = GridModel.SPIN
			KEY_3:
				tool = GridModel.BOUNCE
	elif keycode == KEY_0:
		tool = 9
	elif keycode >= KEY_1 and keycode <= KEY_9:
		tool = keycode - KEY_1  # KEY_1 -> 0 ... KEY_9 -> 8
	return tool


# --- hover ring ---------------------------------------------------------------


func _update_hover() -> void:
	var cell := _cell_under_mouse()
	var valid := _pointer_on_board and _in_grid(cell)
	if valid != _has_hover or cell != _hover_cell:
		_has_hover = valid
		_hover_cell = cell
		_redraw_ring()


## Draw the dotted circle over the hovered cell (or clear it). Same dot walk the play aim ray
## uses for its landing ring (see DottedPath), lifted slightly toward the camera.
func _redraw_ring() -> void:
	_ring_mesh.clear_surfaces()
	if not _has_hover:
		return
	_ring_mat.albedo_color = Color(0.92, 0.86, 0.86, 0.8)
	var center := Hex.cell_to_world(_hover_cell, origin2d, diameter)
	var ring := DottedPath.ring_points(center, diameter * SPHERE_RADIUS, RING_SEGMENTS)
	_ring_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	DottedPath.emit(_ring_mesh, ring, RING_DOT, RING_GAP, to3d)
	_ring_mesh.surface_end()


# --- play / save --------------------------------------------------------------


func _build_level() -> LevelResource:
	return LevelAuthoring.to_level(
		model, height, name_edit.text.strip_edges(), tagline_edit.text.strip_edges()
	)


func _on_play() -> void:
	var lv := _build_level()
	var problems := lv.validate()
	if not problems.is_empty():
		_show_problems(problems)
		return
	# Keep the path we're editing so a Save after the playtest still overwrites it.
	GameState.editor_source_path = _source_path
	GameState.play_draft(lv)


func _on_save() -> void:
	if name_edit.text.strip_edges().is_empty():
		_warn("Name your level before saving.")
		return
	var lv := _build_level()
	var problems := lv.validate()
	if not problems.is_empty():
		_show_problems(problems)
		return
	var path := _source_path if _source_path != "" else _store.unique_path(lv.title)
	var err := _store.save(lv, path)
	if err != OK:
		_warn("Save failed (error %d)." % err)
		return
	_source_path = path
	GameState.editor_source_path = path
	GameState.editor_draft = lv  # a later Play uses the saved version
	status_label.text = 'Saved "%s".' % lv.title
	status_label.modulate = Color(0.6, 0.8, 0.55)
	Log.info(Log.FLOW, "level saved", {"title": lv.title, "path": path})


# --- status line --------------------------------------------------------------


## Live feedback: the field summary when valid, else the first blocking problem.
func _refresh_status() -> void:
	var problems := _build_level().validate()
	if problems.is_empty():
		status_label.text = "%d x %d   %d spheres   ready" % [width, height, model.count_colored()]
		status_label.modulate = Color(0.72, 0.68, 0.74)
	else:
		status_label.text = problems[0]
		status_label.modulate = Color(0.82, 0.62, 0.42)


func _show_problems(problems: PackedStringArray) -> void:
	status_label.text = "Can't play yet: " + problems[0]
	status_label.modulate = Color(0.86, 0.4, 0.4)


func _warn(msg: String) -> void:
	status_label.text = msg
	status_label.modulate = Color(0.86, 0.4, 0.4)
