extends GutTest
## The CPU in Love Edition (docs/ARCHITECTURE.md section 37): it always sends a heart at the opponent
## with its level's usual aim, error and bracketing model; never an item, a walk or a shop action.

const LEVELS: Array[int] = [1, 2, 3, 4]


## A started love duel (new_match skips the shop). `a` and `b` are the CTRL_* levels of tank 0 and 1.
func _love(seed_value: int, a: int, b: int) -> MatchState:
	var s := MatchSettings.new()
	s.seed = seed_value
	s.mode = SimConstants.MODE_LOVE
	s.wind_max = 30
	s.controllers = PackedInt32Array([a, b])
	return Simulation.new_match(s)


## A varied mid-match love state: random levels and wind, a few CPU turns already played so
## last_fire_* (HEART_INDEX) and the meters are filled in. Always in the aim phase.
func _random_love(i: int) -> MatchState:
	var r: Rng = Rng.derive(i * 131 + 17, 321)
	var state: MatchState = _love(9000 + i, r.range_int(1, 4), r.range_int(1, 4))
	state.wind = r.range_int(-30, 30)
	for _k: int in range(r.range_int(0, 5)):
		if state.phase != SimConstants.PHASE_AIM:
			break
		Simulation.apply_action(state, AiPlayer.next_action(state, state.current_tank))
	if state.phase != SimConstants.PHASE_AIM:
		return _love(9000 + i, 2, 2)
	return state


func _is_heart_fire(a: Dictionary) -> bool:
	return a.get("kind", "") == "fire" and a.get("weapon", "") == "heart"


func test_every_action_is_a_valid_heart_fire() -> void:
	var checked: int = 0
	var per_level: Dictionary = {1: 0, 2: 0, 3: 0, 4: 0}
	for i: int in range(200):
		var state: MatchState = _random_love(i)
		for tank: int in [state.current_tank]:
			var level: int = AiProfile.level_of(state, tank)
			var action: Dictionary = AiPlayer.next_action(state, tank)
			assert_true(_is_heart_fire(action), "state %d: %s" % [i, str(action)])
			assert_eq(Simulation.validate_action(state, action), "", "state %d valid" % i)
			assert_eq(action["tank"], tank)
			per_level[level] = (per_level[level] as int) + 1
			checked += 1
	# Every level is exercised from either seat (the random levels cover all four).
	for level: int in LEVELS:
		assert_gt(per_level[level] as int, 20, "level %d covered" % level)
	gut.p("LOVE VALIDITY  %d random love states, all heart fires and valid; by level %s" % [checked, str(per_level)])


func test_all_levels_from_both_seats_on_many_seeds() -> void:
	var n: int = 0
	for level: int in LEVELS:
		for i: int in range(60):
			var state: MatchState = _love(4000 + i, level, level)
			state.current_tank = i % 2
			var action: Dictionary = AiPlayer.next_action(state, state.current_tank)
			assert_true(_is_heart_fire(action), "level %d seed %d" % [level, i])
			assert_eq(Simulation.validate_action(state, action), "")
			n += 1
	assert_eq(n, 240)


func test_shop_actions_are_empty_in_love_mode() -> void:
	var state: MatchState = _love(5, 2, 4)
	assert_eq(AiPlayer.shop_actions(state, 0).size(), 0)
	assert_eq(AiPlayer.shop_actions(state, 1).size(), 0)
	state.phase = SimConstants.PHASE_SHOP  # even if somebody forces the phase
	assert_eq(AiPlayer.shop_actions(state, 0).size(), 0)


func test_never_a_move_or_an_item_even_with_fuel_stock_and_no_reach() -> void:
	var seen: Dictionary = {}
	for i: int in range(120):
		var state: MatchState = _random_love(300 + i)
		# Hand the CPU everything a standard match would use: fuel, shields, kits, damage at 10.
		for t: TankState in state.tanks:
			t.fuel = 200
			t.set_stock("fuel_cell", 2)
			t.set_stock("glow_shield", 1)
			t.set_stock("nanorepair_kit", 1)
			t.set_stock("repulsor_field", 1)
		state.tanks[state.current_tank].last_fire_power = 1000  # looks like a spent full-power shot
		var action: Dictionary = AiPlayer.next_action(state, state.current_tank)
		seen[action["kind"]] = true
		assert_ne(action["kind"], "move", "state %d" % i)
		assert_ne(action["kind"], "use_item", "state %d" % i)
		assert_true(_is_heart_fire(action), "state %d: %s" % [i, str(action)])
	assert_eq(seen.keys(), ["fire"])


