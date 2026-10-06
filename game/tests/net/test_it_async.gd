extends "res://tests/net/net_it_base.gd"
## Timeouts (async and live), a dropped connection, a tampered log, quick messages, presence, a player leaving, and a
## sweep-style "needs resolve" marker, all against the emulators.


func _pair(settings: Dictionary, seats: Array, timers: Dictionary) -> Dictionary:
	var host: NetSession = await _phone("Hana", true)
	var friend: NetSession = await _phone("Finn")
	await _befriend(host, friend)
	var info: Dictionary = await _start_match(host, [friend], settings, seats, timers)
	var id: String = info["matchId"]
	var mh: OnlineMatch = await _open(host, id)
	var mf: OnlineMatch = await _open(friend, id)
	return {"host": host, "friend": friend, "mh": mh, "mf": mf, "id": id}


func _both_ready(c: Dictionary) -> void:
	var mh: OnlineMatch = c["mh"]
	var mf: OnlineMatch = c["mf"]
	assert_true(await _until(func() -> bool: return mh.turn_info()["shop"] == true and mf.turn_info()["shop"] == true))
	assert_true((await mh.submit({"kind": "ready", "tank": 0})).ok)
	# the friend readies last, so the friend's client writes the first aim turn
	assert_true((await mf.submit({"kind": "ready", "tank": 1})).ok)
	assert_true(await _until(func() -> bool: return mh.state.phase == SimConstants.PHASE_AIM and mf.state.phase == SimConstants.PHASE_AIM))


func _count_kind(m: OnlineMatch, kind: String) -> int:
	var n: int = 0
	for e: Dictionary in m.replay.entries:
		if e["kind"] == kind:
			n += 1
	return n


func test_async_timeout_lets_the_ai_play_the_turn() -> void:
	if not _need_emulator():
		return
	var c: Dictionary = await _pair(NetLobby.settings({"rounds": 1, "wind_max": 10}), [NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_cpu(2)],
			NetLobby.timers(0, 24, "auto"))
	var mh: OnlineMatch = c["mh"]
	var mf: OnlineMatch = c["mf"]
	assert_eq(mh.replay.timeout_mode(), "auto")
	# the friend writes the first aim turn with a deadline one second in the past
	mf.debug_deadline_offset_ms = -1000
	await _both_ready(c)
	var first_holder: int = mh.turn_info()["tank"]
	assert_true(await _until(func() -> bool: return _count_kind(mh, "timeout") >= 1 and _count_kind(mf, "timeout") >= 1), "a timeout entry was written after the deadline")
	mf.debug_deadline_offset_ms = null
	assert_true(await _until(func() -> bool: return mh.replay.count == mf.replay.count and mh.turn_info()["tank"] != first_holder or mh.turn_info()["resolving"] == false))
	var timeout_index: int = 0
	for i: int in range(mh.replay.entries.size()):
		if mh.replay.entries[i]["kind"] == "timeout":
			timeout_index = i
			break
	# there is no `fire` entry for the sleeper's tank: the AI's shot is expanded by every client from the marker
	assert_eq(mh.replay.entries[timeout_index], {"kind": "timeout", "tank": first_holder})
	assert_eq(mh.replay.fingerprint(), mf.replay.fingerprint())
	mh.debug_deadline_offset_ms = null
	assert_true(await _play_out([mh, mf], 150.0))
	assert_true(await _until(func() -> bool: return mf.replay.count == mh.replay.count and mf.status == "over"))
	await _assert_in_sync([mh, mf], c["id"] as String, [c["host"], c["friend"]])


