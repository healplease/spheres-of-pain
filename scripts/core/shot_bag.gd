class_name ShotBag
extends RefCounted

## Decides what colour the gun is handed next. Pure logic (no nodes, no engine
## calls) so it's unit-testable headlessly, like GridModel — the controller is the
## only view that drives it.
##
## Two modes, chosen by `true_random`:
##   true  : every draw is an independent uniform pick (the classic feel).
##   false : a "bag" (bingo-cage) draw — a shuffled multiset where each colour still
##           on the board appears once per present colour, dealt out until empty then
##           refilled. This evens out streaks/droughts, the gentler distribution.
##
## The bag follows the colours CURRENTLY present (passed in each `next()` call), so
## it never offers a colour that's been cleared off the board, and it rebuilds when
## that set changes. With every colour present the bag size is present.size()^2,
## matching the "number-of-colours squared" design.

var true_random := true  # set from the Gameplay "True random" setting
var rng := RandomNumberGenerator.new()  # seedable so tests are deterministic

var _bag: Array[int] = []  # remaining shuffled draws (bag mode only)
var _built_for: Array[int] = []  # the present-colour set the current bag was built from


## The next colour to load, drawn only from `present` (the breakable colours still on
## the board, ascending). Returns 0 when the board has none left (game already won).
func next(present: Array[int]) -> int:
	if present.is_empty():
		return 0
	if true_random:
		return present[rng.randi_range(0, present.size() - 1)]
	if _bag.is_empty() or present != _built_for:
		_refill(present)
	return _bag.pop_back()


## Rebuild the bag: each present colour repeated present.size() times, shuffled.
func _refill(present: Array[int]) -> void:
	_built_for = present.duplicate()
	_bag.clear()
	for c in present:
		for _i in present.size():
			_bag.append(c)
	# Shuffle with our own seedable rng (not Array.shuffle()'s global one); see RngUtils.
	_bag = RngUtils.shuffled(_bag, rng)
