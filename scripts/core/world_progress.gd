class_name WorldProgress
extends RefCounted

## Set-of-completed-nodes persistence for the branching world map (replaces the linear
## ProgressStore). Stores which node ids are completed, plus a per-node best score + best tier
## (for medals / replay verdicts on the detail panel). Availability is NOT stored — it's derived
## from the graph + this completed set by WorldUnlock, so unlocking stays a pure function.
##
## ConfigFile, matching the rest of the project's persistence (SettingsStore). The save path is
## injectable so tests use a throwaway file. New filename (world_progress.cfg) so any stale
## old-format progress.cfg from a previous build is simply never read — no migration, no compat.

const SECTION_DONE := "completed"  # one bool key per completed node id (the set)
const SECTION_BEST := "best"  # "score_<id>" -> int, "tier_<id>" -> int (Scoring.Tier)

var path: String
var _completed: Dictionary = {}  # int id -> true (the set WorldUnlock consumes)
var _best_score: Dictionary = {}  # int id -> int
var _best_tier: Dictionary = {}  # int id -> int (Scoring.Tier value)


func _init(save_path: String = "user://world_progress.cfg") -> void:
	path = save_path
	_load()


# --- queries ------------------------------------------------------------------


func is_completed(id: int) -> bool:
	return _completed.has(id)


## The completed ids as a Dictionary (id -> true) — passed straight to WorldUnlock as the set.
func completed_set() -> Dictionary:
	return _completed


func completed_ids() -> Array:
	return _completed.keys()


func best_score(id: int) -> int:
	return int(_best_score.get(id, 0))


## Best (lowest-enum) tier earned on this node; defaults to the neutral middle (FREED) when never
## beaten. Callers should gate display on is_completed() — a never-played node has no real tier.
func best_tier(id: int) -> int:
	return int(_best_tier.get(id, Scoring.Tier.FREED))


func is_empty() -> bool:
	return _completed.is_empty()


# --- mutation -----------------------------------------------------------------


## Record a win. Always marks the node completed; only UPGRADES best score (higher) and best tier
## (lower enum = better — CLEANLY 0 < FREED 1 < BARELY 2), so replaying worse never regresses.
func mark_completed(id: int, score: int = 0, tier: int = Scoring.Tier.FREED) -> void:
	var changed := not _completed.has(id)
	_completed[id] = true
	if score > best_score(id):
		_best_score[id] = score
		changed = true
	if not _best_tier.has(id) or tier < int(_best_tier[id]):
		_best_tier[id] = tier
		changed = true
	if changed:
		_save()


func reset() -> void:
	_completed.clear()
	_best_score.clear()
	_best_tier.clear()
	_save()


# --- persistence --------------------------------------------------------------


func _load() -> void:
	var cf := ConfigFile.new()
	# Missing OR stale/old-format OR malformed file -> start empty, never crash.
	if cf.load(path) != OK:
		return
	if cf.has_section(SECTION_DONE):
		for key in cf.get_section_keys(SECTION_DONE):
			if bool(cf.get_value(SECTION_DONE, key, false)):
				_completed[int(key)] = true
	if cf.has_section(SECTION_BEST):
		for key in cf.get_section_keys(SECTION_BEST):
			if key.begins_with("score_"):
				_best_score[int(key.trim_prefix("score_"))] = int(
					cf.get_value(SECTION_BEST, key, 0)
				)
			elif key.begins_with("tier_"):
				_best_tier[int(key.trim_prefix("tier_"))] = int(cf.get_value(SECTION_BEST, key, 0))


func _save() -> void:
	var cf := ConfigFile.new()
	for id: int in _completed:
		cf.set_value(SECTION_DONE, str(id), true)
	for id: int in _best_score:
		cf.set_value(SECTION_BEST, "score_%d" % id, _best_score[id])
	for id: int in _best_tier:
		cf.set_value(SECTION_BEST, "tier_%d" % id, _best_tier[id])
	cf.save(path)
