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
	var state: MatchState = SimTestUtil.started_match(_settings(seed_value))
	var prints: Array[String] = [Simulation.fingerprint(state)]
	for i: int in range(SCRIPT_STEPS):
		if state.phase == "shop":
			SimTestUtil.begin_round(state)
			for t: TankState in state.tanks:
				t.set_stock("pulse_missile", 50)
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
	var f: String = Simulation.fingerprint(SimTestUtil.started_match(_settings(1)))
	assert_eq(f.length(), 16)
	assert_true(f.is_valid_hex_number(), "hex digits only")
	assert_eq(f, f.to_lower())


func test_duplicate_state_matches_and_is_deep() -> void:
	var s: MatchState = SimTestUtil.started_match(_settings(5))
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
	var base: MatchState = SimTestUtil.started_match(_settings(9))
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
	m.phase = "shop"
	assert_ne(Simulation.fingerprint(m), f0, "phase")
	m = base.duplicate_state()
	m.terrain.cells[12345] = 3 if m.terrain.cells[12345] != 3 else 4
	assert_ne(Simulation.fingerprint(m), f0, "terrain byte")


func test_fingerprint_performance() -> void:
	var s: MatchState = SimTestUtil.started_match(_settings(3))
	var t0: int = Time.get_ticks_msec()
	var f: String = Simulation.fingerprint(s)
	var ms: int = Time.get_ticks_msec() - t0
	print("PERF fingerprint 1600x900: %d ms" % ms)
	assert_eq(f.length(), 16)
	assert_lt(ms, SimTestUtil.perf_budget(100))


func test_new_match_performance_and_duplicate() -> void:
	var t0: int = Time.get_ticks_msec()
	var s: MatchState = Simulation.new_match(_settings(4))
	var t1: int = Time.get_ticks_msec()
	var d: MatchState = s.duplicate_state()
	var t2: int = Time.get_ticks_msec()
	print("PERF new_match 4 tanks: %d ms, duplicate_state: %d ms" % [t1 - t0, t2 - t1])
	assert_eq(d.tanks.size(), 4)


# Pinned values: any change to terrain generation, placement, ballistics, damage, economy or
# the serialization order changes these. Update them only for an intentional rules change
# (and bump saves/replays accordingly). Regenerated for M4 (controllers, last_fire_*), for Love Edition
# (mode, love) and for M6 (teams, friendly_fire, sudden_death_cycles).
func test_pinned_golden_fingerprints() -> void:
	var s: MatchState = _pinned_match()
	assert_eq(Simulation.fingerprint(s), PINS_NEW[0])
	_buy_and_begin(s)
	assert_eq(Simulation.fingerprint(s), PINS_NEW[1])
	Simulation.apply_action(s, SimTestUtil.fire(0, 450, 700))
	Simulation.apply_action(s, SimTestUtil.fire(1, 1350, 650))
	assert_eq(Simulation.fingerprint(s), PINS_NEW[2])


const PINS_NEW: Array[String] = ["12972443f46cbb76", "258741f5e3435474", "343ea5e3283c262d"]
## The same three states' fingerprints before M6. M6 only ADDED three fields to the serialization (teams,
## friendly_fire, sudden_death_cycles); cutting them out of the new bytes must give these exact values, which
## proves a no-teams match plays bit-identically to before (short of sudden death in very long rounds).
const PINS_M5: Array[String] = ["bf70a16bc169cf24", "1cd4005ebc97c24d", "be53e5acd5f9a17b"]


func _pinned_match() -> MatchState:
	var st := MatchSettings.new()
	st.seed = 42
	st.num_tanks = 3
	st.rounds = 2
	return Simulation.new_match(st)


func _buy_and_begin(s: MatchState) -> void:
	for t: TankState in s.tanks:
		Simulation.apply_action(s, {"kind": "buy", "tank": t.id, "item": "pulse_missile", "qty": 2})
	Simulation.apply_action(s, {"kind": "buy", "tank": 1, "item": "glow_shield", "qty": 1})
	SimTestUtil.begin_round(s)


