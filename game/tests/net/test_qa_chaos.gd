extends "res://tests/net/net_it_base.gd"
## M7-Q multi-client chaos: 20 seeded matches with 2 to 4 phones against the emulators, each with a random script of delayed
## submits, simultaneous shop buys, stream drops, a phone closing for a long gap and coming back, a phone leaving mid-match,
## quick messages, and live and async timeouts (short deadlines through the OnlineMatch debug offsets).
##
## After EVERY step the test checks: nobody is disputed (an illegal entry or a wrong stored turn would dispute), phones that hold the
## same number of entries hold the same fingerprint, and the match keeps moving (a stuck turn is a failure). At the end every phone
## that is still in the match must hold the identical log (also equal to the database) and fingerprint, and the match must be over.
## Configurations by seed % 10: 0 three phones + CPU, 1 four phones, 2 teams, 3 shared-phone seat, 4 Love, 5 CPUs of mixed level,
## 6 rich shop (simultaneous buys), 7 async only, 8 teams with a shared phone, 9 four phones with a CPU.
## Seeds are fixed; the 20 matches run in 5 waves of 4 concurrent matches. One seed: QA_CHAOS_SEED=7 with -gunit_test_name=test_chaos_single.

const TICK_SEC: float = 0.05
const MATCH_BUDGET_SEC: float = 150.0
const STUCK_SEC: float = 45.0
const LIVE_OFFSET_MS: int = 3500
const HARD_OFFSET_MS: int = 8000

var _stats: Dictionary = {"matches": 0, "entries": 0, "drops": 0, "gaps": 0, "leaves": 0, "messages": 0, "live_timeouts": 0, "async_timeouts": 0,
		"retries": 0, "failed_signals": 0}


func after_all() -> void:
	gut.p("QA chaos totals: %s" % JSON.stringify(_stats))
	await super.after_all()


# --- configuration -----------------------------------------------------------------------------------------------------------

## {seats, settings, joins (seat count of each guest phone), timers, live (bool)}
func _config(seed_value: int, rng: RandomNumberGenerator) -> Dictionary:
	var kind: int = seed_value % 10
	var level: Callable = func() -> int: return rng.randi_range(1, 4)
	var base: Dictionary = {"rounds": 1, "wind_max": rng.randi_range(0, 60), "start_money": 3000}
	var live_timers: Dictionary = NetLobby.timers(10, 1, "auto")
	match kind:
		0:
			return {"seats": [NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_human(), NetLobby.seat_cpu(level.call())], "settings": base, "joins": [1, 1], "timers": live_timers, "live": true}
		1:
			return {"seats": [NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_human(), NetLobby.seat_human()], "settings": base, "joins": [1, 1, 1], "timers": live_timers, "live": true}
		2:
			base["teams"] = [0, 1, 0, 1]
			base["friendly_fire"] = false
			return {"seats": [NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_cpu(level.call()), NetLobby.seat_cpu(level.call())], "settings": base, "joins": [1], "timers": live_timers, "live": true}
		3:
			return {"seats": [NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_human(), NetLobby.seat_human()], "settings": base, "joins": [2, 1], "timers": live_timers, "live": true}
		4:
			return {"seats": [NetLobby.seat_human(true), NetLobby.seat_human()], "settings": {"mode": 1}, "joins": [1], "timers": live_timers, "live": true}
		5:
			return {"seats": [NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_human(), NetLobby.seat_cpu(1), NetLobby.seat_cpu(4)], "settings": base, "joins": [1, 1], "timers": live_timers, "live": true}
		6:
			base["start_money"] = 20000
			return {"seats": [NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_human(), NetLobby.seat_cpu(level.call())], "settings": base, "joins": [1, 1], "timers": live_timers, "live": true}
		7:
			return {"seats": [NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_human(), NetLobby.seat_cpu(level.call())], "settings": base, "joins": [1, 1], "timers": NetLobby.timers(0, 1, "auto"), "live": false}
		8:
			base["teams"] = [0, 0, 1, 1]
			base["friendly_fire"] = true
			return {"seats": [NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_human(), NetLobby.seat_cpu(level.call())], "settings": base, "joins": [2], "timers": live_timers, "live": true}
		_:
			return {"seats": [NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_human(), NetLobby.seat_human(), NetLobby.seat_cpu(level.call())], "settings": base, "joins": [1, 1, 1], "timers": live_timers, "live": true}


