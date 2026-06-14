extends Node

## Autoload "Log" — the game's observability bus. ONE place that formats and routes
## every diagnostic line, so a bug report (or a Claude debugging session) has a single,
## consistent, greppable record of what the game did.
##
## Why an autoload (not a pure helper): it owns process-wide state (the open log file,
## the level threshold) and must persist across scene changes, like Sound / Settings.
## The pure-logic core (GridModel, ShotSimulator, the *Stores) stays free of it — views
## and controllers observe the model and log on its behalf, preserving the model/view
## split. Nothing in `scripts/core/` should ever call Log.
##
## Usage:
##   Log.info(Log.PLAY, "level ready", {"id": 3, "size": "14x9"})
##   Log.debug(Log.SHOT, "fire", {"color": 2, "aim": aim, "result": "hit", "cell": cell})
##   Log.error(Log.FLOW, "level load failed", {"index": i, "path": path})
##
## Each call becomes one line, e.g.:
##   [   12.345] INFO  PLAY   level ready | id=3 size=14x9
##   [   12.902] DEBUG SHOT   fire | color=2 aim=(0.12,-0.99) result=hit cell=(5,3)
##
## Levels (ascending severity): TRACE < DEBUG < INFO < WARN < ERROR. Lines below
## `min_level` are dropped before formatting. Default threshold: DEBUG in debug builds,
## INFO in release; override with the env var SOP_LOG_LEVEL=trace|debug|info|warn|error.
##
## Sinks (both, independently):
##   - Console: print() for TRACE..INFO; push_warning()/push_error() for WARN/ERROR so
##     the Godot error stream (and the Godot MCP runtime/error queries) surface them.
##   - File: res://temp/session.log when run from the editor/MCP (gitignored; the path
##     Claude reads), otherwise user://logs/session.log for exported/web builds. The
##     previous run is kept as session-prev.log. Every line is flushed, so a crash keeps
##     the tail that led up to it.

enum Level { TRACE, DEBUG, INFO, WARN, ERROR }

## Subsystem tags. Kept short (<= 6 chars) so the column stays aligned, and as constants
## so call sites can't drift into typo'd variants that break grep.
const BOOT := "BOOT"      # session start/stop, environment
const FLOW := "FLOW"      # scene navigation + level loading (GameState)
const PLAY := "PLAY"      # a level's lifecycle: ready, danger escalation, end
const SHOT := "SHOT"      # the shooter: fire / miss
const MODEL := "MODEL"    # results read back off the GridModel (attach: pop/orphan)
const CONFIG := "CONFIG"  # settings pushed into live engine state

const _LEVEL_TAG := ["TRACE", "DEBUG", "INFO ", "WARN ", "ERROR"]
const _FILE_NAME := "session.log"
const _PREV_NAME := "session-prev.log"

var min_level: Level = Level.INFO
var _file: FileAccess = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep logging even if the tree is paused
	min_level = Level.DEBUG if OS.is_debug_build() else Level.INFO
	if OS.has_environment("SOP_LOG_LEVEL"):
		var parsed := _parse_level(OS.get_environment("SOP_LOG_LEVEL"))
		if parsed >= 0:
			min_level = parsed
	_open_file()
	_write_session_header()


func _exit_tree() -> void:
	info(BOOT, "session end")
	if _file != null:
		_file.close()
		_file = null


# --- public API ---------------------------------------------------------------

func trace(category: String, message: String, data: Dictionary = {}) -> void:
	_emit(Level.TRACE, category, message, data)

func debug(category: String, message: String, data: Dictionary = {}) -> void:
	_emit(Level.DEBUG, category, message, data)

func info(category: String, message: String, data: Dictionary = {}) -> void:
	_emit(Level.INFO, category, message, data)

func warn(category: String, message: String, data: Dictionary = {}) -> void:
	_emit(Level.WARN, category, message, data)

