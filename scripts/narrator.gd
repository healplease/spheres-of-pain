extends Node
## Autoload "Narrator" — the pit's grim voice. Owns the line pools (a NarratorLines resource)
## and per-pool "recently said" memory so a line never repeats until its pool is exhausted,
## then reshuffles without an immediate echo. The memory PERSISTS across levels in a run (the
## reason this is an autoload, not scene-owned) so the voice doesn't loop as you descend.
##
## Pure selection — NO scene access. The play scene's NarratorView surfaces the chosen line as
## a fading subtitle; this singleton only decides *which* line. Mirrors the Sound autoload's
## shape (preloaded resource, small public API). Lines are second-person, liturgical, one
## breath — see GDD §2.10 for the locked voice.

const LINES := preload("res://data/narrator_lines.tres")

var rng := RandomNumberGenerator.new()  # seedable; tests inject a seed before line_for()
var lines: NarratorLines = LINES  # swappable in tests for a synthetic pool

# Resolved-pool key (e.g. "descent" or "r1:big_clear") -> NarratorBag. One bag per pool so
# each event's lines cycle independently and never recur until that pool runs dry.
var _bags: Dictionary = {}


func _ready() -> void:
	rng.randomize()


## The next line for an event — region override pool preferred, else global — advancing that
## pool's bag so the same line won't recur until exhausted. Returns "" when nothing is
## authored, so callers can fire on every event without guarding.
func line_for(event_key: String, region_id: int = -1) -> String:
	var pool := lines.pool_for(event_key, region_id)
	if pool.is_empty():
		return ""
	var key := _bag_key(event_key, region_id)
	var bag: NarratorBag = _bags.get(key)
	if bag == null or bag.pool_size() != pool.size():
		bag = NarratorBag.new(pool.size())
		bag.rng = rng
		_bags[key] = bag
	return pool[bag.next()]


## The memory key for a (event, region) pair — distinct per resolved pool so a region's
## override bag never shares state with the global one.
func _bag_key(event_key: String, region_id: int) -> String:
	if lines.has_region_override(event_key, region_id):
		return "r%d:%s" % [region_id, event_key]
	return event_key
