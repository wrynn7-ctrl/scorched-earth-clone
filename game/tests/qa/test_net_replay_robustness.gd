extends GutTest
## M7-Q: NetReplay fed hostile and random logs (no emulator needed).
##  1. malformed entries (wrong types, unknown kinds, missing or huge tank, entries after the end or after a dispute): never a
##     crash, always rejected, and a rejected entry leaves the state untouched;
##  2. a hostile `auto` level, and malformed database values (both were bugs; fixed in M7-QF-B and tested for real now);
##  3. 50 random seeded mixed logs (humans with random legal actions, CPUs, live and async timeouts, teams, Love) replayed through
##     NetReplay give the same fingerprint as the offline path after every entry.

const A: String = NetTestUtil.HUMAN_A
const B: String = NetTestUtil.HUMAN_B


func _aim_replay(cpu_level: int = 1) -> NetReplay:
	var r: NetReplay = NetReplay.create(NetTestUtil.meta([NetTestUtil.human(A), NetTestUtil.human(B), NetTestUtil.cpu(cpu_level)], {"rounds": 1}, {}, 4242))
	r.apply_entry({"kind": "auto_shop", "tank": 2, "level": cpu_level})
	r.apply_entry({"kind": "ready", "tank": 0})
	r.apply_entry({"kind": "ready", "tank": 1})
	return r


# --- 1. malformed entries -------------------------------------------------------------------------------------------------

func _malformed(t: int) -> Array:
	var fire: Dictionary = {"kind": "fire", "tank": t, "angle": 450, "power": 500, "weapon": "spark_dart"}
	var out: Array = []
	for field: String in ["angle", "power", "tank", "weapon"]:
		for junk: Variant in ["x", "", null, true, [1], {"a": 1}, -5, 1 << 62, -(1 << 62), 450.5, 1801, 1001, 0]:
			if junk is int and ((field == "tank" and junk == t) or (field == "angle" and junk >= 0 and junk <= 1800) or (field == "power" and junk >= 1 and junk <= 1000)):
				continue  # a legal value, not junk
			var e: Dictionary = fire.duplicate()
			e[field] = junk
			out.append(e)
		var missing: Dictionary = fire.duplicate()
		missing.erase(field)
		out.append(missing)
	for kind: Variant in [5, null, true, {"a": 1}, ["fire"], "bogus", "", "FIRE", "start_round", "auto ", "Timeout"]:
		out.append({"kind": kind, "tank": t})
	out.append({})
	out.append({"tank": t})
	for e2: Dictionary in [
		{"kind": "auto"}, {"kind": "auto", "tank": t}, {"kind": "auto", "tank": 2}, {"kind": "auto", "tank": 2, "level": "2"},
		{"kind": "auto", "tank": 2, "level": 99}, {"kind": "auto", "tank": 2, "level": 0}, {"kind": "auto", "tank": t, "level": 2},
		{"kind": "auto", "tank": 1 << 62, "level": 2}, {"kind": "auto_shop", "tank": 2, "level": 2}, {"kind": "auto_shop", "tank": -1, "level": 2},
		{"kind": "timeout"}, {"kind": "timeout", "tank": "x"}, {"kind": "timeout", "tank": null}, {"kind": "timeout", "tank": 1 << 62},
		{"kind": "timeout", "tank": -1}, {"kind": "timeout", "tank": 1 - t},
		{"kind": "move", "tank": t}, {"kind": "move", "tank": t, "dx": 1 << 62}, {"kind": "move", "tank": t, "dx": "5"}, {"kind": "move", "tank": t, "dx": 0},
		{"kind": "use_item", "tank": t}, {"kind": "use_item", "tank": t, "item": 5}, {"kind": "use_item", "tank": t, "item": null}, {"kind": "use_item", "tank": t, "item": "nonexistent"},
		{"kind": "buy", "tank": t, "item": "shield", "qty": 1}, {"kind": "sell", "tank": t, "item": "shield", "qty": 1}, {"kind": "ready", "tank": t},
		{"kind": "pass"}, {"kind": "pass", "tank": [t]}, {"kind": "pass", "tank": {"a": 1}}, {"kind": "pass", "tank": null}, {"kind": "pass", "tank": true},
		{"kind": "pass", "tank": str(t)}, {"kind": "pass", "tank": 1 - t},
	]:
		out.append(e2)
	return out


