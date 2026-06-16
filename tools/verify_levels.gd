extends SceneTree
## Release gate: load every authored level the way the game does and fail the
## build (non-zero exit) if any is missing or invalid. Catches export-time
## resource corruption — e.g. a custom-resource property silently dropped during
## the .tres -> binary .res conversion, which shipped 0.1.1 with empty layouts.
## Run headless against the EXPORTED pack so it tests the real artifact, not the
## source tree:
##   godot --headless --main-pack <pack>.pck -s res://tools/verify_levels.gd
##
## SELF-CONTAINED ON PURPOSE: this folder carries a .gdignore, so Godot never
## scans it and autoload globals (GameState, Log, …) are NOT visible here — a
## reference to them is a compile error. So the level set is discovered by
## probing res://levels/level_NN.tres (ResourceLoader honours export remaps),
## which also keeps the gate from drifting out of sync with how many levels ship.
## validate() is duck-typed (has_method, not `is LevelResource`) so a resource
## that lost its script still fails loudly instead of crashing the verifier.

const PATH_FMT := "res://levels/level_%02d.tres"


func _initialize() -> void:
	var failures := 0
	var checked := 0
	var i := 1
	# Levels are numbered contiguously from 1, exactly how the game enumerates
	# them; stop at the first gap and treat what came before as the full set.
	while ResourceLoader.exists(PATH_FMT % i):
		var path := PATH_FMT % i
		checked += 1
		var lv: Resource = ResourceLoader.load(path)
		if lv == null:
			push_error("verify_levels: level %d failed to load: %s" % [i, path])
			failures += 1
		elif not lv.has_method("validate"):
			push_error(
				"verify_levels: level %d is not a LevelResource (script lost?): %s" % [i, path]
			)
			failures += 1
		else:
			var problems: PackedStringArray = lv.call("validate")
			if not problems.is_empty():
				push_error("verify_levels: level %d invalid: %s" % [i, "; ".join(problems)])
				failures += 1
			else:
				print("verify_levels: OK  %d  %s" % [i, str(lv.get("title"))])
		i += 1
	if checked == 0:
		printerr("verify_levels: FAILED — no levels found at %s" % PATH_FMT)
		quit(1)
		return
	if failures > 0:
		printerr("verify_levels: FAILED — %d of %d level(s) bad" % [failures, checked])
		quit(1)
		return
	print("verify_levels: all %d levels valid" % checked)
	quit(0)
