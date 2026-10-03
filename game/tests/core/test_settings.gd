extends GutTest
## Settings validation (docs/ARCHITECTURE.md section 23).


func _settings(tanks: int, rounds: int, wind: int, money: int) -> MatchSettings:
	var s := MatchSettings.new()
	s.seed = 5
	s.num_tanks = tanks
	s.rounds = rounds
	s.wind_max = wind
	s.start_money = money
	return s


func test_defaults() -> void:
	var s := MatchSettings.new()
	assert_eq(s.start_money, 10000)
	assert_true(s.full_unlocked)
	assert_eq(s.wind_max, 100)


func test_clamped_ranges() -> void:
	var cases: Array = [
		# tanks, rounds, wind, money -> expected
		[[-3, -3, -5, -1], [2, 1, 0, 0]],
		[[0, 0, 0, 0], [2, 1, 0, 0]],
		[[1, 1, 1, 1], [2, 1, 1, 1]],
		[[2, 20, 100, 1_000_000], [2, 20, 100, 1_000_000]],
		[[8, 21, 101, 1_000_001], [8, 20, 100, 1_000_000]],
		[[9, 1000, 100000, 1 << 40], [8, 20, 100, 1_000_000]],
		[[5, 7, 55, 12345], [5, 7, 55, 12345]],
	]
	for c: Array in cases:
		var inp: Array = c[0]
		var out: MatchSettings = _settings(inp[0], inp[1], inp[2], inp[3]).clamped()
		assert_eq([out.num_tanks, out.rounds, out.wind_max, out.start_money], c[1], "input %s" % str(inp))


func test_clamped_is_a_copy_and_keeps_other_fields() -> void:
	var s: MatchSettings = _settings(99, 99, 999, 99_999_999)
	s.full_unlocked = false
	s.seed = -123456789012
	var c: MatchSettings = s.clamped()
	assert_eq(s.num_tanks, 99, "the original is untouched")
	assert_eq(c.num_tanks, 8)
	assert_false(c.full_unlocked)
	assert_eq(c.seed, -123456789012)
	assert_ne(c, s)


func test_new_match_stores_clamped_values_and_does_not_touch_the_input() -> void:
	var st: MatchSettings = _settings(100, 0, 500, -50)
	var m: MatchState = Simulation.new_match(st)
	assert_eq(m.settings.num_tanks, 8)
	assert_eq(m.settings.rounds, 1)
	assert_eq(m.settings.wind_max, 100)
	assert_eq(m.settings.start_money, 0)
	assert_eq(m.tanks.size(), 8)
	for t: TankState in m.tanks:
		assert_eq(t.money, 0)
	assert_eq(st.num_tanks, 100, "caller's settings object unchanged")
	assert_eq(st.start_money, -50)
	assert_ne(m.settings, st, "no aliasing")


func test_out_of_range_settings_fingerprint_like_their_clamped_equivalent() -> void:
	var wild: MatchState = Simulation.new_match(_settings(100, 500, 9999, 77_000_000))
	var tame: MatchState = Simulation.new_match(_settings(8, 20, 100, 1_000_000))
	assert_eq(Simulation.fingerprint(wild), Simulation.fingerprint(tame), "the clamped values are what is fingerprinted")
	var other: MatchState = Simulation.new_match(_settings(8, 20, 99, 1_000_000))
	assert_ne(Simulation.fingerprint(other), Simulation.fingerprint(tame))


func test_start_money_zero_is_legal() -> void:
	var m: MatchState = Simulation.new_match(_settings(2, 1, 100, 0))
	assert_eq(m.tanks[0].money, 0)
	assert_eq(Simulation.validate_action(m, {"kind": "buy", "tank": 0, "item": "fuel_cell", "qty": 1}), "no_money")
	assert_eq(Simulation.validate_action(m, {"kind": "ready", "tank": 0}), "")


func test_wind_max_zero_means_no_wind() -> void:
	var m: MatchState = Simulation.new_match(_settings(2, 1, -7, 100))
	for t: TankState in m.tanks:
		Simulation.apply_action(m, {"kind": "ready", "tank": t.id})
	Simulation.start_round(m)
	assert_eq(m.wind, 0)