func test_malformed_entries_are_rejected_dispute_the_replay_and_change_nothing() -> void:
	var t0: int = Time.get_ticks_msec()
	var t: int = _aim_replay().state.current_tank
	var cases: Array = _malformed(t)
	var rejected: int = 0
	for c: Variant in cases:
		var r: NetReplay = _aim_replay()
		var before_fp: String = r.fingerprint()
		var before_count: int = r.count
		var res: Dictionary = r.apply_entry(c as Dictionary)
		if (res["ok"] as bool):
			fail_test("accepted a malformed entry: %s" % JSON.stringify(c))
			continue
		rejected += 1
		assert_true(r.disputed, "rejected entry must dispute: %s" % JSON.stringify(c))
		assert_ne(r.dispute_reason, "", "a dispute carries a reason: %s" % JSON.stringify(c))
		assert_eq(r.count, before_count, "a rejected entry is not counted: %s" % JSON.stringify(c))
		assert_eq(r.fingerprint(), before_fp, "a rejected entry changes no state: %s" % JSON.stringify(c))
		assert_eq(r.dispute_index, before_count)
	assert_eq(rejected, cases.size())
	gut.p("%d malformed entries, all rejected (%d ms)" % [cases.size(), Time.get_ticks_msec() - t0])


func test_a_disputed_replay_accepts_nothing_more() -> void:
	var r: NetReplay = _aim_replay()
	var t: int = r.state.current_tank
	assert_false((r.apply_entry({"kind": "bogus"}) as Dictionary)["ok"])
	var count: int = r.count
	var fp: String = r.fingerprint()
	for e: Dictionary in [{"kind": "pass", "tank": t}, {"kind": "fire", "tank": t, "angle": 450, "power": 500, "weapon": "spark_dart"}, {"kind": "timeout", "tank": t}, {}]:
		var res: Dictionary = r.apply_entry(e)
		assert_false(res["ok"])
		assert_eq(res["err"], "disputed")
	assert_eq(r.count, count)
	assert_eq(r.fingerprint(), fp)
	assert_eq(r.dispute_reason, "invalid_unknown_kind", "the first reason sticks")


func test_every_kind_of_entry_after_the_end_is_rejected() -> void:
	var meta: Dictionary = NetTestUtil.meta([NetTestUtil.human(A), NetTestUtil.cpu(1), NetTestUtil.cpu(2)], {"rounds": 1}, {}, 9)
	var r: NetReplay = NetReplay.create(meta)
	NetTestUtil.play_through(r, 400)
	assert_true(r.ended)
	var fp: String = r.fingerprint()
	var count: int = r.count
	var late: Array = [
		{"kind": "pass", "tank": 0}, {"kind": "fire", "tank": 0, "angle": 450, "power": 500, "weapon": "spark_dart"}, {"kind": "ready", "tank": 0},
		{"kind": "auto", "tank": 1, "level": 1}, {"kind": "auto_shop", "tank": 1, "level": 1}, {"kind": "timeout", "tank": 0},
		{"kind": "timeout", "tank": 0, "async": 1}, {"kind": "buy", "tank": 0, "item": "shield", "qty": 1}, {"kind": "bogus"}, {},
	]
	for e: Variant in late:
		var fresh: NetReplay = NetReplay.create(meta)
		NetTestUtil.play_through(fresh, 400)
		var res: Dictionary = fresh.apply_entry(e as Dictionary)
		assert_false(res["ok"], JSON.stringify(e))
		assert_eq(res["err"], "entry_after_end")
		assert_true(fresh.disputed)
		assert_eq(fresh.fingerprint(), fp)
		assert_eq(fresh.count, count)


