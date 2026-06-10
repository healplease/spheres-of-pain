extends GutTest

## Tests for ShotSimulator — pure logic on the 2D play plane (no scene needed).
## A shot into empty space bounces off the top and exits the bottom (MISS); a
## shot into a sphere attaches (HIT).


func _make_sim() -> ShotSimulator:
	var m := GridModel.new()
	m.width = 11
	m.num_colors = 5
	m.danger_row = 12
	var s := ShotSimulator.new()
	s.model = m
	s.diameter = 56.0
	s.columns = 11
	s.origin = Vector2(346, 80)
	s.play_left = 346.0 - 28.0
	s.play_right = 346.0 + 10 * 56.0 + 56.0
	s.play_bottom = 720.0
	return s


func test_shot_into_empty_centre_misses() -> void:
	var s := _make_sim()
	s.model.cells[Vector2i(0, 0)] = 0  # a lone sphere far to the left
	var sim := s.simulate(Vector2(640, 690), Vector2(0, -1))
	assert_true(sim.get("miss", false), "straight-up into an empty centre should miss")


func test_shot_into_centre_stack_hits() -> void:
	var s := _make_sim()
	for r in range(5):
		s.model.cells[Vector2i(5, r)] = 0
	var sim := s.simulate(Vector2(640, 690), Vector2(0, -1))
	assert_false(sim.get("miss", true), "straight-up into a stack should hit")
	assert_true(sim.has("cell"), "a hit returns a snap cell")


# --- threading: the moving sphere's hitbox is smaller than it looks --------------
# Cell (5, 3) sits at world x = 654 (odd row, +28 offset). A straight-up shot grazes
# it at a perpendicular distance equal to |654 - muzzle.x|.

func test_close_pass_threads_the_gap() -> void:
	# 47 px away: inside where two rendered spheres would touch (0.92·56 ≈ 51), but
	# outside the reduced flying hitbox (0.78·56 ≈ 44) — so the shot slips past.
	var s := _make_sim()
	s.model.cells[Vector2i(5, 3)] = 0
	var sim := s.simulate(Vector2(654.0 - 47.0, 690), Vector2(0, -1))
	assert_true(sim.get("miss", false), "a 47px graze threads past, not a hit")


func test_near_pass_still_hits() -> void:
	# 30 px away: well within the flying hitbox, so it still collides and attaches.
	var s := _make_sim()
	s.model.cells[Vector2i(5, 3)] = 0
	var sim := s.simulate(Vector2(654.0 - 30.0, 690), Vector2(0, -1))
	assert_false(sim.get("miss", true), "a 30px pass is inside the hitbox and hits")
	assert_true(sim.has("cell"), "a hit returns a snap cell")