func test_no_reach_still_fires_a_heart_instead_of_walking() -> void:
	# Flat ground, targets at the far end of the world: out of range for the weakest arcs.
	for level: int in LEVELS:
		var state: MatchState = SimTestUtil.flat_state(2)
		state.settings.mode = SimConstants.MODE_LOVE
		state.settings.rounds = 1
		state.settings.controllers = PackedInt32Array([level, level])
		state.tanks[0].x = 30
		state.tanks[1].x = SimConstants.WORLD_W - 30
		state.tanks[0].fuel = 200
		state.wind = 0
		var action: Dictionary = AiPlayer.next_action(state, 0)
		assert_true(_is_heart_fire(action), "level %d: %s" % [level, str(action)])
		assert_eq(Simulation.validate_action(state, action), "")


func test_a_standard_match_is_unchanged_by_love_support() -> void:
	var state: MatchState = AiTestUtil.duel(42, SimConstants.CTRL_EXPERT, 700, 0)
	var action: Dictionary = AiPlayer.next_action(state, 0)
	assert_ne(action.get("weapon", ""), "heart")
	assert_eq(Simulation.validate_action(state, action), "")


func test_correction_reads_the_last_heart() -> void:
	# After a heart shot, the AI brackets like it does after an explode weapon: the next shot's
	# power moves from the last one's. Expert from a perfect read lands much closer on shot 2.
	var closer: int = 0
	var total: int = 0
	for i: int in range(40):
		var state: MatchState = _love(7000 + i, SimConstants.CTRL_EXPERT, SimConstants.CTRL_HUMAN)
		state.wind = 0
		var first: Dictionary = AiPlayer.next_action(state, 0)
		Simulation.apply_action(state, first)
		assert_eq(state.tanks[0].last_fire_weapon, Catalog.HEART_INDEX)
		if state.phase != SimConstants.PHASE_AIM:
			continue
		Simulation.apply_action(state, {"kind": "pass", "tank": 1})
		var sit: AiSituation = AiPlayer.situation(state, state.tanks[0], 4, AiProfile.for_level(4),
				AiTargets.enemies_of(state, state.tanks[0]))
		if state.tanks[0].last_fire_x < 0:
			continue
		total += 1
		if not sit.corr.is_empty():
			closer += 1
	gut.p("LOVE CORRECTION  correction_for reads the heart in %d of %d shots" % [closer, total])
	assert_gte(closer * 100, total * 90, "the heart is a usable 'last shot' for bracketing")


func test_determinism_copy_and_save_round_trip() -> void:
	var checked: int = 0
	for i: int in range(60):
		var state: MatchState = _random_love(500 + i)
		var tank: int = state.current_tank
		var first: Dictionary = AiPlayer.next_action(state, tank)
		assert_eq(AiPlayer.next_action(state, tank), first, "state %d: twice" % i)
		assert_eq(AiPlayer.next_action(state.duplicate_state(), tank), first, "state %d: copy" % i)
		var res: Dictionary = SaveCodec.decode(SaveCodec.encode(state, []))
		assert_true(res["ok"], "round trip: %s" % str(res["error"]))
		assert_eq(AiPlayer.next_action(res["state"], tank), first, "state %d: SaveCodec" % i)
		checked += 1
	gut.p("LOVE DETERMINISM  %d love states: identical actions for the original, a copy and a decoded save" % checked)
	assert_eq(checked, 60)


func test_it_does_not_change_the_state() -> void:
	for i: int in range(20):
		var state: MatchState = _random_love(800 + i)
		var before: String = Simulation.fingerprint(state)
		AiPlayer.next_action(state, state.current_tank)
		assert_eq(Simulation.fingerprint(state), before)