func test_entries_for_a_missing_seat_or_tank_in_every_phase() -> void:
	# shop phase
	var shop: NetReplay = NetReplay.create(NetTestUtil.meta([NetTestUtil.human(A), NetTestUtil.human(B), NetTestUtil.cpu(2)], {"rounds": 1}, {}, 4242))
	for e: Dictionary in [{"kind": "ready", "tank": 7}, {"kind": "ready", "tank": 3}, {"kind": "ready", "tank": -2}, {"kind": "buy", "tank": 99, "item": "shield", "qty": 1},
			{"kind": "timeout", "tank": 8}, {"kind": "auto_shop", "tank": 7, "level": 2}, {"kind": "auto_shop", "tank": 0, "level": 2}]:
		var fresh: NetReplay = NetReplay.create(NetTestUtil.meta([NetTestUtil.human(A), NetTestUtil.human(B), NetTestUtil.cpu(2)], {"rounds": 1}, {}, 4242))
		var res: Dictionary = fresh.apply_entry(e)
		assert_false(res["ok"], JSON.stringify(e))
	assert_false(shop.disputed)


func test_a_timeout_for_a_cpu_seat_is_a_dispute() -> void:
	# The rules refuse a client timeout on a CPU seat and the sweep writes an `auto` entry for a stuck CPU turn instead, so
	# NetReplay calls a timeout for a seat that was a CPU from the start a dispute (it used to apply it: the AI played at level
	# 2, or in the shop the CPU was marked ready with no purchases, a second way to "ready" a CPU).
	var shop: NetReplay = NetReplay.create(NetTestUtil.meta([NetTestUtil.human(A), NetTestUtil.human(B), NetTestUtil.cpu(2)], {"rounds": 1}, {}, 4242))
	var res: Dictionary = shop.apply_entry({"kind": "timeout", "tank": 2})
	assert_false(res["ok"])
	assert_eq(res["err"], "bad_timeout")
	assert_false(shop.state.tanks[2].ready)
	assert_true(shop.disputed)
	var aim: NetReplay = _aim_replay()
	var guard: int = 0
	while aim.state.current_tank != 2 and guard < 6:
		guard += 1
		assert_true((aim.apply_entry(AiPlayer.next_action(aim.state, aim.state.current_tank)) as Dictionary)["ok"])
	assert_eq(aim.state.current_tank, 2)
	for e: Dictionary in [{"kind": "timeout", "tank": 2}, {"kind": "timeout", "tank": 2, "async": 1}]:
		var fresh: NetReplay = _aim_replay()
		var g: int = 0
		while fresh.state.current_tank != 2 and g < 6:
			g += 1
			fresh.apply_entry(AiPlayer.next_action(fresh.state, fresh.state.current_tank))
		assert_false((fresh.apply_entry(e) as Dictionary)["ok"], JSON.stringify(e))


func test_a_seat_whose_player_left_keeps_its_human_timeouts_in_the_history() -> void:
	# A player who timed out and then left is a CPU Normal seat in the stored meta. A client that opens the match later replays
	# his old timeout against those seats, and must not call it a dispute.
	var meta: Dictionary = NetTestUtil.meta([NetTestUtil.human(A), NetTestUtil.human(B), NetTestUtil.cpu(2)], {"rounds": 1}, {}, 4242)
	var before: NetReplay = NetReplay.create(meta)
	assert_true((before.apply_entry({"kind": "timeout", "tank": 1}) as Dictionary)["ok"], "live skip of a human in the shop")
	var after_meta: Dictionary = meta.duplicate(true)
	(after_meta["seats"] as Array)[1] = {"kind": "cpu", "level": 2, "name": "Bo"}
	var later: NetReplay = NetReplay.create(after_meta)
	assert_true((later.apply_entry({"kind": "timeout", "tank": 1}) as Dictionary)["ok"])
	assert_eq(later.fingerprint(), before.fingerprint())


# --- 2. hostile levels and malformed values -----------------------------------------------------------------------------------------------------------

