extends GutTest
## Base class of the emulator integration tests (test_it_*.gd). They need the Firebase emulators, which
## `tools/run_tests.sh --suite net` starts (it sets CRATERLINE_NET_EMULATOR=1). Without them every test is marked pending,
## so `--suite all` and plain GUT runs stay green.
##
## Each simulated phone is a NetSession with its own sign-in file, all inside this one Godot process.

const SHORT_WAIT: float = 8.0
const LONG_WAIT: float = 40.0

var _sessions: Array[NetSession] = []
var _matches: Array[OnlineMatch] = []


func _emulator_on() -> bool:
	return OS.get_environment("CRATERLINE_NET_EMULATOR") == "1"


## Call first in every test: `if not _need_emulator(): return`.
func _need_emulator() -> bool:
	if _emulator_on():
		return true
	pending("needs the Firebase emulators: run tools/run_tests.sh --suite net")
	return false


## The match loops notice `close()` on their next half-second tick; let them finish so nothing is left hanging at exit.
func after_all() -> void:
	await get_tree().create_timer(0.8).timeout


func after_each() -> void:
	for m: OnlineMatch in _matches:
		m.close()
	_matches.clear()
	for s: NetSession in _sessions:
		s.close()
		if FileAccess.file_exists(s.auth.store_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(s.auth.store_path))
	_sessions.clear()


## A signed-in phone with a profile and a name.
func _phone(label: String, full: bool = false) -> NetSession:
	var path: String = "user://net_it_%s_%d.cfg" % [label, randi()]
	var s: NetSession = NetSession.create(NetConfig.from_environment(), path)
	_sessions.append(s)
	var r: NetResult = await s.start()
	assert_true(r.ok, "start %s: %s" % [label, str(r)])
	if full:
		var f: NetResult = await s.functions.call_function("testSetFull", {"uid": s.uid()})
		assert_true(f.ok, "testSetFull: %s" % str(f))
		await s.account.ensure_profile()
	var n: NetResult = await s.account.set_name(label)
	assert_true(n.ok, "name: %s" % str(n))
	return s


func _befriend(a: NetSession, b: NetSession) -> void:
	var sent: NetResult = await a.friends.send_request(b.account.friend_code())
	assert_true(sent.ok, "send_request: %s" % str(sent))
	var acc: NetResult = await b.friends.respond(a.uid(), true)
	assert_true(acc.ok, "respond: %s" % str(acc))


## Creates a lobby as `host`, has `guests` join by code, starts it. Returns {matchId, code, seed}.
func _start_match(host: NetSession, guests: Array, settings: Dictionary, seats: Array, timers: Dictionary = {}) -> Dictionary:
	var made: NetResult = await host.lobby.create(settings, seats, timers)
	assert_true(made.ok, "create: %s" % str(made))
	if not made.ok:
		return {}
	var info: Dictionary = made.dict()
	for g: Variant in guests:
		var j: NetResult = await (g as NetSession).lobby.join(info["code"] as String)
		assert_true(j.ok, "join: %s" % str(j))
	var started: NetResult = await host.lobby.start(info["matchId"] as String)
	assert_true(started.ok, "start: %s" % str(started))
	info["seed"] = started.dict().get("seed", 0)
	return info


func _open(s: NetSession, match_id: String) -> OnlineMatch:
	var r: NetResult = await s.open_match(match_id)
	assert_true(r.ok, "open_match: %s" % str(r))
	if not r.ok:
		return null
	var m: OnlineMatch = r.value as OnlineMatch
	_matches.append(m)
	return m


## Waits (polling) until `cond` is true or `seconds` pass. `cond` may be a coroutine (use await inside it).
func _until(cond: Callable, seconds: float = SHORT_WAIT) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var ok: bool = await cond.call()
		if ok:
			return true
		await get_tree().create_timer(0.05).timeout
	var last: bool = await cond.call()
	return last


## The same database write the Admin SDK would do (the emulator accepts the bearer token "owner" and skips the rules).
func _admin(method: int, path: String, body: Variant = null) -> NetResult:
	var cfg: NetConfig = NetConfig.from_environment()
	var url: String = "%s/%s.json?ns=%s" % [cfg.database_url, path, cfg.database_namespace]
	var http := NetHttp.new()
	return await http.json_request(method, url, body, PackedStringArray(["Authorization: Bearer owner"]))


