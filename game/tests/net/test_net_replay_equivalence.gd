extends GutTest
## The critical property: a log replayed through NetReplay gives exactly the states the offline game (MatchSession plus the
## same CPU loops the battle controller and CpuShop run) produces for the same actions, and two replays of one log agree.

const A: String = NetTestUtil.HUMAN_A
const B: String = NetTestUtil.HUMAN_B

var _meta: Dictionary = {}


## Runs `meta`'s match the offline way. Humans are driven by AiPlayer (any legal action will do; the point is that the
## net path sees the same state). Returns [{entry, fp}] where fp is the offline fingerprint after every entry that ended a turn
## ("" otherwise), in the order the net log would hold them.
func _offline(meta: Dictionary, max_entries: int) -> Array[Dictionary]:
	var settings: MatchSettings = NetReplay.settings_from_meta(meta)
	var session: MatchSession = MatchSession.create(settings)
	var seats: Array = NetJson.as_list(meta["seats"])
	var out: Array[Dictionary] = []
	var is_cpu: Callable = func(t: int) -> bool: return (seats[t] as Dictionary)["kind"] == "cpu"
	while out.size() < max_entries and session.state.phase != SimConstants.PHASE_MATCH_OVER:
		var st: MatchState = session.state
		if st.phase == SimConstants.PHASE_SHOP:
			var progressed: bool = false
			for t: TankState in st.tanks:
				if t.ready:
					continue
				progressed = true
				if is_cpu.call(t.id):
					# CpuShop.run does every CPU tank in order; one tank at a time here so entries line up
					var one: MatchState = st
					var submit: Callable = func(a: Dictionary) -> String: return session.submit(a)["err"]
					_cpu_shop_one(one, t.id, submit)
					out.append({"entry": {"kind": "auto_shop", "tank": t.id, "level": (seats[t.id] as Dictionary).get("level", 2)}, "fp": ""})
				else:
					session.submit({"kind": "ready", "tank": t.id})
					out.append({"entry": {"kind": "ready", "tank": t.id}, "fp": ""})
				break
			assert_true(progressed)
			if Simulation.all_ready(st):
				session.start_round()
				out.back()["fp"] = Simulation.fingerprint(st)
			continue
		var tank: int = st.current_tank
		var key: String = "%d:%d" % [st.round_index, st.turn_number]
		if is_cpu.call(tank):
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
			out.append({"entry": {"kind": "auto", "tank": tank, "level": (seats[tank] as Dictionary).get("level", 2)}, "fp": Simulation.fingerprint(st)})
		else:
			var action: Dictionary = AiPlayer.next_action(st, tank)
			session.submit(action)
			var ended: bool = "%d:%d" % [st.round_index, st.turn_number] != key or st.phase != SimConstants.PHASE_AIM
			out.append({"entry": Simulation.normalize_action(action), "fp": Simulation.fingerprint(st) if ended else ""})
	return out


## CpuShop's per-tank body (it is private there): the AI's actions, then ready if still needed.
func _cpu_shop_one(state: MatchState, id: int, submit: Callable) -> void:
	for a: Dictionary in AiPlayer.shop_actions(state, id):
		submit.call(a)
	if not state.tanks[id].ready:
		submit.call({"kind": "ready", "tank": id})


func _check(meta: Dictionary, max_entries: int = 300) -> void:
	var offline: Array[Dictionary] = _offline(meta, max_entries)
	assert_gt(offline.size(), 6, "the offline match produced a log")
	var replay: NetReplay = NetReplay.create(meta)
	var turn_ends: int = 0
	for i: int in range(offline.size()):
		var entry: Dictionary = offline[i]["entry"]
		var r: Dictionary = replay.apply_entry(entry)
		assert_true(r["ok"], "entry %d %s: %s" % [i, str(entry), str(r["err"])])
		if not (r["ok"] as bool):
			return
		var want: String = offline[i]["fp"]
		if want != "":
			turn_ends += 1
			if replay.fingerprint() != want:
				fail_test("entry %d (%s): fingerprints differ" % [i, str(entry)])
				return
	assert_gt(turn_ends, 3)
	assert_eq(replay.state.phase == SimConstants.PHASE_MATCH_OVER, offline.size() < max_entries)
	# A second, independent replay of the same log lands on the same state (what two phones do).
	var again: NetReplay = NetReplay.create(meta)
	for item: Dictionary in offline:
		again.apply_entry(item["entry"])
	assert_eq(again.fingerprint(), replay.fingerprint())


func test_one_human_two_cpus_two_rounds() -> void:
	_check(NetTestUtil.meta([NetTestUtil.human(A), NetTestUtil.cpu(2), NetTestUtil.cpu(3)], {"rounds": 2, "wind_max": 60}))


func test_two_humans_one_cpu_one_round() -> void:
	_check(NetTestUtil.meta([NetTestUtil.human(A), NetTestUtil.human(B), NetTestUtil.cpu(1)], {"rounds": 1}, {}, 777))


func test_teams_with_friendly_fire_off() -> void:
	_check(NetTestUtil.meta([NetTestUtil.human(A), NetTestUtil.cpu(2), NetTestUtil.human(B), NetTestUtil.cpu(4)],
			{"teams": [0, 1, 0, 1], "friendly_fire": false, "rounds": 1}, {}, 31337))


func test_love_match() -> void:
	_check(NetTestUtil.meta([NetTestUtil.human(A), NetTestUtil.human(B)], {"mode": 1, "rounds": 1, "start_money": 0}, {}, 99), 600)


func test_the_log_is_independent_of_how_it_arrives() -> void:
	# Replaying in one go, or entry by entry through forks and plan_batch, gives the same state.
	var meta: Dictionary = NetTestUtil.meta([NetTestUtil.human(A), NetTestUtil.cpu(2), NetTestUtil.cpu(2)], {"rounds": 1}, {}, 5)
	var direct: NetReplay = NetReplay.create(meta)
	var log: Array[Dictionary] = NetTestUtil.play_through(direct, 300)
	var rebuilt: NetReplay = NetReplay.create(meta)
	for item: Dictionary in log:
		var plan: Dictionary = rebuilt.plan_batch([item["entry"]] as Array[Dictionary], 1)
		assert_true(plan["ok"])
		rebuilt.apply_entry(item["entry"])
	assert_eq(rebuilt.fingerprint(), direct.fingerprint())
	assert_true(direct.ended)
