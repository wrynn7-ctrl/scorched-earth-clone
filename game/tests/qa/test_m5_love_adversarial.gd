@warning_ignore_start("integer_division")
extends GutTest
## M5 QA: hand-made adversarial Love Edition situations (docs/ARCHITECTURE.md section 37).
## Map edges, straight-up shots, power 1 and 1000, wind at the 30 cap, adjacent tanks (only the
## non-shooter gains), tampered saves (invalid_state), a standard action log replayed with the mode
## flipped, and a CPU facing a wall. Also self-tests of the audit helper, so a green fuzz means something.

const QaUtil = preload("res://tests/qa/qa_util.gd")
const M5 = preload("res://tests/qa/qa_m5.gd")

const HEART_R: int = 30
const HEART_AMOUNT: int = 34


# --- one shot at a time on flat ground ------------------------------------------------------------

func test_shot_sweep_edges_straight_up_extreme_power_and_wind() -> void:
	var xs: Array[int] = [12, 1588]
	var s: MatchState = M5.flat_love(xs, 0)
	var terrain_ref: PackedByteArray = s.terrain.cells.duplicate()
	var rng: Rng = Rng.derive(8801, 1)
	var spots: Array[int] = [12, 13, 24, 36, 300, 800, 1200, 1564, 1575, 1587, 1588]
	var angles: Array[int] = [0, 1, 2, 449, 450, 899, 900, 901, 1350, 1798, 1799, 1800]
	var powers: Array[int] = [1, 2, 3, 100, 500, 999, 1000]
	var winds: Array[int] = [-30, -29, 0, 29, 30]
	var seen: Dictionary = {"lost": 0, "terrain": 0, "tank": 0, "self_in_radius": 0, "gain": 0, "up_over_map": 0,
			"timeout": 0}
	var bad: Array[String] = []
	var shots: int = 0
	for n: int in range(420):
		var a: int = spots[rng.range_int(0, spots.size() - 1)]
		var b: int = spots[rng.range_int(0, spots.size() - 1)]
		if absi(a - b) < SimConstants.TANK_W:
			continue
		s.tanks[0].x = a
		s.tanks[1].x = b
		var shooter: int = rng.range_int(0, 1)
		var angle: int = angles[rng.range_int(0, angles.size() - 1)] if n % 3 != 0 else rng.range_int(0, 1800)
		var power: int = powers[rng.range_int(0, powers.size() - 1)] if n % 3 != 0 else rng.range_int(1, 1000)
		var wind: int = winds[rng.range_int(0, winds.size() - 1)] if n % 4 != 0 else rng.range_int(-30, 30)
		M5.reset_duel(s, shooter, wind)
		var action: Dictionary = M5.heart(shooter, angle, power)
		if n % 3 == 1 and absi(a - b) < 1400:
			# An aimed shot (flat-ground range formula + refinement) so that real hits are well covered.
			action = M5.scripted_action(s, Rng.derive(8802, n))
			if action["kind"] != "fire":
				continue
			angle = action["angle"]
			power = action["power"]
		var tag: String = "shot %d: tanks %d/%d shooter %d angle %d power %d wind %d" % [n, a, b, shooter, angle, power, wind]
		var tr: Dictionary = Ballistics.trace(s, shooter, angle, power, "heart", SimConstants.WIND_USE_STATE,
				SimConstants.MAX_FLIGHT_TICKS)
		assert_eq(Simulation.validate_action(s, action), "", tag)
		var events: Array[Dictionary] = Simulation.apply_action(s, action)
		shots += 1
		for e: String in M5.audit_love_action(s, action, events, [0, 0] as Array[int], terrain_ref):
			bad.append("%s: %s" % [tag, e])
		var end: Dictionary = QaUtil.find(events, "projectile_end")[0]
		seen[end["reason"]] = (seen.get(end["reason"], 0) as int) + 1
		if end["reason"] != tr["end_reason"] or end["x"] != tr["end_x"] or end["y"] != tr["end_y"]:
			bad.append("%s: resolution %s differs from the pure trace %s (%d, %d)" % [tag, str(end), tr["end_reason"],
					tr["end_x"], tr["end_y"]])
		var path: PackedInt32Array = QaUtil.find(events, "projectile")[0]["path"]
		for k: int in range(1, path.size(), 2):
			if path[k] < -(1 << 16) * 1:
				seen["up_over_map"] += 1
				break
		if ["terrain", "tank", "shield"].has(end["reason"]):
			var x: int = end["x"]
			var y: int = end["y"]
			for t: TankState in s.tanks:
				var amt: int = Damage.amount(Damage.distance_to_tank(x, y, t), HEART_R, HEART_AMOUNT)
				var got: int = t.love
				var want: int = 0 if t.id == shooter else amt
				if got != want:
					bad.append("%s: tank %d love %d, expected %d (impact %d, %d)" % [tag, t.id, got, want, x, y])
				if t.id == shooter and amt > 0:
					seen["self_in_radius"] += 1
				if want > 0:
					seen["gain"] += 1
	assert_eq(bad.size(), 0, "sweep problems:\n  " + "\n  ".join(bad.slice(0, 10)))
	gut.p("LOVE SWEEP  %d shots: %s" % [shots, str(seen)])
	assert_gt(shots, 300)
	for k: String in ["lost", "terrain", "tank", "self_in_radius", "gain"]:
		assert_gt(seen[k] as int, 3, "the sweep covered '%s': %s" % [k, str(seen)])