# --- one phone -------------------------------------------------------------------------------------------------------------------

func _new_phone(label: String, session: NetSession) -> Dictionary:
	return {"label": label, "s": session, "m": null, "busy": false, "ready_at": 0, "left": false, "reopen_at": 0, "is_host": false}


func _arm(m: OnlineMatch, live: bool) -> void:
	m.debug_deadline_offset_ms = HARD_OFFSET_MS
	if live:
		m.debug_live_offset_ms = LIVE_OFFSET_MS
	m.heartbeat_interval_ms = 5000


func _open_phone(p: Dictionary, id: String, live: bool) -> bool:
	var m: OnlineMatch = await _open(p["s"] as NetSession, id)
	if m == null:
		return false
	_arm(m, live)
	p["m"] = m
	m.failed.connect(func(code: int, reason: String) -> void: _stats["failed_signals"] += 1; push_warning("chaos %s failed(%d, %s)" % [p["label"], code, reason]))
	return true


## One phone's player acts: an aim action, or a shop visit (sometimes with purchases) ended by READY. Returns the NetResult or null.
func _act(p: Dictionary, rng: RandomNumberGenerator, ctx: Dictionary) -> void:
	var m: OnlineMatch = p["m"]
	if m == null:
		return
	var moves: Array = _scripted_move(m)
	if moves.is_empty():
		return
	p["busy"] = true
	var t: Dictionary = m.turn_info()
	if (t["shop"] as bool) and rng.randf() < 0.6:
		var seat: int = (moves[0] as Dictionary)["tank"]
		var buys: Array[Dictionary] = AiPlayer.shop_actions(m.fork_state(), seat)
		var chosen: Array = []
		for b: Dictionary in buys:
			if chosen.size() >= 3:
				break
			chosen.append(b)
		var batch: Array = chosen + moves
		var r: NetResult = await m.submit_many(batch, 4.0)
		if not r.ok:
			# a purchase the state no longer allows (a timeout readied this seat first): fall back to the plain READY
			r = await m.submit_many(_scripted_move(m), 4.0)
		_note(ctx, p, r)
	else:
		var r2: NetResult = await m.submit_many(moves, 4.0)
		_note(ctx, p, r2)
	p["ready_at"] = Time.get_ticks_msec() + int(rng.randf_range(0.0, 700.0) if rng.randf() < 0.8 else rng.randf_range(2000.0, 6000.0))
	p["busy"] = false


func _note(ctx: Dictionary, p: Dictionary, r: NetResult) -> void:
	if r == null or r.ok:
		return
	# Losing a race, a timeout that already moved the turn on, a dropped connection: all legal outcomes of chaos. Anything else is logged.
	var tolerated: bool = r.code in [NetError.Code.STALE, NetError.Code.TIMEOUT, NetError.Code.OFFLINE, NetError.Code.PRECONDITION, NetError.Code.ILLEGAL_ACTION, NetError.Code.SERVER, NetError.Code.CLOSED]
	(ctx["log"] as Array).append("%s submit refused: %s%s" % [p["label"], str(r), "" if tolerated else "  (UNEXPECTED)"])
	if not tolerated:
		(ctx["problems"] as Array).append("%s submit failed unexpectedly: %s" % [p["label"], str(r)])


# --- the chaos -----------------------------------------------------------------------------------------------------------------

func _open_phones(phones: Array) -> Array:
	var out: Array = []
	for p: Dictionary in phones:
		if p["m"] != null and not p["left"]:
			out.append(p)
	return out


