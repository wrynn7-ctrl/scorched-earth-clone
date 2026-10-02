@warning_ignore_start("integer_division")
extends GutTest
## Seeded fuzzing: 300 random matches mixing valid shots and invalid actions.
## Failures print the match index and seed so any case can be replayed.

const QaUtil = preload("res://tests/qa/qa_util.gd")
const MATCHES: int = 300
const ROOT_SEED: int = 0xF0220000


## Returns [action, expected validate_action result] for an invalid action (current phase: aim).
func _invalid_action(state: MatchState, rng: Rng) -> Array:
	var n: int = state.tanks.size()
	var cur: int = state.current_tank
	var good: Dictionary = QaUtil.fire(cur, rng.range_int(0, 1800), rng.range_int(1, 1000))
	var a: Dictionary = good.duplicate()
	match rng.range_int(0, 13):
		0:
			a["tank"] = (cur + 1 + rng.range_int(0, n - 2)) % n
			return [a, "not_your_turn"]
		1:
			a["tank"] = -1 - rng.range_int(0, 5)
			return [a, "bad_tank"]
		2:
			a["tank"] = n + rng.range_int(0, 1000)
			return [a, "bad_tank"]
		3:
			a["angle"] = -1 - rng.range_int(0, 3600)
			return [a, "bad_angle"]
		4:
			a["angle"] = 1801 + rng.range_int(0, 100000)
			return [a, "bad_angle"]
		5:
			a["power"] = -rng.range_int(0, 500)
			return [a, "bad_power"]
		6:
			a["power"] = 1001 + rng.range_int(0, 100000)
			return [a, "bad_power"]
		7:
			a["angle"] = float(a["angle"])
			return [a, "bad_field"]
		8:
			a["power"] = str(a["power"])
			return [a, "bad_field"]
		9:
			a["weapon"] = "w%d" % rng.range_int(0, 99)
			return [a, "unknown_weapon"]
		10:
			a.erase(["tank", "angle", "power", "weapon"][rng.range_int(0, 3)])
			return [a, "bad_field"]
		11:
			a["kind"] = ["dance", "shoot", "", "Fire", "PASS"][rng.range_int(0, 4)]
			return [a, "unknown_kind"]
		12:
			return [{}, "bad_action"]
		_:
			a["tank"] = true
			return [a, "bad_field"]


## Hard invariants after every state change; returns an array of violations.
func _violations(state: MatchState, prev: Array[int]) -> Array[String]:
	var errs: Array[String] = QaUtil.check_invariants(state)
	for t: TankState in state.tanks:
		if prev[0] == state.round_index:
			var base: int = 1 + t.id * 4
			if t.health > prev[base]:
				errs.append("tank %d health rose %d -> %d" % [t.id, prev[base], t.health])
			if prev[base + 1] == 0 and t.alive:
				errs.append("tank %d resurrected" % t.id)
			if t.x != prev[base + 2]:
				errs.append("tank %d moved sideways" % t.id)
			if t.y < prev[base + 3]:
				errs.append("tank %d rose from %d to %d" % [t.id, prev[base + 3], t.y])
		if t.alive and QaUtil.tank_embedded(state, t):
			errs.append("tank %d is embedded in terrain" % t.id)
	var cells: PackedByteArray = state.terrain.cells
	if cells.size() != SimConstants.WORLD_W * SimConstants.WORLD_H:
		errs.append("terrain buffer resized")
	return errs


## [round_index, then per tank: health, alive, x, y].
func _snap(state: MatchState) -> Array[int]:
	var out: Array[int] = [state.round_index]
	for t: TankState in state.tanks:
		out.append_array([t.health, 1 if t.alive else 0, t.x, t.y])
	return out


func _random_settings(rng: Rng, m: int) -> MatchSettings:
	var seed_value: int = rng.next_u32()
	match m % 7:
		0: seed_value = -seed_value
		1: seed_value = (seed_value << 31) | rng.next_u32()
		2: seed_value = m
	var wm: int = [100, 100, 100, 0, 1, 37, 100][m % 7]
	return QaUtil.settings(seed_value, rng.range_int(2, 8), rng.range_int(1, 3), wm)