## CPU `level` (tank 0) against CPU Normal (tank 1) until the match is over. Returns
## {over, turns, errors, winner}.
func _play_match(seed_value: int, level: int) -> Dictionary:
	var state: MatchState = _love(seed_value, level, SimConstants.CTRL_NORMAL)
	var errors: Array[String] = []
	var turns: int = 0
	while state.phase != SimConstants.PHASE_MATCH_OVER and turns < 600:
		var action: Dictionary = AiPlayer.next_action(state, state.current_tank)
		var err: String = Simulation.validate_action(state, action)
		if err != "" or not _is_heart_fire(action):
			errors.append("%s: %s" % [str(action), err])
			break
		Simulation.apply_action(state, action)
		turns += 1
	var winner: int = -1
	if state.tanks[0].love >= 100:
		winner = 1
	elif state.tanks[1].love >= 100:
		winner = 0
	return {"over": state.phase == SimConstants.PHASE_MATCH_OVER, "turns": turns, "errors": errors, "winner": winner}


func test_cpu_vs_cpu_love_matches_run_to_match_over() -> void:
	var lines: Array[String] = []
	for level: int in LEVELS:
		var wins: int = 0
		var total_turns: int = 0
		var n: int = 25
		for i: int in range(n):
			var res: Dictionary = _play_match(6100 + i * 3 + level, level)
			assert_eq((res["errors"] as Array).size(), 0, "level %d seed %d: %s" % [level, i, str(res["errors"])])
			assert_true(res["over"], "level %d seed %d reached match_over (%d turns)" % [level, i, res["turns"]])
			total_turns += res["turns"] as int
			if res["winner"] == 0:
				wins += 1
		lines.append("level %d vs Normal: %d/%d wins, avg %d turns" % [level, wins, n, total_turns / n])
	gut.p("LOVE MATCHES  " + "; ".join(lines))


## Shots the CPU `level` needs (alone, the opponent only passes) to fill the opponent's meter.
func _shots_to_fill(seed_value: int, level: int) -> int:
	var state: MatchState = _love(seed_value, level, SimConstants.CTRL_HUMAN)
	var shots: int = 0
	while state.phase != SimConstants.PHASE_MATCH_OVER and shots < 120:
		if state.current_tank == 0:
			Simulation.apply_action(state, AiPlayer.next_action(state, 0))
			shots += 1
		else:
			Simulation.apply_action(state, {"kind": "pass", "tank": 1})
	return shots


func test_expert_fills_the_meter_faster_than_easy() -> void:
	var sum: Dictionary = {1: 0, 2: 0, 3: 0, 4: 0}
	var n: int = 40
	for i: int in range(n):
		for level: int in LEVELS:
			sum[level] = (sum[level] as int) + _shots_to_fill(2000 + i, level)
	var avg_x10: Dictionary = {}
	for level: int in LEVELS:
		avg_x10[level] = (sum[level] as int) * 10 / n
	gut.p("LOVE SPEED  average turns to fill the opponent's meter over %d seeds: easy %.1f  normal %.1f  hard %.1f  expert %.1f" % [
			n, float(avg_x10[1]) / 10.0, float(avg_x10[2]) / 10.0, float(avg_x10[3]) / 10.0, float(avg_x10[4]) / 10.0])
	assert_lt(sum[4] as int, sum[1] as int, "Expert needs fewer turns than Easy")
	assert_lt(sum[4] as int, sum[2] as int, "Expert needs fewer turns than Normal")
	assert_lt((avg_x10[4] as int) * 2, avg_x10[1] as int, "Expert is more than twice as fast as Easy")
	assert_lte((avg_x10[4] as int), 60, "Expert fills the meter in about 3-6 turns")


func test_love_decision_budget() -> void:
	var us: Array[int] = []
	var worst_traces: int = 0
	for i: int in range(120):
		var state: MatchState = _random_love(1200 + i)
		var t0: int = Time.get_ticks_usec()
		AiPlayer.next_action(state, state.current_tank)
		us.append(Time.get_ticks_usec() - t0)
		worst_traces = maxi(worst_traces, AimSolver.trace_count)
	var p95: float = float(AiTestUtil.percentile(us, 95)) / 1000.0
	gut.p("LOVE BUDGET  decision ms median %.1f / p95 %.1f / max %.1f (limit p95 %.1f); most real traces %d (limit %d)" % [
			float(AiTestUtil.percentile(us, 50)) / 1000.0, p95, float(AiTestUtil.percentile(us, 100)) / 1000.0,
			SimTestUtil.perf_budget_f(15.0), worst_traces, AimSolver.TRACE_BUDGET])
	assert_lte(p95, SimTestUtil.perf_budget_f(15.0), "p95 decision time (ms)")
	assert_lte(worst_traces, AimSolver.TRACE_BUDGET)