func test_async_timeout_end_finishes_the_match() -> void:
	if not _need_emulator():
		return
	var c: Dictionary = await _pair(NetLobby.settings({"rounds": 1}), [NetLobby.seat_human(true), NetLobby.seat_human()], NetLobby.timers(0, 24, "end"))
	var mh: OnlineMatch = c["mh"]
	var mf: OnlineMatch = c["mf"]
	var over: Array = [0]
	mh.status_changed.connect(func(s: String) -> void: over[0] = over[0] + (1 if s == "over" else 0))
	mf.debug_deadline_offset_ms = -1000
	await _both_ready(c)
	assert_true(await _until(func() -> bool: return mh.status == "over" and mf.status == "over"), "status over after the timeout")
	assert_true(mh.replay.ended_by_timeout)
	assert_true(mf.replay.ended_by_timeout)
	assert_eq(over[0], 1)
	var late: NetResult = await mh.submit({"kind": "pass", "tank": 0})
	assert_true(late.is_code(NetError.Code.PRECONDITION))


func test_live_timeout_passes_while_the_holder_is_online() -> void:
	if not _need_emulator():
		return
	var c: Dictionary = await _pair(NetLobby.settings({"rounds": 1, "wind_max": 10}), [NetLobby.seat_human(true), NetLobby.seat_human()], NetLobby.timers(10, 72, "auto"))
	var mh: OnlineMatch = c["mh"]
	var mf: OnlineMatch = c["mf"]
	assert_eq(mh.replay.timeout_mode(), "pass")
	mf.debug_live_offset_ms = -1000
	await _both_ready(c)
	var holder: int = mh.turn_info()["tank"]
	assert_true(mh.turn_info().has("liveDeadline"))
	assert_true(await _until(func() -> bool: return _count_kind(mh, "timeout") >= 1 and _count_kind(mf, "timeout") >= 1), "live timeout written")
	mf.debug_live_offset_ms = null
	assert_true(await _until(func() -> bool: return mh.turn_info()["tank"] != holder))
	assert_eq(mh.replay.fingerprint(), mf.replay.fingerprint())
	assert_lt(mh.live_seconds_left(), 11.0)


func test_disconnect_then_catch_up() -> void:
	if not _need_emulator():
		return
	var c: Dictionary = await _pair(NetLobby.settings({"rounds": 1, "wind_max": 10}), [NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_cpu(3)],
			NetLobby.timers(0, 72, "auto"))
	var mh: OnlineMatch = c["mh"]
	var mf: OnlineMatch = c["mf"]
	await _both_ready(c)
	var states: Array = []
	mf.connection_changed.connect(func(s: int) -> void: states.append(s))
	var caught: Array = []
	mf.entry_applied.connect(func(i: int, r: Dictionary) -> void: caught.append([i, r["catch_up"]]))
	var before: int = mf.replay.count
	# the friend's phone loses its connection for 4 s; meanwhile the host plays two turns
	mf.debug_drop_streams(4.0)
	assert_true(await _until(func() -> bool: return mf.connection == OnlineMatch.Connection.RECONNECTING))
	var played: int = 0
	var guard: int = 0
	while played < 1 and guard < 40:
		guard += 1
		var r: NetResult = await _step(mh)
		if r != null and r.ok:
			played += 1
		await get_tree().create_timer(0.1).timeout
	assert_eq(played, 1)
	assert_gt(mh.replay.count, before)
	assert_eq(mf.replay.count, before, "the friend's phone has not seen it")
	assert_true(await _until(func() -> bool: return mf.replay.count == mh.replay.count, 15.0), "the friend caught up after reconnecting")
	assert_eq(mf.connection, OnlineMatch.Connection.LIVE)
	assert_true(states.has(OnlineMatch.Connection.RECONNECTING) and states.has(OnlineMatch.Connection.LIVE))
	assert_gt(caught.size(), 0)
	for item: Variant in caught:
		assert_true((item as Array)[1], "history replayed after a reconnect is flagged catch_up")
	assert_eq(mf.replay.fingerprint(), mh.replay.fingerprint())
	assert_true(await _play_out([mh, mf], 150.0))
	assert_true(await _until(func() -> bool: return mf.replay.count == mh.replay.count and mf.status == "over"))
	await _assert_in_sync([mh, mf], c["id"] as String, [c["host"], c["friend"]])