func test_auto_level_must_be_the_seats_own_so_a_writer_cannot_pick_the_ai_strength() -> void:
	# play both humans' turns until it is the CPU's (seat level 1), then try the CPU's turn at level 4 and at its own level
	var guard_runs: Array[NetReplay] = [_aim_replay(1), _aim_replay(1), _aim_replay(1)]
	for r: NetReplay in guard_runs:
		var guard: int = 0
		while r.state.current_tank != 2 and guard < 6:
			guard += 1
			assert_true((r.apply_entry(AiPlayer.next_action(r.state, r.state.current_tank)) as Dictionary)["ok"])
		assert_eq(r.state.current_tank, 2, "reached the CPU's turn")
	var honest: Dictionary = guard_runs[0].apply_entry({"kind": "auto", "tank": 2, "level": 1})
	assert_true(honest["ok"], "the seat's own level is accepted")
	var before_fp: String = guard_runs[1].fingerprint()
	var hostile: Dictionary = guard_runs[1].apply_entry({"kind": "auto", "tank": 2, "level": 4})
	assert_false(hostile["ok"], "an auto entry with a level that is not the seat's is refused")
	assert_eq(hostile["err"], "bad_auto_level")
	assert_true(guard_runs[1].disputed)
	assert_eq(guard_runs[1].fingerprint(), before_fp, "and changes nothing")
	for level: int in [2, 3, 0, 5, -1]:
		var other: NetReplay = _aim_replay(1)
		var g2: int = 0
		while other.state.current_tank != 2 and g2 < 6:
			g2 += 1
			other.apply_entry(AiPlayer.next_action(other.state, other.state.current_tank))
		assert_false((other.apply_entry({"kind": "auto", "tank": 2, "level": level}) as Dictionary)["ok"], "level %d" % level)
	# the shop visit too
	var meta: Dictionary = NetTestUtil.meta([NetTestUtil.human(A), NetTestUtil.human(B), NetTestUtil.cpu(1)], {"rounds": 1}, {}, 4242)
	var shop: NetReplay = NetReplay.create(meta)
	assert_false((shop.apply_entry({"kind": "auto_shop", "tank": 2, "level": 4}) as Dictionary)["ok"])
	var shop2: NetReplay = NetReplay.create(meta)
	assert_true((shop2.apply_entry({"kind": "auto_shop", "tank": 2, "level": 1}) as Dictionary)["ok"])


