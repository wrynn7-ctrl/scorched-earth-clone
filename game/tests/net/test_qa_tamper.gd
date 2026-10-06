extends "res://tests/net/net_it_base.gd"
## M7-Q: what a malicious member can still do THROUGH THE RULES (writes below go through the clients' own authenticated database
## handle, so the rules apply), and what the other clients do about it. Companion of firebase/test/qa/rules/attacks.test.ts.


func _pair(seats: Array, timers: Dictionary = {}) -> Dictionary:
	var host: NetSession = await _phone("Hana", true)
	var friend: NetSession = await _phone("Finn")
	await _befriend(host, friend)
	var info: Dictionary = await _start_match(host, [friend], NetLobby.settings({"rounds": 1, "wind_max": 10}), seats, timers if not timers.is_empty() else NetLobby.timers(60, 72, "auto"))
	var mh: OnlineMatch = await _open(host, info["matchId"] as String)
	var mf: OnlineMatch = await _open(friend, info["matchId"] as String)
	assert_true(await _until(func() -> bool: return mh.turn_info()["shop"] == true and mf.turn_info()["shop"] == true))
	assert_true((await mh.submit({"kind": "ready", "tank": 0})).ok)
	assert_true((await mf.submit({"kind": "ready", "tank": 1})).ok)
	assert_true(await _until(func() -> bool: return mh.state.phase == SimConstants.PHASE_AIM and mf.state.phase == SimConstants.PHASE_AIM))
	assert_true(await _until(func() -> bool: return mh.turn_info()["resolving"] == false and mf.turn_info()["resolving"] == false))
	return {"host": host, "friend": friend, "mh": mh, "mf": mf, "id": info["matchId"]}


## The OnlineMatch (and its session) of whoever holds the turn.
func _holder(c: Dictionary) -> Array:
	var mh: OnlineMatch = c["mh"]
	if mh.is_my_turn():
		return [mh, c["host"]]
	return [c["mf"], c["friend"]]


func test_a_holder_can_end_the_match_early_with_status_over_and_the_other_client_notices() -> void:
	if not _need_emulator():
		return
	var c: Dictionary = await _pair([NetLobby.seat_human(true), NetLobby.seat_human()])
	var pair: Array = _holder(c)
	var holder: OnlineMatch = pair[0]
	var session: NetSession = pair[1]
	var other: OnlineMatch = c["mf"] if holder == c["mh"] else c["mh"]
	var n: int = holder.replay.count
	var action: Dictionary = Simulation.normalize_action(AiPlayer.next_action(holder.state, holder.state.current_tank))
	# a legal shot plus "over": the rules accept it (a legal first entry and a count bump are all they can check)
	var res: NetResult = await session.db.patch("matches/%s" % c["id"], {"actions/%d" % n: action, "meta/actionCount": n + 1, "meta/status": "over"})
	assert_true(res.ok, "documented: the rules accept it (%s)" % str(res))
	assert_true(await _until(func() -> bool: return other.replay.count == n + 1 and (other.status == "over" or other.is_disputed()), 10.0))
	if other.status == "over" and not other.is_disputed() and not other.replay.ended:
		pending("BUG (medium): the match is 'over' for the other client although the simulation is not (phase %s, %d tanks alive, no dispute). A holder who is losing can end the match with any legal action plus meta/status = over. Cause: build_rules.mjs statusRule only needs a count bump; OnlineMatch._set_status trusts it and _check_turn returns early when status != playing. Fix: a client that sees status over while replay.ended is false should dispute (reason 'status_over_early')." % [other.state.phase, other.state.tanks.size()])
		return
	assert_true(other.is_disputed() or other.replay.ended)