func test_acting_while_behind_catches_up_first() -> void:
	if not _need_emulator():
		return
	var c: Dictionary = await _pair(NetLobby.settings({"rounds": 1, "wind_max": 10}), [NetLobby.seat_human(true), NetLobby.seat_human()], NetLobby.timers(0, 72, "auto"))
	var mh: OnlineMatch = c["mh"]
	var mf: OnlineMatch = c["mf"]
	await _both_ready(c)
	# whoever is not on turn loses the connection, the other plays, and the first answers at once
	var first: OnlineMatch = mh if mh.turn_info()["tank"] == 0 else mf
	var second: OnlineMatch = mf if first == mh else mh
	second.debug_drop_streams(30.0)
	assert_true(await _until(func() -> bool: return second.connection != OnlineMatch.Connection.LIVE))
	var r1: NetResult = await _step(first)
	assert_true(r1.ok, str(r1))
	assert_true(second.replay.count < first.replay.count)
	var seat: int = second.my_seats[0]
	var r2: NetResult = await second.submit({"kind": "fire", "tank": seat, "angle": 900, "power": 400, "weapon": "spark_dart"})
	assert_true(r2.ok, "the lagging phone caught up through a refetch and played: %s" % str(r2))
	assert_eq(second.replay.fingerprint(), first.replay.fingerprint())


func test_tampered_entry_disputes_both_clients_and_stops_play() -> void:
	if not _need_emulator():
		return
	var c: Dictionary = await _pair(NetLobby.settings({"rounds": 1, "wind_max": 10}), [NetLobby.seat_human(true), NetLobby.seat_human()], NetLobby.timers(60, 72, "auto"))
	var mh: OnlineMatch = c["mh"]
	var mf: OnlineMatch = c["mf"]
	await _both_ready(c)
	var reasons: Array = []
	mh.disputed.connect(func(why: String, i: int) -> void: reasons.append([why, i]))
	mf.disputed.connect(func(why: String, i: int) -> void: reasons.append([why, i]))
	var n: int = mh.replay.count
	var wrong: int = 1 - (mh.turn_info()["tank"] as int)
	# written through the admin path (rules skipped): a shot by the tank whose turn it is not
	var bad: NetResult = await _admin(HTTPClient.METHOD_PATCH, "matches/%s" % c["id"], {
		"actions/%d" % n: {"kind": "fire", "tank": wrong, "angle": 450, "power": 500, "weapon": "spark_dart"},
		"meta/actionCount": n + 1})
	assert_true(bad.ok, str(bad))
	assert_true(await _until(func() -> bool: return mh.is_disputed() and mf.is_disputed()), "both clients report disputed")
	assert_eq(reasons.size(), 2)
	assert_eq((reasons[0] as Array)[1], n)
	assert_eq((reasons[0] as Array)[0], "invalid_not_your_turn")
	var blocked: NetResult = await mh.submit({"kind": "pass", "tank": 0})
	assert_true(blocked.is_code(NetError.Code.DISPUTED))
	# the host can give the match up
	var gave_up: NetResult = await mh.abandon()
	assert_true(gave_up.ok, str(gave_up))
	assert_true(await _until(func() -> bool: return mf.status == "abandoned"))
	assert_true((await mf.abandon()).is_code(NetError.Code.PERMISSION))


func test_a_reported_fingerprint_that_differs_disputes() -> void:
	if not _need_emulator():
		return
	var c: Dictionary = await _pair(NetLobby.settings({"rounds": 1, "wind_max": 10}), [NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_cpu(2)], NetLobby.timers(60, 72, "auto"))
	var mh: OnlineMatch = c["mh"]
	var mf: OnlineMatch = c["mf"]
	await _both_ready(c)
	assert_true(await _until(func() -> bool: return not mh.fingerprints.is_empty()))
	var index: int = mh.fingerprints.keys()[0]
	var put: NetResult = await _admin(HTTPClient.METHOD_PUT, "matches/%s/fp/%d/someoneElse" % [c["id"], index], "0000000000000000")
	assert_true(put.ok, str(put))
	assert_true(await _until(func() -> bool: return mh.is_disputed() and mf.is_disputed()))
	assert_eq(mh.replay.dispute_reason, "fingerprint")


