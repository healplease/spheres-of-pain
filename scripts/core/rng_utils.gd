class_name RngUtils
extends RefCounted

## Pure RNG helpers shared by the seedable draw bags ([[ShotBag]], [[NarratorBag]]). Kept in
## the Log-free core so it stays unit-testable.


## Fisher–Yates shuffle using the supplied seedable rng — NOT Array.shuffle(), which draws
## from the global RNG and so wouldn't be reproducible in tests.
##
## Returns the shuffled array; the caller MUST reassign it (`arr = RngUtils.shuffled(arr, rng)`).
## A PackedInt32Array is copy-on-write: the first index write inside this function rebinds the
## local to a fresh buffer, leaving the caller's original untouched — so only the returned value
## is guaranteed shuffled. A plain Array is shuffled in place too, but reassigning is harmless
## and keeps one call pattern for both. Elements are ints (the draw bags' index/colour ids).
static func shuffled(arr: Variant, rng: RandomNumberGenerator) -> Variant:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: int = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
	return arr
