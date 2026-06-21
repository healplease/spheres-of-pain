extends GutTest

## Tests for WorldProgress: the completed-set + best score/tier persistence, on a throwaway save
## file so the real user:// progress is never touched. Replaces the old linear ProgressStore tests.

const TEST_PATH := "user://test_world_progress.cfg"


func before_each() -> void:
	_wipe()


func after_all() -> void:
	_wipe()


func _wipe() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func test_fresh_store_is_empty() -> void:
	var p := WorldProgress.new(TEST_PATH)
	assert_true(p.is_empty(), "no nodes completed at start")
	assert_false(p.is_completed(1), "node 1 not yet completed")


func test_mark_completed_adds_to_set() -> void:
	var p := WorldProgress.new(TEST_PATH)
	p.mark_completed(3)
	assert_true(p.is_completed(3), "node 3 marked completed")
	assert_false(p.is_completed(4), "unrelated node stays incomplete")
	assert_eq(p.completed_set(), {3: true}, "completed_set is the {id:true} set")


func test_best_score_only_upgrades() -> void:
	var p := WorldProgress.new(TEST_PATH)
	p.mark_completed(2, 500)
	p.mark_completed(2, 200)  # a worse replay
	assert_eq(p.best_score(2), 500, "best score keeps the higher value")
	p.mark_completed(2, 900)
	assert_eq(p.best_score(2), 900, "a better replay raises it")


func test_best_tier_only_improves() -> void:
	var p := WorldProgress.new(TEST_PATH)
	p.mark_completed(1, 0, Scoring.Tier.BARELY)
	p.mark_completed(1, 0, Scoring.Tier.CLEANLY)  # lower enum = better
	assert_eq(p.best_tier(1), Scoring.Tier.CLEANLY, "best tier keeps the better verdict")
	p.mark_completed(1, 0, Scoring.Tier.FREED)  # worse than CLEANLY
	assert_eq(p.best_tier(1), Scoring.Tier.CLEANLY, "a worse replay never regresses the tier")


func test_persistence_roundtrip() -> void:
	var p := WorldProgress.new(TEST_PATH)
	p.mark_completed(5, 1200, Scoring.Tier.CLEANLY)
	p.mark_completed(8)
	var q := WorldProgress.new(TEST_PATH)
	assert_true(q.is_completed(5), "fresh instance reads the saved set")
	assert_true(q.is_completed(8))
	assert_eq(q.best_score(5), 1200, "best score persisted")
	assert_eq(q.best_tier(5), Scoring.Tier.CLEANLY, "best tier persisted")


func test_reset_clears_and_persists() -> void:
	var p := WorldProgress.new(TEST_PATH)
	p.mark_completed(7, 300)
	p.reset()
	assert_true(p.is_empty(), "reset empties the set")
	var q := WorldProgress.new(TEST_PATH)
	assert_true(q.is_empty(), "reset persisted to disk")


func test_stale_or_malformed_file_loads_empty() -> void:
	# A leftover old-format / corrupt file must degrade to an empty store, not crash.
	var cf := ConfigFile.new()
	cf.set_value("progress", "highest_unlocked", 9)  # the OLD ProgressStore schema
	cf.save(TEST_PATH)
	var p := WorldProgress.new(TEST_PATH)
	assert_true(p.is_empty(), "old-format file is ignored cleanly")
	assert_false(p.is_completed(1))