func test_the_stored_turn_must_match_the_simulation() -> void:
	if not _need_emulator():
		return
	var c: Dictionary = await _pair(NetLobby.settings({"rounds": 1, "wind_max": 10}), [NetLobby.seat_human(true), NetLobby.seat_human()], NetLobby.timers(60, 72, "auto"))
	var mh: OnlineMatch = c["mh"]
	var mf: OnlineMatch = c["mf"]
	await _both_ready(c)
	var turn: Dictionary = (mh.turn_info()).duplicate()
	var other: int = 1 - (turn["tank"] as int)
	var uid: String = mh.replay.seat_uid(other)
	var res: NetResult = await _admin(HTTPClient.METHOD_PUT, "matches/%s/meta/turn" % c["id"],
			{"tank": other, "uid": uid, "deadline": turn["deadline"], "index": (turn["index"] as int) + 1})
	assert_true(res.ok, str(res))
	assert_true(await _until(func() -> bool: return mh.is_disputed() and mf.is_disputed(), 10.0), "a wrong meta/turn is a dispute")
	assert_true(mh.replay.dispute_reason.begins_with("turn_"))


func test_quick_messages_and_presence() -> void:
	if not _need_emulator():
		return
	var c: Dictionary = await _pair(NetLobby.settings({"rounds": 1}), [NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_cpu(1)], NetLobby.timers(60, 72, "auto"))
	var mh: OnlineMatch = c["mh"]
	var mf: OnlineMatch = c["mf"]
	var got: Array = []
	mf.message_received.connect(func(seat: int, msg: int, who: String) -> void: got.append([seat, msg, who]))
	var presence: Array = []
	mf.presence_changed.connect(func(who: String, online: bool) -> void: presence.append([who, online]))
	assert_true(await _until(func() -> bool: return mf.is_online((c["host"] as NetSession).uid())), "heartbeat seen")
	assert_true(await _until(func() -> bool: return presence.has([(c["host"] as NetSession).uid(), true])))
	assert_true((await mh.send_message(3)).ok)
	assert_true(await _until(func() -> bool: return got.size() == 1))
	assert_eq(got[0], [0, 3, (c["host"] as NetSession).uid()])
	assert_true((await mh.send_message(4)).is_code(NetError.Code.RATE_LIMITED), "client-side 3 s limit")
	assert_true((await mh.send_message(99)).is_code(NetError.Code.INVALID))
	assert_true((await mf.send_message(1, 0)).is_code(NetError.Code.ILLEGAL_ACTION), "not the friend's seat")
	# the rules enforce the limit as well: a second write inside 3 s is refused even from a client that skips its own check
	await get_tree().create_timer(3.2).timeout
	assert_true((await mh.send_message(5)).ok)
	mh._last_msg_ms = -1000000
	assert_true((await mh.send_message(6)).is_code(NetError.Code.RATE_LIMITED))
	assert_true(await _until(func() -> bool: return got.size() == 2))
	# presence goes stale (set through the admin path) and comes back
	var host_uid: String = (c["host"] as NetSession).uid()
	await _admin(HTTPClient.METHOD_PUT, "matches/%s/presence/%s" % [c["id"], host_uid], mf.now_ms() - 120000)
	assert_true(await _until(func() -> bool: return not mf.is_online(host_uid)), "stale heartbeat reads offline")
	assert_true(presence.has([host_uid, false]))
	await _admin(HTTPClient.METHOD_PUT, "matches/%s/presence/%s" % [c["id"], host_uid], mf.now_ms())
	assert_true(await _until(func() -> bool: return mf.is_online(host_uid)))


