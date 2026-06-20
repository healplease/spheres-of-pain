class_name DangerView
extends Node

## The danger-feedback subsystem. As the field nears the lose line it drives two
## linked heartbeats (audio, via Sound) and two shader effects (the bottom miss-exit
## line's blink and a red injury vignette), all escalating together off a single
## tier. The blink/vignette throb at the tier's BPM; the phase is integrated on the
## CPU each frame so the rate can be tweened without the throb spiking.
##
## The controller owns the model and the scene; it hands this node the two shader
## materials (setup) and calls set_tier() after every shot. This node owns nothing
## but the danger state — a single-responsibility slice of the old controller.

enum DangerTier { NONE, SLOW, FAST }

const DANGER_BPM_SLOW := 67.0  # two rows from the line
const DANGER_BPM_FAST := 80.0  # one row from the line
const DANGER_LINE_AMBIENT := 1.7  # the line's resting pulse when safe (shader default)
const DANGER_FADE := 1.0
const VIG_SLIGHT := 0.45  # vignette intensity at two rows (rim only)
const VIG_INTENSE := 1.0  # vignette intensity at one row (heavy injury)
const VIG_EDGE_FAR := 0.62  # vignette confined to the screen rim
const VIG_EDGE_NEAR := 0.42  # reaches further in for the one-row injury look
const CLOSE_INTENSITY := 1.0  # the lose payoff drives the vignette to full
const CLOSE_EDGE := 0.05  # ...and reaches almost to the centre — the dark closes in
const CLOSE_TIME := 1.4  # seconds for the close-out to swallow the screen
const PULSE_DECAY := 2.2  # how fast the big-clear throb bleeds off (units/sec; ~0.5 s tail)

var _line_mat: ShaderMaterial  # the bottom miss-exit bar (danger_line.gdshader)
var _vig_mat: ShaderMaterial  # the red injury vignette (danger_vignette.gdshader)
var _tween: Tween
var _tier := DangerTier.NONE
# Beat phase (radians) and the current blink rate (rad/s), integrated each frame and
# pushed to both shaders. Accumulating phase on the CPU keeps the throb continuous
# while the rate is tweened (tweening sin(TIME*speed) directly spikes on rate change).
var _phase := 0.0
var _speed := DANGER_LINE_AMBIENT
# One-shot inward "constriction" throb on big clears (E2.8): a spike set by pulse(), bled off
# each frame and pushed to the vignette's pulse_burst uniform. Fast attack, slow-ish decay.
var _pulse := 0.0


## Bind the two shader materials and seed every uniform we later tween so
## get_shader_parameter() returns a real float for the fade's start value.
func setup(line_mat: ShaderMaterial, vig_mat: ShaderMaterial) -> void:
	_line_mat = line_mat
	_vig_mat = vig_mat
	_vig_mat.set_shader_parameter("intensity", 0.0)
	_vig_mat.set_shader_parameter("edge", VIG_EDGE_FAR)
	_vig_mat.set_shader_parameter("pulse_burst", 0.0)


func _process(delta: float) -> void:
	# Runs every frame (including through the game-over fade) so the throb stays
	# smooth no matter how _speed is being tweened. fmod keeps the phase small.
	_phase = fmod(_phase + _speed * delta, TAU)
	if _pulse > 0.0:
		_pulse = maxf(0.0, _pulse - PULSE_DECAY * delta)
	if _line_mat:
		_line_mat.set_shader_parameter("phase", _phase)
	if _vig_mat:
		_vig_mat.set_shader_parameter("phase", _phase)
		_vig_mat.set_shader_parameter("pulse_burst", _pulse)


## The danger tier for a given rows-to-line, as a DangerTier: SLOW at exactly two rows, FAST at
## one, NONE otherwise. Shared with NarratorDirector so its "danger rising" gate escalates on the
## same thresholds as the audio/visuals.
static func tier_for(rows_left: int) -> DangerTier:
	match rows_left:
		2:
			return DangerTier.SLOW
		1:
			return DangerTier.FAST
	return DangerTier.NONE


