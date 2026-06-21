class_name RegionResource
extends Resource

## A named region of the descent: a set of world-map nodes sharing a palette, a framing line,
## and a named boss landmark. Pure data (like LevelResource) — the 3D world map reads it to tint
## the atmosphere over the region and to anchor the camera, and the Narrator keys its region
## sub-pools by `id`. Membership is now an explicit node-id set (the branching graph isn't a
## contiguous level range), and the boss/entry nodes are named so GameState can gate the descent.

@export var id: int = 0  ## region index (0-based); matches NarratorLines region_pools keys
@export var title: String = ""  ## the region's grim name (e.g. "The Ossuary")
@export_multiline var framing_line: String = ""  ## one breath of story for the region
@export var boss_name: String = ""  ## the region's named boss (its node is boss_node_id)

## Graph anchors. A region's entry node is gated on the PREVIOUS region's boss (that's the only
## door between regions); its boss node gates the NEXT region's entry. node_ids is the authoritative
## membership used by contains_node() / region_for_node().
@export var entry_node_id: int = 0
@export var boss_node_id: int = 0
@export var node_ids: PackedInt32Array = PackedInt32Array()

## Where the region sits on the single continuous map surface (the 3D view frames the camera and
## blends the environment by these). Logical map space, matching MapNodeResource.map_position.
@export_group("Map")
@export var map_center: Vector2 = Vector2.ZERO
@export var map_bounds: Rect2 = Rect2()

## Per-region atmosphere the world map blends as you drag between regions (mirrors LevelResource's
## theme accents). accent tints UI/markers; fog/ember tint the environment over the region.
@export_group("Theme")
@export var accent: Color = Color(0.78, 0.72, 0.65)
@export var fog_color: Color = Color(0.025, 0.02, 0.045)
@export var ember_color: Color = Color(1.0, 0.62, 0.3)


## Whether a world-map node id belongs to this region.
func contains_node(node_id: int) -> bool:
	return node_ids.has(node_id)
