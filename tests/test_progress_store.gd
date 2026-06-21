extends GutTest

## Tests for ProgressStore sequential unlock + persistence, on a throwaway
## save file so the real user:// progress is never touched.

const TEST_PATH := "user://test_progress.cfg"


func before_each() -> void:
	_wipe()


func after_all() -> void:
	_wipe()


func _wipe() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func test_fresh_store_unlocks_only_first() -> void:
	var p := ProgressStore.new(TEST_PATH)
	assert_true(p.is_unlocked(1), "level 1 always open")
	assert_false(p.is_unlocked(2), "level 2 locked at start")


func test_completing_unlocks_next() -> void:
	var p := ProgressStore.new(TEST_PATH)
	p.mark_completed(1)
	assert_true(p.is_unlocked(2), "beating 1 unlocks 2")
	assert_false(p.is_unlocked(3), "3 still locked")


func test_replaying_earlier_never_regresses() -> void:
	var p := ProgressStore.new(TEST_PATH)
	p.mark_completed(3)
	assert_true(p.is_unlocked(4))
	p.mark_completed(1)
	assert_true(p.is_unlocked(4), "replaying level 1 keeps 4 unlocked")


func test_persistence_roundtrip() -> void:
	var p := ProgressStore.new(TEST_PATH)
	p.mark_completed(5)
	var q := ProgressStore.new(TEST_PATH)
	assert_true(q.is_unlocked(6), "fresh instance reads the saved unlock")
	assert_false(q.is_unlocked(7))


func test_reset() -> void:
	var p := ProgressStore.new(TEST_PATH)
	p.mark_completed(7)
	p.reset()
	assert_false(p.is_unlocked(2), "reset returns to only level 1")
	var q := ProgressStore.new(TEST_PATH)
	assert_false(q.is_unlocked(2), "reset persisted")
