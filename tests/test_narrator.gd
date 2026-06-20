extends GutTest

## Tests for the grim narrator's pure pieces: NarratorBag (never-repeat shuffled draw),
## NarratorLines (region-preferring pool lookup), and the Narrator script's line selection.
## All run headless + deterministically via seeded RNGs and a synthetic line set — no autoload
## state is touched (a fresh narrator.gd instance is used, not the global singleton).


func _lines() -> NarratorLines:
	var nl := NarratorLines.new()
	nl.pools = {
		"descent": PackedStringArray(["a", "b", "c"]),
		"victory": PackedStringArray(["only"]),
	}
	nl.region_pools = {
		1: {"descent": PackedStringArray(["R", "S"])},
	}
	return nl


func _narrator(seed_value: int) -> Node:
	# A fresh instance (not the autoload), so the test never mutates global state. Not added
	# to the tree, so _ready()'s randomize() doesn't fire and the seed stays in control.
	var n: Node = autofree(load("res://scripts/autoload/narrator.gd").new())
	n.lines = _lines()
	n.rng.seed = seed_value
	return n


func _unique(values: Array) -> int:
	var seen := {}
	for v in values:
		seen[v] = true
	return seen.size()


# --- NarratorBag --------------------------------------------------------------


func test_bag_deals_every_index_once_per_cycle() -> void:
	var bag := NarratorBag.new(4)
	bag.rng.seed = 5
	var seen := {}
	for i in 4:
		var idx := bag.next()
		assert_between(idx, 0, 3, "draw %d in range" % i)
		assert_false(seen.has(idx), "index %d not repeated within a cycle" % idx)
		seen[idx] = true
	assert_eq(seen.size(), 4, "all four indices appear once per cycle")


func test_bag_never_repeats_back_to_back() -> void:
	# Within a cycle each index is unique; the only repeat risk is the reshuffle boundary,
	# which the bag forbids. Ten cycles of three must never serve the same index twice running.
	var bag := NarratorBag.new(3)
	bag.rng.seed = 1
	var prev := -1
	for i in 30:
		var idx := bag.next()
		assert_ne(idx, prev, "no index repeats back-to-back (draw %d)" % i)
		prev = idx


func test_bag_single_entry_always_zero() -> void:
	var bag := NarratorBag.new(1)
	for i in 5:
		assert_eq(bag.next(), 0, "a one-line pool can only return index 0")


func test_bag_empty_returns_negative() -> void:
	assert_eq(NarratorBag.new(0).next(), -1, "an empty pool has no index to return")


# --- NarratorLines ------------------------------------------------------------


func test_pool_for_prefers_region_then_global() -> void:
	var nl := _lines()
	assert_eq(nl.pool_for("descent", 1).size(), 2, "region 1 has its own 2-line descent pool")
	assert_true("R" in nl.pool_for("descent", 1), "region override content used")
	assert_eq(nl.pool_for("descent", 0).size(), 3, "region 0 has no override -> global 3-line pool")
	assert_eq(nl.pool_for("descent", -1).size(), 3, "no region -> global pool")
	assert_eq(nl.pool_for("missing", -1).size(), 0, "unknown event -> empty pool")


func test_has_region_override() -> void:
	var nl := _lines()
	assert_true(nl.has_region_override("descent", 1), "region 1 overrides descent")
	assert_false(nl.has_region_override("victory", 1), "region 1 does not override victory")
	assert_false(nl.has_region_override("descent", 0), "region 0 has no overrides")
	assert_false(nl.has_region_override("descent", -1), "no region id -> no override")


# --- Narrator selection -------------------------------------------------------


func test_line_for_empty_when_unauthored() -> void:
	assert_eq(_narrator(1).line_for("nope"), "", "unauthored event yields the empty string")


func test_line_for_uses_region_then_global() -> void:
	var n := _narrator(7)
	for i in 10:
		assert_true(n.line_for("descent", 1) in ["R", "S"], "region 1 draws from its sub-pool")
	for i in 10:
		assert_true(n.line_for("descent", 0) in ["a", "b", "c"], "region 0 falls back to global")


func test_line_for_never_repeats_until_pool_exhausted() -> void:
	var n := _narrator(3)
	var got := [n.line_for("descent"), n.line_for("descent"), n.line_for("descent")]
	assert_eq(_unique(got), 3, "all three descent lines are used before any repeats")


func test_line_for_single_entry_pool() -> void:
	var n := _narrator(9)
	for i in 5:
		assert_eq(n.line_for("victory"), "only", "a one-line pool always returns that line")


# --- authored data ------------------------------------------------------------


func test_authored_lines_resource_parses() -> void:
	# Guards the real .tres: every event the controller fires must have lines, and the
	# region sub-pools must resolve by their int id (the hand-authored int-key dict path).
	var nl: NarratorLines = load("res://data/narrator_lines.tres")
	assert_not_null(nl, "narrator_lines.tres loads as NarratorLines")
	for key in ["descent", "big_clear", "lucky_chain", "danger_rising", "victory", "defeat"]:
		assert_gt(nl.pool_for(key).size(), 0, "global pool '%s' is authored" % key)
	for region_id in [0, 1, 2]:
		assert_true(
			nl.has_region_override("descent", region_id),
			"region %d authors a descent sub-pool" % region_id
		)
		assert_gt(
			nl.pool_for("descent", region_id).size(),
			0,
			"region %d descent sub-pool resolves by int key" % region_id
		)