func error(category: String, message: String, data: Dictionary = {}) -> void:
	_emit(Level.ERROR, category, message, data)


## True if a line at `level` would be emitted. Guard expensive payloads with this:
##   if Log.enabled(Log.Level.TRACE): Log.trace(Log.MODEL, "board", {"dump": model.ascii()})
func enabled(level: Level) -> bool:
	return level >= min_level


# --- internals ----------------------------------------------------------------

func _emit(level: Level, category: String, message: String, data: Dictionary) -> void:
	if level < min_level:
		return
	var line := "[%9.3f] %s %-6s %s%s" % [
		Time.get_ticks_msec() / 1000.0,
		_LEVEL_TAG[level],
		category,
		message,
		_format_data(data),
	]
	match level:
		Level.WARN:
			push_warning(line)
		Level.ERROR:
			push_error(line)
		_:
			print(line)
	if _file != null:
		_file.store_line(line)
		_file.flush()   # low volume (event-driven, not per-frame); keep the tail through a crash


## Render a data dict as logfmt-style ` | key=value key=value`. Values are kept
## space-free (Vector2i -> "(5,3)", arrays -> "[a,b]") so the line splits cleanly on
## whitespace; only string values that contain spaces/quotes are quoted.
func _format_data(data: Dictionary) -> String:
	if data.is_empty():
		return ""
	var parts := PackedStringArray()
	for k in data:
		parts.append("%s=%s" % [k, _value(data[k])])
	return " | " + " ".join(parts)


func _value(v: Variant) -> String:
	if v is String:
		var s: String = v
		if s.is_empty() or s.contains(" ") or s.contains("\""):
			return "\"%s\"" % s.replace("\"", "'")
		return s
	if v is bool:
		return "true" if v else "false"
	if v is Vector2i:
		return "(%d,%d)" % [v.x, v.y]
	if v is Vector2:
		return "(%.2f,%.2f)" % [v.x, v.y]
	if v is Array:
		var items := PackedStringArray()
		for e in v:
			items.append(_value(e))
		return "[" + ",".join(items) + "]"
	return str(v)


## Choose a writable log directory and open the file, rotating the prior run aside.
## Prefers res://temp (gitignored, the path tooling reads) when running from the editor
## or the MCP; falls back to user://logs for exported/web builds where res:// is read-only.
## A failure to open is non-fatal: file logging is simply disabled, console logging stays.
func _open_file() -> void:
	var base := "res://temp" if OS.has_feature("editor") else "user://logs"
	DirAccess.make_dir_recursive_absolute(base)
	var path := base + "/" + _FILE_NAME
	if FileAccess.file_exists(path):
		var prev := base + "/" + _PREV_NAME
		DirAccess.remove_absolute(prev)         # rename can't overwrite on Windows
		DirAccess.rename_absolute(path, prev)   # keep exactly one prior session
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null and base != "user://logs":
		# res:// wasn't writable after all (e.g. an exported debug build) — fall back.
		DirAccess.make_dir_recursive_absolute("user://logs")
		_file = FileAccess.open("user://logs/" + _FILE_NAME, FileAccess.WRITE)


func _write_session_header() -> void:
	var where := _file.get_path_absolute() if _file != null else "(console only)"
	if _file != null:
		_file.store_line("==== Spheres of Pain — session log ============================================")
	info(BOOT, "session start", {
		"version": str(ProjectSettings.get_setting("application/config/version", "dev")),
		"time": Time.get_datetime_string_from_system(false, true),
		"platform": OS.get_name(),
		"debug": OS.is_debug_build(),
		"level": _LEVEL_TAG[min_level].strip_edges(),
		"file": where,
	})


func _parse_level(s: String) -> int:
	match s.strip_edges().to_upper():
		"TRACE": return Level.TRACE
		"DEBUG": return Level.DEBUG
		"INFO": return Level.INFO
		"WARN", "WARNING": return Level.WARN
		"ERROR": return Level.ERROR
	return -1