func test_a_holder_who_writes_the_turn_for_himself_again_gets_the_match_disputed() -> void:
	if not _need_emulator():
		return
	var c: Dictionary = await _pair([NetLobby.seat_human(true), NetLobby.seat_human()])
	var pair: Array = _holder(c)
	var holder: OnlineMatch = pair[0]
	var session: NetSession = pair[1]
	var other: OnlineMatch = c["mf"] if holder == c["mh"] else c["mh"]
	var n: int = holder.replay.count
	var tank: int = holder.state.current_tank
	var action: Dictionary = Simulation.normalize_action({"kind": "move", "tank": tank, "dx": 3})
	if Simulation.validate_action(holder.state, action) != "":
		action = Simulation.normalize_action(AiPlayer.next_action(holder.state, tank))
	var turn: Dictionary = holder._make_turn({"tank": tank, "uid": holder.uid})
	var res: NetResult = await session.db.patch("matches/%s" % c["id"], {"actions/%d" % n: action, "meta/actionCount": n + 1, "meta/turn": turn})
	assert_true(res.ok, "the rules cannot know the turn is wrong (%s)" % str(res))
	var reasons: Array = []
	other.disputed.connect(func(why: String, _i: int) -> void: reasons.append(why))
	assert_true(await _until(func() -> bool: return other.is_disputed(), 12.0), "the other client calls the wrong stored turn a dispute")
	assert_true(other.replay.dispute_reason.begins_with("turn_"), "dispute reason: %s" % other.replay.dispute_reason)


func test_the_writer_of_an_auto_entry_picks_the_ai_level_of_a_cpu() -> void:
	if not _need_emulator():
		return
	# seat 2 is CPU level 1; a member writes the CPU's turn with level 4
	var c: Dictionary = await _pair([NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_cpu(1)])
	var tampered: bool = false
	var guard: int = 0
	while not tampered and guard < 12:
		guard += 1
		var pair: Array = _holder(c)
		var holder: OnlineMatch = pair[0]
		var session: NetSession = pair[1]
		if not holder.is_my_turn():
			await get_tree().create_timer(0.2).timeout
			continue
		var tank: int = holder.state.current_tank
		var action: Dictionary = Simulation.normalize_action(AiPlayer.next_action(holder.state, tank))
		var typed: Array[Dictionary] = [action]
		var plan: Dictionary = holder.replay.plan_batch(typed)
		var entries: Array = plan["entries"]
		var has_cpu: bool = false
		for e: Variant in entries:
			if (e as Dictionary)["kind"] == "auto":
				has_cpu = true
		if not has_cpu:
			var r: NetResult = await holder.submit(action)
			assert_true(r.ok, str(r))
			await get_tree().create_timer(0.3).timeout
			continue
		var honest_fp: String = plan["fingerprint"]
		for i: int in range(entries.size()):
			if (entries[i] as Dictionary)["kind"] == "auto":
				entries[i] = {"kind": "auto", "tank": (entries[i] as Dictionary)["tank"], "level": 4}
		var base: int = holder.replay.count
		var update: Dictionary = holder._build_update(plan, base)
		var res: NetResult = await session.db.patch("matches/%s" % c["id"], update)
		assert_true(res.ok, "the rules accept any level 1..4 for a CPU seat (%s)" % str(res))
		var other: OnlineMatch = c["mf"] if holder == c["mh"] else c["mh"]
		assert_true(await _until(func() -> bool: return other.replay.count == base + entries.size() or other.is_disputed(), 10.0))
		await get_tree().create_timer(0.5).timeout
		tampered = true
		if not other.is_disputed() and other.replay.fingerprint() != honest_fp:
			pending("BUG (medium): a member wrote {kind: auto, level: 4} for a level-1 CPU seat: the rules and every client accepted it, no dispute, and the state differs from the honest turn (fingerprint %s vs %s). The writer chooses how well each CPU plays. Cause: rules never compare the entry level with seats/N/level and NetReplay._apply_auto only range-checks it." % [other.replay.fingerprint(), honest_fp])
			return
		assert_true(other.is_disputed(), "a tampered AI level must be refused")
	assert_true(tampered, "reached a CPU turn")
