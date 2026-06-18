class_name UserLevels
extends RefCounted

## Persistence for player-authored levels: real LevelResource .tres files under
## user://levels/, saved with ResourceSaver and loaded through the exact same path
## as the built-in res://levels/ files (no parallel format). Mirrors the
## ProgressStore pattern — the directory is injectable so tests use a throwaway one.

const DIR := "user://levels/"

var dir: String


func _init(save_dir: String = DIR) -> void:
	dir = save_dir
	_ensure_dir()


func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(dir)


## A filesystem-safe, lower-case slug for a level name: non-alphanumeric runs become
## single underscores, with a fallback so a blank/symbol-only name still yields a file.
static func slug(name: String) -> String:
	var out := ""
	for ch in name.strip_edges().to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif not out.ends_with("_"):
			out += "_"
	out = out.trim_prefix("_").trim_suffix("_")
	return out if not out.is_empty() else "level"


## A not-yet-taken path for a new level named `name` (slug + a numeric suffix if the
## bare slug is already on disk), so saving two "Twin Gallows" never clobbers the first.
func unique_path(name: String) -> String:
	var base := dir.path_join(slug(name))
	var candidate := base + ".tres"
	var i := 2
	while FileAccess.file_exists(candidate):
		candidate = "%s_%d.tres" % [base, i]
		i += 1
	return candidate


## Write `level` to `path` (use unique_path() for a new file, or an existing path to
## overwrite when editing). Returns an Error code; the directory is ensured first.
func save(level: LevelResource, path: String) -> int:
	_ensure_dir()
	return ResourceSaver.save(level, path)


## Every saved level as {path, title}, sorted by title — what the My Levels screen
## paginates. Unreadable / non-LevelResource files are skipped.
func list() -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir() and f.ends_with(".tres"):
			var path := dir.path_join(f)
			var lv := load(path) as LevelResource
			if lv != null:
				out.append({"path": path, "title": lv.title})
		f = d.get_next()
	d.list_dir_end()
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a.title.naturalnocasecmp_to(b.title) < 0
	)
	return out


func load_level(path: String) -> LevelResource:
	return load(path) as LevelResource


func delete(path: String) -> int:
	return DirAccess.remove_absolute(path)