func test_a_player_leaving_is_replaced_by_a_cpu_and_the_match_goes_on() -> void:
	if not _need_emulator():
		return
	var c: Dictionary = await _pair(NetLobby.settings({"rounds": 1, "wind_max": 10}), [NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_cpu(2)], NetLobby.timers(60, 72, "auto"))
	var mh: OnlineMatch = c["mh"]
	var mf: OnlineMatch = c["mf"]
	await _both_ready(c)
	var seats_seen: Array = []
	mh.seats_changed.connect(func(s: Array) -> void: seats_seen.append(s))
	mf.close()
	var left: NetResult = await (c["friend"] as NetSession).lobby.leave(c["id"] as String)
	assert_true(left.is_code(NetError.Code.NONE) or left.ok, str(left))
	assert_true(await _until(func() -> bool: return seats_seen.size() >= 1), "the host sees the seat change")
	assert_true(mh.replay.seat_is_cpu(1))
	assert_eq(mh.my_seats, [0])
	assert_true(await _play_out([mh], 150.0), "the host finishes the match against the CPUs")
	assert_gt(_count_kind(mh, "auto"), 0)
	assert_false(mh.is_disputed())


func test_a_sweep_style_timeout_marker_is_resolved_by_a_client() -> void:
	if not _need_emulator():
		return
	var c: Dictionary = await _pair(NetLobby.settings({"rounds": 1, "wind_max": 10}), [NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_cpu(2)], NetLobby.timers(0, 72, "auto"))
	var mh: OnlineMatch = c["mh"]
	var mf: OnlineMatch = c["mf"]
	await _both_ready(c)
	assert_true(await _until(func() -> bool: return mh.turn_info()["resolving"] == false))
	var tank: int = mh.turn_info()["tank"]
	var n: int = mh.replay.count
	var idx: int = mh.turn_info()["index"]
	# what the scheduled sweep writes for a human who missed the deadline: the entry and a "needs resolve" turn
	var res: NetResult = await _admin(HTTPClient.METHOD_PATCH, "matches/%s" % c["id"], {
		"actions/%d" % n: {"kind": "timeout", "tank": tank}, "meta/actionCount": n + 1,
		"meta/turn": {"tank": -1, "uid": "any", "deadline": 0, "index": idx + 1}})
	assert_true(res.ok, str(res))
	assert_true(await _until(func() -> bool: return mh.replay.count > n and mf.replay.count > n and mh.turn_info()["tank"] >= 0 and mf.turn_info()["tank"] >= 0 and mh.turn_info()["index"] > idx + 1, 15.0), "a client resolved the marker")
	assert_ne(mh.turn_info()["tank"], tank)
	assert_eq(mh.replay.fingerprint(), mf.replay.fingerprint())
	assert_false(mh.is_disputed() or mf.is_disputed())


func test_presence_heartbeat_repeats_while_open() -> void:
	if not _need_emulator():
		return
	var c: Dictionary = await _pair(NetLobby.settings({"rounds": 1}), [NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_cpu(1)], NetLobby.timers(60, 72, "auto"))
	var mh: OnlineMatch = c["mh"]
	var host: NetSession = c["host"]
	assert_eq(mh.heartbeat_interval_ms, 30000, "the real interval is 30 s")
	mh.heartbeat_interval_ms = 1000
	var path: String = "matches/%s/presence/%s" % [c["id"], host.uid()]
	var first: int = (await host.db.get_value(path)).value
	await get_tree().create_timer(2.6).timeout
	var later: int = (await host.db.get_value(path)).value
	assert_gt(later, first + 900, "a newer server timestamp was written")
	mh.close()
	var frozen: int = (await host.db.get_value(path)).value
	await get_tree().create_timer(1.6).timeout
	assert_eq((await host.db.get_value(path)).value, frozen, "no heartbeat after close")
