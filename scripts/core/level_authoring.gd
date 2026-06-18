class_name LevelAuthoring
extends RefCounted

## Turns an editor's working GridModel into a serialisable LevelResource — the
## inverse of LevelResource.build_model(). Pure data, no scene tree, so it can be
## unit-tested headlessly alongside the rest of scripts/core/.
##
## The editor stores its in-progress board as a GridModel (the same cells dict the
## game uses); this packs that back into the ASCII `layout` plus the model params a
## level needs. `num_colors` is derived from the colours actually placed and
## `danger_row` from the editor's field height, so neither has to be a panel field.

## Empty rows of headroom below the authored field before the lose line, mirroring
## LevelController3D.GROWTH_BUFFER so a user level plays with the same headroom a
## free-play or built-in board gets.
const DANGER_BUFFER := 9


## The layout character for a cell value: the inverse of the parse table in
## LevelResource.build_model(). Breakables render as their digit; the three
## indestructible sentinels render as X / S / B.
static func char_for(value: int) -> String:
	match value:
		GridModel.BLACK:
			return "X"
		GridModel.SPIN:
			return "S"
		GridModel.BOUNCE:
			return "B"
		_:
			return str(value) if value >= 0 else "."


## Distinct breakable colours determine num_colors: the field must declare at least
## as many colours as the highest id placed (ids are 0-based, so +1). Clamped into
## the validator's legal [1, 10]; an empty board yields 1 (validate() then flags the
## missing breakables separately).
static func derive_num_colors(model: GridModel) -> int:
	var top := -1
	for v in model.cells.values():
		if v >= 0 and v > top:
			top = v
	return clampi(top + 1, 1, 10)


## Pack `model` (plus the editor's field height + text) into a fresh LevelResource.
## Rows are emitted 0..deepest-occupied (trailing empty rows trimmed, like the
## shipped levels); each row is padded to model.width. Theme colours keep the
## LevelResource defaults — they aren't authorable yet. The result still needs
## validate() before it is played or saved (an empty board is invalid).
static func to_level(
	model: GridModel, height: int, title: String, tagline: String
) -> LevelResource:
	var lv := LevelResource.new()
	lv.id = 0  # user levels are addressed by filename, not by a level index
	lv.title = title
	lv.lore_fragment = tagline
	lv.width = model.width
	lv.num_colors = derive_num_colors(model)
	lv.danger_row = height + DANGER_BUFFER

	var deepest := -1
	for cell in model.cells:
		if cell.y > deepest:
			deepest = cell.y

	var layout := PackedStringArray()
	for r in range(deepest + 1):
		var row := ""
		for c in range(model.width):
			var cell := Vector2i(c, r)
			row += char_for(model.cells[cell]) if model.cells.has(cell) else "."
		layout.append(row)
	lv.layout = layout
	return lv