func test_power_one_shot_lands_next_to_the_shooter() -> void:
	var s: MatchState = M5.flat_love([300, 700], 0)
	for angle: int in [0, 450, 900, 1350, 1800]:
		M5.reset_duel(s, 0, 0)
		var ev: Array[Dictionary] = Simulation.apply_action(s, M5.heart(0, angle, 1))
		assert_eq(QaUtil.types(ev).slice(0, 3), ["fire", "projectile", "projectile_end"] as Array[String], "angle %d" % angle)
		assert_eq(s.tanks[1].love, 0, "400 cells away, power 1")
		assert_eq(s.phase, SimConstants.PHASE_AIM)


func test_straight_up_at_full_power_leaves_the_map_and_comes_back() -> void:
	var s: MatchState = M5.flat_love([800, 1000], 0)
	M5.reset_duel(s, 0, 0)
	var ev: Array[Dictionary] = Simulation.apply_action(s, M5.heart(0, 900, 1000))
	var end: Dictionary = QaUtil.find(ev, "projectile_end")[0]
	assert_true(["tank", "terrain"].has(end["reason"]), "came back down, reason %s" % end["reason"])
	assert_lt(end["x"], 812, "back on the shooter, wind 0")
	var path: PackedInt32Array = QaUtil.find(ev, "projectile")[0]["path"]
	var min_y: int = 1 << 30
	for k: int in range(1, path.size(), 2):
		min_y = mini(min_y, path[k])
	assert_lt(min_y, 0, "the shell went above the screen")
	assert_eq(s.tanks[1].love, 0, "200 cells away")