func test_malformed_values_from_the_database_never_raise_engine_errors() -> void:
	# `async` as a string, seats that are not seats, a settings value of the wrong type: each used to raise an engine error
	# (invalid operands, invalid cast, wrong assignment) and some were accepted. From the database nothing can be trusted, so
	# malformed means disputed (an entry) or unusable (the meta), and never an error.
	var r: NetReplay = _aim_replay()
	var t: int = r.state.current_tank
	for junk: Variant in ["1", "", null, true, false, 1.5, 0, 2, -1, [1], {"a": 1}]:
		var fresh: NetReplay = _aim_replay()
		var res: Dictionary = fresh.apply_entry({"kind": "timeout", "tank": t, "async": junk})
		assert_false(res["ok"], "async %s is malformed" % JSON.stringify(junk))
		assert_true(fresh.disputed)
		assert_eq(fresh.dispute_reason, "bad_timeout")
	assert_true((_aim_replay().apply_entry({"kind": "timeout", "tank": t, "async": 1}) as Dictionary)["ok"], "async 1 is the one valid value")
	assert_true((_aim_replay().apply_entry({"kind": "timeout", "tank": t}) as Dictionary)["ok"], "and so is no async")
	assert_eq(NetReplay.timeout_mode({"kind": "timeout", "tank": t, "async": "1"}), NetReplay.TIMEOUT_PASS)

	var bad_seat_lists: Array = [
		[1, 2, 3], ["a", "b"], [null, null], [[], []], [{"kind": 5}, {"kind": "human"}], [{"kind": "robot"}, {"kind": "human"}],
		[{"kind": "human", "uid": 5}, {"kind": "human"}], [{"kind": "human", "name": []}, {"kind": "human"}],
		[{"kind": "cpu", "level": "2"}, {"kind": "human"}], [{"kind": "cpu", "level": 9}, {"kind": "human"}], [{"kind": "cpu", "level": 2.5}, {"kind": "human"}],
		[{"kind": "human"}], [{"kind": "human"}, {"kind": "human"}, {"kind": "human"}, {"kind": "human"}, {"kind": "human"}, {"kind": "human"}, {"kind": "human"}, {"kind": "human"}, {"kind": "human"}],
	]
	for seats: Array in bad_seat_lists:
		var m: Dictionary = NetTestUtil.meta([NetTestUtil.human(A), NetTestUtil.human(B)])
		m["seats"] = seats
		assert_eq(NetReplay.meta_error(m), "bad_seats", JSON.stringify(seats))
		assert_null(NetReplay.create(m), JSON.stringify(seats))
	var bad_settings: Array = [
		{"friendly_fire": "yes"}, {"full_unlocked": 1}, {"rounds": "3"}, {"rounds": 2.5}, {"wind_max": null}, {"start_money": []}, {"mode": "1"},
		{"num_tanks": "2"}, {"seed": "7"}, {"teams": "a"}, {"teams": ["a", "b"]}, {"controllers": [0, "x"]}, {"controllers": 5},
	]
	for overrides: Dictionary in bad_settings:
		var m2: Dictionary = NetTestUtil.meta([NetTestUtil.human(A), NetTestUtil.human(B)], overrides)
		assert_ne(NetReplay.meta_error(m2), "", JSON.stringify(overrides))
		assert_null(NetReplay.create(m2), JSON.stringify(overrides))
	for timers: Variant in ["x", [], {"liveSec": "60"}, {"asyncHours": 1.5}, {"asyncTimeout": 5}]:
		var m3: Dictionary = NetTestUtil.meta([NetTestUtil.human(A), NetTestUtil.human(B)])
		m3["timers"] = timers
		assert_eq(NetReplay.meta_error(m3), "bad_timers", JSON.stringify(timers))
	var m4: Dictionary = NetTestUtil.meta([NetTestUtil.human(A), NetTestUtil.human(B)])
	m4["seed"] = "7"
	assert_ne(NetReplay.meta_error(m4), "")
	# a later seats update that is not a seat list is ignored, so the replay keeps working on the seats it has
	var live: NetReplay = _aim_replay()
	var seats_before: Array = live.seats
	live.set_seats([1, 2, 3])
	assert_eq(live.seats, seats_before)
	assert_eq(NetReplay.seats_error([1, 2, 3]), "bad_seats")
	assert_eq(NetReplay.seats_error([{"kind": "human"}, {"kind": "cpu", "level": 2}]), "")


func test_odd_but_harmless_values_replay_the_same_everywhere() -> void:
	# Accepted by the simulation (extra keys, a whole float where an int goes): both replays must still agree exactly.
	var t: int = _aim_replay().state.current_tank
	for e: Dictionary in [{"kind": "pass", "tank": t, "extra": {"deep": [1, 2, {"x": null}]}}, {"kind": "pass", "tank": float(t)},
			{"kind": "fire", "tank": t, "angle": 450.0, "power": 500.0, "weapon": "spark_dart"}]:
		var one: NetReplay = _aim_replay()
		var two: NetReplay = _aim_replay()
		assert_eq((one.apply_entry(e) as Dictionary)["ok"], (two.apply_entry(e) as Dictionary)["ok"])
		assert_eq(one.fingerprint(), two.fingerprint(), JSON.stringify(e))


# --- 3. 50 random mixed logs against the offline path --------------------------------------------------------------------------

const MATCHES: int = 50
const MAX_ENTRIES: int = 70


