extends GutTest
## The aim search (AimSolver) and its fast shell model (AiFlight) against the real physics.


func _flat(dist: int, wind: int = 0) -> MatchState:
	return AiTestUtil.flat_duel(SimConstants.CTRL_EXPERT, dist, wind, {"pulse_missile": 5})


func _ctx(state: MatchState, wind: int, dir: int = 1, row: int = -1) -> AimSolver.Ctx:
	AimSolver.reset_budget()
	var t: TankState = state.tanks[0]
	var c: AimSolver.Ctx = AimSolver.new_ctx(state, 0, t.x, t.y, wind, dir, AiFlight.new(state.terrain))
	c.row = row
	return c


func test_surface_matches_the_terrain() -> void:
	var state: MatchState = AiTestUtil.duel(3, SimConstants.CTRL_EXPERT, 600, 0)
	var flight := AiFlight.new(state.terrain)
	for x: int in range(0, SimConstants.WORLD_W, 37):
		assert_eq(flight.surface(x), state.terrain.surface_y(x), "column %d" % x)
	assert_eq(flight.rest_y(700), TankState.rest_y(state.terrain, 700))


func test_model_flight_matches_ballistics_trace() -> void:
	# Free flights on generated terrain: where the model says a shell comes down is where
	# Ballistics.trace says it does (within 2 cells), except when a tank box is hit first.
	var checked: int = 0
	var agree: int = 0
	for i: int in range(150):
		var r: Rng = Rng.derive(i, 31)
		var state: MatchState = AiTestUtil.duel(200 + i, SimConstants.CTRL_EXPERT, r.range_int(300, 1200), 0)
		var me: TankState = state.tanks[0]
		var angle: int = r.range_int(200, 1600)
		var power: int = r.range_int(150, 1000)
		var wind: int = r.range_int(-100, 100)
		var tr: Dictionary = Ballistics.trace(state, 0, angle, power, "pulse_missile", wind, 700)
		if tr["end_reason"] != "terrain" and tr["end_reason"] != "lost":
			continue
		var flight := AiFlight.new(state.terrain)
		flight.fly_shot(me.x, me.y, angle, power, wind, 700)
		checked += 1
		if absi(flight.r_x - (tr["end_x"] as int)) <= 2:
			agree += 1
	gut.p("MODEL   landing within 2 cells of Ballistics.trace in %d/%d random flights" % [agree, checked])
	assert_gt(checked, 100)
	assert_gte(agree * 100, 98 * checked)


func test_model_matches_trace_exactly_for_a_free_flight_to_the_floor() -> void:
	var state: MatchState = _flat(700, 40)
	var me: TankState = state.tanks[0]
	var tr: Dictionary = Ballistics.trace(state, 0, 520, 640, "pulse_missile", 40, 700)
	var flight := AiFlight.new(state.terrain)
	flight.fly_shot(me.x, me.y, 520, 640, 40, 700)
	assert_eq(flight.r_x, tr["end_x"])
	assert_eq(flight.r_y, tr["end_y"])
	assert_eq(flight.r_px, tr["px"])
	assert_eq(flight.r_vy, tr["vy"])
	assert_eq(flight.r_reason, AiFlight.REASON_TERRAIN)


func test_solve_power_lands_on_the_aim_point() -> void:
	for dist: int in [320, 600, 900, 1250]:
		for wind: int in [-90, 0, 70]:
			var state: MatchState = _flat(dist, wind)
			var c: AimSolver.Ctx = _ctx(state, wind)
			var plan: Dictionary = AimSolver.solve_power(c, 480, 300 + dist)
			assert_lte(absi(plan["err"] as int), AimSolver.TOL_ACCEPT, "dist %d wind %d: %s" % [dist, wind, str(plan)])
			var tr: Dictionary = Ballistics.trace(state, 0, 480, plan["power"], "pulse_missile", wind, 700)
			assert_lte(absi((tr["end_x"] as int) - 300 - dist), 20, "real landing, dist %d wind %d" % [dist, wind])


func test_solve_power_works_to_the_left_with_mirrored_angles() -> void:
	var state: MatchState = _flat(700)
	# Shoot from the right tank at the left one.
	var t: TankState = state.tanks[1]
	AimSolver.reset_budget()
	var c: AimSolver.Ctx = AimSolver.new_ctx(state, 1, t.x, t.y, 0, -1, AiFlight.new(state.terrain))
	var plan: Dictionary = AimSolver.solve_direct(c, state.tanks[0].x, 450)
	assert_true(plan["ok"])
	assert_gt(plan["angle"], 900, "mirrored angle for a shot to the left")
	var tr: Dictionary = Ballistics.trace(state, 1, plan["angle"], plan["power"], "pulse_missile", 0, 700)
	assert_lte(absi((tr["end_x"] as int) - state.tanks[0].x), 20)


