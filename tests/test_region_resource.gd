extends GutTest

## Region data + GameState lookups: the three authored regions load, claim their world-map nodes,
## and region_for_node / region_id_for_node resolve correctly (the Narrator's region sub-pools and
## the world map both depend on this). Every graph node must belong to exactly one region.


func test_three_regions_load() -> void:
	assert_eq(GameState.regions().size(), 3, "three regions are authored and load")


func test_region_ids_follow_descent_order() -> void:
	assert_eq(GameState.region_id_for_node(1), 0, "node 1 -> The Ossuary (id 0)")
	assert_eq(GameState.region_id_for_node(11), 1, "node 11 -> The Drowned Cloister (id 1)")
	assert_eq(GameState.region_id_for_node(21), 2, "node 21 -> The Ashen Vigil (id 2)")


func test_out_of_range_node_has_no_region() -> void:
	assert_eq(GameState.region_id_for_node(999), -1, "a node past the descent claims no region")
	assert_null(GameState.region_for_node(0), "node 0 is below the first region")


func test_contains_node_membership() -> void:
	var ossuary := GameState.region_for_node(3)
	assert_true(ossuary.contains_node(3), "the region claims its own node")
	assert_false(ossuary.contains_node(11), "and not a node from the next region")


func test_entry_and_boss_anchors() -> void:
	var rs := GameState.regions()
	assert_eq(rs[0].entry_node_id, 1, "Ossuary entry is node 1")
	assert_eq(rs[0].boss_node_id, 5, "Ossuary boss is node 5")
	assert_eq(rs[1].entry_node_id, 11, "Cloister entry is node 11")
	assert_eq(rs[1].boss_node_id, 15, "Cloister boss is node 15")
	assert_eq(rs[2].entry_node_id, 21, "Vigil entry is node 21")
	assert_eq(rs[2].boss_node_id, 25, "Vigil boss is node 25 (the final boss)")


func test_every_graph_node_belongs_to_exactly_one_region() -> void:
	var graph := GameState.world_graph()
	assert_not_null(graph, "world graph loads")
	for n in graph.nodes:
		var claims := 0
		for r in GameState.regions():
			if r.contains_node(n.id):
				claims += 1
		assert_eq(claims, 1, "node %d belongs to exactly one region" % n.id)
