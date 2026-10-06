extends GutTest
## NetReplay without any network: expansions of auto / auto_shop / timeout, the automatic start of a round, disputes, the
## expected turn, batches and forks.

const A: String = NetTestUtil.HUMAN_A
const B: String = NetTestUtil.HUMAN_B


func _replay(seats: Array, overrides: Dictionary = {}, timers: Dictionary = {}) -> NetReplay:
	var r: NetReplay = NetReplay.create(NetTestUtil.meta(seats, overrides, timers))
	assert_not_null(r)
	return r


func _two_humans_one_cpu(overrides: Dictionary = {}, timers: Dictionary = {}) -> NetReplay:
	return _replay([NetTestUtil.human(A), NetTestUtil.human(B), NetTestUtil.cpu(2)], overrides, timers)


func test_meta_errors() -> void:
	assert_eq(NetReplay.meta_error({}), "missing_settings")
	var m: Dictionary = NetTestUtil.meta([NetTestUtil.human(A), NetTestUtil.human(B)])
	assert_eq(NetReplay.meta_error(m), "")
	m["seed"] = 0
	(m["settings"] as Dictionary)["seed"] = 0
	assert_eq(NetReplay.meta_error(m), "seed_missing")
	assert_null(NetReplay.create(m))
	var one: Dictionary = NetTestUtil.meta([NetTestUtil.human(A)])
	assert_eq(NetReplay.meta_error(one), "bad_seats")


func test_settings_follow_the_meta() -> void:
	var m: Dictionary = NetTestUtil.meta([NetTestUtil.human(A), NetTestUtil.human(B), NetTestUtil.cpu(3), NetTestUtil.cpu(1)],
			{"teams": [0, 1, 0, 1], "friendly_fire": false, "rounds": 2})
	var s: MatchSettings = NetReplay.settings_from_meta(m)
	assert_eq(s.num_tanks, 4)
	assert_eq(s.rounds, 2)
	assert_eq(s.controllers, PackedInt32Array([0, 0, 3, 1]))
	assert_eq(s.teams, PackedInt32Array([0, 1, 0, 1]))
	assert_false(s.friendly_fire)
	assert_eq(s.seed, 4242)


func test_database_arrays_may_come_as_keyed_dictionaries() -> void:
	var m: Dictionary = NetTestUtil.meta([NetTestUtil.human(A), NetTestUtil.cpu(2)])
	m["seats"] = {"0": m["seats"][0], "1": m["seats"][1]}
	(m["settings"] as Dictionary)["controllers"] = {"0": 0, "1": 2}
	var r: NetReplay = NetReplay.create(m)
	assert_not_null(r)
	assert_true(r.seat_is_cpu(1))
	assert_eq(r.state.settings.controllers, PackedInt32Array([0, 2]))


func test_a_new_match_starts_in_the_shop_and_asks_for_the_cpu_shop_first() -> void:
	var r: NetReplay = _two_humans_one_cpu()
	assert_eq(r.state.phase, SimConstants.PHASE_SHOP)
	assert_eq(r.pending_cpu_entry(), {"kind": "auto_shop", "tank": 2, "level": 2})
	assert_eq(r.expected_turn(), {"tank": -2, "uid": "any"})


func test_auto_shop_buys_then_readies_like_the_offline_cpu_shop() -> void:
	var r: NetReplay = _two_humans_one_cpu()
	var res: Dictionary = r.apply_entry({"kind": "auto_shop", "tank": 2, "level": 2})
	assert_true(res["ok"], str(res))
	assert_true(r.state.tanks[2].ready)
	var steps: Array = res["steps"]
	assert_eq((steps[steps.size() - 1]["action"] as Dictionary)["kind"], "ready")
	assert_true(steps.size() >= 2, "the Normal AI buys something with 10000 credits")
	assert_eq(r.pending_cpu_entry(), {})
	assert_false(res["turn_ended"])