func test_a_tall_wall_makes_the_solver_lob_steeply() -> void:
	var state: MatchState = _flat(900)
	# A 330-cell wall between the tanks (top at y = 270).
	state.terrain.flatten(560, 620, 270)
	var c: AimSolver.Ctx = _ctx(state, 0, 1, state.tanks[1].y - 6)
	var plan: Dictionary = AimSolver.solve_direct(c, state.tanks[1].x, 450)
	assert_true(plan["ok"], "a steep lob clears the wall: %s" % str(plan))
	assert_gt(plan["angle"], 450 + 100, "steeper than the preferred 45 degrees")
	var tr: Dictionary = Ballistics.trace(state, 0, plan["angle"], plan["power"], "pulse_missile", 0, 700)
	assert_eq(tr["hit_tank"], 1, "and it really lands on the target")


func test_an_unreachable_target_is_reported_not_ok() -> void:
	var state: MatchState = _flat(1250, -100)  # a gale straight into the shell
	var c: AimSolver.Ctx = _ctx(state, -100)
	var plan: Dictionary = AimSolver.solve_direct(c, 2600, 450)  # beyond any shell's reach
	assert_false(plan["ok"])
	assert_lte(plan["power"], SimConstants.MAX_POWER)
	assert_lt(plan["err"], 0, "it falls short of the aim point")


func test_verify_confirms_a_seeker_shot_with_the_real_trace() -> void:
	# The model flies a plain shell; the Seeker steers itself. verify() asks the real trace,
	# and the Seeker's homing lands it on the target (or the aim is shifted until it does).
	var fixed: int = 0
	for i: int in range(20):
		var state: MatchState = _flat(800 + i * 10, 60)
		var c: AimSolver.Ctx = _ctx(state, 60, 1, state.tanks[1].y - 6)
		var plan: Dictionary = AimSolver.solve_direct(c, state.tanks[1].x, 450)
		AimSolver.reset_budget()
		var checked: Dictionary = AimSolver.verify(c, plan, "seeker", 1, state.tanks[1].x)
		assert_lte(AimSolver.trace_count, AimSolver.MAX_VERIFY)
		assert_true(checked["verified"])
		if checked["hit"] or absi(checked["real_err"] as int) <= AimSolver.VERIFY_TOL:
			fixed += 1
	gut.p("VERIFY  seeker shots confirmed or corrected by real-trace feedback: %d/20" % fixed)
	assert_gte(fixed, 16)


func test_a_correct_plan_costs_one_confirming_trace() -> void:
	var state: MatchState = _flat(800)
	var c: AimSolver.Ctx = _ctx(state, 0, 1, state.tanks[1].y - 6)
	var plan: Dictionary = AimSolver.solve_direct(c, state.tanks[1].x, 450)
	AimSolver.reset_budget()
	var checked: Dictionary = AimSolver.verify(c, plan, "pulse_missile", 1, state.tanks[1].x)
	assert_true(checked["verified"])
	assert_true(checked["hit"] or absi(checked["real_err"] as int) <= AimSolver.VERIFY_TOL)
	assert_eq(AimSolver.trace_count, 1, "a correct plan needs one confirmation only")


func test_needs_verify_only_when_the_model_can_be_wrong() -> void:
	var state: MatchState = _flat(800)
	var c: AimSolver.Ctx = _ctx(state, 0)
	assert_false(AimSolver.needs_verify(c, 1, state.tanks[1].x, "pulse_missile"), "plain duel")
	assert_false(AimSolver.needs_verify(c, 1, state.tanks[1].x, "seeker"), "a Seeker steers itself in: plain aim is enough")
	state.wells.append({"owner": 1, "x": 600, "y": 400, "expires_turn": 9})
	state.tanks[1].repulsor_charge = 10
	assert_false(AimSolver.needs_verify(c, 1, state.tanks[1].x, "pulse_missile"), "wells and repulsors are in the model")
	# A third tank: an enemy in the way is just hit instead; a teammate is not wanted there.
	var third := TankState.new()
	third.id = 2
	third.team = 2
	third.x = 700
	third.y = state.tanks[0].y
	state.tanks.append(third)
	assert_false(AimSolver.needs_verify(c, 1, state.tanks[1].x, "pulse_missile"), "enemy between")
	third.team = state.tanks[0].team
	assert_true(AimSolver.needs_verify(c, 1, state.tanks[1].x, "pulse_missile"), "teammate between")