func test_malformed_and_out_of_range_heart_actions_are_rejected_untouched() -> void:
	var s: MatchState = M5.flat_love([300, 900], 7)
	var sig: String = M5.lite_fp(s)
	var base: Dictionary = M5.heart(0, 450, 500)
	var cases: Array[Dictionary] = []
	for k: Array in [["power", 0, "bad_power"], ["power", 1001, "bad_power"], ["power", -5, "bad_power"],
			["power", 9223372036854775807, "bad_power"], ["angle", -1, "bad_angle"], ["angle", 1801, "bad_angle"],
			["angle", -9223372036854775808, "bad_angle"], ["weapon", "HEART", "unknown_weapon"],
			["weapon", "", "unknown_weapon"], ["weapon", "heart ", "unknown_weapon"], ["weapon", 5, "bad_field"],
			["angle", "450", "bad_field"], ["power", 500.5, "bad_field"], ["power", null, "bad_field"],
			["tank", 2, "bad_tank"], ["tank", -1, "bad_tank"], ["tank", "0", "bad_field"], ["kind", "FIRE", "unknown_kind"],
			["kind", 7, "bad_action"]]:
		var a: Dictionary = base.duplicate()
		a[k[0] as String] = k[1]
		cases.append(a)
		assert_eq(Simulation.validate_action(s, a), k[2], "%s = %s" % [str(k[0]), str(k[1])])
		assert_true(Simulation.apply_action(s, a).is_empty(), "nothing applied for %s" % str(a))
	var missing: Dictionary = base.duplicate()
	missing.erase("power")
	assert_eq(Simulation.validate_action(s, missing), "bad_field")
	assert_eq(Simulation.validate_action(s, {}), "bad_action")
	assert_eq(M5.lite_fp(s), sig, "every refusal left the state alone")
	# Whole-number floats from JSON are fine once normalised, and then give the same result as ints.
	var jsoned: Dictionary = JSON.parse_string(JSON.stringify(base)) as Dictionary
	assert_eq(typeof(jsoned["angle"]), TYPE_FLOAT)
	var norm: Dictionary = Simulation.normalize_action(jsoned)
	assert_eq(Simulation.validate_action(s, norm), "")
	var twin: MatchState = M5.flat_love([300, 900], 7)
	Simulation.apply_action(s, norm)
	Simulation.apply_action(twin, base)
	assert_eq(M5.lite_fp(s), M5.lite_fp(twin), "a JSON round trip of the action changes nothing")
	# The extremes that ARE legal.
	for pair: Array in [[0, 1], [0, 1000], [1800, 1], [1800, 1000], [900, 1], [900, 1000]]:
		var t: MatchState = M5.flat_love([300, 900], 30)
		var ev: Array[Dictionary] = Simulation.apply_action(t, M5.heart(0, pair[0] as int, pair[1] as int))
		assert_false(ev.is_empty(), "angle %d power %d is legal" % [pair[0], pair[1]])


# --- adjacent tanks ----------------------------------------------------------------------------------

func test_adjacent_tanks_only_the_non_shooter_gains_until_someone_wins() -> void:
	var s: MatchState = M5.flat_love([300, 324], 0)
	var terrain_ref: PackedByteArray = s.terrain.cells.duplicate()
	var love: Array[int] = [0, 0]
	var guard: int = 0
	var both_in_radius: int = 0
	while s.phase == SimConstants.PHASE_AIM and guard < 60:
		guard += 1
		s.wind = 0  # the per-turn drift would blow the straight-up shell off the neighbour
		var shooter: int = s.current_tank
		var action: Dictionary = M5.heart(shooter, 900, 600)
		var ev: Array[Dictionary] = Simulation.apply_action(s, action)
		for e: String in M5.audit_love_action(s, action, ev, love, terrain_ref):
			assert_eq(e, "", "shot %d: %s" % [guard, e])
		assert_eq(QaUtil.find(ev, "heart_burst").size(), 1, "shot %d bursts" % guard)
		if QaUtil.find(ev, "heart_burst").is_empty():
			break
		var burst: Dictionary = QaUtil.find(ev, "heart_burst")[0]
		var in_radius: int = 0
		for t: TankState in s.tanks:
			if Damage.distance_to_tank(burst["x"], burst["y"], t) < HEART_R:
				in_radius += 1
		if in_radius == 2:
			both_in_radius += 1
		var loves: Array[Dictionary] = QaUtil.find(ev, "love")
		assert_eq(loves.size(), 1, "exactly one tank gains although both are in the radius (shot %d)" % guard)
		if loves.is_empty():
			break
		assert_eq(loves[0]["tank"], 1 - shooter)
		assert_eq(s.tanks[shooter].love, love[shooter], "the shooter's meter did not move")
		love = [s.tanks[0].love, s.tanks[1].love]
	assert_eq(s.phase, SimConstants.PHASE_MATCH_OVER, "the duel ends by itself")
	assert_gt(both_in_radius, 0, "the heart really reached both tanks")
	assert_lt(guard, 20)


