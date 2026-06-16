extends GutTest

## Tests for BoardView3D.mat_for — the single colour/sentinel -> material dispatch
## shared by the board, projectile, and muzzle. Pure (static) and headless-safe.


func test_mat_for_dispatches_specials_and_colours() -> void:
	var black := StandardMaterial3D.new()
	var spin := StandardMaterial3D.new()
	var bounce := StandardMaterial3D.new()
	var specials := {
		GridModel.BLACK: black,
		GridModel.SPIN: spin,
		GridModel.BOUNCE: bounce,
	}
	var mats := [StandardMaterial3D.new(), StandardMaterial3D.new(), StandardMaterial3D.new()]
	assert_eq(BoardView3D.mat_for(mats, specials, GridModel.BLACK), black, "black -> obsidian")
	assert_eq(BoardView3D.mat_for(mats, specials, GridModel.SPIN), spin, "spin -> swirl")
	assert_eq(BoardView3D.mat_for(mats, specials, GridModel.BOUNCE), bounce, "bounce -> pulse")
	assert_eq(BoardView3D.mat_for(mats, specials, 0), mats[0], "colour 0 -> palette 0")
	assert_eq(BoardView3D.mat_for(mats, specials, 1), mats[1], "colour 1 -> palette 1")


func test_mat_for_wraps_high_colour_ids() -> void:
	var mats := [StandardMaterial3D.new(), StandardMaterial3D.new(), StandardMaterial3D.new()]
	assert_eq(
		BoardView3D.mat_for(mats, {}, 5), mats[5 % mats.size()], "colour id wraps into the palette"
	)
