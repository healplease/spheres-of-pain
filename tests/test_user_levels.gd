extends GutTest

## Tests for UserLevels: the user://levels/ store — save / list / load / delete
## round-trips plus the filename slug + uniqueness rules. Runs against a throwaway
## directory (the store's dir is injectable) so the real save folder is never touched.

const TEST_DIR := "user://test_user_levels/"

var _store: UserLevels


func before_each() -> void:
	_clear_dir()
	_store = UserLevels.new(TEST_DIR)


func after_all() -> void:
	_clear_dir()


func _clear_dir() -> void:
	var d := DirAccess.open(TEST_DIR)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir():
			d.remove(f)
		f = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(TEST_DIR)


func _sample(title: String, color: int = 1) -> LevelResource:
	var lv := LevelResource.new()
	lv.title = title
	lv.width = 3
	lv.num_colors = color + 1
	lv.danger_row = 12
	lv.layout = PackedStringArray(["%d%d%d" % [color, color, color]])
	return lv


# --- slug ---------------------------------------------------------------------


func test_slug_lowercases_and_replaces_symbols() -> void:
	assert_eq(
		UserLevels.slug("Twin Gallows!"), "twin_gallows", "spaces/symbols -> single underscore"
	)
	assert_eq(UserLevels.slug("The  Pit  3"), "the_pit_3", "runs collapse, digits kept")


func test_slug_falls_back_when_empty() -> void:
	assert_eq(UserLevels.slug("   "), "level", "blank name -> fallback slug")
	assert_eq(UserLevels.slug("!!!"), "level", "symbol-only name -> fallback slug")


# --- save / load round-trip ---------------------------------------------------


func test_save_then_load_round_trips() -> void:
	var path := _store.unique_path("Round Trip")
	assert_eq(_store.save(_sample("Round Trip"), path), OK, "save returns OK")
	assert_true(FileAccess.file_exists(path), "file written to disk")
	var loaded := _store.load_level(path)
	assert_not_null(loaded, "loads back as a LevelResource")
	assert_eq(loaded.title, "Round Trip", "title survives the round-trip")
	assert_eq(loaded.validate(), PackedStringArray(), "loaded level is still valid")


func test_unique_path_avoids_clobbering() -> void:
	var p1 := _store.unique_path("Dup")
	_store.save(_sample("Dup"), p1)
	var p2 := _store.unique_path("Dup")
	assert_ne(p2, p1, "second save of the same name gets a distinct path")
	_store.save(_sample("Dup"), p2)
	assert_eq(_store.list().size(), 2, "both files coexist")


# --- list ---------------------------------------------------------------------


func test_list_reports_titles_sorted() -> void:
	_store.save(_sample("Beta"), _store.unique_path("Beta"))
	_store.save(_sample("Alpha"), _store.unique_path("Alpha"))
	var entries := _store.list()
	assert_eq(entries.size(), 2, "both levels listed")
	assert_eq(entries[0].title, "Alpha", "sorted by title")
	assert_eq(entries[1].title, "Beta", "sorted by title")


func test_list_empty_when_none() -> void:
	assert_eq(_store.list().size(), 0, "fresh store lists nothing")


# --- delete -------------------------------------------------------------------


func test_delete_removes_the_file() -> void:
	var path := _store.unique_path("Doomed")
	_store.save(_sample("Doomed"), path)
	assert_eq(_store.delete(path), OK, "delete returns OK")
	assert_false(FileAccess.file_exists(path), "file gone from disk")
	assert_eq(_store.list().size(), 0, "no longer listed")
