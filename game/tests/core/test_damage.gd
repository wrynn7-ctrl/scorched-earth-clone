extends GutTest


func _tank_at(x: int, y: int) -> TankState:
	var t := TankState.new()
	t.x = x
	t.y = y
	return t


func test_direct_hit_is_full_damage() -> void:
	var t: TankState = _tank_at(500, 600)
	assert_eq(Damage.distance_to_tank(500, 595, t), 0)
	assert_eq(Damage.amount(0, 28, 55), 55)
	assert_eq(Damage.distance_to_tank(488, 588, t), 0, "top-left cell is inside")
	assert_eq(Damage.distance_to_tank(511, 599, t), 0, "bottom-right cell is inside")


func test_distance_at_or_beyond_radius_is_zero() -> void:
	assert_eq(Damage.amount(28, 28, 55), 0)
	assert_eq(Damage.amount(29, 28, 55), 0)
	assert_eq(Damage.amount(1000, 28, 55), 0)
	assert_eq(Damage.amount(0, 0, 55), 0, "r = 0 does no damage")


func test_minimum_one_inside_radius() -> void:
	assert_eq(Damage.amount(27, 28, 55), 1)
	assert_eq(Damage.amount(27, 28, 1), 1)


func test_monotonic_decreasing_with_distance() -> void:
	var prev: int = 1 << 30
	for d: int in range(0, 40):
		var a: int = Damage.amount(d, 28, 55)
		assert_true(a <= prev, "non-increasing at d=%d" % d)
		if d < 28:
			assert_true(a >= 1)
		prev = a
	assert_eq(Damage.amount(14, 28, 55), 27)


func test_distance_to_box_edges_and_corner() -> void:
	var t: TankState = _tank_at(500, 600)
	assert_eq(Damage.distance_to_tank(520, 595, t), 9, "right of box: nearest cell x=511")
	assert_eq(Damage.distance_to_tank(500, 610, t), 11, "below box: nearest cell y=599")
	assert_eq(Damage.distance_to_tank(500, 580, t), 8, "above box: nearest cell y=588")
	assert_eq(Damage.distance_to_tank(515, 584, t), 5, "corner: dx=4, dy=-4 -> isqrt(32)")


func test_compute_for_state() -> void:
	var s: MatchState = SimTestUtil.flat_state(3)
	s.tanks[0].x = 300
	s.tanks[1].x = 320
	s.tanks[2].x = 900
	var res: Array[Dictionary] = Damage.compute(s, 310, 594, 28, 55)
	assert_eq(res.size(), 2, "far tank is untouched")
	assert_eq(res[0]["tank"], 0)
	assert_eq(res[0]["amount"], 55)
	assert_eq(res[1]["tank"], 1)
	assert_eq(res[1]["amount"], 55)
	s.tanks[1].alive = false
	assert_eq(Damage.compute(s, 310, 594, 28, 55).size(), 1, "dead tanks are skipped")
	var before: String = Simulation.fingerprint(s)
	Damage.compute(s, 310, 594, 28, 55)
	assert_eq(Simulation.fingerprint(s), before, "compute is pure")