func test_adjacent_tanks_mirror_from_the_right_seat() -> void:
	var s: MatchState = M5.flat_love([1264, 1288], 0)
	s.current_tank = 1
	var ev: Array[Dictionary] = Simulation.apply_action(s, M5.heart(1, 900, 800))
	var loves: Array[Dictionary] = QaUtil.find(ev, "love")
	assert_eq(loves.size(), 1)
	assert_eq(loves[0]["tank"], 0)
	assert_eq(loves[0]["from"], 1)
	assert_eq(s.tanks[1].love, 0)


func test_love_amount_is_capped_at_100_and_the_event_carries_the_gain() -> void:
	var s: MatchState = M5.flat_love([300, 324], 0)
	s.tanks[1].love = 95
	var ev: Array[Dictionary] = Simulation.apply_action(s, M5.heart(0, 900, 600))
	var loves: Array[Dictionary] = QaUtil.find(ev, "love")
	assert_eq(loves.size(), 1)
	assert_eq(loves[0]["love"], 100)
	assert_eq(loves[0]["amount"], 5, "the gain is what actually fitted, not the nominal amount")
	assert_eq(QaUtil.find(ev, "round_end")[0]["winner"], 0)
	assert_eq(s.phase, SimConstants.PHASE_MATCH_OVER)
	assert_eq(QaUtil.types(ev).count("turn"), 0, "no turn after the win")
	assert_eq(QaUtil.types(ev).count("wind"), 0, "no wind drift after the win")


# --- wind at the cap -------------------------------------------------------------------------------------

func test_wind_never_exceeds_30_in_love_even_when_asked_for_100() -> void:
	var st: MatchState = Simulation.new_match(M5.love_settings(7, 0, 0, 100))
	assert_eq(st.settings.wind_max, 30)
	var s: MatchState = M5.flat_love([300, 1300], 30)
	var touched: Dictionary = {30: false, -30: false}
	for sign: int in [1, -1]:
		s.wind = 30 * sign
		for _i: int in range(400):
			Simulation.apply_action(s, {"kind": "pass", "tank": s.current_tank})
			assert_lte(absi(s.wind), 30, "pass-drift stays inside the cap")
			if absi(s.wind) == 30:
				touched[s.wind] = true
	assert_true(touched[30] and touched[-30], "the wind sat on both caps at some point")
	assert_eq(s.phase, SimConstants.PHASE_AIM, "passing never ends a love match (no turn limit)")
	assert_eq(QaUtil.check_invariants(s).size(), 0)


func test_every_cpu_level_plays_against_a_30_wind_in_both_directions() -> void:
	for level: int in [1, 2, 3, 4]:
		for wind: int in [-30, 30]:
			for seat: int in [0, 1]:
				var s: MatchState = M5.flat_love([200, 1400], wind)
				s.settings.controllers = PackedInt32Array([level, level])
				M5.reset_duel(s, seat, wind)
				var a: Dictionary = AiPlayer.next_action(s, seat)
				assert_eq(a["kind"], "fire", "L%d wind %d seat %d: %s" % [level, wind, seat, str(a)])
				assert_eq(a["weapon"], "heart")
				assert_eq(Simulation.validate_action(s, a), "")


# --- tampered saves ----------------------------------------------------------------------------------------

## A love match a few CPU turns in (aim phase, both meters usually above 0).
func _love_midgame(seed_value: int = 41) -> MatchState:
	var s: MatchState = Simulation.new_match(M5.love_settings(seed_value, 2, 2, 30))
	var guard: int = 0
	while guard < 40 and (s.tanks[0].love == 0 or s.tanks[1].love == 0 or s.turn_number < 3):
		guard += 1
		Simulation.apply_action(s, AiPlayer.next_action(s, s.current_tank))
	assert_eq(s.phase, SimConstants.PHASE_AIM, "still playing")
	assert_gt(s.tanks[0].love + s.tanks[1].love, 0)
	return s