func _chaos_event(phones: Array, rng: RandomNumberGenerator, ctx: Dictionary, id: String) -> void:
	var open: Array = _open_phones(phones)
	if open.is_empty():
		return
	var roll: float = rng.randf()
	var p: Dictionary = open[rng.randi_range(0, open.size() - 1)]
	var m: OnlineMatch = p["m"]
	if roll < 0.30:
		m.debug_drop_streams(rng.randf_range(0.4, 4.0))
		_stats["drops"] += 1
		(ctx["log"] as Array).append("%s: streams dropped" % p["label"])
	elif roll < 0.55:
		m.send_message(rng.randi_range(0, 7))
		_stats["messages"] += 1
	elif roll < 0.72 and not (p["is_host"] as bool) and ctx["gaps_left"] > 0 and open.size() > 2:
		# a long gap: the phone closes its match, comes back later and must catch up
		ctx["gaps_left"] = (ctx["gaps_left"] as int) - 1
		m.close()
		p["m"] = null
		p["reopen_at"] = Time.get_ticks_msec() + rng.randi_range(5000, 11000)
		_stats["gaps"] += 1
		(ctx["log"] as Array).append("%s: closed for a gap" % p["label"])
		if rng.randf() < 0.5:
			# a phone that has been gone long enough for its heartbeat to be stale: no live skip is allowed for it, only the hard deadline
			var stale: NetResult = await _admin(HTTPClient.METHOD_PUT, "matches/%s/presence/%s" % [id, (p["s"] as NetSession).uid()], m.now_ms() - 120000)
			(ctx["log"] as Array).append("%s: heartbeat made stale (%s)" % [p["label"], str(stale.ok)])
	elif roll < 0.80 and not (p["is_host"] as bool) and ctx["leaves_left"] > 0 and open.size() > 2 and p["reopen_at"] == 0:
		# a player leaves mid-turn: their seats become CPU Normal and the others carry on
		ctx["leaves_left"] = (ctx["leaves_left"] as int) - 1
		p["left"] = true
		m.close()
		p["m"] = null
		_stats["leaves"] += 1
		(ctx["log"] as Array).append("%s: LEFT the match" % p["label"])
		var left: NetResult = await (p["s"] as NetSession).lobby.leave(id)
		if not left.ok:
			(ctx["problems"] as Array).append("leave failed: %s" % str(left))


## Cheap checks after every step. Returns "" or what went wrong.
func _check(phones: Array) -> String:
	var by_count: Dictionary = {}
	for p: Dictionary in _open_phones(phones):
		var m: OnlineMatch = p["m"]
		if m.is_disputed():
			return "%s is disputed: %s (index %d)" % [p["label"], m.replay.dispute_reason, m.replay.dispute_index]
		var key: int = m.replay.count
		var fp: String = m.replay.fingerprint()
		if by_count.has(key) and by_count[key] != fp:
			return "phones with %d entries disagree on the state (%s)" % [key, p["label"]]
		by_count[key] = fp
	return ""


func _progress(phones: Array) -> int:
	var best: int = 0
	for p: Dictionary in _open_phones(phones):
		best = maxi(best, (p["m"] as OnlineMatch).replay.count)
	return best


func _all_over(phones: Array) -> bool:
	for p: Dictionary in _open_phones(phones):
		if (p["m"] as OnlineMatch).status == NetProtocol.STATUS_PLAYING:
			return false
	return true


