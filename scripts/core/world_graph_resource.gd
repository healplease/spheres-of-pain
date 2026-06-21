class_name WorldGraphResource
extends Resource

## The whole branching descent: every MapNodeResource plus the single node that is open on a
## fresh save. Pure data — GameState loads + caches it like regions(), the world-map view walks
## `nodes` to place markers and roads, and WorldUnlock derives availability from it. Headless and
## Log-free so it (and the graph shape) can be unit-tested without the scene tree.

@export var nodes: Array[MapNodeResource] = []
## The one node available with an empty completed-set (the very first descent node). It must have
## empty prerequisites; this field just names it so the view can frame/focus the start.
@export var start_node_id: int = 1

# Lazy id -> MapNodeResource index, built on first lookup (a broken/edited graph never crashes a
# query; a missing id just resolves to null).
var _by_id: Dictionary = {}


## The node with this id, or null if none. O(1) after the first call.
func node(id: int) -> MapNodeResource:
	if _by_id.is_empty():
		_index()
	return _by_id.get(id, null)


func has_node(id: int) -> bool:
	if _by_id.is_empty():
		_index()
	return _by_id.has(id)


func node_ids() -> PackedInt32Array:
	var out := PackedInt32Array()
	for n in nodes:
		out.append(n.id)
	return out


func _index() -> void:
	for n in nodes:
		_by_id[n.id] = n


## Human-readable list of structural problems; empty means the graph is well-formed. Called by
## tests (not at runtime): duplicate ids, dangling prerequisite/successor references, and a
## start_node_id that doesn't exist. Per-node level/objective validity is LevelResource.validate().
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	var seen := {}
	for n in nodes:
		if seen.has(n.id):
			problems.append("duplicate node id %d" % n.id)
		seen[n.id] = true
	for n in nodes:
		for p in n.prerequisites:
			if not seen.has(p):
				problems.append("node %d: prerequisite %d does not exist" % [n.id, p])
		for s in n.successors:
			if not seen.has(s):
				problems.append("node %d: successor %d does not exist" % [n.id, s])
	if not seen.has(start_node_id):
		problems.append("start_node_id %d does not exist" % start_node_id)
	return problems