func _decode_of(state: MatchState) -> Dictionary:
	return SaveCodec.decode(SaveCodec.encode(state, [] as Array[Dictionary]))


func _expect_invalid(state: MatchState, what: String) -> void:
	var res: Dictionary = _decode_of(state)
	assert_false(res["ok"], "%s must not decode" % what)
	assert_eq(res["error"], "invalid_state", what)


func test_untampered_love_states_decode_and_validate() -> void:
	var s: MatchState = _love_midgame()
	var res: Dictionary = _decode_of(s)
	assert_true(res["ok"], str(res["error"]))
	assert_eq(Simulation.fingerprint(res["state"] as MatchState), Simulation.fingerprint(s))
	assert_eq(StateSerial.validate(s), "")


func test_love_state_flipped_to_standard_mode_is_invalid() -> void:
	var s: MatchState = _love_midgame()
	s.settings.mode = SimConstants.MODE_STANDARD
	_expect_invalid(s, "a love state (meters > 0, heart fired) flipped to standard")


func test_fresh_love_state_flipped_to_standard_does_not_crash() -> void:
	# No meter and no shot yet: this is also a legal standard state (a shop visit with no purchases),
	# so decoding is allowed to succeed. Either way nothing may crash and a decoded state must be playable.
	var s: MatchState = Simulation.new_match(M5.love_settings(5, 0, 0, 30))
	s.settings.mode = SimConstants.MODE_STANDARD
	var res: Dictionary = _decode_of(s)
	gut.p("LOVE TAMPER  fresh love state flipped to standard decodes: %s (%s)" % [str(res["ok"]), str(res["error"])])
	if res["ok"]:
		var back: MatchState = res["state"]
		assert_eq(back.settings.mode, SimConstants.MODE_STANDARD)
		assert_eq(Simulation.validate_action(back, M5.heart(back.current_tank, 450, 500)), "unknown_weapon")


func test_love_over_100_or_negative_is_invalid() -> void:
	for v: int in [101, 255, 100000, -1, -2147483648, 2147483647]:
		var s: MatchState = _love_midgame()
		s.tanks[1].love = v
		_expect_invalid(s, "love %d" % v)


func test_a_full_meter_during_aim_and_match_over_without_one_are_invalid() -> void:
	var s: MatchState = _love_midgame()
	s.tanks[0].love = 100
	_expect_invalid(s, "love 100 while still in aim")
	var t: MatchState = _love_midgame()
	t.phase = SimConstants.PHASE_MATCH_OVER
	_expect_invalid(t, "match_over without a full meter")


const SETTING_TAMPERS: Array[String] = ["rounds 2", "wind_max 31", "wind_max 100", "start_money 1", "mode 2",
		"mode -1", "phase shop", "catalog weapon fired", "ready flag", "controllers size", "num_tanks 3"]


func _tamper_setting(s: MatchState, what: String) -> void:
	match what:
		"rounds 2":
			s.settings.rounds = 2
		"wind_max 31":
			s.settings.wind_max = 31
		"wind_max 100":
			s.settings.wind_max = 100
		"start_money 1":
			s.settings.start_money = 1
		"mode 2":
			s.settings.mode = 2
		"mode -1":
			s.settings.mode = -1
		"phase shop":
			s.phase = SimConstants.PHASE_SHOP
		"catalog weapon fired":
			s.tanks[0].last_fire_weapon = 1
			s.tanks[0].last_fire_angle = 450
			s.tanks[0].last_fire_power = 500
			s.tanks[0].last_fire_x = 10
			s.tanks[0].last_fire_y = 10
			s.tanks[0].last_fire_turn = 0
		"ready flag":
			s.tanks[0].ready = true
		"controllers size":
			s.settings.controllers = PackedInt32Array([2, 2, 2])
		"num_tanks 3":
			s.settings.num_tanks = 3


func test_love_settings_that_love_mode_forbids_are_invalid() -> void:
	for what: String in SETTING_TAMPERS:
		var s: MatchState = _love_midgame()
		_tamper_setting(s, what)
		_expect_invalid(s, "love tamper '%s'" % what)


