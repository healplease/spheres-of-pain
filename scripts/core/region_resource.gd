class_name RegionResource
extends Resource

## A named region of the descent: a contiguous block of campaign levels sharing a palette,
## a framing line, and a named boss landmark. Pure data (like LevelResource) — the descent
## map reads it to group + tint the level column, and the Narrator keys region sub-pools by
## `id`. The boss *boards* are deferred (E1.5); only the boss *name* is framing for now.

@export var id: int = 0  # region index (0-based); matches NarratorLines region_pools keys
@export var title: String = ""  # the region's grim name (e.g. "The Ossuary")
@export var first_level: int = 1  # inclusive campaign level index of the region's first level
@export var last_level: int = 5  # inclusive index of the last
@export_multiline var framing_line: String = ""  # one breath, shown atop the region in the map
@export var boss_name: String = ""  # the region's named boss landmark (its board lands in E1.5)

## Region tint for the descent-map section header (mirrors LevelResource's theme accents).
@export_group("Theme")
@export var accent: Color = Color(0.78, 0.72, 0.65)


## Whether a campaign level index falls inside this region (inclusive both ends).
func contains(level_index: int) -> bool:
	return level_index >= first_level and level_index <= last_level