func _random_meta(rng: RandomNumberGenerator, index: int) -> Dictionary:
	var n: int = rng.randi_range(2, 5)
	var seats: Array = []
	var humans: int = 0
	for i: int in range(n):
		if rng.randf() < 0.45:
			seats.append(NetTestUtil.human("u%d" % i, "P%d" % i))
			humans += 1
		else:
			seats.append(NetTestUtil.cpu(rng.randi_range(1, 4)))
	if humans == 0:
		seats[0] = NetTestUtil.human("u0", "P0")
		humans = 1
	var overrides: Dictionary = {"rounds": rng.randi_range(1, 2), "wind_max": rng.randi_range(0, 100), "start_money": rng.randi_range(0, 20000)}
	if n >= 4 and rng.randf() < 0.3:
		var teams: Array = []
		for i2: int in range(n):
			teams.append(i2 % 2)
		overrides["teams"] = teams
		overrides["friendly_fire"] = rng.randf() < 0.5
	if n == 2 and humans == 2 and rng.randf() < 0.4:
		overrides["mode"] = 1
		overrides["rounds"] = 1
		overrides["start_money"] = 0
	var m: Dictionary = NetTestUtil.meta(seats, overrides, {"asyncTimeout": "auto"}, 1000 + index * 7919)
	return m


func _cpu_loop(session: MatchSession, tank: int, level: int) -> void:
	# CpuDriver's loop with the controller of `tank` set to `level` for the duration (AiPlayer reads the level from the settings)
	var st: MatchState = session.state
	var current: PackedInt32Array = st.settings.controllers
	var changed: PackedInt32Array = current.duplicate()
	changed[tank] = level
	st.settings.controllers = changed
	var key: String = "%d:%d" % [st.round_index, st.turn_number]
	var calls: int = 0
	while "%d:%d" % [st.round_index, st.turn_number] == key and st.phase == SimConstants.PHASE_AIM:
		calls += 1
		var a: Dictionary = Simulation.normalize_action(AiPlayer.next_action(st, tank))
		var err: String = Simulation.validate_action(st, a)
		if err == "" and calls >= CpuDriver.MAX_CALLS and not CpuDriver.ends_turn(a):
			err = "cpu_runaway"
		if err != "":
			a = {"kind": "pass", "tank": tank}
		session.submit(a)
	st.settings.controllers = current


func _shop_visit(session: MatchSession, tank: int, level: int) -> void:
	var st: MatchState = session.state
	var current: PackedInt32Array = st.settings.controllers
	var changed: PackedInt32Array = current.duplicate()
	changed[tank] = level
	st.settings.controllers = changed
	for a: Dictionary in AiPlayer.shop_actions(st, tank):
		if Simulation.validate_action(st, Simulation.normalize_action(a)) == "":
			session.submit(a)
	if not st.tanks[tank].ready:
		session.submit({"kind": "ready", "tank": tank})
	st.settings.controllers = current


func _random_human_action(rng: RandomNumberGenerator, st: MatchState, tank: int) -> Dictionary:
	var roll: float = rng.randf()
	var candidates: Array[Dictionary] = []
	if roll < 0.35:
		candidates.append({"kind": "fire", "tank": tank, "angle": rng.randi_range(0, 1800), "power": rng.randi_range(1, 1000), "weapon": "spark_dart"})
	elif roll < 0.5:
		candidates.append({"kind": "move", "tank": tank, "dx": rng.randi_range(-30, 30)})
	elif roll < 0.6:
		candidates.append({"kind": "pass", "tank": tank})
	for c: Dictionary in candidates:
		if Simulation.validate_action(st, Simulation.normalize_action(c)) == "":
			return Simulation.normalize_action(c)
	return Simulation.normalize_action(AiPlayer.next_action(st, tank))


