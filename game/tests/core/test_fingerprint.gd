extends GutTest

const SCRIPT_STEPS: int = 20


func _settings(seed_value: int) -> MatchSettings:
	var s := MatchSettings.new()
	s.seed = seed_value
	s.num_tanks = 4
	s.rounds = 6
	return s


## Runs a fixed scripted game from scratch; returns the fingerprint after every action.
func _run_script(seed_value: int) -> Array[String]:
	var state: MatchState = Simulation.new_match(_settings(seed_value))
	var prints: Array[String] = [Simulation.fingerprint(state)]
	for i: int in range(SCRIPT_STEPS):
		if state.phase == "round_over":
			Simulation.start_round(state)
		assert_eq(state.phase, "aim")
		var angle: int = 200 + (i * 137) % 1400
		var power: int = 350 + (i * 211) % 650
		var ev: Array[Dictionary] = Simulation.apply_action(state, SimTestUtil.fire(state.current_tank, angle, power))
		assert_gt(ev.size(), 3, "action %d produced events" % i)
		prints.append(Simulation.fingerprint(state))
	return prints


func test_same_seed_same_fingerprints_after_every_action() -> void:
	var a: Array[String] = _run_script(777)
	var b: Array[String] = _run_script(777)
	assert_eq(a.size(), SCRIPT_STEPS + 1)
	assert_eq(a, b)
	# state actually evolves
	var distinct: Dictionary = {}
	for f: String in a:
		distinct[f] = true
	assert_gt(distinct.size(), SCRIPT_STEPS / 2)


func test_different_seed_different_fingerprints() -> void:
	assert_ne(_run_script(777)[0], _run_script(778)[0])


func test_fingerprint_format() -> void:
	var f: String = Simulation.fingerprint(Simulation.new_match(_settings(1)))
	assert_eq(f.length(), 16)
	assert_true(f.is_valid_hex_number(), "hex digits only")
	assert_eq(f, f.to_lower())


func test_duplicate_state_matches_and_is_deep() -> void:
	var s: MatchState = Simulation.new_match(_settings(5))
	Simulation.apply_action(s, SimTestUtil.fire(s.current_tank, 600, 700))
	var d: MatchState = s.duplicate_state()
	assert_eq(Simulation.fingerprint(d), Simulation.fingerprint(s))
	# mutate the copy in every area; the original must not change
	var before: String = Simulation.fingerprint(s)
	d.terrain.carve_circle(800, 700, 50)
	d.tanks[0].health = 1
	d.wind += 5
	d.wind_rng_state[0] += 1
	d.settings.rounds = 99
	assert_ne(Simulation.fingerprint(d), before)
	assert_eq(Simulation.fingerprint(s), before)
	# and the copy keeps simulating identically to the original
	var s2: MatchState = s.duplicate_state()
	var ev1: Array[Dictionary] = Simulation.apply_action(s, SimTestUtil.fire(s.current_tank, 500, 800))
	var ev2: Array[Dictionary] = Simulation.apply_action(s2, SimTestUtil.fire(s2.current_tank, 500, 800))
	assert_eq(ev1.size(), ev2.size())
	assert_eq(Simulation.fingerprint(s), Simulation.fingerprint(s2))


func test_fingerprint_sensitive_to_each_field() -> void:
	var base: MatchState = Simulation.new_match(_settings(9))
	var f0: String = Simulation.fingerprint(base)
	var m: MatchState = base.duplicate_state()
	m.tanks[1].x += 1
	assert_ne(Simulation.fingerprint(m), f0, "tank x")
	m = base.duplicate_state()
	m.tanks[1].power += 1
	assert_ne(Simulation.fingerprint(m), f0, "tank power")
	m = base.duplicate_state()
	m.current_tank = 2
	assert_ne(Simulation.fingerprint(m), f0, "current tank")
	m = base.duplicate_state()
	m.wind += 1
	assert_ne(Simulation.fingerprint(m), f0, "wind")
	m = base.duplicate_state()
	m.phase = "round_over"
	assert_ne(Simulation.fingerprint(m), f0, "phase")
	m = base.duplicate_state()
	m.terrain.cells[12345] = 3 if m.terrain.cells[12345] != 3 else 4
	assert_ne(Simulation.fingerprint(m), f0, "terrain byte")


func test_fingerprint_performance() -> void:
	var s: MatchState = Simulation.new_match(_settings(3))
	var t0: int = Time.get_ticks_msec()
	var f: String = Simulation.fingerprint(s)
	var ms: int = Time.get_ticks_msec() - t0
	print("PERF fingerprint 1600x900: %d ms" % ms)
	assert_eq(f.length(), 16)
	assert_lt(ms, 100)


func test_new_match_performance_and_duplicate() -> void:
	var t0: int = Time.get_ticks_msec()
	var s: MatchState = Simulation.new_match(_settings(4))
	var t1: int = Time.get_ticks_msec()
	var d: MatchState = s.duplicate_state()
	var t2: int = Time.get_ticks_msec()
	print("PERF new_match 4 tanks: %d ms, duplicate_state: %d ms" % [t1 - t0, t2 - t1])
	assert_eq(d.tanks.size(), 4)


# Pinned values: any change to terrain generation, placement, ballistics, damage or the
# serialization order changes these. Update them only for an intentional rules change
# (and bump saves/replays accordingly).
func test_pinned_golden_fingerprints() -> void:
	var st := MatchSettings.new()
	st.seed = 42
	st.num_tanks = 3
	st.rounds = 2
	var s: MatchState = Simulation.new_match(st)
	assert_eq(Simulation.fingerprint(s), "d1bf76dbc0d3ea72")
	Simulation.apply_action(s, SimTestUtil.fire(0, 450, 700))
	Simulation.apply_action(s, SimTestUtil.fire(1, 1350, 650))
	assert_eq(Simulation.fingerprint(s), "d858ede05872ef7b")