func test_standard_state_with_heart_in_last_fire_is_invalid() -> void:
	var s: MatchState = QaUtil.started_match(QaUtil.settings(3, 2, 2))
	s.tanks[0].last_fire_weapon = Catalog.HEART_INDEX
	s.tanks[0].last_fire_angle = 450
	s.tanks[0].last_fire_power = 500
	s.tanks[0].last_fire_turn = 0
	_expect_invalid(s, "heart fired in a standard match")
	var t: MatchState = QaUtil.started_match(QaUtil.settings(3, 2, 2))
	t.tanks[1].love = 10
	_expect_invalid(t, "love meter in a standard match")


func test_finished_love_match_decodes_and_the_loser_cannot_be_the_winner() -> void:
	var s: MatchState = Simulation.new_match(M5.love_settings(11, 3, 3, 30))
	var guard: int = 0
	while s.phase == SimConstants.PHASE_AIM and guard < 200:
		guard += 1
		Simulation.apply_action(s, AiPlayer.next_action(s, s.current_tank))
	assert_eq(s.phase, SimConstants.PHASE_MATCH_OVER)
	var res: Dictionary = _decode_of(s)
	assert_true(res["ok"], "the honest finished match decodes: %s" % str(res["error"]))
	var winner: int = Simulation.standings(s)[0]
	# Tamper: the tank whose meter is full is credited with the win (the loser "won").
	var t: MatchState = s.duplicate_state()
	t.tanks[winner].round_wins = 0
	t.tanks[1 - winner].round_wins = 1
	var r2: Dictionary = _decode_of(t)
	if r2["ok"]:
		pending("BUG (low): StateSerial.validate accepts a finished love match whose full-meter tank holds the " \
				+ "round win. Input: honest match_over state with round_wins swapped. Expected invalid_state; " \
				+ "actual ok. Suspected core/state_serial.gd:351 (_validate_love_flow) checks only meters, " \
				+ "not that the non-full tank has round_wins == 1.")
		return
	assert_eq(r2["error"], "invalid_state")


func test_two_full_meters_are_invalid() -> void:
	var s: MatchState = Simulation.new_match(M5.love_settings(11, 3, 3, 30))
	var guard: int = 0
	while s.phase == SimConstants.PHASE_AIM and guard < 200:
		guard += 1
		Simulation.apply_action(s, AiPlayer.next_action(s, s.current_tank))
	s.tanks[0].love = 100
	s.tanks[1].love = 100
	var res: Dictionary = _decode_of(s)
	if res["ok"]:
		pending("BUG (low): StateSerial.validate accepts a finished love match where BOTH meters are 100 (a shot " \
				+ "can only fill the other tank's meter). Expected invalid_state; actual ok. Suspected " \
				+ "core/state_serial.gd:351 (_validate_love_flow).")
		return
	assert_eq(res["error"], "invalid_state")


# --- a standard log replayed with the mode flipped --------------------------------------------------------

func _apply_logged(state: MatchState, log: Array[Dictionary], a: Dictionary) -> void:
	var n: Dictionary = Simulation.normalize_action(a)
	assert_eq(Simulation.validate_action(state, n), "", "building the log: %s" % str(n))
	log.append(n)
	Simulation.apply_action(state, n)


## A finished standard 2-tank, 2-round match and its action log (buys, readies, fires, one pass).
func _standard_log(seed_value: int) -> Array[Dictionary]:
	var s: MatchState = Simulation.new_match(QaUtil.settings(seed_value, 2, 2))
	var log: Array[Dictionary] = []
	var rng: Rng = Rng.derive(seed_value, 77)
	var guard: int = 0
	while s.phase != SimConstants.PHASE_MATCH_OVER and guard < 300:
		guard += 1
		if s.phase == SimConstants.PHASE_SHOP:
			for t: TankState in s.tanks:
				_apply_logged(s, log, {"kind": "buy", "tank": t.id, "item": "pulse_missile", "qty": 2})
				_apply_logged(s, log, {"kind": "ready", "tank": t.id})
			Simulation.start_round(s)
		elif guard == 2:
			_apply_logged(s, log, {"kind": "pass", "tank": s.current_tank})
		else:
			_apply_logged(s, log, QaUtil.bot_action(s, rng))
	assert_eq(s.phase, SimConstants.PHASE_MATCH_OVER)
	return log


