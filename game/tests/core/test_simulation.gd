extends GutTest

const RANK: Dictionary = {
	"fire": 0, "projectile": 1, "projectile_end": 2, "explosion": 3, "terrain_carve": 4,
	"damage": 5, "terrain_settle": 6, "tank_fall": 7, "tank_destroyed": 9, "round_end": 10,
	"wind": 11, "turn": 12,
}


func _settings(seed_value: int, tanks: int, rounds: int = 3) -> MatchSettings:
	var s := MatchSettings.new()
	s.seed = seed_value
	s.num_tanks = tanks
	s.rounds = rounds
	return s


func _types(events: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in events:
		out.append(e["type"])
	return out


func _find(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in events:
		if e["type"] == type:
			out.append(e)
	return out


## Asserts the section 10 ordering rules and returns the rank sequence for further checks.
func _check_order(events: Array[Dictionary]) -> void:
	var last_rank: int = -1
	var seen_fall_damage: bool = false
	var last_tick: int = 0
	for e: Dictionary in events:
		var type: String = e["type"]
		assert_true(RANK.has(type), "known event type %s" % type)
		var rank: int = RANK[type]
		if type == "damage":
			if e["cause"] == "fall":
				rank = 7  # fall damage is paired with its tank_fall (ARCHITECTURE §10)
				seen_fall_damage = true
			else:
				assert_false(seen_fall_damage, "explosion damage precedes fall damage")
		assert_true(rank >= last_rank, "event order: %s after rank %d" % [type, last_rank])
		last_rank = rank
		var tick: int = e["tick"]
		assert_true(tick >= last_tick, "ticks non-decreasing")
		last_tick = tick
	assert_eq(events[0]["type"], "fire")
	var types: Array[String] = _types(events)
	var tail: Array[String] = [types[types.size() - 2], types[types.size() - 1]]
	assert_true(tail == (["wind", "turn"] as Array[String]) or types[types.size() - 1] == "round_end",
			"ends with wind+turn or round_end")


# --- new_match ---------------------------------------------------------------

func test_new_match_initial_state() -> void:
	var s: MatchState = Simulation.new_match(_settings(12345, 4))
	assert_eq(s.round_index, 0)
	assert_eq(s.phase, "aim")
	assert_eq(s.tanks.size(), 4)
	assert_eq(s.current_tank, 0)
	assert_eq(s.turn_number, 0)
	assert_true(absi(s.wind) <= SimConstants.WIND_MAX)
	assert_eq(s.terrain.width, SimConstants.WORLD_W)
	assert_eq(s.terrain.height, SimConstants.WORLD_H)
	var prev_x: int = -1
	for t: TankState in s.tanks:
		assert_true(t.alive)
		assert_eq(t.health, SimConstants.MAX_HEALTH)
		assert_eq(t.power, SimConstants.DEFAULT_POWER)
		assert_gt(t.x, prev_x, "tanks ordered left to right")
		prev_x = t.x
		assert_eq(t.angle, 450 if t.x < SimConstants.WORLD_W / 2 else 1350)
		assert_eq(t.y, TankState.rest_y(s.terrain, t.x), "rests on highest surface")
		assert_false(s.terrain.is_solid(t.x, t.y - 1), "air above the tank")
		assert_true(s.terrain.is_solid(t.x, t.y), "ground below the tank")
		for c: int in range(t.x - 12, t.x + 12):
			assert_eq(s.terrain.surface_y(c), t.y, "flat pad under the tank at %d" % c)
	# each tank stays inside its own segment
	var seg: int = SimConstants.WORLD_W / 4
	for t: TankState in s.tanks:
		assert_true(absi(t.x - (t.id * seg + seg / 2)) <= seg / 5)


func test_new_match_deterministic_and_seed_sensitive() -> void:
	var a: MatchState = Simulation.new_match(_settings(99, 3))
	var b: MatchState = Simulation.new_match(_settings(99, 3))
	var c: MatchState = Simulation.new_match(_settings(100, 3))
	assert_eq(Simulation.fingerprint(a), Simulation.fingerprint(b))
	assert_ne(Simulation.fingerprint(a), Simulation.fingerprint(c))


func test_new_match_does_not_alias_settings() -> void:
	var st: MatchSettings = _settings(5, 2)
	var s: MatchState = Simulation.new_match(st)
	st.num_tanks = 8
	assert_eq(s.settings.num_tanks, 2)


# --- validate_action ---------------------------------------------------------

func test_validate_accepts_legal_fire() -> void:
	var s: MatchState = SimTestUtil.flat_state()
	assert_eq(Simulation.validate_action(s, SimTestUtil.fire(0, 450, 500)), "")
	assert_eq(Simulation.validate_action(s, SimTestUtil.fire(0, 0, 1)), "")
	assert_eq(Simulation.validate_action(s, SimTestUtil.fire(0, 1800, 1000)), "")


func test_invalid_actions_rejected_and_change_nothing() -> void:
	var s: MatchState = SimTestUtil.flat_state()
	var before: String = Simulation.fingerprint(s)
	var bad: Array[Dictionary] = [
		SimTestUtil.fire(1, 450, 500),
		SimTestUtil.fire(0, -1, 500),
		SimTestUtil.fire(0, 1801, 500),
		SimTestUtil.fire(0, 450, 0),
		SimTestUtil.fire(0, 450, 1001),
		SimTestUtil.fire(5, 450, 500),
		SimTestUtil.fire(-1, 450, 500),
		{"kind": "fire", "tank": 0, "angle": 450, "power": 500, "weapon": "nope"},
		{"kind": "fire", "tank": 0, "angle": 450, "power": 500},
		{"kind": "fire", "tank": 0, "angle": 45.5, "power": 500, "weapon": "pulse_missile"},
		{"kind": "dance", "tank": 0},
		{"tank": 0},
		{},
	]
	for a: Dictionary in bad:
		assert_ne(Simulation.validate_action(s, a), "", "should be invalid: %s" % str(a))
		var ev: Array[Dictionary] = Simulation.apply_action(s, a)
		assert_eq(ev.size(), 0, "no events for %s" % str(a))
		assert_eq(Simulation.fingerprint(s), before, "state unchanged by %s" % str(a))


func test_error_keys() -> void:
	var s: MatchState = SimTestUtil.flat_state()
	assert_eq(Simulation.validate_action(s, SimTestUtil.fire(1, 450, 500)), "not_your_turn")
	assert_eq(Simulation.validate_action(s, SimTestUtil.fire(0, 1801, 500)), "bad_angle")
	assert_eq(Simulation.validate_action(s, SimTestUtil.fire(0, 450, 1001)), "bad_power")
	assert_eq(Simulation.validate_action(s, SimTestUtil.fire(9, 450, 500)), "bad_tank")
	assert_eq(Simulation.validate_action(s, {"kind": "fire", "tank": 0, "angle": 1, "power": 5, "weapon": "x"}), "unknown_weapon")
	s.tanks[0].alive = false
	assert_eq(Simulation.validate_action(s, SimTestUtil.fire(0, 450, 500)), "tank_dead")
	s.tanks[0].alive = true
	s.phase = "round_over"
	assert_eq(Simulation.validate_action(s, SimTestUtil.fire(0, 450, 500)), "bad_phase")


# --- apply_action ------------------------------------------------------------

func test_scripted_shots_have_sensible_event_order() -> void:
	var s: MatchState = Simulation.new_match(_settings(2024, 3, 5))
	var script: Array[Vector2i] = [Vector2i(450, 700), Vector2i(1350, 650), Vector2i(600, 500), Vector2i(1200, 900),
			Vector2i(900, 300), Vector2i(300, 800)]
	for a: Vector2i in script:
		if s.phase != "aim":
			Simulation.start_round(s)
		var tank: int = s.current_tank
		var ev: Array[Dictionary] = Simulation.apply_action(s, SimTestUtil.fire(tank, a.x, a.y))
		assert_gt(ev.size(), 3)
		_check_order(ev)
		var fire: Dictionary = ev[0]
		assert_eq(fire["tank"], tank)
		assert_eq(fire["angle"], a.x)
		var proj: Dictionary = ev[1]
		assert_eq(proj["type"], "projectile")
		var path: PackedInt32Array = proj["path"]
		var end: Dictionary = _find(ev, "projectile_end")[0]
		assert_eq(path.size() / 2, end["tick"], "one path point per tick")
		if end["reason"] == "terrain" or end["reason"] == "tank":
			assert_eq(_find(ev, "explosion").size(), 1)
			assert_eq(_find(ev, "terrain_carve").size(), 1)
			assert_eq(_find(ev, "explosion")[0]["radius"], 28)
		else:
			assert_eq(_find(ev, "explosion").size(), 0, "no explosion when the shell is lost")


func test_self_hit_straight_up_damages_shooter() -> void:
	var s: MatchState = SimTestUtil.flat_state()
	var ev: Array[Dictionary] = Simulation.apply_action(s, SimTestUtil.fire(0, 900, 300))
	_check_order(ev)
	assert_eq(_find(ev, "projectile_end")[0]["reason"], "tank")
	var dmg: Array[Dictionary] = _find(ev, "damage")
	assert_gt(dmg.size(), 0)
	assert_eq(dmg[0]["tank"], 0)
	assert_eq(dmg[0]["amount"], 55)
	assert_eq(dmg[0]["health"], 45)
	assert_eq(dmg[0]["cause"], "explosion")
	# The crater under its own tracks makes it fall a little: that adds fall damage (FALL_SAFE exceeded).
	var total: int = 0
	for d: Dictionary in dmg:
		total += d["amount"] as int
	assert_eq(s.tanks[0].health, SimConstants.MAX_HEALTH - total)
	assert_eq(_find(ev, "tank_fall").size(), 1)
	assert_eq(s.tanks[0].angle, 900, "tank remembers its last aim")
	assert_eq(s.tanks[0].power, 300)
	# turn passed to the other tank; wind drifted within bounds
	assert_eq(s.current_tank, 1)
	assert_eq(s.turn_number, 1)
	assert_true(absi(s.wind) <= SimConstants.WIND_DRIFT)
	var wind_ev: Dictionary = _find(ev, "wind")[0]
	assert_eq(wind_ev["wind"], s.wind)
	assert_eq(_find(ev, "turn")[0]["tank"], 1)


func test_shot_into_ground_carves_crater() -> void:
	var s: MatchState = SimTestUtil.flat_state()
	var p: int = SimTestUtil.power_for_target(s, 450, 800)
	var ev: Array[Dictionary] = Simulation.apply_action(s, SimTestUtil.fire(0, 450, p))
	_check_order(ev)
	var carve: Dictionary = _find(ev, "terrain_carve")[0]
	var cx: int = carve["x"]
	assert_true(absi(cx - 800) < 10)
	assert_false(s.terrain.is_solid(cx, SimTestUtil.GROUND_Y + 5), "crater below impact")
	assert_eq(_find(ev, "damage").size(), 0, "nobody near")
	assert_eq(_find(ev, "terrain_settle").size(), 1)
	assert_eq(_find(ev, "tank_fall").size(), 0)


func test_lost_shot_has_no_explosion_and_passes_turn() -> void:
	var s: MatchState = SimTestUtil.flat_state()
	s.tanks[0].x = 50
	var before_terrain: PackedByteArray = s.terrain.cells.duplicate()
	var ev: Array[Dictionary] = Simulation.apply_action(s, SimTestUtil.fire(0, 1350, 600))
	_check_order(ev)
	assert_eq(_find(ev, "projectile_end")[0]["reason"], "lost")
	assert_eq(_types(ev), ["fire", "projectile", "projectile_end", "wind", "turn"] as Array[String])
	assert_eq(s.terrain.cells, before_terrain)
	assert_eq(s.current_tank, 1)


func test_tank_over_crater_falls_and_takes_fall_damage() -> void:
	var s: MatchState = SimTestUtil.flat_state()
	var victim: TankState = s.tanks[1]
	# Dig a pit under the victim so it hovers; the next explosion nearby triggers the settle/fall check.
	s.terrain.carve_circle(victim.x, SimTestUtil.GROUND_Y, 40)
	var expected_rest: int = TankState.rest_y(s.terrain, victim.x)
	assert_gt(expected_rest, victim.y + 30, "pit is deep enough")
	var p: int = SimTestUtil.power_for_target(s, 450, victim.x)
	var ev: Array[Dictionary] = Simulation.apply_action(s, SimTestUtil.fire(0, 450, p))
	_check_order(ev)
	var falls: Array[Dictionary] = _find(ev, "tank_fall")
	assert_eq(falls.size(), 1)
	assert_eq(falls[0]["tank"], 1)
	assert_eq(falls[0]["from_y"], SimTestUtil.GROUND_Y)
	var to_y: int = falls[0]["to_y"]
	assert_gt(to_y, SimTestUtil.GROUND_Y + SimConstants.FALL_SAFE)
	assert_eq(victim.y, to_y)
	assert_eq(victim.y, TankState.rest_y(s.terrain, victim.x), "victim rests on the surface again")
	var fall_dmg: Array[Dictionary] = []
	for d: Dictionary in _find(ev, "damage"):
		if d["cause"] == "fall":
			fall_dmg.append(d)
	assert_eq(fall_dmg.size(), 1)
	assert_eq(fall_dmg[0]["amount"], (to_y - SimConstants.FALL_SAFE - SimTestUtil.GROUND_Y) / SimConstants.FALL_DMG_DIV)
	assert_eq(fall_dmg[0]["tank"], 1)
	assert_true(victim.health < SimConstants.MAX_HEALTH)


func test_small_fall_is_free() -> void:
	var s: MatchState = SimTestUtil.flat_state()
	var victim: TankState = s.tanks[1]
	victim.y = SimTestUtil.GROUND_Y - 8  # hovering 8 cells above the ground
	# Land just right of the tank (clear of its hit box) so the blast's settle range overlaps it.
	var p: int = SimTestUtil.power_for_target(s, 450, victim.x + 36)
	var ev: Array[Dictionary] = Simulation.apply_action(s, SimTestUtil.fire(0, 450, p))
	_check_order(ev)
	var falls: Array[Dictionary] = _find(ev, "tank_fall")
	assert_eq(falls.size(), 1)
	assert_eq(falls[0]["from_y"], SimTestUtil.GROUND_Y - 8)
	assert_eq(falls[0]["to_y"], SimTestUtil.GROUND_Y)
	for d: Dictionary in _find(ev, "damage"):
		assert_ne(d["cause"], "fall", "8 cell fall is within FALL_SAFE")


func test_kill_last_enemy_ends_round_with_winner() -> void:
	var s: MatchState = SimTestUtil.flat_state()
	s.tanks[1].health = 1
	var p: int = SimTestUtil.power_for_target(s, 450, s.tanks[1].x)
	var ev: Array[Dictionary] = Simulation.apply_action(s, SimTestUtil.fire(0, 450, p))
	_check_order(ev)
	assert_false(s.tanks[1].alive)
	assert_eq(s.tanks[1].health, 0)
	var destroyed: Array[Dictionary] = _find(ev, "tank_destroyed")
	assert_eq(destroyed.size(), 1)
	assert_eq(destroyed[0]["tank"], 1)
	var end: Array[Dictionary] = _find(ev, "round_end")
	assert_eq(end.size(), 1)
	assert_eq(end[0]["winner"], 0)
	assert_eq(ev[ev.size() - 1]["type"], "round_end")
	assert_eq(_find(ev, "turn").size(), 0, "no turn after round end")
	assert_eq(s.phase, "round_over")
	# No further shots until the next round starts.
	assert_eq(Simulation.validate_action(s, SimTestUtil.fire(0, 450, 500)), "bad_phase")


func test_mutual_destruction_is_draw() -> void:
	var s: MatchState = SimTestUtil.flat_state()
	s.tanks[0].health = 10
	var ev: Array[Dictionary] = Simulation.apply_action(s, SimTestUtil.fire(0, 900, 300))
	assert_eq(_find(ev, "round_end")[0]["winner"], 1, "self-kill: the survivor wins")
	var s2: MatchState = SimTestUtil.flat_state()
	s2.tanks[1].x = s2.tanks[0].x + 20
	s2.tanks[0].health = 5
	s2.tanks[1].health = 5
	var ev2: Array[Dictionary] = Simulation.apply_action(s2, SimTestUtil.fire(0, 900, 300))
	assert_eq(_find(ev2, "tank_destroyed").size(), 2)
	assert_eq(_find(ev2, "round_end")[0]["winner"], -1)


func test_turn_skips_dead_tanks_and_wraps() -> void:
	var s: MatchState = SimTestUtil.flat_state(4)
	s.tanks[1].alive = false
	s.tanks[1].health = 0
	s.current_tank = 0
	s.tanks[0].x = 100
	Simulation.apply_action(s, SimTestUtil.fire(0, 1350, 400))
	assert_eq(s.current_tank, 2, "dead tank 1 skipped")
	s.tanks[2].x = 100
	s.tanks[3].x = 1500
	Simulation.apply_action(s, SimTestUtil.fire(2, 1350, 400))
	assert_eq(s.current_tank, 3)
	Simulation.apply_action(s, SimTestUtil.fire(3, 450, 400))
	assert_eq(s.current_tank, 0, "wraps around")


func test_wind_drift_clamped_to_wind_max() -> void:
	var s: MatchState = SimTestUtil.flat_state()
	s.settings.wind_max = 3
	s.wind = 3
	for i: int in range(30):
		s.tanks[s.current_tank].x = 100 if s.current_tank == 0 else 1500
		Simulation.apply_action(s, SimTestUtil.fire(s.current_tank, 1350 if s.current_tank == 0 else 450, 400))
		assert_true(absi(s.wind) <= 3, "wind %d" % s.wind)


# --- rounds ------------------------------------------------------------------

func test_start_round_and_match_over() -> void:
	var s: MatchState = Simulation.new_match(_settings(31337, 2, 2))
	assert_eq(Simulation.start_round(s).size(), 0, "cannot start while a round is running")
	var fp0: String = Simulation.fingerprint(s)
	# Force the end of round 0 directly.
	s.tanks[1].alive = false
	s.tanks[1].health = 0
	s.phase = "round_over"
	var ev: Array[Dictionary] = Simulation.start_round(s)
	assert_eq(_types(ev), ["round_start", "wind", "turn"] as Array[String])
	assert_eq(ev[0]["round"], 1)
	assert_eq(ev[0]["tick"], 0)
	assert_eq(s.round_index, 1)
	assert_eq(s.phase, "aim")
	assert_eq(s.current_tank, 1, "first turn rotates with the round")
	assert_eq(ev[2]["tank"], 1)
	for t: TankState in s.tanks:
		assert_true(t.alive)
		assert_eq(t.health, SimConstants.MAX_HEALTH)
	assert_ne(Simulation.fingerprint(s), fp0, "new terrain and placement")
	# Round 1 is the last round: ending it ends the match. Tank 1 shoots straight up and kills itself.
	s.tanks[1].health = 1
	s.wind = 0  # a calm shot comes straight back down
	var ev2: Array[Dictionary] = Simulation.apply_action(s, SimTestUtil.fire(1, 900, 300))
	assert_eq(_find(ev2, "round_end")[0]["winner"], 0)
	assert_eq(s.phase, "match_over")
	assert_eq(Simulation.start_round(s).size(), 0)


func test_rounds_use_independent_streams() -> void:
	var a: MatchState = Simulation.new_match(_settings(8, 2, 3))
	var b: MatchState = Simulation.new_match(_settings(8, 2, 3))
	a.phase = "round_over"
	Simulation.start_round(a)
	b.phase = "round_over"
	Simulation.start_round(b)
	assert_eq(Simulation.fingerprint(a), Simulation.fingerprint(b))
	assert_eq(a.round_index, 1)


func test_apply_action_performance() -> void:
	var s: MatchState = Simulation.new_match(_settings(42, 2, 3))
	var t0: int = Time.get_ticks_msec()
	var ev: Array[Dictionary] = Simulation.apply_action(s, SimTestUtil.fire(0, 450, 800))
	var ms: int = Time.get_ticks_msec() - t0
	print("PERF apply_action (pulse missile, %d events): %d ms" % [ev.size(), ms])
	assert_lt(ms, 200)
