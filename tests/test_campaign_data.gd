# gdlint:disable=max-public-methods
extends GutTest

## Data-integrity sweep over the whole authored campaign: every one of the 30 level files is valid
## and playable, and the world graph is well-formed (reachable, one boss per region, spine length 5,
## the boss the only inter-region door, optional paths harder than the spine, monotone difficulty).

# --- the 30 level files -------------------------------------------------------


func test_all_30_levels_validate() -> void:
	for i in range(1, GameState.LEVEL_COUNT + 1):
		var path := "res://levels/level_%02d.tres" % i
		var lv := load(path) as LevelResource
		assert_not_null(lv, "%s loads as LevelResource" % path)
		if lv == null:
			continue
		assert_eq(lv.id, i, "%s id matches filename" % path)
		assert_eq(lv.validate(), PackedStringArray(), "%s passes validation" % path)
		var m := lv.build_model()
		assert_false(m.is_won(), "%s not instantly won" % path)
		assert_false(m.is_lost(), "%s not instantly lost" % path)
		assert_false(lv.title.is_empty(), "%s has a title" % path)
		assert_false(lv.lore_fragment.is_empty(), "%s has lore" % path)


func test_level_envelope_is_sane() -> void:
	for i in range(1, GameState.LEVEL_COUNT + 1):
		var lv := _level(i)
		assert_between(lv.num_colors, 3, 7, "level %d num_colors within the authored envelope" % i)
		assert_between(lv.width, 9, 18, "level %d width within the authored envelope" % i)


func test_objective_tags_match_type_for_all() -> void:
	for i in range(1, GameState.LEVEL_COUNT + 1):
		var lv := _level(i)
		var tagged := lv.objective_cells().size() > 0
		if lv.objective_type == LevelResource.Objective.CLEAR:
			assert_false(tagged, "level %d is CLEAR and carries no '@'/'*' tags" % i)
		else:
			assert_true(tagged, "level %d has an objective and at least one tagged cell" % i)
			assert_lt(lv.objective_color, lv.num_colors, "level %d objective_color in range" % i)


# --- the world graph ----------------------------------------------------------


func test_world_graph_is_well_formed() -> void:
	assert_eq(_graph().validate(), PackedStringArray(), "no dangling/duplicate node references")


func test_every_node_has_a_region_in_range() -> void:
	for n in _graph().nodes:
		assert_between(n.region_id, 0, 2, "node %d region_id in {0,1,2}" % n.id)


func test_exactly_one_boss_per_region() -> void:
	var bosses := {0: 0, 1: 0, 2: 0}
	for n in _graph().nodes:
		if n.is_boss():
			bosses[n.region_id] += 1
	assert_eq(bosses, {0: 1, 1: 1, 2: 1}, "each region has exactly one boss")


func test_each_spine_is_five_nodes_entry_to_boss() -> void:
	var graph := _graph()
	for r in GameState.regions():
		var id := r.entry_node_id
		var seen := {}
		var length := 0
		# Follow the primary (first) successor from the entry until the boss.
		while id != 0 and not seen.has(id):
			seen[id] = true
			length += 1
			var n := graph.node(id)
			if n.is_boss():
				break
			id = n.successors[0] if n.successors.size() > 0 else 0
		assert_eq(length, 5, "region %d spine is entry -> ... -> boss in 5 nodes" % r.id)
		assert_eq(graph.node(id).id, r.boss_node_id, "region %d spine ends at its boss" % r.id)


func test_boss_is_the_only_inter_region_edge() -> void:
	var graph := _graph()
	var crossings := 0
	for n in graph.nodes:
		for s in n.successors:
			if graph.node(s).region_id != n.region_id:
				crossings += 1
				assert_true(n.is_boss(), "cross-region edge %d->%d leaves from a boss" % [n.id, s])
	assert_eq(crossings, 2, "exactly two region crossings (R1->R2, R2->R3)")


func test_every_node_reachable_from_the_start() -> void:
	var graph := _graph()
	var reached := {graph.start_node_id: true}
	var frontier := [graph.start_node_id]
	while not frontier.is_empty():
		var cur: int = frontier.pop_back()
		for s in graph.node(cur).successors:
			if not reached.has(s):
				reached[s] = true
				frontier.append(s)
	assert_eq(reached.size(), graph.nodes.size(), "every node reachable from the start node")


func test_spine_difficulty_is_monotone_nondecreasing() -> void:
	var graph := _graph()
	for r in GameState.regions():
		var id := r.entry_node_id
		var prev: LevelResource = null
		while id != 0:
			var n := graph.node(id)
			var lv := _level(id)
			if prev != null:
				assert_gte(
					lv.num_colors, prev.num_colors, "spine colours never drop at node %d" % id
				)
				assert_gte(lv.width, prev.width, "spine width never drops at node %d" % id)
			prev = lv
			if n.is_boss():
				break
			id = n.successors[0] if n.successors.size() > 0 else 0


func test_optional_nodes_harder_than_region_entry() -> void:
	var graph := _graph()
	for r in GameState.regions():
		var entry := _level(r.entry_node_id)
		var floor_indest := _indestructibles(entry)
		for n in graph.nodes:
			if n.region_id != r.id:
				continue
			if (
				n.node_kind
				in [
					MapNodeResource.Kind.ENTRY,
					MapNodeResource.Kind.SPINE,
					MapNodeResource.Kind.BOSS
				]
			):
				continue
			var lv := _level(n.id)
			var harder := (
				lv.width > entry.width
				or lv.num_colors > entry.num_colors
				or _indestructibles(lv) > floor_indest
			)
			assert_true(harder, "optional node %d is harder than its region's entry" % n.id)


# --- helpers ------------------------------------------------------------------


func _level(i: int) -> LevelResource:
	return load("res://levels/level_%02d.tres" % i) as LevelResource


func _graph() -> WorldGraphResource:
	return GameState.world_graph()


func _indestructibles(lv: LevelResource) -> int:
	var n := 0
	for row in lv.layout:
		for c in row:
			if c in ["X", "x", "S", "s", "B", "b"]:
				n += 1
	return n
