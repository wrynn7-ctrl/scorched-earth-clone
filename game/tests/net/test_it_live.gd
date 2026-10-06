extends "res://tests/net/net_it_base.gd"
## Live matches: two phones in one process, a CPU, a full short match, plus teams, Love, a shared phone and a shop race.


func test_full_live_match_with_a_cpu() -> void:
	if not _need_emulator():
		return
	var host: NetSession = await _phone("Hana", true)
	var friend: NetSession = await _phone("Finn")
	await _befriend(host, friend)
	var info: Dictionary = await _start_match(host, [friend], NetLobby.settings({"rounds": 1, "wind_max": 30, "start_money": 5000}),
			[NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_cpu(2)], NetLobby.timers(60, 72, "auto"))
	var id: String = info["matchId"]
	var mh: OnlineMatch = await _open(host, id)
	var mf: OnlineMatch = await _open(friend, id)
	var applied_h: Array = []
	var applied_f: Array = []
	mh.entry_applied.connect(func(i: int, r: Dictionary) -> void: applied_h.append([i, r]))
	mf.entry_applied.connect(func(i: int, r: Dictionary) -> void: applied_f.append([i, r]))
	assert_eq(mh.my_seats, [0])
	assert_eq(mf.my_seats, [1])
	# the first resolve (CPU shop, then the shop turn) happens by itself
	assert_true(await _until(func() -> bool: return mh.turn_info()["shop"] == true and mf.turn_info()["shop"] == true), "shop turn set by a resolver")
	assert_eq(mh.replay.count, 1, "one auto_shop entry for the CPU")
	assert_true(await _play_out([mh, mf], 150.0), "the match ended")
	assert_true(await _until(func() -> bool: return mh.status == "over" and mf.status == "over"))
	assert_eq(mh.state.phase, SimConstants.PHASE_MATCH_OVER)
	assert_true(await _until(func() -> bool: return mf.replay.count == mh.replay.count))
	await _assert_in_sync([mh, mf], id, [host, friend])
	# every entry reached both phones, in order, with a timeline
	assert_eq(applied_h.size(), mh.replay.count)
	assert_true(await _until(func() -> bool: return applied_f.size() == mf.replay.count))
	for i: int in range(applied_h.size()):
		assert_eq((applied_h[i] as Array)[0], i)
	var any_events: bool = false
	for item: Variant in applied_f:
		if ((item as Array)[1]["events"] as Array).size() > 0:
			any_events = true
	assert_true(any_events)
	# nothing can be played after the end
	var late: NetResult = await mh.submit({"kind": "pass", "tank": 0})
	assert_true(late.is_code(NetError.Code.PRECONDITION))
	# the match shows as finished in "Your matches"
	assert_true(await _until(func() -> bool: return ((await friend.matches.refresh()).list()[0] as Dictionary)["status"] == "over"))


func _two_phones(settings: Dictionary, seats: Array, timers: Dictionary = {}) -> Dictionary:
	var host: NetSession = await _phone("Hana", true)
	var friend: NetSession = await _phone("Finn")
	await _befriend(host, friend)
	var info: Dictionary = await _start_match(host, [friend], settings, seats, timers)
	var mh: OnlineMatch = await _open(host, info["matchId"] as String)
	var mf: OnlineMatch = await _open(friend, info["matchId"] as String)
	return {"host": host, "friend": friend, "mh": mh, "mf": mf, "id": info["matchId"]}


func _finish(c: Dictionary) -> void:
	var mh: OnlineMatch = c["mh"]
	var mf: OnlineMatch = c["mf"]
	assert_true(await _play_out([mh, mf], 150.0), "the match ended")
	assert_true(await _until(func() -> bool: return mh.status == "over" and mf.status == "over"))
	assert_true(await _until(func() -> bool: return mf.replay.count == mh.replay.count))
	await _assert_in_sync([mh, mf], c["id"] as String, [c["host"], c["friend"]])


func test_teams_match() -> void:
	if not _need_emulator():
		return
	var c: Dictionary = await _two_phones(NetLobby.settings({"rounds": 1, "teams": [0, 1, 0, 1], "friendly_fire": false, "wind_max": 20}),
			[NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_cpu(2), NetLobby.seat_cpu(1)])
	var mh: OnlineMatch = c["mh"]
	assert_eq(mh.state.settings.teams, PackedInt32Array([0, 1, 0, 1]))
	assert_false(mh.state.settings.friendly_fire)
	await _finish(c)


