extends GutTest
## M7-Q: NetReplay fed hostile and random logs (no emulator needed).
##  1. malformed entries (wrong types, unknown kinds, missing or huge tank, entries after the end or after a dispute): never a
##     crash, always rejected, and a rejected entry leaves the state untouched;
##  2. a hostile `auto` level, and malformed values that DO crash (documented as pending BUGs, run with QA_RUN_BUGS=1);
##  3. 50 random seeded mixed logs (humans with random legal actions, CPUs, live and async timeouts, teams, Love) replayed through
##     NetReplay give the same fingerprint as the offline path after every entry.

const A: String = NetTestUtil.HUMAN_A
const B: String = NetTestUtil.HUMAN_B
const RUN_BUGS_ENV: String = "QA_RUN_BUGS"


func _run_bugs() -> bool:
	return OS.get_environment(RUN_BUGS_ENV) == "1"


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


func test_documents_that_a_timeout_for_a_cpu_seat_is_accepted_by_the_replay() -> void:
	# The rules refuse a client timeout on a CPU seat, the sweep writes one for a CPU turn stuck past its deadline (see
	# firebase/test/qa/functions/abuse_matches.test.ts), and NetReplay applies it (the AI plays at level 2, or in the shop the
	# CPU is marked ready with no purchases) instead of calling it a dispute. Harmless, but it is a second way to "ready" a CPU.
	var shop: NetReplay = NetReplay.create(NetTestUtil.meta([NetTestUtil.human(A), NetTestUtil.human(B), NetTestUtil.cpu(2)], {"rounds": 1}, {}, 4242))
	assert_true((shop.apply_entry({"kind": "timeout", "tank": 2}) as Dictionary)["ok"])
	assert_true(shop.state.tanks[2].ready)


# --- 2. known bugs -----------------------------------------------------------------------------------------------------------

func test_auto_level_is_authoritative_so_a_writer_picks_the_ai_strength() -> void:
	var honest: NetReplay = _aim_replay(1)
	var t: int = honest.state.current_tank
	# play both humans' turns until it is the CPU's, then compare the CPU's turn at its seat level (1) and at level 4
	var a: NetReplay = _aim_replay(1)
	var b: NetReplay = _aim_replay(1)
	var guard: int = 0
	while a.state.current_tank != 2 and guard < 6:
		guard += 1
		var action: Dictionary = AiPlayer.next_action(a.state, a.state.current_tank)
		assert_true((a.apply_entry(action) as Dictionary)["ok"])
		assert_true((b.apply_entry(action) as Dictionary)["ok"])
	assert_eq(a.state.current_tank, 2, "reached the CPU's turn (first human %d)" % t)
	var ra: Dictionary = a.apply_entry({"kind": "auto", "tank": 2, "level": 1})
	var rb: Dictionary = b.apply_entry({"kind": "auto", "tank": 2, "level": 4})
	assert_true(ra["ok"])
	if (rb["ok"] as bool) and a.fingerprint() != b.fingerprint():
		pending("BUG (medium): NetReplay accepts `auto` with level 4 for a CPU seat of level 1 and plays a different turn (fingerprints differ), "
				+ "so the entry's writer chooses how well each CPU plays. Cause: net_replay.gd _apply_auto/_apply_auto_shop only range-check "
				+ "the level (1..4) and never compare it with seat_level(tank); the rules (build_rules.mjs) do not either. "
				+ "Fix: reject an auto/auto_shop entry whose level != seat_level(tank).")
		return
	assert_false(rb["ok"], "an auto entry with a level that is not the seat's must be refused")


func test_malformed_values_that_crash_the_replay() -> void:
	# BUG (low), not executed by default because the engine prints a engine error (which fails the whole run):
	#   {kind: "timeout", tank: t, async: "1"}  -> net_replay.gd:346 timeout_mode `entry.get("async", 0) == 1` compares String with int:
	#       "Invalid operands 'String' and 'int' in operator '=='", and the entry is then ACCEPTED as a live skip instead of disputed.
	#   meta.seats = [1, 2, 3] -> net_replay.gd:146 seat_is_cpu `(seats[tank] as Dictionary)` Invalid cast, SCRIPT ERROR on first entry.
	#   meta.settings.friendly_fire = "yes" -> net_replay.gd:82 assigns a String to a bool: SCRIPT ERROR, MatchSettings null, create() crashes.
	# All three need a hand-written database value (the rules reject async != 1, the callables validate settings and seats), so they are
	# only reachable through the Admin SDK or a hand-edited emulator, but "malformed log never crashes" is the contract.
	if not _run_bugs():
		pending("BUG (low): malformed `async` / seats / friendly_fire values raise engine errors in NetReplay (details in the test comment); run with QA_RUN_BUGS=1")
		return
	var r: NetReplay = _aim_replay()
	var res: Dictionary = r.apply_entry({"kind": "timeout", "tank": r.state.current_tank, "async": "1"})
	assert_false(res["ok"])
	var bad_seats: Dictionary = NetTestUtil.meta([NetTestUtil.human(A), NetTestUtil.human(B)])
	bad_seats["seats"] = [1, 2, 3]
	assert_null(NetReplay.create(bad_seats))
	var bad_ff: Dictionary = NetTestUtil.meta([NetTestUtil.human(A), NetTestUtil.human(B)], {"friendly_fire": "yes"})
	assert_null(NetReplay.create(bad_ff))


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
