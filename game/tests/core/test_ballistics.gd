extends GutTest


func _trace(s: MatchState, angle: int, power: int, wind: int) -> Dictionary:
	return Ballistics.trace(s, 0, angle, power, "pulse_missile", wind, SimConstants.MAX_FLIGHT_TICKS)


func test_straight_up_returns_near_launch_x() -> void:
	var s: MatchState = SimTestUtil.flat_state()
	var tr: Dictionary = _trace(s, 900, 400, 0)
	var ex: int = tr["end_x"]
	assert_true(absi(ex - s.tanks[0].x) <= 1, "end_x %d vs %d" % [ex, s.tanks[0].x])
	# It climbs well above the muzzle, then comes back down onto its own tank.
	var path: PackedInt32Array = tr["path"]
	var min_y: int = 1 << 40
	for i: int in range(1, path.size(), 2):
		min_y = mini(min_y, path[i])
	assert_true(FixedMath.to_cell(min_y) < SimTestUtil.GROUND_Y - 100, "apex height")
	assert_eq(tr["end_reason"], "tank")
	assert_eq(tr["hit_tank"], 0, "falls back onto the shooter's own tank")


func test_straight_up_path_is_vertical_without_wind() -> void:
	var s: MatchState = SimTestUtil.flat_state()
	var path: PackedInt32Array = _trace(s, 900, 300, 0)["path"]
	for i: int in range(0, path.size(), 2):
		assert_eq(path[i], FixedMath.from_cell(s.tanks[0].x), "x constant at tick %d" % (i / 2))


func test_wind_pushes_shot() -> void:
	var s: MatchState = SimTestUtil.flat_state()
	var zero: int = _trace(s, 450, 600, 0)["end_x"]
	var right: int = _trace(s, 450, 600, 50)["end_x"]
	var left: int = _trace(s, 450, 600, -50)["end_x"]
	assert_gt(right, zero, "positive wind -> further right")
	assert_lt(left, zero, "negative wind -> further left")


func test_wind_use_state() -> void:
	var s: MatchState = SimTestUtil.flat_state()
	s.wind = 40
	var from_state: Dictionary = Ballistics.trace(s, 0, 450, 600, "pulse_missile", SimConstants.WIND_USE_STATE, 1500)
	var explicit: Dictionary = _trace(s, 450, 600, 40)
	assert_eq(from_state["path"], explicit["path"])
	assert_ne(from_state["path"], _trace(s, 450, 600, 0)["path"])


func test_45_degrees_goes_further_than_20() -> void:
	var s: MatchState = SimTestUtil.flat_state()
	var far: int = _trace(s, 450, 600, 0)["end_x"]
	var near: int = _trace(s, 200, 600, 0)["end_x"]
	assert_gt(far, near)
	assert_gt(far, s.tanks[0].x + 400, "45 deg at power 600 flies a good distance")
	assert_eq(_trace(s, 450, 600, 0)["end_reason"], "terrain")


func test_full_power_crosses_the_map() -> void:
	# Gameplay sanity (ARCHITECTURE section 6 tuning): power 800-1000 at 45 deg must cross the map.
	var s: MatchState = SimTestUtil.flat_state()
	s.tanks[0].x = 100
	s.tanks[1].x = 1500
	s.tanks[1].alive = false  # nothing in the way
	var r800: int = _trace(s, 450, 800, 0)["end_x"]
	var r1000: Dictionary = _trace(s, 450, 1000, 0)
	assert_gt(r800, 100 + 1000, "power 800 range %d" % r800)
	var e1000: int = r1000["end_x"]
	assert_true(e1000 > 100 + 1500 or r1000["end_reason"] == "lost", "power 1000 range %d" % e1000)


func test_off_side_edge_is_lost() -> void:
	var s: MatchState = SimTestUtil.flat_state()
	s.tanks[0].x = 50
	var tr: Dictionary = _trace(s, 1350, 600, 0)
	assert_eq(tr["end_reason"], "lost")
	var ex: int = tr["end_x"]
	assert_true(ex < 0 or ex >= SimConstants.WORLD_W)
	assert_eq(tr["hit_tank"], -1)
	assert_eq(_trace(s, 1800, 1000, 0)["end_reason"], "lost")


func test_shot_above_the_screen_comes_back() -> void:
	var s: MatchState = SimTestUtil.flat_state()
	var path: PackedInt32Array = _trace(s, 900, 1000, 0)["path"]
	var min_y: int = 1 << 40
	for i: int in range(1, path.size(), 2):
		min_y = mini(min_y, path[i])
	assert_true(min_y < 0, "went above y=0")
	assert_eq(_trace(s, 900, 1000, 0)["end_reason"], "tank")


func test_shooter_not_hit_at_launch() -> void:
	var s: MatchState = SimTestUtil.flat_state()
	for angle: int in range(0, 1801, 100):
		var tr: Dictionary = _trace(s, angle, 500, 0)
		var hit: int = tr["hit_tank"]
		var ticks: int = tr["ticks"]
		if hit == 0:
			assert_gt(ticks, 10, "angle %d must not self-hit at launch" % angle)
	# Low-speed flat shots drop to the ground beside the tank without touching it.
	var low_right: Dictionary = _trace(s, 0, 1, 0)
	assert_eq(low_right["end_reason"], "terrain")
	assert_eq(low_right["hit_tank"], -1)
	var low_left: Dictionary = _trace(s, 1800, 1, 0)
	assert_eq(low_left["end_reason"], "terrain")


func test_other_tank_is_hit() -> void:
	var s: MatchState = SimTestUtil.flat_state()
	var p: int = SimTestUtil.power_for_target(s, 450, s.tanks[1].x)
	var tr: Dictionary = _trace(s, 450, p, 0)
	assert_eq(tr["hit_tank"], 1)
	assert_eq(tr["end_reason"], "tank")
	s.tanks[1].alive = false
	assert_eq(_trace(s, 450, p, 0)["hit_tank"], -1, "dead tanks are ignored")


func test_trace_does_not_mutate_state() -> void:
	var s: MatchState = SimTestUtil.flat_state()
	var before: String = Simulation.fingerprint(s)
	_trace(s, 450, 700, 20)
	_trace(s, 900, 1000, 0)
	assert_eq(Simulation.fingerprint(s), before)


func test_timeout_and_max_ticks() -> void:
	var s: MatchState = SimTestUtil.flat_state()
	var tr: Dictionary = Ballistics.trace(s, 0, 900, 600, "pulse_missile", 0, 5)
	assert_eq(tr["end_reason"], "timeout")
	var path: PackedInt32Array = tr["path"]
	assert_eq(path.size(), 10, "5 ticks recorded")


func test_substeps_do_not_tunnel_thin_floor() -> void:
	# A very fast shot straight down must still stop at the ground, not skip through it.
	var s: MatchState = SimTestUtil.flat_state()
	s.tanks[0].x = 700
	var tr: Dictionary = _trace(s, 900, 1000, 0)
	assert_true(["tank", "terrain"].has(tr["end_reason"]))
	var tr2: Dictionary = Ballistics.trace(s, 0, 1700, 1000, "pulse_missile", 0, 1500)
	assert_true(tr2["end_reason"] != "timeout")


func test_deterministic() -> void:
	var s: MatchState = SimTestUtil.flat_state()
	assert_eq(_trace(s, 523, 777, 13)["path"], _trace(s, 523, 777, 13)["path"])
