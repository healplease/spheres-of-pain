extends GutTest

## Pure unlock-derivation tests on a small hand-built fixture graph (a fork, two merges, a
## dead-end, and a region gate) so they don't depend on the 30 authored level files. Asserts the
## one WorldUnlock rule produces the whole branching topology: forks open both children, merges
## are OR/AND gates, region entries wait on the prior boss, and dead-ends never block the spine.

const S := WorldUnlock.State


# region0: 1(entry) -> 2(spine) -> 3(boss) -> 4(branch off 1); 5 dead-end off 4;
# 6 = merge(2 OR 4); 7 = merge(2 AND 4). region1: 8(entry) gated on 3 (region0 boss).
func _fixture() -> WorldGraphResource:
	var g := WorldGraphResource.new()
	g.start_node_id = 1
	g.nodes = [
		_node(1, MapNodeResource.Kind.ENTRY, 0, [], [2, 4]),
		_node(2, MapNodeResource.Kind.SPINE, 0, [1], [3, 6, 7]),
		_node(3, MapNodeResource.Kind.BOSS, 0, [2], [8]),
		_node(4, MapNodeResource.Kind.CROSSROAD, 0, [1], [5, 6, 7]),
		_node(5, MapNodeResource.Kind.DEAD_END, 0, [4], []),
		_node(6, MapNodeResource.Kind.BRANCH, 0, [2, 4], []),  # gate ANY (default)
		_node(7, MapNodeResource.Kind.BRANCH, 0, [2, 4], [], MapNodeResource.Gate.ALL),
		_node(8, MapNodeResource.Kind.ENTRY, 1, [3], []),
	]
	return g


func _node(
	id: int,
	kind: MapNodeResource.Kind,
	region: int,
	prereqs: Array,
	succ: Array,
	gate: MapNodeResource.Gate = MapNodeResource.Gate.ANY
) -> MapNodeResource:
	var n := MapNodeResource.new()
	n.id = id
	n.node_kind = kind
	n.region_id = region
	n.prerequisites = PackedInt32Array(prereqs)
	n.successors = PackedInt32Array(succ)
	n.gate_mode = gate
	return n


func test_fixture_graph_is_well_formed() -> void:
	assert_eq(_fixture().validate(), PackedStringArray(), "fixture graph has no dangling refs")


func test_first_node_available_on_fresh_save() -> void:
	var g := _fixture()
	assert_eq(WorldUnlock.node_state(g, 1, {}), S.AVAILABLE, "entry node open from the start")
	assert_eq(WorldUnlock.node_state(g, 2, {}), S.LOCKED, "everything else locked")


func test_completed_node_reads_completed() -> void:
	assert_eq(WorldUnlock.node_state(_fixture(), 1, {1: true}), S.COMPLETED)


func test_fork_unlocks_both_successors() -> void:
	var g := _fixture()
	var done := {1: true}  # completing the entry forks to 2 (spine) and 4 (branch)
	assert_eq(WorldUnlock.node_state(g, 2, done), S.AVAILABLE, "fork opens the spine child")
	assert_eq(WorldUnlock.node_state(g, 4, done), S.AVAILABLE, "fork opens the branch child too")


func test_merge_any_opens_on_either_parent() -> void:
	var g := _fixture()
	assert_eq(WorldUnlock.node_state(g, 6, {2: true}), S.AVAILABLE, "ANY merge opens on one parent")
	assert_eq(WorldUnlock.node_state(g, 6, {4: true}), S.AVAILABLE, "ANY merge opens on the other")


func test_merge_all_needs_both_parents() -> void:
	var g := _fixture()
	assert_eq(WorldUnlock.node_state(g, 7, {2: true}), S.LOCKED, "ALL merge waits for both")
	assert_eq(WorldUnlock.node_state(g, 7, {2: true, 4: true}), S.AVAILABLE, "both -> open")


func test_region_entry_gated_on_prior_boss() -> void:
	var g := _fixture()
	assert_eq(
		WorldUnlock.node_state(g, 8, {2: true}), S.LOCKED, "region 2 entry shut until the boss"
	)
	assert_eq(WorldUnlock.node_state(g, 8, {3: true}), S.AVAILABLE, "boss completed opens region 2")


func test_dead_end_never_blocks_the_spine() -> void:
	var g := _fixture()
	# Node 3 (spine boss) depends only on 2; whether the dead-end 5 is done changes nothing.
	assert_eq(WorldUnlock.node_state(g, 3, {2: true}), S.AVAILABLE)
	assert_eq(
		WorldUnlock.node_state(g, 3, {2: true, 5: true}), S.AVAILABLE, "dead-end is irrelevant"
	)


func test_available_ids_lists_only_open_nodes() -> void:
	var ids := WorldUnlock.available_ids(_fixture(), {1: true})
	assert_eq(Array(ids), [2, 4], "after the entry, exactly the two forked children are available")


func test_full_traversal_reaches_every_node() -> void:
	# Transitive closure of `successors` from the start node must cover the whole graph (no orphan).
	var g := _fixture()
	var reached := {g.start_node_id: true}
	var frontier := [g.start_node_id]
	while not frontier.is_empty():
		var cur: int = frontier.pop_back()
		for s in g.node(cur).successors:
			if not reached.has(s):
				reached[s] = true
				frontier.append(s)
	assert_eq(reached.size(), g.nodes.size(), "every node reachable from the start")


func test_inter_region_edges_originate_only_at_bosses() -> void:
	var g := _fixture()
	var crossings := 0
	for n in g.nodes:
		for s in n.successors:
			if g.node(s).region_id != n.region_id:
				crossings += 1
				assert_true(
					n.is_boss(), "cross-region edge %d->%d must leave from a boss" % [n.id, s]
				)
	assert_eq(crossings, 1, "fixture has exactly one region crossing (boss 3 -> entry 8)")