# --- playing ------------------------------------------------------------------------------------------------------------

## What a (scripted) player does now with the seats of `m`: the next action for an aim turn (AiPlayer's choice, any legal
## action will do), or `ready` for every unready seat in the shop. Returns [] when it is not this phone's move.
func _scripted_move(m: OnlineMatch) -> Array:
	if not m.is_my_turn() or m.is_disputed():
		return []
	var t: Dictionary = m.turn_info()
	if t["shop"] as bool:
		var out: Array = []
		for seat: int in m.my_seats:
			if not m.state.tanks[seat].ready:
				out.append({"kind": "ready", "tank": seat})
		return out
	var tank: int = t["tank"]
	return [AiPlayer.next_action(m.state, tank)]


## One scripted step for `m`: submits what _scripted_move says. Returns the NetResult, or null when it was not its move.
func _step(m: OnlineMatch) -> NetResult:
	var move: Array = _scripted_move(m)
	if move.is_empty():
		return null
	return await m.submit_many(move, 5.0)


## Every phone plays its own turns until the match is over (or `seconds` pass).
func _play_out(ms: Array, seconds: float = 120.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	var busy: Dictionary = {}
	while Time.get_ticks_msec() < deadline:
		var over: bool = true
		for m: OnlineMatch in ms:
			if m.status == NetProtocol.STATUS_PLAYING and not m.is_disputed():
				over = false
		if over:
			return true
		for m: OnlineMatch in ms:
			if busy.get(m, false) == true:
				continue
			if not _scripted_move(m).is_empty():
				busy[m] = true
				_step_and_release(m, busy)
		await get_tree().create_timer(0.02).timeout
	return false


func _step_and_release(m: OnlineMatch, busy: Dictionary) -> void:
	var r: NetResult = await _step(m)
	if r != null and not r.ok:
		push_warning("scripted step failed: %s" % str(r))
	await get_tree().create_timer(0.05).timeout
	busy[m] = false


## Both phones replayed the same log: same count, same state, same fingerprints at every turn end, and the database holds
## equal fingerprints from every member.
func _assert_in_sync(ms: Array, match_id: String, members: Array) -> void:
	var first: OnlineMatch = ms[0]
	for m: OnlineMatch in ms:
		assert_false(m.is_disputed(), "no dispute: %s" % m.replay.dispute_reason)
		assert_eq(m.replay.count, first.replay.count, "same number of entries")
		assert_eq(m.replay.fingerprint(), first.replay.fingerprint(), "same final state")
		for index: Variant in first.fingerprints.keys():
			if m.fingerprints.has(index):
				assert_eq(m.fingerprints[index], first.fingerprints[index], "fingerprint at entry %s" % str(index))
	var shared: int = 0
	for index: Variant in first.fingerprints.keys():
		var all_have: bool = true
		for m: OnlineMatch in ms:
			all_have = all_have and m.fingerprints.has(index)
		if all_have:
			shared += 1
	assert_gt(shared, 2, "several turn ends were checked on every phone")
	var reported: NetResult = null
	for _try: int in range(100):
		reported = await (members[0] as NetSession).db.get_value("matches/%s/fp" % match_id)
		var most: int = 0
		var table: Dictionary = NetJson.indexed(reported.value)
		for index: Variant in table.keys():
			most = maxi(most, (table[index] as Dictionary).size())
		if most > 1 and table.size() >= first.fingerprints.size():
			break
		await get_tree().create_timer(0.1).timeout
	var compared: int = 0
	var final_table: Dictionary = NetJson.indexed(reported.value)
	for index: Variant in final_table.keys():
		var per: Dictionary = final_table[index] as Dictionary
		if per.size() > 1:
			compared += 1
			var vals: Array = per.values()
			for v: Variant in vals:
				assert_eq(v, vals[0], "database fingerprints agree at %s" % str(index))
	assert_gt(compared, 0, "the database holds fingerprints from more than one member")