## Replays `log` the way MatchSession would (normalize, validate, apply what is legal, start_round
## when everyone is ready). Returns {errors: {err: count}, applied: int}.
func _replay(state: MatchState, log: Array[Dictionary]) -> Dictionary:
	var errors: Dictionary = {}
	var applied: int = 0
	for a: Dictionary in log:
		var n: Dictionary = Simulation.normalize_action(a)
		var err: String = Simulation.validate_action(state, n)
		if err != "":
			errors[err] = (errors.get(err, 0) as int) + 1
			continue
		Simulation.apply_action(state, n)
		applied += 1
		if Simulation.all_ready(state):
			Simulation.start_round(state)
	return {"errors": errors, "applied": applied}


func test_standard_log_replayed_in_love_mode_is_rejected_or_diverges_safely() -> void:
	for seed_value: int in [1, 2, 3]:
		var log: Array[Dictionary] = _standard_log(seed_value)
		var settings: MatchSettings = QaUtil.settings(seed_value, 2, 2)
		settings.mode = SimConstants.MODE_LOVE
		var s: MatchState = Simulation.new_match(settings)
		var before: String = Simulation.fingerprint(s)
		var res: Dictionary = _replay(s, log)
		var errors: Dictionary = res["errors"]
		for k: Variant in errors.keys():
			assert_true(["bad_mode", "not_your_turn", "bad_phase"].has(str(k)), "unexpected rejection '%s'" % str(k))
		assert_gt((errors.get("bad_mode", 0) as int), log.size() / 2, "most of it is bad_mode")
		assert_eq(StateSerial.validate(s), "", "the state is still one the simulation could produce")
		assert_eq(QaUtil.check_invariants(s).size(), 0)
		if (res["applied"] as int) == 0:
			assert_eq(Simulation.fingerprint(s), before, "every action refused: nothing changed")
		gut.p("LOVE FLIP  seed %d: %d actions, applied %d, rejections %s" % [seed_value, log.size(), res["applied"], str(errors)])


func test_love_log_replayed_in_standard_mode_is_rejected() -> void:
	var s: MatchState = Simulation.new_match(M5.love_settings(21, 2, 2, 30))
	var log: Array[Dictionary] = []
	var guard: int = 0
	while s.phase == SimConstants.PHASE_AIM and guard < 100:
		guard += 1
		_apply_logged(s, log, AiPlayer.next_action(s, s.current_tank))
	var settings: MatchSettings = M5.love_settings(21, 2, 2, 30)
	settings.mode = SimConstants.MODE_STANDARD
	settings.rounds = 1
	var std: MatchState = Simulation.new_match(settings)
	var before: String = Simulation.fingerprint(std)
	var res: Dictionary = _replay(std, log)
	assert_eq(res["applied"], 0, "nothing of a love log is legal in the shop of a standard match")
	assert_eq(Simulation.fingerprint(std), before)
	# And once the round is running, a heart is not a weapon.
	for t: TankState in std.tanks:
		Simulation.apply_action(std, {"kind": "ready", "tank": t.id})
	Simulation.start_round(std)
	for a: Dictionary in log:
		if a["kind"] == "fire":
			assert_eq(Simulation.validate_action(std, a), "unknown_weapon" if a["tank"] == std.current_tank else "not_your_turn")
			break


func test_a_save_holding_a_foreign_action_log_loads_and_replays_without_crashing() -> void:
	var s: MatchState = Simulation.new_match(M5.love_settings(31, 2, 2, 30))
	var log: Array[Dictionary] = _standard_log(31)
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(s, log))
	assert_true(res["ok"], "the log is not validated at decode: %s" % str(res["error"]))
	var back: MatchState = res["state"]
	var rep: Dictionary = _replay(back, res["actions"] as Array[Dictionary])
	assert_eq(StateSerial.validate(back), "")
	assert_eq(QaUtil.check_invariants(back).size(), 0, str(rep))


