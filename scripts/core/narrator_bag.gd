class_name NarratorBag
extends RefCounted

## A "never repeat until exhausted" shuffled draw over the index range [0, size). next()
## hands back each index once in a random order, reshuffles when the bag empties, and never
## returns the same index twice in a row across a reshuffle boundary. Pure + seedable (inject
## `rng`) so it's unit-testable, like ShotBag — the Narrator keeps one bag per line pool so a
## line never recurs until its pool runs dry (then a fresh shuffle, no immediate echo).

var rng := RandomNumberGenerator.new()  # seedable so tests are deterministic

var _size: int = 0
var _order: PackedInt32Array = []  # the current shuffled draw order
var _pos: int = 0  # how far through _order we've dealt
var _last: int = -1  # the index returned last, to forbid an immediate repeat on reshuffle


func _init(size: int) -> void:
	_size = size


func pool_size() -> int:
	return _size


## The next index to use, advancing the bag. -1 only if the pool is empty; with a single
## entry it always returns 0 (a one-line pool can only repeat — nothing to vary).
func next() -> int:
	if _size <= 0:
		return -1
	if _size == 1:
		return 0
	if _pos >= _order.size():
		_reshuffle()
	var idx := _order[_pos]
	_pos += 1
	_last = idx
	return idx


## Re-deal the bag: a fresh shuffle with our own seedable rng (see RngUtils), then guarantee
## the first draw isn't the line we just said.
func _reshuffle() -> void:
	_order = RngUtils.shuffled(PackedInt32Array(range(_size)), rng)
	if _order[0] == _last and _size > 1:
		var t := _order[0]
		_order[0] = _order[1]
		_order[1] = t
	_pos = 0