func test_love_match() -> void:
	if not _need_emulator():
		return
	var c: Dictionary = await _two_phones(NetLobby.settings({"mode": 1}), [NetLobby.seat_human(true), NetLobby.seat_human()])
	var mh: OnlineMatch = c["mh"]
	assert_eq(mh.state.settings.mode, SimConstants.MODE_LOVE)
	assert_true(await _until(func() -> bool: return mh.turn_info()["tank"] == 0), "no shop in love: tank 0 starts")
	await _finish(c)


func test_shared_phone_seats() -> void:
	if not _need_emulator():
		return
	var host: NetSession = await _phone("Hana", true)
	var friend: NetSession = await _phone("Finn")
	await _befriend(host, friend)
	# the host plays seat 0 on his phone; the friend takes two seats on hers
	var made: NetResult = await host.lobby.create(NetLobby.settings({"rounds": 1, "wind_max": 20}),
			[NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_human(), NetLobby.seat_cpu(1)])
	assert_true(made.ok, str(made))
	var info: Dictionary = {"matchId": made.dict()["matchId"], "code": made.dict()["code"]}
	var joined: NetResult = await friend.lobby.join(info["code"] as String, 2, ["Finn A", "Finn B"])
	assert_true(joined.ok, str(joined))
	assert_eq(joined.dict()["seats"], [1, 2])
	var started: NetResult = await host.lobby.start(info["matchId"] as String)
	assert_true(started.ok, str(started))
	var mh: OnlineMatch = await _open(host, info["matchId"] as String)
	var mf: OnlineMatch = await _open(friend, info["matchId"] as String)
	assert_eq(mf.my_seats, [1, 2])
	assert_eq(mf.seat_name(2), "Finn B")
	# one phone cannot play another phone's seat, and the shop batch readies both of hers in one update
	assert_true(await _until(func() -> bool: return mf.turn_info()["shop"] == true))
	var wrong: NetResult = await mf.submit({"kind": "ready", "tank": 0})
	assert_true(wrong.is_code(NetError.Code.ILLEGAL_ACTION))
	assert_eq(wrong.reason, "not_your_seat")
	var both: NetResult = await mf.submit_many([{"kind": "ready", "tank": 1}, {"kind": "ready", "tank": 2}])
	assert_true(both.ok, str(both))
	assert_eq((both.dict()["entries"] as Array).size(), 2)
	var mixed: NetResult = await mf.submit_many([{"kind": "fire", "tank": 1, "angle": 1, "power": 1, "weapon": "spark_dart"}, {"kind": "pass", "tank": 2}])
	assert_eq(mixed.reason, "one_aim_action_per_update")
	await _finish({"mh": mh, "mf": mf, "id": info["matchId"], "host": host, "friend": friend})


func test_concurrent_shop_is_serialized_by_retry() -> void:
	if not _need_emulator():
		return
	var c: Dictionary = await _two_phones(NetLobby.settings({"rounds": 1, "wind_max": 10}),
			[NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_cpu(2)])
	var mh: OnlineMatch = c["mh"]
	var mf: OnlineMatch = c["mf"]
	assert_true(await _until(func() -> bool: return mh.turn_info()["shop"] == true and mf.turn_info()["shop"] == true))
	# both press READY in the same frame, with a purchase first: only one can win index 1
	var results: Array = [null, null]
	var go_h: Callable = func() -> void: results[0] = await mh.submit_many([{"kind": "buy", "tank": 0, "item": "pulse_missile", "qty": 1}, {"kind": "ready", "tank": 0}])
	var go_f: Callable = func() -> void: results[1] = await mf.submit_many([{"kind": "ready", "tank": 1}])
	go_h.call()
	go_f.call()
	assert_true(await _until(func() -> bool: return results[0] != null and results[1] != null))
	assert_true((results[0] as NetResult).ok, str(results[0]))
	assert_true((results[1] as NetResult).ok, str(results[1]))
	assert_gt(mh.write_retries + mf.write_retries, 0, "one of them lost the race and retried")
	assert_true(await _until(func() -> bool: return mh.replay.count == mf.replay.count and mh.state.phase == SimConstants.PHASE_AIM))
	assert_eq(mh.replay.fingerprint(), mf.replay.fingerprint())
	assert_gt(mh.state.tanks[0].stock_of("pulse_missile"), 0)
	await _finish(c)
