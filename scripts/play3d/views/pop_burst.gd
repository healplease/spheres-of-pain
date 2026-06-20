class_name PopBurst
extends Node3D

## A small round-robin pool of pop_burst.tscn instances (E2.3). The controller calls
## fire(world_pos, magnitude) when a cluster is freed; this positions the next free burst,
## scales how much it throws by the clear's magnitude × the Effects-Intensity slider, and
## restart()s its four one-shot layers. Round-robin reuse (not a finished-signal recycle)
## keeps it dead simple — with POOL_SIZE bursts and ~2 s lifetimes, real overlap is rare,
## and the worst case just cuts off the oldest still-playing burst.

const BURST_SCENE := preload("res://scenes/pop_burst.tscn")
const POOL_SIZE := 5
const LAYERS: Array[String] = ["Ash", "Shards", "Embers", "Wisps"]
# Magnitude (matched + orphaned spheres) that fills a burst out completely; smaller clears
# emit a floor fraction so even a 3-match still spits a little. Mirrors the shake tiers.
const FULL_AT := 18.0
const RATIO_MIN := 0.25
# The whole burst grows a touch for bigger clears, so a catastrophe reads physically larger.
const SCALE_MIN := 0.85
const SCALE_MAX := 1.3

var _pool: Array[Node3D] = []
var _next := 0


func _ready() -> void:
	for i in POOL_SIZE:
		var burst := BURST_SCENE.instantiate()
		add_child(burst)
		_pool.append(burst)


## Fire one burst at a world position, its volume scaled by the clear's magnitude. No-op
## when Effects Intensity is 0, so the accessibility slider silences particles completely.
func fire(world_pos: Vector3, magnitude: int) -> void:
	var fx := Settings.fx_intensity()
	if fx <= 0.0:
		return
	var fill := clampf(float(magnitude) / FULL_AT, 0.0, 1.0)
	var ratio := maxf(RATIO_MIN, fill) * fx
	var burst := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	burst.global_position = world_pos
	burst.scale = Vector3.ONE * lerpf(SCALE_MIN, SCALE_MAX, fill)
	for layer_name in LAYERS:
		var p := burst.get_node(layer_name) as GPUParticles3D
		p.amount_ratio = clampf(ratio, 0.0, 1.0)
		p.restart()
