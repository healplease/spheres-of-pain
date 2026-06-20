class_name NarratorDirector
extends Node

## Decides WHEN the grim narrator speaks during a level: gates ambient barks (big clear, lucky
## chain, danger rising) behind a cooldown so the voice stays rare, and forces milestone lines
## (descent, victory, defeat). Pulls lines from the Narrator autoload (region sub-pools, never-
## repeat memory) and hands them to a [[NarratorView]] to fade in. A sub-controller of
## LevelController3D that owns only the narration cadence; the danger thresholds it reacts to
## come from [[DangerView]].tier_for so the "danger rising" gate matches the audio/visuals.

# Narrator event gates — restraint is the brand, so only rare, earned moments speak. A clear must
# free at least this many spheres to earn a "big clear" line; an orphan sweep at least this many
# (and bigger than the matched pop) to earn the rarer "lucky chain" line.
const NARR_BIG_CLEAR_MIN := 8
const NARR_LUCKY_ORPHAN_MIN := 6
# Minimum gap (ms) between *ambient* barks so the voice doesn't chatter under fast play. Milestone
# lines (descent / victory / defeat) bypass it and always speak.
const NARR_COOLDOWN_MSEC := 17000

var _view: NarratorView
var _region_id := -1  # current level's region for Narrator sub-pools; -1 = none / free play
var _last_danger_bucket := DangerView.DangerTier.NONE  # last danger tier; narrate only on a rise
var _last_say_msec := 0  # when the narrator last spoke (ms); gates ambient barks by the cooldown
var _live := true  # cleared at game over so a pending descent/danger bark won't speak after the end


## Bind the subtitle view + the level's region, seed the danger tier from the opening board (so a
## level that starts near the line doesn't spuriously narrate "danger rising" on its first grow),
## and start "on cooldown" so ambient barks hold for a beat — the forced descent line still speaks.
func setup(view: NarratorView, region_id: int, initial_rows_to_danger: int) -> void:
	_view = view
	_region_id = region_id
	_last_danger_bucket = DangerView.tier_for(initial_rows_to_danger)
	_last_say_msec = Time.get_ticks_msec()


## The level ended: forced victory/defeat lines still speak (via say), but any ambient bark still
## pending — a descent timer mid-flight — must stay silent.
func mark_ended() -> void:
	_live = false


## Show a narrator line for an event, region sub-pool preferred. Ambient barks are rate-limited by
## NARR_COOLDOWN_MSEC; pass `force` for milestone lines (descent / victory / defeat) that must
## always speak. The line is only drawn from the pool (consuming the bag) when it will actually
## show, so a suppressed bark wastes no variety.
func say(event_key: String, force := false) -> void:
	if _view == null:
		return
	var now := Time.get_ticks_msec()
	if not force and now - _last_say_msec < NARR_COOLDOWN_MSEC:
		return
	var line := Narrator.line_for(event_key, _region_id)
	if line == "":
		return
	_last_say_msec = now
	Log.debug(Log.PLAY, "narrator", {"event": event_key, "region": _region_id, "forced": force})
	_view.show_line(line)


## Let the centre intro (title + lore) have its moment, then murmur the descent line from the
## bottom as it fades — two beats, not one cluttered frame.
func say_descent_after_intro() -> void:
	await get_tree().create_timer(4.0).timeout
	if is_inside_tree() and _live:
		say("descent", true)


## A clear earns at most one bark, gated hard so routine pops stay silent: a sweep that dwarfs its
## trigger reads as a "lucky chain"; otherwise a large total is a "big clear".
func narrate_clear(popped: int, orphaned: int) -> void:
	if orphaned >= NARR_LUCKY_ORPHAN_MIN and orphaned > popped:
		say("lucky_chain")
	elif popped + orphaned >= NARR_BIG_CLEAR_MIN:
		say("big_clear")


## Narrate the dread only when proximity to the lose line genuinely worsens (a tier rise), never
## every shot — and never as the field crosses it (defeat speaks then instead).
func narrate_danger(rows_left: int) -> void:
	var bucket := DangerView.tier_for(rows_left)
	if bucket > _last_danger_bucket and bucket > DangerView.DangerTier.NONE and _live:
		say("danger_rising")
	_last_danger_bucket = bucket
