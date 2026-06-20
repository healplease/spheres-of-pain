class_name LoadingOverlay
extends CanvasLayer

## The grimdark loading veil shown while a level's 3D board is built. It paints the level
## title + lore fragment over near-black with a thin progress bar that fills as the field's
## spheres spawn, then fades to reveal the finished board. Its own scene, instanced by
## LevelController3D and driven via begin() / set_progress() / dismiss(); pure presentation,
## it owns no game state. The veil sits on a high CanvasLayer so it covers the 3D viewport
## and every other HUD layer, which also lets the (masked) shader compiles and node spawns
## happen out of sight.

const FADE_OUT_TIME := 0.6
## Keep the veil up at least this long after begin() so a tiny board doesn't flash it for a
## single frame — the title + lore want a breath to read regardless of how fast the build is.
const MIN_SHOW := 0.5

var _shown_at := 0.0  # uptime (seconds) when begin() ran, for the MIN_SHOW floor

@onready var _root: Control = $Root
@onready var _title: Label = $Root/Box/Title
@onready var _lore: Label = $Root/Box/Lore
@onready var _bar: ProgressBar = $Root/Box/Bar


## Show the veil with this level's title + lore and a zeroed bar.
func begin(title: String, lore: String) -> void:
	_title.text = title
	_lore.text = lore
	_bar.value = 0.0
	_shown_at = _now()


## Drive the bar from a 0..1 build fraction.
func set_progress(fraction: float) -> void:
	_bar.value = clampf(fraction, 0.0, 1.0) * 100.0


## Fill the bar, honour the MIN_SHOW floor, fade out and free. Awaitable, so the controller
## can hand control back to gameplay only once the board is revealed.
func dismiss() -> void:
	_bar.value = 100.0
	var elapsed := _now() - _shown_at
	if elapsed < MIN_SHOW:
		await get_tree().create_timer(MIN_SHOW - elapsed).timeout
	var tw := _root.create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_OUT_TIME)
	await tw.finished
	queue_free()


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
