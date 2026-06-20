extends GutTest

## Tests for RngUtils.shuffled — the seedable Fisher–Yates shared by the draw bags. Pure logic
## with an injected RNG, so these run headless and deterministically.


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func test_array_result_is_a_permutation() -> void:
	var arr: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
	var out: Array = RngUtils.shuffled(arr, _rng(42))
	out.sort()
	assert_eq(out, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], "shuffle keeps the same multiset (Array)")


func test_same_seed_is_deterministic() -> void:
	var a: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
	var b: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
	assert_eq(
		RngUtils.shuffled(a, _rng(7)),
		RngUtils.shuffled(b, _rng(7)),
		"same seed -> identical permutation"
	)


func test_different_seeds_diverge() -> void:
	var a: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
	var b: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
	assert_ne(
		RngUtils.shuffled(a, _rng(1)),
		RngUtils.shuffled(b, _rng(2)),
		"different seeds -> different order (with 10 elements collisions are vanishing)"
	)


func test_packed_int32_is_actually_shuffled() -> void:
	# Guards the copy-on-write trap: a PackedInt32Array mutated through a parameter would write
	# to a copy and leave the source ordered. The returned value must be genuinely reordered.
	var ordered := PackedInt32Array(range(10))
	var out: PackedInt32Array = RngUtils.shuffled(PackedInt32Array(range(10)), _rng(5))
	assert_ne(out, ordered, "returned PackedInt32Array is reordered, not the untouched copy")
	var as_array: Array[int] = []
	for v in out:
		as_array.append(v)
	as_array.sort()
	assert_eq(as_array, range(10), "shuffle keeps the same multiset (PackedInt32Array)")