func test_the_last_ready_starts_the_round_by_itself() -> void:
	var r: NetReplay = _two_humans_one_cpu()
	r.apply_entry({"kind": "auto_shop", "tank": 2, "level": 2})
	r.apply_entry({"kind": "ready", "tank": 0})
	assert_eq(r.state.phase, SimConstants.PHASE_SHOP)
	var res: Dictionary = r.apply_entry({"kind": "ready", "tank": 1})
	assert_true(res["ok"])
	assert_eq(r.state.phase, SimConstants.PHASE_AIM)
	assert_eq(r.state.round_index, 0)
	var steps: Array = res["steps"]
	assert_eq((steps[steps.size() - 1]["action"] as Dictionary)["kind"], "start_round")
	assert_true(res["turn_ended"])
	assert_eq(r.count, 3)


func test_auto_plays_a_whole_cpu_turn() -> void:
	var r: NetReplay = _replay([NetTestUtil.cpu(3), NetTestUtil.human(A)])
	assert_eq(r.pending_cpu_entry()["kind"], "auto_shop")
	r.apply_entry(r.pending_cpu_entry())
	r.apply_entry({"kind": "ready", "tank": 1})
	assert_eq(r.state.phase, SimConstants.PHASE_AIM)
	assert_eq(r.state.current_tank, 0)
	var res: Dictionary = r.apply_entry(r.pending_cpu_entry())
	assert_true(res["ok"], str(res))
	assert_ne(r.state.current_tank, 0)
	assert_true(res["turn_ended"])
	var last: Dictionary = (res["steps"] as Array).back()["action"]
	assert_true(last["kind"] == "fire" or last["kind"] == "pass")
	assert_true((res["events"] as Array).size() > 0)


func test_auto_for_a_human_seat_or_the_wrong_tank_is_disputed() -> void:
	var r: NetReplay = _two_humans_one_cpu()
	r.apply_entry({"kind": "auto_shop", "tank": 2, "level": 2})
	r.apply_entry({"kind": "ready", "tank": 0})
	r.apply_entry({"kind": "ready", "tank": 1})
	var tank: int = r.state.current_tank
	var res: Dictionary = r.apply_entry({"kind": "auto", "tank": tank, "level": 2})
	if r.seat_is_cpu(tank):
		assert_true(res["ok"])
	else:
		assert_false(res["ok"])
		assert_eq(res["err"], "bad_auto")
		assert_true(r.disputed)
		assert_eq(r.dispute_index, 3)
		# nothing more is applied after a dispute
		assert_eq(r.apply_entry({"kind": "pass", "tank": tank})["err"], "disputed")


func test_a_tampered_entry_disputes() -> void:
	var r: NetReplay = _replay([NetTestUtil.human(A), NetTestUtil.human(B)])
	r.apply_entry({"kind": "ready", "tank": 0})
	r.apply_entry({"kind": "ready", "tank": 1})
	var wrong: int = 1 - r.state.current_tank
	var res: Dictionary = r.apply_entry({"kind": "fire", "tank": wrong, "angle": 450, "power": 500, "weapon": "spark_dart"})
	assert_false(res["ok"])
	assert_eq(res["err"], "invalid_not_your_turn")
	assert_true(r.disputed)
	assert_eq(r.count, 2, "the bad entry is not counted")


func test_out_of_range_and_unknown_entries_dispute() -> void:
	for bad: Dictionary in [
		{"kind": "fire", "tank": 0, "angle": 9999, "power": 500, "weapon": "spark_dart"},
		{"kind": "teleport", "tank": 0},
		{"kind": "auto", "tank": 0, "level": 9},
		{"kind": "timeout", "tank": 1},
	]:
		var r: NetReplay = _replay([NetTestUtil.human(A), NetTestUtil.human(B)])
		r.apply_entry({"kind": "ready", "tank": 0})
		r.apply_entry({"kind": "ready", "tank": 1})
		var tank: int = r.state.current_tank
		var fixed: Dictionary = bad.duplicate()
		if fixed["kind"] == "timeout":
			fixed["tank"] = 1 - tank
		elif fixed["kind"] != "teleport":
			fixed["tank"] = tank
		assert_false(r.apply_entry(fixed)["ok"], str(fixed))
		assert_true(r.disputed)