func test_model_follows_repulsor_fields_like_the_real_trace() -> void:
	var agree: int = 0
	var deflected: int = 0
	for i: int in range(40):
		var r: Rng = Rng.derive(i, 62)
		var state: MatchState = _flat(700 + i * 8)
		state.tanks[1].repulsor_charge = r.range_int(10, 100)
		var angle: int = r.range_int(350, 700)
		var power: int = r.range_int(450, 800)
		var tr: Dictionary = Ballistics.trace(state, 0, angle, power, "pulse_missile", 0, 420)
		var flight := AiFlight.new(state.terrain, state.wells, AiPlayer.others_with_repulsors(state, state.tanks[0]))
		flight.fly_shot(300, state.tanks[0].y, angle, power, 0, 420)
		var plain := AiFlight.new(state.terrain)
		plain.fly_shot(300, state.tanks[0].y, angle, power, 0, 420)
		if absi(plain.r_x - flight.r_x) > 5:
			deflected += 1
		# A shell that enters the target's box is a hit in the real trace (the model has no boxes).
		if tr["end_reason"] == "tank" or absi(flight.r_x - (tr["end_x"] as int)) <= 2:
			agree += 1
	gut.p("MODEL   repulsor fields: shot deflected in %d/40 flights; model agrees with the real trace in %d/40" % [deflected, agree])
	assert_gte(deflected, 5, "the scenario really exercises the field")
	assert_gte(agree, 38)


func test_model_follows_gravity_wells_like_the_real_trace() -> void:
	var agree: int = 0
	for i: int in range(40):
		var r: Rng = Rng.derive(i, 61)
		var state: MatchState = _flat(900)
		state.wells.append({"owner": 1, "x": r.range_int(500, 1000), "y": r.range_int(300, 560), "expires_turn": 9})
		var angle: int = r.range_int(350, 800)
		var power: int = r.range_int(400, 900)
		var tr: Dictionary = Ballistics.trace(state, 0, angle, power, "pulse_missile", 0, 700)
		if tr["end_reason"] != "terrain":
			agree += 1  # (a shell caught in a well's orbit is not compared)
			continue
		var flight := AiFlight.new(state.terrain, state.wells)
		flight.fly_shot(300, state.tanks[0].y, angle, power, 0, 700)
		if absi(flight.r_x - (tr["end_x"] as int)) <= 2:
			agree += 1
	assert_gte(agree, 38, "the model includes wells: %d/40 flights agree" % agree)


func test_trace_budget_is_enforced() -> void:
	var state: MatchState = _flat(800)
	AimSolver.reset_budget()
	for _i: int in range(AimSolver.TRACE_BUDGET + 5):
		AimSolver.counted_trace(state, 0, 450, 500, "pulse_missile", 0)
	assert_eq(AimSolver.trace_count, AimSolver.TRACE_BUDGET)
	assert_true(AimSolver.counted_trace(state, 0, 450, 500, "pulse_missile", 0).is_empty())
	assert_eq(AimSolver.traces_left(), 0)
	AimSolver.reset_budget()
	assert_eq(AimSolver.traces_left(), AimSolver.TRACE_BUDGET)


func test_beam_angle_points_the_lance_at_the_target() -> void:
	for dist: int in [300, 700, 850]:
		var state: MatchState = _flat(dist)
		state.tanks[1].y = 560  # on a small rise
		state.terrain.flatten(state.tanks[1].x - 14, state.tanks[1].x + 13, 560)
		var me: TankState = state.tanks[0]
		var t: TankState = state.tanks[1]
		var angle: int = AimSolver.beam_angle(me.x, me.y, t.x, t.y - SimConstants.TANK_H / 2)
		var tr: Dictionary = Ballistics.trace_beam(state, 0, angle, WeaponDefs.get_def("photon_lance"))
		assert_eq(tr["hit_tank"], 1, "beam at dist %d angle %d" % [dist, angle])


func test_model_x_at_row_reads_an_old_shot_independent_of_its_crater() -> void:
	var state: MatchState = _flat(700)
	var me: TankState = state.tanks[0]
	var tr: Dictionary = Ballistics.trace(state, 0, 470, 600, "pulse_missile", 0, 700)
	var before: int = AimSolver.model_x_at_row(AiFlight.new(state.terrain), me.x, me.y, 470, 600, 0, tr["end_y"])
	state.terrain.carve_circle(tr["end_x"], tr["end_y"], 60)  # the crater it would have made
	var after: int = AimSolver.model_x_at_row(AiFlight.new(state.terrain), me.x, me.y, 470, 600, 0, tr["end_y"])
	assert_eq(after, before)
	assert_lte(absi(before - (tr["end_x"] as int)), 2)
