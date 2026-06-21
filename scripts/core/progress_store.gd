class_name ProgressStore
extends RefCounted

## Sequential-unlock persistence: levels unlock in order, and the furthest
## unlocked level survives restarts via a ConfigFile. The save path is
## injectable so tests can use a throwaway file instead of the real save.

const SECTION := "progress"
const KEY_HIGHEST := "highest_unlocked"

var path: String
var highest_unlocked: int = 1


func _init(save_path: String = "user://progress.cfg") -> void:
	path = save_path
	_load()


func is_unlocked(level_id: int) -> bool:
	return level_id <= highest_unlocked


## Beating level N unlocks N+1. Replaying an earlier level never regresses.
func mark_completed(level_id: int) -> void:
	var unlocked := level_id + 1
	if unlocked > highest_unlocked:
		highest_unlocked = unlocked
		_save()


func reset() -> void:
	highest_unlocked = 1
	_save()


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(path) == OK:
		highest_unlocked = int(cf.get_value(SECTION, KEY_HIGHEST, 1))


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value(SECTION, KEY_HIGHEST, highest_unlocked)
	cf.save(path)