func test_fuzz_300_random_matches() -> void:
	var t0: int = Time.get_ticks_msec()
	var actions: int = 0
	var invalid: int = 0
	var timelines: int = 0
	var round_ends: int = 0
	var match_overs: int = 0
	var failures: Array[String] = []
	for m: int in range(MATCHES):
		var rng := Rng.new(ROOT_SEED + m)
		var settings: MatchSettings = _random_settings(rng, m)
		var tag: String = "match %d (seed %d, %d tanks, %d rounds, wind_max %d)" % [m, settings.seed, settings.num_tanks,
				settings.rounds, settings.wind_max]
		var state: MatchState = Simulation.new_match(settings)
		var errs: Array[String] = QaUtil.check_invariants(state)
		if not errs.is_empty() or state.phase != SimConstants.PHASE_SHOP:
			failures.append("%s: new_match invariants: %s" % [tag, "; ".join(errs)])
			continue
		if Simulation.start_round(state).size() != 0:
			failures.append("%s: start_round worked before anyone was ready" % tag)
		QaUtil.enter_round(state)
		errs = QaUtil.check_invariants(state)
		if not errs.is_empty() or state.phase != SimConstants.PHASE_AIM:
			failures.append("%s: first round invariants: %s" % [tag, "; ".join(errs)])
			continue
		var fragile: bool = m % 3 == 0  # 1-hit-point tanks: rounds end quickly, exercises round/match over
		if fragile:
			for t: TankState in state.tanks:
				t.health = 1 + rng.range_int(0, 20)
		var n_actions: int = rng.range_int(6, 11)
		for i: int in range(n_actions):
			actions += 1
			var prev: Array[int] = _snap(state)
			var sig: String = QaUtil.quick_sig(state)
			var roll: int = rng.range_int(0, 9)
			var step_tag: String = "%s action %d" % [tag, i]
			if state.phase == SimConstants.PHASE_MATCH_OVER:
				match_overs += 1
				var ma: Dictionary = QaUtil.fire(0, 450, 500)
				if Simulation.validate_action(state, ma) != "bad_phase" or Simulation.apply_action(state, ma).size() != 0 \
						or Simulation.start_round(state).size() != 0 or QaUtil.quick_sig(state) != sig:
					failures.append("%s: actions after match_over were not rejected cleanly" % step_tag)
				break
			if state.phase == SimConstants.PHASE_SHOP:
				if roll == 0:  # a fire attempt or an early start_round between rounds must be refused
					invalid += 1
					var fa: Dictionary = QaUtil.fire(state.current_tank, 450, 500)
					if Simulation.validate_action(state, fa) != "bad_phase" or Simulation.apply_action(state, fa).size() != 0 \
							or Simulation.start_round(state).size() != 0 or QaUtil.quick_sig(state) != sig:
						failures.append("%s: fire/start_round in the shop (not ready) not refused" % step_tag)
					continue
				var sr: Array[Dictionary] = QaUtil.enter_round(state)
				var sr_errs: Array[String] = QaUtil.check_event_fields(sr)
				if sr.size() != 3 or not sr_errs.is_empty() or state.phase != SimConstants.PHASE_AIM:
					failures.append("%s: bad start_round result %s %s" % [step_tag, str(QaUtil.types(sr)), "; ".join(sr_errs)])
					break
				if state.current_tank != state.round_index % state.tanks.size():
					failures.append("%s: first tank of round %d is %d" % [step_tag, state.round_index, state.current_tank])
				if fragile:
					for t: TankState in state.tanks:
						t.health = 1 + rng.range_int(0, 20)
				prev = _snap(state)
				errs = _violations(state, prev)
				if not errs.is_empty():
					failures.append("%s after start_round: %s" % [step_tag, "; ".join(errs)])
					break
				continue
			# phase == aim
			if roll < 3 and not (fragile and roll == 0):
				invalid += 1
				var pair: Array = _invalid_action(state, rng)
				var act: Dictionary = pair[0]
				var got: String = Simulation.validate_action(state, act)
				if got != pair[1]:
					failures.append("%s: validate(%s) = '%s', expected '%s'" % [step_tag, str(act), got, pair[1]])
				if Simulation.apply_action(state, act).size() != 0 or QaUtil.quick_sig(state) != sig:
					failures.append("%s: invalid action %s had an effect" % [step_tag, str(act)])
				if Simulation.start_round(state).size() != 0 or QaUtil.quick_sig(state) != sig:
					failures.append("%s: start_round during aim had an effect" % step_tag)
				continue
			var action: Dictionary
			if roll < 6 and not fragile:
				action = QaUtil.fire_for(state, state.current_tank, rng.range_int(0, 1800), rng.range_int(1, 1000))
			else:
				action = QaUtil.bot_action(state, rng)
			if roll == 9:
				action["junk"] = rng.next_u32()  # unknown keys must be ignored
			var ev: Array[Dictionary] = Simulation.apply_action(state, action)
			timelines += 1
			var fe: Array[String] = QaUtil.check_event_fields(ev)
			var oe: Array[String] = QaUtil.check_order(ev, false)
			if ev.is_empty():
				failures.append("%s: legal action %s produced no events" % [step_tag, str(action)])
				break
			if not fe.is_empty() or not oe.is_empty():
				failures.append("%s: contract: %s %s" % [step_tag, "; ".join(fe), "; ".join(oe)])
			errs = _violations(state, prev)
			if not errs.is_empty():
				failures.append("%s after %s: %s" % [step_tag, str(action), "; ".join(errs)])
				break
			# terrain around the blast must be settled (nothing floating)
			var carve: Array[Dictionary] = QaUtil.find(ev, "terrain_carve")
			if not carve.is_empty():
				var probe: Terrain = state.terrain.duplicate_terrain()
				var cx: int = carve[0]["x"]
				if probe.settle(cx - 40, cx + 40).size() != 0:
					failures.append("%s: dirt left floating near the blast" % step_tag)
			if not QaUtil.find(ev, "round_end").is_empty():
				round_ends += 1
			if failures.size() > 15:
				break
		if failures.size() > 15:
			break
	var ms: int = Time.get_ticks_msec() - t0
	gut.p("FUZZ: %d matches, %d actions (%d invalid, %d timelines, %d round_ends, %d match_over) in %d ms" % [
			MATCHES, actions, invalid, timelines, round_ends, match_overs, ms])
	assert_eq(failures.size(), 0, "fuzz failures:\n%s" % "\n".join(failures))
	assert_gt(timelines, 1500, "fuzz exercised plenty of timelines")
	assert_gt(round_ends, 20, "fuzz reached round ends")
	assert_lt(ms, SimTestUtil.perf_budget(90000), "fuzz stays within its time budget")