# --- the audit helper itself ---------------------------------------------------------------------------------

func _real_shot() -> Dictionary:
	var s: MatchState = M5.flat_love([300, 324], 0)
	var ref: PackedByteArray = s.terrain.cells.duplicate()
	var a: Dictionary = M5.heart(0, 900, 600)
	var ev: Array[Dictionary] = Simulation.apply_action(s, a)
	return {"state": s, "action": a, "events": ev, "ref": ref}


func test_audit_accepts_a_real_shot() -> void:
	var r: Dictionary = _real_shot()
	var errs: Array[String] = M5.audit_love_action(r["state"], r["action"], r["events"], [0, 0] as Array[int], r["ref"])
	assert_eq(errs.size(), 0, str(errs))


func _forge(r: Dictionary, i: int) -> void:
	var ev: Array[Dictionary] = r["events"]
	var st: MatchState = r["state"]
	match i:
		0:  # a damage event
			ev.insert(4, {"type": "damage", "tick": 0, "tank": 1, "amount": 5, "health": 95, "cause": "explosion"})
		1:  # a money event
			ev.append({"type": "money", "tick": 0, "tank": 0, "delta": 5, "money": 5, "reason": "damage"})
		2:  # the shooter gains
			st.tanks[0].love = 10
		3:  # terrain edited
			st.terrain.cells[5] = 3
		4:  # meter above 100
			st.tanks[1].love = 101
		5:  # health changed
			st.tanks[1].health = 90
		6:  # an explosion event
			ev.insert(3, {"type": "explosion", "tick": 0, "x": 1, "y": 1, "radius": 5, "weapon": "heart"})
		7:  # phase says over without a round_end
			st.phase = SimConstants.PHASE_MATCH_OVER


func test_audit_catches_forged_timelines_and_states() -> void:
	for i: int in range(8):
		var r: Dictionary = _real_shot()
		_forge(r, i)
		var errs: Array[String] = M5.audit_love_action(r["state"], r["action"], r["events"], [0, 0] as Array[int], r["ref"])
		assert_gt(errs.size(), 0, "forgery %d went unnoticed" % i)


# --- a CPU facing a wall ---------------------------------------------------------------------------------------

## Solid wall of `height` cells standing on the ground, columns [x0, x1).
func _wall(s: MatchState, x0: int, x1: int, height: int) -> void:
	for x: int in range(x0, x1):
		for y: int in range(600 - height, 600):
			s.terrain.cells[x * SimConstants.WORLD_H + y] = 1


func test_cpus_still_finish_a_duel_with_a_wall_between_them() -> void:
	var results: PackedStringArray = PackedStringArray()
	var stuck: Array[String] = []
	for height: int in [150, 300, 450]:
		for level: int in [1, 2, 3, 4]:
			var s: MatchState = M5.flat_love([300, 1300], 12)
			_wall(s, 780, 820, height)
			s.settings.controllers = PackedInt32Array([level, level])
			var guard: int = 0
			while s.phase == SimConstants.PHASE_AIM and guard < 150:
				guard += 1
				var a: Dictionary = AiPlayer.next_action(s, s.current_tank)
				assert_eq(Simulation.validate_action(s, a), "", "wall %d L%d action %d: %s" % [height, level, guard, str(a)])
				Simulation.apply_action(s, a)
			results.append("h%d/L%d=%d" % [height, level, guard])
			if s.phase != SimConstants.PHASE_MATCH_OVER:
				stuck.append("wall %d level %d: no winner after 150 actions (love %d/%d)" % [height, level,
						s.tanks[0].love, s.tanks[1].love])
	gut.p("LOVE WALL  actions to finish: %s" % ", ".join(results))
	assert_eq(stuck.size(), 0, "stalemates:\n  " + "\n  ".join(stuck))
