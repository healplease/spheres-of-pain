extends Node
## Autoload "Sound" — the game's audio bus. Owns all audio state: the looping
## ambience bed, auto-wired UI feedback (every Button in the tree gets
## click/hover sounds via `node_added`), and gameplay SFX. Other code only ever
## calls `Sound.play_*()`; nothing outside this singleton touches audio.

const AMBIENCE := preload("res://audio/music/dungeon_ambient_1.ogg")
const INTRO := preload("res://audio/music/intro.ogg")
const UI_CLICK := preload("res://audio/sfx/ui/click_002.ogg")
const UI_HOVER := preload("res://audio/sfx/ui/click_004.ogg")
const UI_BACK := preload("res://audio/sfx/ui/back_002.ogg")
const POPS: Array[AudioStream] = [
	preload("res://audio/sfx/pops/pop1.ogg"),
	preload("res://audio/sfx/pops/pop2.ogg"),
	preload("res://audio/sfx/pops/pop3.ogg"),
	preload("res://audio/sfx/pops/pop4.ogg"),
	preload("res://audio/sfx/pops/pop5.ogg"),
	preload("res://audio/sfx/pops/pop6.ogg"),
	preload("res://audio/sfx/pops/pop7.ogg"),
	preload("res://audio/sfx/pops/pop8.ogg"),
]
# Looping tension pulses (loop=true is set in their .import). They play whenever the
# field is one/two rows from the lose line; see set_heartbeat_* below.
const HEARTBEAT_SLOW := preload("res://audio/sfx/heartbeat1.ogg")  # 2 rows from losing
const HEARTBEAT_FAST := preload("res://audio/sfx/heartbeat2.ogg")  # 1 row from losing

# Volume dials (dB). Tune to taste; buses give a second, global layer of control.
const AMBIENCE_DB := -10.0
const POP_DB := -12.0
const CLICK_DB := -8.0
const HOVER_DB := -18.0
const INTRO_DB := 0.0
const HEARTBEAT_DB := -4.0  # the heartbeats' "100%" target
const SILENT_DB := -60.0  # effective silence (never linear_to_db(0) = -inf)

# Gap between the individual pops of a cluster burst (seconds), so a big clear
# reads as a few deliberate, sequenced pops instead of one mushy overlap.
const POP_SEQUENCE_GAP := 0.09
# How long a heartbeat takes to grow 0 -> 100% (and to fade back out), per spec.
const HEARTBEAT_FADE := 1.0

var _ambience: AudioStreamPlayer
var _intro: AudioStreamPlayer
var _click: AudioStreamPlayer
var _hover: AudioStreamPlayer
var _pops: AudioStreamPlayer
var _hb_slow: AudioStreamPlayer
var _hb_fast: AudioStreamPlayer
var _hb_slow_tween: Tween
var _hb_fast_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Looping is set in the ogg's .import options (loop=true), not here. Buses are
	# split by category (Ambience / HUD / Gameplay, all under Master) so the Audio
	# settings sliders can dial each independently; the BGM bus is reserved for future music.
	_ambience = _make_player(&"Ambience", AMBIENCE_DB, 1)
	_ambience.stream = AMBIENCE
	_ambience.play()

	# The startup title stinger rides the (otherwise unused) BGM bus — it's the
	# title theme, not gameplay/ambience. One-shot; the menu fires play_intro().
	_intro = _make_player(&"BGM", INTRO_DB, 1)
	_intro.stream = INTRO

	# Two looping dread pulses on the Gameplay bus, started silent and faded in/out
	# by row proximity to the lose line (see set_heartbeat_slow/fast).
	_hb_slow = _make_player(&"Gameplay", SILENT_DB, 1)
	_hb_slow.stream = HEARTBEAT_SLOW
	_hb_fast = _make_player(&"Gameplay", SILENT_DB, 1)
	_hb_fast.stream = HEARTBEAT_FAST

	_click = _make_player(&"HUD", CLICK_DB, 3)
	_hover = _make_player(&"HUD", HOVER_DB, 3)
	_hover.stream = UI_HOVER

	# Pop variations: the randomizer picks a stream and jitters pitch/volume per
	# shot, so ripple-staggered clusters crackle instead of machine-gunning one
	# sample. Polyphony lets a big cluster overlap freely.
	var rand := AudioStreamRandomizer.new()
	for p in POPS:
		rand.add_stream(-1, p)
	rand.random_pitch = 1.12
	rand.random_volume_offset_db = 2.0
	_pops = _make_player(&"Gameplay", POP_DB, 12)
	_pops.stream = rand

	get_tree().node_added.connect(_on_node_added)