func test_entries_after_the_end_are_disputed() -> void:
	var r: NetReplay = _replay([NetTestUtil.human(A), NetTestUtil.human(B)], {}, {"asyncTimeout": "end", "liveSec": 0})
	r.apply_entry({"kind": "ready", "tank": 0})
	r.apply_entry({"kind": "ready", "tank": 1})
	var tank: int = r.state.current_tank
	var res: Dictionary = r.apply_entry({"kind": "timeout", "tank": tank})
	assert_true(res["ok"])
	assert_true(r.ended)
	assert_true(r.ended_by_timeout)
	assert_true(res["over"])
	assert_eq(r.expected_turn(), {})
	assert_eq(r.apply_entry({"kind": "pass", "tank": tank})["err"], "entry_after_end")


func test_timeout_modes() -> void:
	assert_eq(_replay([NetTestUtil.human(A), NetTestUtil.human(B)], {}, {"liveSec": 60}).timeout_mode(), "pass")
	assert_eq(_replay([NetTestUtil.human(A), NetTestUtil.human(B)], {}, {"liveSec": 0}).timeout_mode(), "auto")
	assert_eq(_replay([NetTestUtil.human(A), NetTestUtil.human(B)], {}, {"liveSec": 0, "asyncTimeout": "end"}).timeout_mode(), "end")
	assert_eq(_replay([NetTestUtil.human(A), NetTestUtil.human(B)], {}, {"liveSec": 60, "asyncTimeout": "end"}).timeout_mode(), "end")


func _into_aim(r: NetReplay) -> void:
	for t: TankState in r.state.tanks:
		if r.seat_is_cpu(t.id):
			r.apply_entry({"kind": "auto_shop", "tank": t.id, "level": r.seat_level(t.id)})
		else:
			r.apply_entry({"kind": "ready", "tank": t.id})


func test_live_timeout_passes_the_turn() -> void:
	var r: NetReplay = _replay([NetTestUtil.human(A), NetTestUtil.human(B)], {}, {"liveSec": 60})
	_into_aim(r)
	var tank: int = r.state.current_tank
	var res: Dictionary = r.apply_entry({"kind": "timeout", "tank": tank})
	assert_true(res["ok"], str(res))
	assert_eq((res["steps"] as Array)[0]["action"], {"kind": "pass", "tank": tank})
	assert_ne(r.state.current_tank, tank)


func test_async_timeout_lets_the_ai_play_the_turn() -> void:
	var r: NetReplay = _replay([NetTestUtil.human(A), NetTestUtil.human(B)], {}, {"liveSec": 0})
	_into_aim(r)
	var tank: int = r.state.current_tank
	var res: Dictionary = r.apply_entry({"kind": "timeout", "tank": tank})
	assert_true(res["ok"], str(res))
	assert_ne(r.state.current_tank, tank)
	var last: Dictionary = (res["steps"] as Array).back()["action"]
	assert_true(last["kind"] == "fire" or last["kind"] == "pass")
	# the controller is put back after the AI call (it is part of the fingerprint)
	assert_eq(r.state.settings.controllers[tank], 0)


func test_shop_timeouts() -> void:
	var r: NetReplay = _replay([NetTestUtil.human(A), NetTestUtil.human(B)], {}, {"liveSec": 60})
	var res: Dictionary = r.apply_entry({"kind": "timeout", "tank": 0})
	assert_true(res["ok"])
	assert_true(r.state.tanks[0].ready)
	var r2: NetReplay = _replay([NetTestUtil.human(A), NetTestUtil.human(B)], {}, {"liveSec": 0})
	var res2: Dictionary = r2.apply_entry({"kind": "timeout", "tank": 1})
	assert_true(res2["ok"], str(res2))
	assert_true(r2.state.tanks[1].ready)
	assert_false(r2.apply_entry({"kind": "timeout", "tank": 1})["ok"], "already ready")


func test_expected_turn_and_check() -> void:
	var r: NetReplay = _two_humans_one_cpu()
	assert_eq(r.check_turn({"tank": -2, "uid": "any", "deadline": 1, "index": 1}), "")
	assert_eq(r.check_turn({"tank": -1, "uid": "any", "deadline": 0, "index": 0}), "", "needs resolve is always fine")
	assert_eq(r.check_turn({"tank": 0, "uid": A}), "turn_tank")
	_into_aim(r)
	var tank: int = r.state.current_tank
	var want: Dictionary = r.expected_turn()
	assert_eq(want["tank"], tank)
	assert_eq(want["uid"], NetProtocol.UID_CPU if r.seat_is_cpu(tank) else r.seat_uid(tank))
	assert_eq(r.check_turn({"tank": tank, "uid": want["uid"]}), "")
	assert_eq(r.check_turn({"tank": tank, "uid": "mallory"}), "turn_uid")


