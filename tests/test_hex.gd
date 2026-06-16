extends GutTest

## Tests for Hex.distance — the odd-r offset hex step-distance used to time the
## ripple pop. Each neighbour must be exactly one step away; distance is symmetric
## and zero to self.


func test_distance_to_self_is_zero() -> void:
	assert_eq(Hex.distance(Vector2i(4, 3), Vector2i(4, 3)), 0, "a cell is distance 0 from itself")


func test_every_neighbour_is_distance_one() -> void:
	# Check on both row parities, including negative rows (cube halving must stay exact).
	for cell in [Vector2i(5, 0), Vector2i(5, 1), Vector2i(3, 4), Vector2i(2, -1)]:
		for nb in Hex.neighbors(cell):
			assert_eq(Hex.distance(cell, nb), 1, "%s -> %s is one step" % [cell, nb])


func test_distance_is_symmetric() -> void:
	var a := Vector2i(1, 0)
	var b := Vector2i(7, 5)
	assert_eq(Hex.distance(a, b), Hex.distance(b, a), "distance is symmetric")


func test_two_steps_along_a_row() -> void:
	# Two cells over on the same row are two steps apart.
	assert_eq(Hex.distance(Vector2i(2, 0), Vector2i(4, 0)), 2, "two columns over is distance 2")


func test_straight_down_two_rows() -> void:
	# Going down two rows in the same column: each row step is one hop, so distance 2.
	assert_eq(
		Hex.distance(Vector2i(3, 2), Vector2i(3, 4)), 2, "two rows down (same col) is distance 2"
	)
