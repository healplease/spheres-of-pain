extends Node
## Autoload "Sound" — the game's audio bus. Owns all audio state: the looping
## ambience bed, auto-wired UI feedback (every Button in the tree gets
## click/hover sounds via `node_added`), and gameplay SFX. Other code only ever
## calls `Sound.play_*()`; nothing outside this singleton touches audio.

const AMBIENCE := preload("res://audio/music/dungeon_ambient_1.ogg")
const UI_CLICK := preload("res://audio/sfx/ui/click_002.ogg")
const UI_HOVER := preload("res://audio/sfx/ui/click_004.ogg")
const UI_BACK := preload("res://audio/sfx/ui/back_002.ogg")
const POPS: Array[AudioStream] = [
	preload("res://audio/sfx/pops/universfield-bubble-pop-02-293341.wav"),
	preload("res://audio/sfx/pops/universfield-bubble-pop-03-320977.wav"),
	preload("res://audio/sfx/pops/universfield-bubble-pop-04-323580.wav"),
	preload("res://audio/sfx/pops/universfield-bubble-pop-05-323639.wav"),
	preload("res://audio/sfx/pops/universfield-bubble-pop-06-351337.wav"),
	preload("res://audio/sfx/pops/universfield-bubble-pop-07-351339.wav"),
	preload("res://audio/sfx/pops/universfield-bubble-pop-07-487896.wav"),
	preload("res://audio/sfx/pops/universfield-bubble-pop-293342.wav"),
]

# Volume dials (dB). Tune to taste; buses give a second, global layer of control.
const AMBIENCE_DB := -10.0
const POP_DB := -12.0
const CLICK_DB := -8.0
const HOVER_DB := -18.0

var _ambience: AudioStreamPlayer
var _click: AudioStreamPlayer
var _hover: AudioStreamPlayer
var _pops: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Looping is set in the ogg's .import options (loop=true), not here.
	_ambience = _make_player(&"Music", AMBIENCE_DB, 1)
	_ambience.stream = AMBIENCE
	_ambience.play()

	_click = _make_player(&"SFX", CLICK_DB, 3)
	_hover = _make_player(&"SFX", HOVER_DB, 3)
	_hover.stream = UI_HOVER

	# Pop variations: the randomizer picks a stream and jitters pitch/volume per
	# shot, so ripple-staggered clusters crackle instead of machine-gunning one
	# sample. Polyphony lets a big cluster overlap freely.
	var rand := AudioStreamRandomizer.new()
	for p in POPS:
		rand.add_stream(-1, p)
	rand.random_pitch = 1.12
	rand.random_volume_offset_db = 2.0
	_pops = _make_player(&"SFX", POP_DB, 12)
	_pops.stream = rand

	get_tree().node_added.connect(_on_node_added)


func play_pop() -> void:
	_pops.play()


func play_click() -> void:
	_click.stream = UI_CLICK
	_click.play()


func play_back() -> void:
	_click.stream = UI_BACK
	_click.play()


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