func test_full_unlocked_is_fingerprinted_and_cloned() -> void:
	var a: MatchSettings = _settings(2, 1, 100, 100)
	var b: MatchSettings = a.duplicate_settings()
	b.full_unlocked = false
	assert_ne(Simulation.fingerprint(Simulation.new_match(a)), Simulation.fingerprint(Simulation.new_match(b)))
	assert_false(Simulation.new_match(b).settings.full_unlocked)


# --- free version caps (docs/ARCHITECTURE.md section 32) ----------------------------------------

func _free(tanks: int, rounds: int) -> MatchSettings:
	var s: MatchSettings = _settings(tanks, rounds, 100, 10000)
	s.full_unlocked = false
	return s


func test_free_constants() -> void:
	assert_eq(SimConstants.FREE_MAX_TANKS, 4)
	assert_eq(SimConstants.FREE_MAX_ROUNDS, 5)


func test_free_clamps_tanks_to_two_to_four() -> void:
	var cases: Array = [[-1, 2], [0, 2], [1, 2], [2, 2], [3, 3], [4, 4], [5, 4], [8, 4], [100, 4]]
	for c: Array in cases:
		var cl: MatchSettings = _free(c[0], 1).clamped()
		assert_eq(cl.num_tanks, c[1], "tanks %d" % c[0])
		assert_eq(cl.controllers.size(), cl.num_tanks, "controllers match tanks %d" % c[0])


func test_free_clamps_rounds_above_five() -> void:
	var cases: Array = [[-2, 1], [0, 1], [1, 1], [3, 3], [5, 5], [6, 5], [10, 5], [20, 5], [999, 5]]
	for c: Array in cases:
		assert_eq(_free(2, c[0]).clamped().rounds, c[1], "rounds %d" % c[0])


func test_free_trims_controllers_and_keeps_the_leading_ones() -> void:
	var s: MatchSettings = _free(8, 1)
	s.controllers = PackedInt32Array([0, 1, 2, 4, 3, 2, 1, 0])
	var cl: MatchSettings = s.clamped()
	assert_eq(cl.controllers, PackedInt32Array([0, 1, 2, 2]), "trimmed to 4, Expert clamped to Normal")
	assert_eq(s.controllers.size(), 8, "original untouched")


func test_free_leaves_money_and_wind_alone() -> void:
	var s: MatchSettings = _settings(8, 20, 37, 123_456)
	s.full_unlocked = false
	var cl: MatchSettings = s.clamped()
	assert_eq([cl.wind_max, cl.start_money], [37, 123_456])


func test_full_is_unaffected_by_free_caps() -> void:
	var cl: MatchSettings = _settings(8, 20, 100, 10000).clamped()
	assert_eq([cl.num_tanks, cl.rounds, cl.controllers.size()], [8, 20, 8])


func test_new_match_free_stores_capped_values() -> void:
	var m: MatchState = Simulation.new_match(_free(8, 20))
	assert_eq([m.settings.num_tanks, m.settings.rounds, m.tanks.size()], [4, 5, 4])
	assert_eq(StateSerial.validate(m), "")


func test_free_new_match_equals_explicit_free_four_five() -> void:
	assert_eq(Simulation.fingerprint(Simulation.new_match(_free(8, 20))),
			Simulation.fingerprint(Simulation.new_match(_free(4, 5))))


func test_validate_rejects_free_state_with_too_many_tanks_or_rounds() -> void:
	var six: MatchState = Simulation.new_match(_settings(6, 3, 100, 100))
	assert_eq(StateSerial.validate(six), "", "the same state is fine in the full version")
	six.settings.full_unlocked = false
	assert_ne(StateSerial.validate(six), "", "6 tanks in the free version")
	var rounds: MatchState = Simulation.new_match(_settings(2, 10, 100, 100))
	assert_eq(StateSerial.validate(rounds), "")
	rounds.settings.full_unlocked = false
	assert_ne(StateSerial.validate(rounds), "", "10 rounds in the free version")


func test_validate_accepts_free_limits() -> void:
	var m: MatchState = Simulation.new_match(_free(4, 5))
	assert_eq(StateSerial.validate(m), "")


func test_free_save_with_too_many_tanks_is_rejected_on_decode() -> void:
	var m: MatchState = Simulation.new_match(_settings(6, 3, 100, 100))
	m.settings.full_unlocked = false
	var bytes: PackedByteArray = SaveCodec.encode(m, [] as Array[Dictionary])
	var res: Dictionary = SaveCodec.decode(bytes)
	assert_false(res["ok"])
	assert_eq(res["error"], "invalid_state")