func test_plan_batch_adds_the_cpu_entries_and_changes_nothing() -> void:
	var r: NetReplay = _two_humans_one_cpu()
	var before: String = r.fingerprint()
	var plan: Dictionary = r.plan_batch([{"kind": "ready", "tank": 0}])
	assert_true(plan["ok"])
	# the CPU shop visit is still owed (a resolve would have written it first), so it follows the human's entry
	assert_eq(r.fingerprint(), before)
	assert_eq(r.count, 0)
	var entries: Array = plan["entries"]
	assert_eq(entries[0], {"kind": "ready", "tank": 0})
	assert_eq(entries[1]["kind"], "auto_shop")
	assert_false(plan["over"])


func test_plan_batch_refuses_an_illegal_action() -> void:
	var r: NetReplay = _two_humans_one_cpu()
	var plan: Dictionary = r.plan_batch([{"kind": "fire", "tank": 0, "angle": 450, "power": 500, "weapon": "spark_dart"}])
	assert_false(plan["ok"])
	assert_eq(plan["err"], "invalid_bad_phase")


func test_plan_batch_respects_the_cap_and_reports_more_cpu_work() -> void:
	var seats: Array = [NetTestUtil.human(A)]
	for i: int in range(7):
		seats.append(NetTestUtil.cpu(1))
	var r: NetReplay = _replay(seats)
	var plan: Dictionary = r.plan_batch([], 3)
	assert_eq((plan["entries"] as Array).size(), 3)
	assert_true(plan["more_cpu"])
	var full: Dictionary = r.plan_batch([])
	assert_eq((full["entries"] as Array).size(), 7)
	assert_false(full["more_cpu"])


func test_fork_is_independent() -> void:
	var r: NetReplay = _two_humans_one_cpu()
	var f: NetReplay = r.fork()
	f.apply_entry({"kind": "ready", "tank": 0})
	assert_true(f.state.tanks[0].ready)
	assert_false(r.state.tanks[0].ready)
	assert_eq(r.count, 0)
	assert_eq(f.count, 1)


func test_seat_changes_do_not_touch_history() -> void:
	var r: NetReplay = _two_humans_one_cpu()
	var fp: String = r.fingerprint()
	var seats: Array = r.seats.duplicate()
	seats[1] = {"kind": "cpu", "level": 2, "name": "CPU"}
	r.set_seats(seats)
	assert_eq(r.fingerprint(), fp)
	assert_true(r.seat_is_cpu(1))
	assert_eq(r.pending_cpu_entry()["kind"], "auto_shop")


func test_love_match_has_no_shop_and_ends_with_the_match() -> void:
	var m: Dictionary = NetTestUtil.meta([NetTestUtil.human(A), NetTestUtil.human(B)], {"mode": 1, "rounds": 1, "start_money": 0})
	var r: NetReplay = NetReplay.create(m)
	assert_eq(r.state.phase, SimConstants.PHASE_AIM)
	assert_eq(r.pending_cpu_entry(), {})
	var log: Array[Dictionary] = NetTestUtil.play_through(r, 600)
	assert_true(r.ended, "a love match finishes: %d entries" % log.size())
	assert_eq(r.state.phase, SimConstants.PHASE_MATCH_OVER)


func test_ends_turn_matches_the_offline_cpu_driver() -> void:
	for a: Dictionary in [{"kind": "fire"}, {"kind": "pass"}, {"kind": "move"}, {"kind": "use_item", "item": "nanorepair_kit"}, {"kind": "use_item", "item": "glow_shield"}]:
		assert_eq(NetReplay.ends_turn(a), CpuDriver.ends_turn(a), str(a))
	assert_eq(NetReplay.MAX_CPU_CALLS, CpuDriver.MAX_CALLS)
