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


# --- no legal attach cell -> miss, never a silent overwrite ----------------------


func test_no_legal_attach_cell_returns_sentinel() -> void:
	# A fully-enclosed impact: the collision cell and every candidate neighbour are
	# occupied, so there is no empty cell to attach to. _snap_cell must report failure
	# (x < 0) rather than returning an occupied/disconnected cell that attach() would
	# silently overwrite or strand.
	var s := _make_sim()
	var collided := Vector2i(5, 5)
	s.model.cells[collided] = 0
	for nb in Hex.neighbors(collided):
		s.model.cells[nb] = 0
	var p := Hex.cell_to_world(collided, s.origin, s.diameter)
	var cell := s._snap_cell(p, collided)
	assert_true(cell.x < 0, "no legal attach cell -> invalid sentinel")
	assert_false(s.model.cells.has(cell), "sentinel is not a settled sphere")


# --- bounce spheres: reflect the shot like a wall, never catch it -----------------
# Cell (5, 3) is at world (654, 225.5): odd row (+28 offset), row 3 -> y = 80 + 3·56·0.866.


func _path_min_y(path: PackedVector2Array) -> float:
	var m := INF
	for p in path:
		m = minf(m, p.y)
	return m


func test_bounce_reflects_dead_centre_shot() -> void:
	# Straight up into the centre of a bounce: it ricochets straight back down and exits
	# the bottom. Crucially it turns around at the sphere (~y265), never climbing to the
	# top wall (~y80) — that's how we know it bounced rather than passed through.
	var s := _make_sim()
	s.model.cells[Vector2i(5, 3)] = GridModel.BOUNCE
	var sim := s.simulate(Vector2(654, 690), Vector2(0, -1))
	assert_true(sim.get("miss", false), "a dead-centre bounce sends the ball back out the bottom")
	assert_gt(
		_path_min_y(sim.path), 200.0, "ball bounced off the sphere, never reached the top wall"
	)


func test_bounce_is_never_an_attach_target() -> void:
	var s := _make_sim()
	var bcell := Vector2i(5, 3)
	s.model.cells[bcell] = GridModel.BOUNCE
	var sim := s.simulate(Vector2(654, 690), Vector2(0, -1))
	if sim.has("cell"):
		assert_ne(sim.cell, bcell, "a fired sphere never attaches onto a bounce bubble")
	assert_eq(s.model.cells[bcell], GridModel.BOUNCE, "the bounce sphere is left untouched")


func test_bounce_graze_outside_hitbox_threads_past() -> void:
	# 47px to the side is outside the flying hitbox (0.78·56 ≈ 44), so the ball slips by
	# without bouncing and climbs to the top wall (small min-y) before exiting.
	var s := _make_sim()
	s.model.cells[Vector2i(5, 3)] = GridModel.BOUNCE
	var sim := s.simulate(Vector2(654.0 - 47.0, 690), Vector2(0, -1))
	assert_true(sim.get("miss", false), "a 47px graze threads past the bounce")
	assert_lt(_path_min_y(sim.path), 150.0, "no bounce: the ball reached the top wall")


func test_bounce_field_always_terminates() -> void:
	# A thicket of bounce bubbles: however the ball ricochets, simulate() must return a
	# result (the bounce budget + step cap guarantee termination) and never report a
	# bounce cell as the landing.
	var s := _make_sim()
	for r in range(2, 6):
		for c in range(3, 8):
			s.model.cells[Vector2i(c, r)] = GridModel.BOUNCE
	var sim := s.simulate(Vector2(640, 690), Vector2(0.3, -1))
	assert_true(sim.has("miss") or sim.has("cell"), "simulate terminates with a result")
	if sim.has("cell"):
		assert_ne(s.model.cells.get(sim.cell, 999), GridModel.BOUNCE, "never lands on a bounce")
