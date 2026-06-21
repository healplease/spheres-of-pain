class_name MapNodeResource
extends Resource

## One node on the world map: a single level's place in the branching descent. Pure data
## (like LevelResource / RegionResource) — the world-map view reads it to place a marker and
## draw roads, WorldUnlock reads it to derive availability, and tests read it to check the
## graph is well-formed. Nothing here touches the scene tree.
##
## Every node is a playable level (`id` == campaign level index, 1:1 with levels/level_NN.tres).
## Dead-ends are ordinary completable levels that simply have no `successors` (no road onward) —
## winning them reveals lore but advances nothing.

## What role the node plays in its region's topology. Mostly descriptive (the renderer styles
## roads/markers by it); the actual gating is in `prerequisites`. ENTRY = a region's first node;
## SPINE = on the main path to the boss; BRANCH/CROSSROAD = optional side paths (CROSSROAD has
## >=2 successors — a real fork); DEAD_END = optional, no successors; BOSS = the region's gate out.
enum Kind { ENTRY, SPINE, BRANCH, CROSSROAD, DEAD_END, BOSS }

## How multiple prerequisites combine into "is this node reachable yet". ANY (default) is an
## OR-gate: a merge node opens as soon as EITHER inbound road is cleared. ALL is an AND-gate:
## the node waits for every inbound road. A node with 0 or 1 prerequisite ignores this.
enum Gate { ANY, ALL }

@export var id: int = 0  ## unique node id across the whole map; == campaign level index (1..30)
@export var region_id: int = 0  ## which RegionResource.id this node sits in
@export var node_kind: Kind = Kind.SPINE
## Position on the single continuous world surface, in the map's own logical 2D space
## (the 3D view lifts it onto the Z=0 plane via its own to3d). Authoring-space, not world metres.
@export var map_position: Vector2 = Vector2.ZERO
## The node ids that gate this node's availability. Empty = no prerequisites (a start/entry node
## that is reachable from the outset). This is the SINGLE SOURCE OF TRUTH for unlocking; the rule
## in WorldUnlock reads only this (+ gate_mode). A region's entry node lists the PREVIOUS region's
## boss id here, which is what makes the boss the only door between regions.
@export var prerequisites: PackedInt32Array = PackedInt32Array()
@export var gate_mode: Gate = Gate.ANY  ## how `prerequisites` combine (default OR / merge)
## Outgoing edges, for the renderer (draw a road from here to each) and for fork/merge topology.
## Redundant with the successors' `prerequisites` (which is authoritative) but convenient. The
## first entry is treated as the SPINE/primary road; extras are optional branches.
@export var successors: PackedInt32Array = PackedInt32Array()
## Optional authored "what to expect" line for the detail panel; when empty the panel derives a
## summary from the level's objective + modifiers. Lore proper lives in LevelResource.lore_fragment.
@export_multiline var summary: String = ""


func is_boss() -> bool:
	return node_kind == Kind.BOSS


func is_dead_end() -> bool:
	return node_kind == Kind.DEAD_END