func test_no_teams_states_still_hash_to_the_pre_m6_fingerprints() -> void:
	var s: MatchState = _pinned_match()
	assert_eq(SimTestUtil.pre_m6_fingerprint(s), PINS_M5[0])
	_buy_and_begin(s)
	assert_eq(SimTestUtil.pre_m6_fingerprint(s), PINS_M5[1])
	Simulation.apply_action(s, SimTestUtil.fire(0, 450, 700))
	Simulation.apply_action(s, SimTestUtil.fire(1, 1350, 650))
	assert_eq(SimTestUtil.pre_m6_fingerprint(s), PINS_M5[2], "ten-odd actions later the whole state is still the old one")


func test_a_team_match_has_its_own_pinned_fingerprint() -> void:
	var st := MatchSettings.new()
	st.seed = 42
	st.num_tanks = 4
	st.rounds = 2
	st.teams = PackedInt32Array([0, 1, 0, 1])
	st.friendly_fire = false
	var s: MatchState = Simulation.new_match(st)
	assert_eq(Simulation.fingerprint(s), "8c4f581e15b26698")
	_buy_and_begin(s)
	assert_eq(Simulation.fingerprint(s), "a58c04dc9e5de6da")


func test_fingerprint_covers_every_new_field() -> void:
	var base: MatchState = SimTestUtil.started_match(_settings(11))
	var f0: String = Simulation.fingerprint(base)
	var edits: Dictionary = {
		"money": func(m: MatchState) -> void: m.tanks[0].money += 1,
		"kills": func(m: MatchState) -> void: m.tanks[0].kills += 1,
		"damage_dealt": func(m: MatchState) -> void: m.tanks[0].damage_dealt += 1,
		"round_wins": func(m: MatchState) -> void: m.tanks[0].round_wins += 1,
		"ready": func(m: MatchState) -> void: m.tanks[0].ready = true,
		"fuel": func(m: MatchState) -> void: m.tanks[0].fuel += 1,
		"shield_type": func(m: MatchState) -> void: m.tanks[0].shield_type = 3,
		"shield_hp": func(m: MatchState) -> void: m.tanks[0].shield_hp = 3,
		"repulsor_charge": func(m: MatchState) -> void: m.tanks[0].repulsor_charge = 3,
		"inventory": func(m: MatchState) -> void: m.tanks[0].inventory[27] += 1,
		"wells": func(m: MatchState) -> void: m.wells.append({"owner": 0, "x": 5, "y": 6, "expires_turn": 7}),
		"start_money": func(m: MatchState) -> void: m.settings.start_money += 1,
		"full_unlocked": func(m: MatchState) -> void: m.settings.full_unlocked = false,
		"round_index": func(m: MatchState) -> void: m.round_index += 1,
		"alive": func(m: MatchState) -> void: m.tanks[1].alive = false,
	}
	var seen: Dictionary = {}
	for key: String in edits:
		var m: MatchState = base.duplicate_state()
		(edits[key] as Callable).call(m)
		var f: String = Simulation.fingerprint(m)
		assert_ne(f, f0, "fingerprint covers %s" % key)
		assert_false(seen.has(f), "edit %s gives a distinct fingerprint" % key)
		seen[f] = true
	# well fields individually
	var w: MatchState = base.duplicate_state()
	w.wells.append({"owner": 0, "x": 5, "y": 6, "expires_turn": 7})
	var fw: String = Simulation.fingerprint(w)
	for field: String in ["owner", "x", "y", "expires_turn"]:
		var w2: MatchState = w.duplicate_state()
		w2.wells[0][field] = (w2.wells[0][field] as int) + 1
		assert_ne(Simulation.fingerprint(w2), fw, "well %s is hashed" % field)
