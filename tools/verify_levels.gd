extends SceneTree
## Release gate: load every authored level the way the game does and fail the
## build (non-zero exit) if any is missing or invalid. Catches export-time
## resource corruption — e.g. a custom-resource property silently dropped during
## the .tres -> binary .res conversion, which shipped 0.1.1 with empty layouts.
## Run headless against the EXPORTED pack so it tests the real artifact, not the
## source tree:
##   godot --headless --main-pack <pack>.pck -s res://tools/verify_levels.gd
## Duck-typed (no hard LevelResource dependency) so a resource that lost its
## script still fails loudly instead of crashing the verifier.

const LEVEL_COUNT := 10


func _initialize() -> void:
	var failures := 0
	for i in range(1, LEVEL_COUNT + 1):
		var path := "res://levels/level_%02d.tres" % i
		var lv: Resource = ResourceLoader.load(path)
		if lv == null:
			push_error("verify_levels: level %d failed to load: %s" % [i, path])
			failures += 1
			continue
		if not lv.has_method("validate"):
			push_error("verify_levels: level %d is not a LevelResource (script lost?): %s" % [i, path])
			failures += 1
			continue
		var problems: PackedStringArray = lv.call("validate")
		if not problems.is_empty():
			push_error("verify_levels: level %d invalid: %s" % [i, "; ".join(problems)])
			failures += 1
			continue
		print("verify_levels: OK  %d  %s" % [i, str(lv.get("title"))])
	if failures > 0:
		printerr("verify_levels: FAILED — %d of %d level(s) bad" % [failures, LEVEL_COUNT])
		quit(1)
		return
	print("verify_levels: all %d levels valid" % LEVEL_COUNT)
	quit(0)