func play_pop() -> void:
	_pops.play()


## Play a burst of pops sized to how many spheres just cleared, so a large cluster
## fires a handful of deliberate pops rather than one sound per bubble (which turns
## to noise on big clears). Buckets: 3-5 -> 1, 6-9 -> 2, 10-15 -> 3, 16+ -> 4.
func play_cluster_pop(cluster_size: int) -> void:
	var count := _pop_count_for(cluster_size)
	play_pop()
	for i in range(1, count):
		get_tree().create_timer(i * POP_SEQUENCE_GAP).timeout.connect(play_pop)


func _pop_count_for(n: int) -> int:
	if n >= 16:
		return 4
	if n >= 10:
		return 3
	if n >= 6:
		return 2
	return 1


func play_click() -> void:
	_click.stream = UI_CLICK
	_click.play()


func play_back() -> void:
	_click.stream = UI_BACK
	_click.play()


# --- startup intro stinger ----------------------------------------------------


## Play the one-shot title stinger that scores the "SPHERES / OF / PAIN" reveal.
func play_intro() -> void:
	_intro.play()


## Cut the stinger short (the player skipped the intro).
func stop_intro() -> void:
	_intro.stop()


# --- danger heartbeats --------------------------------------------------------


## Slow pulse: on when the field is exactly two rows from the lose line. Each call
## fades over HEARTBEAT_FADE; toggling it re-kills the in-flight fade so rapid
## on/off swings (a clear right after a grow) can't stack competing tweens.
func set_heartbeat_slow(on: bool) -> void:
	_hb_slow_tween = _fade_loop(_hb_slow, _hb_slow_tween, on)


## Fast pulse: on at one row from losing. Independent of the slow pulse, so the
## controller's two calls produce the escalation (slow fades out as fast fades in).
func set_heartbeat_fast(on: bool) -> void:
	_hb_fast_tween = _fade_loop(_hb_fast, _hb_fast_tween, on)


## Hard-stop both pulses with no fade — used when the game screen is torn down.
func stop_heartbeats() -> void:
	for p: AudioStreamPlayer in [_hb_slow, _hb_fast]:
		p.stop()
		p.volume_db = SILENT_DB
	if _hb_slow_tween and _hb_slow_tween.is_valid():
		_hb_slow_tween.kill()
	if _hb_fast_tween and _hb_fast_tween.is_valid():
		_hb_fast_tween.kill()


## Fade a looping player toward full (on) or silence (off) over HEARTBEAT_FADE,
## starting playback on the way up and stopping it once fully faded out. Kills any
## previous fade on the same player first. Returns the new tween to store.
func _fade_loop(player: AudioStreamPlayer, prev: Tween, on: bool) -> Tween:
	if prev and prev.is_valid():
		prev.kill()
	if on and not player.playing:
		player.volume_db = SILENT_DB
		player.play()
	var tw := create_tween()
	tw.tween_property(player, "volume_db", HEARTBEAT_DB if on else SILENT_DB, HEARTBEAT_FADE)
	if not on:
		tw.tween_callback(player.stop)
	return tw


func _make_player(bus: StringName, db: float, polyphony: int) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = db
	p.max_polyphony = polyphony
	add_child(p)
	return p


func _on_node_added(n: Node) -> void:
	if n is BaseButton and not n.has_meta("snd_wired"):
		n.set_meta("snd_wired", true)
		n.pressed.connect(_on_button_pressed.bind(n))
		n.mouse_entered.connect(_on_button_hovered.bind(n))
		n.focus_entered.connect(_on_button_hovered.bind(n))


func _on_button_pressed(b: BaseButton) -> void:
	# Retreating actions get the heavier "back" thunk; everything else clicks.
	var n := String(b.name).to_lower()
	if n.contains("back") or n.contains("menu"):
		play_back()
	else:
		play_click()


func _on_button_hovered(b: BaseButton) -> void:
	if not b.disabled:
		_hover.play()
