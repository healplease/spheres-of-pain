class_name WorldUnlock
extends RefCounted

## Pure progression logic: given the world graph and the set of completed node ids, derive each
## node's display state. No nodes, no logging, no engine singletons — unit-testable headlessly
## exactly like Scoring / GridModel. The world-map view calls all_states() once per open and
## colours markers from it; GameState exposes thin wrappers (node_state / available_ids).
##
## The whole branching topology falls out of ONE rule with no special-casing:
##   * a FORK (1 node -> 2) = both children list the parent as a prerequisite; completing the
##     parent satisfies both, so both become AVAILABLE at once.
##   * a MERGE (2 -> 1) = the child lists both parents as prerequisites with gate_mode ANY, so it
##     opens on EITHER (set ALL to require both).
##   * a REGION GATE = a region's entry node lists the previous region's boss as its prerequisite,
##     so the boss is structurally the only door onward.

enum State { LOCKED, AVAILABLE, COMPLETED }


## State of a single node. COMPLETED if its id is in `completed` (a Dictionary used as a set:
## id -> true, for O(1) membership); else AVAILABLE if its prerequisites are met; else LOCKED.
static func node_state(graph: WorldGraphResource, id: int, completed: Dictionary) -> State:
	if completed.has(id):
		return State.COMPLETED
	var n := graph.node(id)
	if n == null:
		return State.LOCKED
	if _prereqs_met(n, completed):
		return State.AVAILABLE
	return State.LOCKED


## Whole-map id -> State. One call per map open; the view reads marker colours from it.
static func all_states(graph: WorldGraphResource, completed: Dictionary) -> Dictionary:
	var out := {}
	for n in graph.nodes:
		out[n.id] = node_state(graph, n.id, completed)
	return out


## Every currently-reachable (AVAILABLE) node id — for focus targeting / "where can I go now".
static func available_ids(graph: WorldGraphResource, completed: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	for n in graph.nodes:
		if node_state(graph, n.id, completed) == State.AVAILABLE:
			out.append(n.id)
	return out


## Are this node's prerequisites satisfied by the completed set? Empty prerequisites => met (the
## start/entry node is always reachable). ALL = every prerequisite completed; ANY = at least one.
static func _prereqs_met(n: MapNodeResource, completed: Dictionary) -> bool:
	if n.prerequisites.is_empty():
		return true
	if n.gate_mode == MapNodeResource.Gate.ALL:
		for p in n.prerequisites:
			if not completed.has(p):
				return false
		return true
	for p in n.prerequisites:
		if completed.has(p):
			return true
	return false