func _chaos(seed_value: int) -> void:
	if not _need_emulator():
		return
	var started: int = Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 13
	var cfg: Dictionary = _config(seed_value, rng)
	var live: bool = cfg["live"]
	var ctx: Dictionary = {"log": [], "problems": [], "gaps_left": 2, "leaves_left": 1 if rng.randf() < 0.6 else 0}
	var host: NetSession = await _phone("H%d" % seed_value, true)
	var phones: Array = [_new_phone("host", host)]
	(phones[0] as Dictionary)["is_host"] = true
	var made: NetResult = await host.lobby.create(NetLobby.settings(cfg["settings"] as Dictionary), cfg["seats"] as Array, cfg["timers"] as Dictionary)
	assert_true(made.ok, "create: %s" % str(made))
	if not made.ok:
		return
	var info: Dictionary = made.dict()
	var id: String = info["matchId"]
	var joins: Array = cfg["joins"]
	for j: int in range(joins.size()):
		var guest: NetSession = await _phone("G%d_%d" % [seed_value, j])
		var count: int = joins[j]
		var res: NetResult = await guest.lobby.join(info["code"] as String, count)
		assert_true(res.ok, "join %d: %s" % [j, str(res)])
		phones.append(_new_phone("guest%d" % j, guest))
	var go: NetResult = await host.lobby.start(id)
	assert_true(go.ok, "start: %s" % str(go))
	for p: Dictionary in phones:
		var ok: bool = await _open_phone(p, id, live)
		assert_true(ok, "open %s" % p["label"])
		if not ok:
			return

	var last_progress_at: int = Time.get_ticks_msec()
	var last_progress: int = 0
	var failure: String = ""
	var ticks: int = 0
	while Time.get_ticks_msec() - started < int(MATCH_BUDGET_SEC * 1000.0):
		ticks += 1
		var now: int = Time.get_ticks_msec()
		# phones that were away come back
		for p2: Dictionary in phones:
			if p2["m"] == null and not p2["left"] and p2["reopen_at"] != 0 and now >= (p2["reopen_at"] as int):
				p2["reopen_at"] = 0
				(ctx["log"] as Array).append("%s: reopened" % p2["label"])
				if not await _open_phone(p2, id, live):
					failure = "%s could not reopen" % p2["label"]
		if rng.randf() < 0.035:
			await _chaos_event(phones, rng, ctx, id)
		for p3: Dictionary in _open_phones(phones):
			if not (p3["busy"] as bool) and now >= (p3["ready_at"] as int) and not _scripted_move(p3["m"] as OnlineMatch).is_empty():
				_act(p3, rng, ctx)
		failure = failure if failure != "" else _check(phones)
		if failure != "":
			break
		var progress: int = _progress(phones)
		if progress != last_progress:
			last_progress = progress
			last_progress_at = now
		elif now - last_progress_at > int(STUCK_SEC * 1000.0) and not _all_over(phones):
			failure = "stuck: no new entry for %d s (turn %s)" % [STUCK_SEC, JSON.stringify(((_open_phones(phones)[0] as Dictionary)["m"] as OnlineMatch).turn_info())]
			break
		if _all_over(phones) and not _open_phones(phones).is_empty():
			break
		await get_tree().create_timer(TICK_SEC).timeout

	if failure == "" and not _all_over(phones):
		failure = "the match did not end within %d s (entries %d)" % [int(MATCH_BUDGET_SEC), _progress(phones)]
	# phones that were away at the end come back and must catch up too
	for p4: Dictionary in phones:
		if p4["m"] == null and not p4["left"]:
			if not await _open_phone(p4, id, live):
				failure = failure if failure != "" else "%s could not reopen at the end" % p4["label"]
	if failure == "":
		failure = await _final_checks(phones, id)
	for p5: Dictionary in _open_phones(phones):
		var m5: OnlineMatch = p5["m"]
		_stats["retries"] += m5.write_retries
		for e: Dictionary in m5.replay.entries:
			if e["kind"] == "timeout":
				if e.has("async"):
					_stats["async_timeouts"] += 1
				else:
					_stats["live_timeouts"] += 1
	_stats["matches"] += 1
	_stats["entries"] += _progress(phones)
	var problems: Array = ctx["problems"]
	if failure != "" or not problems.is_empty():
		var log: Array = ctx["log"]
		fail_test("chaos seed %d (config %d): %s %s\n  recent events: %s" % [seed_value, seed_value % 10, failure, str(problems), "\n    ".join(log.slice(maxi(0, log.size() - 25)))])
	else:
		gut.p("chaos seed %d ok: %d entries, %.0f s, drops %d gaps %d leaves %d" % [seed_value, _progress(phones), float(Time.get_ticks_msec() - started) / 1000.0, _stats["drops"], _stats["gaps"], _stats["leaves"]])


