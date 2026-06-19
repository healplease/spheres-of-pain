extends GutTest

## Region data + GameState lookups: the three authored region .tres files must cover the whole
## campaign (levels 1..LEVEL_COUNT) contiguously, and region_for_level / region_id_for_level must
## resolve correctly — both the descent map and the Narrator's region sub-pools depend on this.


func test_three_regions_load() -> void:
	assert_eq(GameState.regions().size(), 3, "three regions are authored and load")


func test_regions_cover_every_campaign_level() -> void:
	for i in range(1, GameState.LEVEL_COUNT + 1):
		assert_not_null(GameState.region_for_level(i), "level %d belongs to a region" % i)


func test_region_ids_follow_descent_order() -> void:
	assert_eq(GameState.region_id_for_level(1), 0, "L1 -> The Ossuary (id 0)")
	assert_eq(GameState.region_id_for_level(6), 1, "L6 -> The Drowned Cloister (id 1)")
	assert_eq(GameState.region_id_for_level(15), 2, "L15 -> The Ashen Vigil (id 2)")


func test_out_of_range_level_has_no_region() -> void:
	assert_eq(GameState.region_id_for_level(999), -1, "a level past the descent claims no region")
	assert_null(GameState.region_for_level(0), "level 0 is below the first region")


func test_region_contains_is_inclusive() -> void:
	var ossuary := GameState.region_for_level(3)
	assert_true(ossuary.contains(ossuary.first_level), "contains() includes the first level")
	assert_true(ossuary.contains(ossuary.last_level), "contains() includes the last level")
	assert_false(ossuary.contains(ossuary.last_level + 1), "contains() excludes the next region")
