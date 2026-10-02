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