## Runs one random match both ways. Returns "" when every entry agreed, else a description.
func _one_match(index: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150 + index
	var meta: Dictionary = _random_meta(rng, index)
	var seats: Array = meta["seats"]
	var session: MatchSession = MatchSession.create(NetReplay.settings_from_meta(meta))
	var replay: NetReplay = NetReplay.create(meta)
	var st: MatchState = session.state
	var n_entries: int = 0
	var timeouts: int = 0
	while n_entries < MAX_ENTRIES and st.phase != SimConstants.PHASE_MATCH_OVER:
		var entry: Dictionary = {}
		if st.phase == SimConstants.PHASE_SHOP:
			var tank: int = -1
			for t: TankState in st.tanks:
				if not t.ready:
					tank = t.id
					break
			if tank < 0:
				return "shop with everybody ready (match %d)" % index
			var cpu: bool = (seats[tank] as Dictionary)["kind"] == "cpu"
			if cpu:
				var lvl: int = (seats[tank] as Dictionary)["level"]
				entry = {"kind": "auto_shop", "tank": tank, "level": lvl}
				_shop_visit(session, tank, lvl)
			elif rng.randf() < 0.12:
				entry = {"kind": "timeout", "tank": tank, "async": 1} if rng.randf() < 0.5 else {"kind": "timeout", "tank": tank}
				timeouts += 1
				if entry.has("async"):
					_shop_visit(session, tank, NetProtocol.TIMEOUT_AI_LEVEL)
				else:
					session.submit({"kind": "ready", "tank": tank})
			else:
				var buys: Array[Dictionary] = AiPlayer.shop_actions(st, tank)
				if not buys.is_empty() and rng.randf() < 0.5:
					var b: Dictionary = Simulation.normalize_action(buys[0])
					if Simulation.validate_action(st, b) == "":
						session.submit(b)
						entry = b
				if entry.is_empty():
					entry = {"kind": "ready", "tank": tank}
					session.submit(entry)
			if Simulation.all_ready(st):
				session.start_round()
		else:
			var tank2: int = st.current_tank
			var cpu2: bool = (seats[tank2] as Dictionary)["kind"] == "cpu"
			if cpu2:
				var lvl2: int = (seats[tank2] as Dictionary)["level"]
				entry = {"kind": "auto", "tank": tank2, "level": lvl2}
				_cpu_loop(session, tank2, lvl2)
			elif rng.randf() < 0.1:
				if rng.randf() < 0.5:
					entry = {"kind": "timeout", "tank": tank2, "async": 1}
					_cpu_loop(session, tank2, NetProtocol.TIMEOUT_AI_LEVEL)
				else:
					entry = {"kind": "timeout", "tank": tank2}
					session.submit({"kind": "pass", "tank": tank2})
				timeouts += 1
			else:
				entry = _random_human_action(rng, st, tank2)
				session.submit(entry)
		var res: Dictionary = replay.apply_entry(entry)
		if not (res["ok"] as bool):
			return "match %d entry %d %s rejected: %s" % [index, n_entries, JSON.stringify(entry), res["err"]]
		n_entries += 1
		if replay.fingerprint() != Simulation.fingerprint(st):
			return "match %d entry %d %s: fingerprints differ (seats %s)" % [index, n_entries - 1, JSON.stringify(entry), JSON.stringify(seats)]
		if (replay.state.phase == SimConstants.PHASE_MATCH_OVER) != (st.phase == SimConstants.PHASE_MATCH_OVER):
			return "match %d: match-over disagrees" % index
	# a second replay of the entries lands in the same place
	var again: NetReplay = NetReplay.create(meta)
	for e: Dictionary in replay.entries:
		again.apply_entry(e)
	if again.fingerprint() != replay.fingerprint():
		return "match %d: two replays of the same log differ" % index
	return ""


func test_fifty_random_mixed_logs_match_the_offline_game_entry_by_entry() -> void:
	var t0: int = Time.get_ticks_msec()
	var failures: Array[String] = []
	for i: int in range(MATCHES):
		var why: String = _one_match(i)
		if why != "":
			failures.append(why)
	assert_eq(failures, [], "NetReplay and the offline path must agree on every entry of every log")
	gut.p("%d random matches replayed entry by entry (%d ms)" % [MATCHES, Time.get_ticks_msec() - t0])
