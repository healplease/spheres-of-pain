extends GutTest

## Tests for ShotBag — the gun's colour source. The bag is pure logic with its own
## seedable RNG, so these run headless and deterministically (no global randi()).


func _bag(true_random: bool, seed_value: int) -> ShotBag:
	var b := ShotBag.new()
	b.true_random = true_random
	b.rng.seed = seed_value
	return b


func test_true_random_stays_in_present() -> void:
	var bag := _bag(true, 123)
	var present: Array[int] = [2, 5, 6]
	for i in 100:
		assert_true(bag.next(present) in present, "true-random draw %d is a present colour" % i)


func test_bag_deals_balanced_cycle() -> void:
	# Over one full cycle, each present colour appears exactly present.size() times.
	var bag := _bag(false, 99)
	var present: Array[int] = [0, 1, 2]
	var counts := {0: 0, 1: 0, 2: 0}
	for i in 9:
		var c := bag.next(present)
		assert_true(c in present, "draw %d in present" % i)
		counts[c] += 1
	assert_eq(counts[0], 3, "colour 0 appears 3 times per 9-draw cycle")
	assert_eq(counts[1], 3, "colour 1 appears 3 times per 9-draw cycle")
	assert_eq(counts[2], 3, "colour 2 appears 3 times per 9-draw cycle")


func test_bag_refills_after_exhaustion() -> void:
	# The bag empties after present.size()^2 draws, then refills to another balanced
	# cycle — so two cycles each stay even (the 5th draw here must trigger a refill).
	var bag := _bag(false, 7)
	var present: Array[int] = [0, 1]
	for cycle in 2:
		var counts := {0: 0, 1: 0}
		for i in 4:
			counts[bag.next(present)] += 1
		assert_eq(counts[0], 2, "cycle %d: colour 0 dealt twice" % cycle)
		assert_eq(counts[1], 2, "cycle %d: colour 1 dealt twice" % cycle)


func test_bag_rebuilds_when_present_shrinks() -> void:
	# A colour cleared off the board changes the present set mid-bag; the bag must
	# rebuild to the new size and never serve the vanished colour again.
	var bag := _bag(false, 3)
	var present: Array[int] = [0, 1, 2]
	bag.next(present)  # builds a 9-item bag for {0,1,2}
	var shrunk: Array[int] = [0, 1]
	var counts := {0: 0, 1: 0}
	for i in 4:
		var c := bag.next(shrunk)
		assert_true(c in shrunk, "draw stays within the new present set")
		counts[c] += 1
	assert_eq(counts[0], 2, "rebuilt bag deals colour 0 twice")
	assert_eq(counts[1], 2, "rebuilt bag deals colour 1 twice")
	for i in 20:
		assert_ne(bag.next(shrunk), 2, "the cleared colour never returns")


func test_empty_present_returns_zero() -> void:
	var empty: Array[int] = []
	assert_eq(_bag(false, 1).next(empty), 0, "no colours on board -> fallback 0 (bag mode)")
	assert_eq(_bag(true, 1).next(empty), 0, "fallback holds in true-random mode too")