func _final_checks(phones: Array, id: String) -> String:
	var open: Array = _open_phones(phones)
	var reference: OnlineMatch = (open[0] as Dictionary)["m"]
	# every phone reaches the final count and state
	var all_in_step: Callable = func() -> bool:
		for p: Dictionary in open:
			var m: OnlineMatch = p["m"]
			if m.replay.count != reference.replay.count or m.status != NetProtocol.STATUS_OVER:
				return false
		return true
	var converged: bool = await _until(all_in_step, 30.0)
	if not converged:
		var seen: Array = []
		for p2: Dictionary in open:
			seen.append("%s:%d/%s" % [p2["label"], (p2["m"] as OnlineMatch).replay.count, (p2["m"] as OnlineMatch).status])
		return "phones did not converge on count and status over: %s" % str(seen)
	for p3: Dictionary in open:
		var m3: OnlineMatch = p3["m"]
		if m3.is_disputed():
			return "%s disputed at the end: %s" % [p3["label"], m3.replay.dispute_reason]
		if m3.replay.fingerprint() != reference.replay.fingerprint():
			return "%s ends in another state than the others" % p3["label"]
		if m3.replay.entries != reference.replay.entries:
			return "%s holds another log" % p3["label"]
		if not m3.replay.ended:
			return "%s: status over but the simulation did not end" % p3["label"]
	# the database holds exactly that log, and every reported fingerprint agrees
	var host: NetSession = (phones[0] as Dictionary)["s"]
	var db_log: NetResult = await host.db.get_value("matches/%s/actions" % id)
	var stored: Dictionary = NetJson.indexed(db_log.value)
	if stored.size() != reference.replay.count:
		return "database holds %d entries, phones %d" % [stored.size(), reference.replay.count]
	for i: int in range(reference.replay.count):
		if stored[i] != reference.replay.entries[i]:
			return "database entry %d differs from the replay" % i
	await get_tree().create_timer(0.8).timeout
	var fps: NetResult = await host.db.get_value("matches/%s/fp" % id)
	var table: Dictionary = NetJson.indexed(fps.value)
	for index: Variant in table.keys():
		var per: Dictionary = table[index] as Dictionary
		var vals: Array = per.values()
		for v: Variant in vals:
			if v != vals[0]:
				return "reported fingerprints differ at entry %s: %s" % [str(index), str(per)]
	return ""


## Several matches at once in this one process: the time goes into waiting (timeouts, gaps), not into computing.
func _wave(seeds: Array) -> void:
	var left: Array = [seeds.size()]
	for seed_value: Variant in seeds:
		_run_counted(seed_value as int, left)
	while (left[0] as int) > 0:
		await get_tree().create_timer(0.25).timeout


func _run_counted(seed_value: int, left: Array) -> void:
	await _chaos(seed_value)
	left[0] = (left[0] as int) - 1


func test_chaos_wave_1() -> void:
	await _wave([1, 6, 11, 16])


func test_chaos_wave_2() -> void:
	await _wave([2, 7, 12, 17])


func test_chaos_wave_3() -> void:
	await _wave([3, 8, 13, 18])


func test_chaos_wave_4() -> void:
	await _wave([4, 9, 14, 19])


func test_chaos_wave_5() -> void:
	await _wave([5, 10, 15, 20])


## Debugging aid: QA_CHAOS_SEED=7 tools/run_tests.sh --suite net -gselect=test_qa_chaos -gunit_test_name=test_chaos_single
func test_chaos_single() -> void:
	var seed_text: String = OS.get_environment("QA_CHAOS_SEED")
	if seed_text == "":
		pass_test("QA_CHAOS_SEED not set")
		return
	await _chaos(seed_text.to_int())


## Exploration: QA_CHAOS_SEEDS=21,22,23,24 runs those seeds as one wave (nothing happens when it is not set).
func test_chaos_extra_seeds() -> void:
	var text: String = OS.get_environment("QA_CHAOS_SEEDS")
	if text == "":
		pass_test("QA_CHAOS_SEEDS not set")
		return
	var seeds: Array = []
	for part: String in text.split(",", false):
		seeds.append(part.strip_edges().to_int())
	await _wave(seeds)
