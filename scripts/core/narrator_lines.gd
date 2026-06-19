class_name NarratorLines
extends Resource

## The grim narrator's lines — data, not code (mirrors the "levels are data" philosophy), so
## the voice is authored in a .tres and reshaped without touching logic. `pools` maps an event
## key → its global line pool; `region_pools` optionally overrides per region (region_id → {
## event_key → lines }) for region-flavoured barks. Pure data + lookup; the Narrator autoload
## owns the never-repeat memory and the RNG. Event keys in use: descent, big_clear, lucky_chain,
## danger_rising, victory, defeat.

@export var pools: Dictionary = {}
@export var region_pools: Dictionary = {}


## True when a region authors its own override pool for this event (so the Narrator can key its
## memory to the right pool).
func has_region_override(event_key: String, region_id: int) -> bool:
	if region_id < 0 or not region_pools.has(region_id):
		return false
	return (region_pools[region_id] as Dictionary).has(event_key)


## The pool to draw from for an event — a region override when one exists, else the global
## pool, else empty (caller treats empty as "say nothing").
func pool_for(event_key: String, region_id: int = -1) -> PackedStringArray:
	if has_region_override(event_key, region_id):
		return region_pools[region_id][event_key]
	if pools.has(event_key):
		return pools[event_key]
	return PackedStringArray()