## Map proximity to the lose line (rows_left = rows_to_danger) onto a tier and route
## it to BOTH the audio heartbeats and the visuals so they stay locked together. Anything
## but one/two rows — safe, won, or lost (game_over) — is NONE. No-op if unchanged, so the
## per-shot re-calls don't restart the fade.
func set_tier(rows_left: int, game_over: bool) -> void:
	var tier := DangerTier.NONE if game_over else tier_for(rows_left)
	if tier == _tier:
		return
	_tier = tier
	(
		Log
		. info(
			Log.PLAY,
			"danger tier",
			{
				"tier": DangerTier.keys()[tier],
				"rows_to_danger": rows_left,
			}
		)
	)

	Sound.set_heartbeat_slow(tier == DangerTier.SLOW)
	Sound.set_heartbeat_fast(tier == DangerTier.FAST)

	# Per-tier targets: the vignette's intensity/reach, and the shared blink speed
	# (the bottom line and the vignette throb at the same BPM).
	var vig_intensity := 0.0
	var vig_edge := VIG_EDGE_FAR
	var line_speed := DANGER_LINE_AMBIENT
	match tier:
		DangerTier.SLOW:
			vig_intensity = VIG_SLIGHT
			line_speed = _bpm_to_speed(DANGER_BPM_SLOW)
		DangerTier.FAST:
			vig_intensity = VIG_INTENSE
			vig_edge = VIG_EDGE_NEAR
			line_speed = _bpm_to_speed(DANGER_BPM_FAST)

	if _tween and _tween.is_valid():
		_tween.kill()
	var tw := create_tween().set_parallel(true)
	_tween_param(tw, _vig_mat, "intensity", vig_intensity)
	_tween_param(tw, _vig_mat, "edge", vig_edge)
	# Ramp the blink *rate*; _process integrates it into a continuous phase.
	tw.tween_property(self, "_speed", line_speed, DANGER_FADE)
	_tween = tw


## Fire a one-shot inward constriction throb (E2.8), e.g. on a big clear. `strength` (0..1) is
## scaled by the Effects-Intensity slider and taken as the max of any throb still decaying, so
## back-to-back clears reinforce rather than stomp. _process bleeds it back to 0.
func pulse(strength: float) -> void:
	_pulse = clampf(maxf(_pulse, strength * Settings.fx_intensity()), 0.0, 1.0)


## The lose payoff (E2.7): instead of receding on game-over, the red injury vignette closes
## INWARD to swallow the screen. Overrides the tier fade (kills its tween) and parks the tier
## at NONE so a later set_tier no-op can't fight it. The CPU phase keeps throbbing as it
## closes. Pair with the controller's black-fill + desaturation for the full close.
func close_out() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tier = DangerTier.NONE
	var tw := create_tween().set_parallel(true)
	tw.tween_method(
		func(v: float) -> void: _vig_mat.set_shader_parameter("intensity", v),
		float(_vig_mat.get_shader_parameter("intensity")),
		CLOSE_INTENSITY,
		CLOSE_TIME
	)
	tw.tween_method(
		func(v: float) -> void: _vig_mat.set_shader_parameter("edge", v),
		float(_vig_mat.get_shader_parameter("edge")),
		CLOSE_EDGE,
		CLOSE_TIME
	)
	_tween = tw


## Tween one float shader uniform from its current value to `to` over DANGER_FADE,
## as a parallel leg of `tw`. The uniform must already be seeded (see setup).
func _tween_param(tw: Tween, mat: ShaderMaterial, param: String, to: float) -> void:
	var from: float = mat.get_shader_parameter(param)
	tw.tween_method(
		func(v: float) -> void: mat.set_shader_parameter(param, v), from, to, DANGER_FADE
	)


static func _bpm_to_speed(bpm: float) -> float:
	return TAU * bpm / 60.0
