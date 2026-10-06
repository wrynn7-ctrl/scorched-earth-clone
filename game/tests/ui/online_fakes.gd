class_name OnlineFakes
extends RefCounted
## Fakes for the online UI tests: a NetSession whose parts answer from memory (no network, no emulator), and an
## OnlineMatch that is driven by the test (`push_remote`, `submit_many` applies entries through the real NetReplay).
## Every fake records what the UI asked in `calls` ([{name, args}]) and answers from `replies` when a test scripts one
## (`replies["send_request"] = NetResult.failure(...)`), else with success.

const ME: String = "uidMe"
const OTHER: String = "uidOther"
const THIRD: String = "uidThird"
const DEFAULT_PROFILE: Dictionary = {"friendCode": "ABCD2345", "name": "ME", "nameHidden": false, "full": false, "protocol": 1}


## Scripted answers and the call log, shared by the fake parts of one session.
class FakeScript:
	extends RefCounted
	var calls: Array[Dictionary] = []
	var replies: Dictionary = {}

	func rec(method: String, args: Array = []) -> void:
		calls.append({"name": method, "args": args})

	func reply(method: String, default: Variant = null) -> NetResult:
		if replies.has(method):
			var r: Variant = replies[method]
			if r is Callable:
				return (r as Callable).call() as NetResult
			return r as NetResult
		return NetResult.success(default)

	func count(method: String) -> int:
		var n: int = 0
		for c: Dictionary in calls:
			if c["name"] == method:
				n += 1
		return n

	func last(method: String) -> Dictionary:
		for i: int in range(calls.size() - 1, -1, -1):
			if calls[i]["name"] == method:
				return calls[i]
		return {}


class FakeAccount:
	extends NetAccount
	var sc: FakeScript = null

	func _init(script: FakeScript, config: NetConfig, auth: NetAuth, clock: NetClock) -> void:
		super._init(config, auth, null, null, clock)
		sc = script

	func set_name(raw: String) -> NetResult:
		sc.rec("set_name", [raw])
		if sc.replies.has("set_name"):
			return sc.reply("set_name")
		var clean: String = NameFilter.clean(raw)
		if clean == "":
			return NetResult.failure(NetError.Code.NAME_REJECTED, "empty")
		if not NameFilter.is_allowed(clean):
			return NetResult.failure(NetError.Code.NAME_REJECTED, "blocked")
		profile["name"] = clean
		profile_changed.emit(profile)
		return NetResult.success(clean)

	func fetch_public(uid: String, _refresh: bool = false) -> NetResult:
		sc.rec("fetch_public", [uid])
		return NetResult.success({"uid": uid, "name": uid, "hidden": false, "display": uid.to_upper()})

	func delete_my_data() -> NetResult:
		sc.rec("delete_my_data")
		var r: NetResult = sc.reply("delete_my_data", {"deleted": true})
		if r.ok:
			profile = {}
		return r

	func link_google(_sign_in: GoogleSignIn) -> NetResult:
		sc.rec("link_google")
		var r: NetResult = sc.reply("link_google", {"email": "me@example.com"})
		if r.ok:
			_auth.anonymous = false
			_auth.email = "me@example.com"
		return r

	func restore_with_google(_sign_in: GoogleSignIn) -> NetResult:
		sc.rec("restore_with_google")
		return sc.reply("restore_with_google", {"email": "me@example.com"})

	func ensure_profile() -> NetResult:
		sc.rec("ensure_profile")
		return sc.reply("ensure_profile", profile)

	func bind_push(push: PushService) -> void:
		sc.rec("bind_push")
		_push = push

	func refresh_profile() -> NetResult:
		sc.rec("refresh_profile")
		return NetResult.success(profile)

	func verify_purchase(purchase_token: String) -> NetResult:
		sc.rec("verify_purchase", [purchase_token])
		var r: NetResult = sc.reply("verify_purchase", {"full": true})
		if r.ok:
			profile["full"] = true
			profile_changed.emit(profile)
		return r


class FakeFriends:
	extends NetFriends
	var sc: FakeScript = null
	var blocks: Array = []

	func _init(script: FakeScript) -> void:
		super._init(null, null, null, null)
		sc = script

	func send_request(code: String) -> NetResult:
		sc.rec("send_request", [code])
		return sc.reply("send_request", {"status": "sent", "name": "ANNA"})

	func request_by_uid(target_uid: String, match_id: String) -> NetResult:
		sc.rec("request_by_uid", [target_uid, match_id])
		return sc.reply("request_by_uid", {"status": "sent", "name": "ANNA"})

	func respond(from_uid: String, accept: bool) -> NetResult:
		sc.rec("respond", [from_uid, accept])
		var r: NetResult = sc.reply("respond", {"status": "accepted" if accept else "declined"})
		if r.ok:
			requests = requests.filter(func(e: Variant) -> bool: return (e as Dictionary).get("uid", "") != from_uid)
		return r

	func remove_friend(friend_uid: String) -> NetResult:
		sc.rec("remove_friend", [friend_uid])
		var r: NetResult = sc.reply("remove_friend", {"removed": true})
		if r.ok:
			friends = friends.filter(func(e: Variant) -> bool: return (e as Dictionary).get("uid", "") != friend_uid)
		return r

	func block(target_uid: String) -> NetResult:
		sc.rec("block", [target_uid])
		var r: NetResult = sc.reply("block", {"blocked": true})
		if r.ok:
			friends = friends.filter(func(e: Variant) -> bool: return (e as Dictionary).get("uid", "") != target_uid)
			if not blocks.has(target_uid):
				blocks.append(target_uid)
		return r

	func unblock(target_uid: String) -> NetResult:
		sc.rec("unblock", [target_uid])
		var r: NetResult = sc.reply("unblock", {"unblocked": true})
		if r.ok:
			blocks.erase(target_uid)
		return r

	func report(target_uid: String, reason: String = "offensive_name") -> NetResult:
		sc.rec("report", [target_uid, reason])
		return sc.reply("report", {"hidden": false, "duplicate": false})

	func list_friends() -> NetResult:
		sc.rec("list_friends")
		return sc.reply("list_friends", friends)

	func list_requests() -> NetResult:
		sc.rec("list_requests")
		return sc.reply("list_requests", requests)

	func list_blocks() -> NetResult:
		sc.rec("list_blocks")
		return sc.reply("list_blocks", blocks.duplicate())

	func list_invites() -> NetResult:
		sc.rec("list_invites")
		return sc.reply("list_invites", invites)

	func dismiss_invite(match_id: String) -> NetResult:
		sc.rec("dismiss_invite", [match_id])
		var r: NetResult = sc.reply("dismiss_invite")
		if r.ok:
			invites = invites.filter(func(e: Variant) -> bool: return (e as Dictionary).get("matchId", "") != match_id)
		return r

	func watch() -> void:
		sc.rec("friends_watch")

	func unwatch() -> void:
		pass


class FakeMatches:
	extends NetMatches
	var sc: FakeScript = null

	func _init(script: FakeScript) -> void:
		super._init(null, null)
		sc = script

	func refresh() -> NetResult:
		sc.rec("matches_refresh")
		return sc.reply("matches_refresh", list)

	func watch() -> void:
		sc.rec("matches_watch")

	func unwatch() -> void:
		pass

	func dismiss(match_id: String) -> NetResult:
		sc.rec("matches_dismiss", [match_id])
		var r: NetResult = sc.reply("matches_dismiss")
		if r.ok:
			list = list.filter(func(e: Variant) -> bool: return (e as Dictionary).get("matchId", "") != match_id)
		return r


## A lobby server in memory with the rules of `updateLobby` / `joinMatch` / `startMatch` that matter to the client.
class FakeLobby:
	extends NetLobby
	var sc: FakeScript = null
	var net_uid: String = ME
	var metas: Dictionary = {}
	var watching: String = ""

	func _init(script: FakeScript) -> void:
		super._init(null, null, null)
		sc = script

	func put_lobby(match_id: String, meta: Dictionary) -> void:
		metas[match_id] = meta

	func create(match_settings: Dictionary, seats: Array, match_timers: Dictionary = {}) -> NetResult:
		sc.rec("create", [match_settings, seats, match_timers])
		if sc.replies.has("create"):
			return sc.reply("create")
		var id: String = "m%d" % (metas.size() + 1)
		var built: Array = []
		for s: Variant in seats:
			var d: Dictionary = s as Dictionary
			if d.get("kind", "") == "cpu":
				built.append({"kind": "cpu", "level": d.get("level", 2), "name": "CPU %d" % (built.size() + 1)})
			elif d.get("mine", false) == true or (built.is_empty() and not _any_mine(seats)):
				built.append({"kind": "human", "uid": net_uid, "name": "ME"})
			else:
				built.append({"kind": "human"})
		metas[id] = {"hostUid": net_uid, "code": "ABC234", "status": "lobby", "protocol": NetProtocol.VERSION,
				"seats": built, "settings": _settings_for(match_settings, built), "timers": match_timers}
		return NetResult.success({"matchId": id, "code": "ABC234"})

	static func _any_mine(seats: Array) -> bool:
		for s: Variant in seats:
			if (s as Dictionary).get("mine", false) == true:
				return true
		return false

	func _settings_for(raw: Dictionary, seats: Array) -> Dictionary:
		var out: Dictionary = raw.duplicate(true)
		out["num_tanks"] = seats.size()
		var controllers: Array = []
		for s: Variant in seats:
			controllers.append((s as Dictionary).get("level", 2) if (s as Dictionary).get("kind", "") == "cpu" else 0)
		out["controllers"] = controllers
		return out

	func update(match_id: String, match_settings: Variant = null, seats: Variant = null, match_timers: Variant = null) -> NetResult:
		sc.rec("update", [match_id, match_settings, seats, match_timers])
		if sc.replies.has("update"):
			return sc.reply("update")
		var meta: Dictionary = metas[match_id]
		var next_seats: Array = LobbyModel.seats_of(meta)
		if seats != null:
			next_seats = []
			for spec: Variant in seats as Array:
				var d: Dictionary = spec as Dictionary
				if d.get("kind", "") == "cpu":
					next_seats.append({"kind": "cpu", "level": d.get("level", 2), "name": "CPU %d" % (next_seats.size() + 1)})
				elif str(d.get("uid", "")) != "":
					next_seats.append({"kind": "human", "uid": d["uid"], "name": _name_of(meta, str(d["uid"]))})
				elif d.get("mine", false) == true:
					next_seats.append({"kind": "human", "uid": net_uid, "name": "ME %d" % (next_seats.size() + 1)})
				else:
					next_seats.append({"kind": "human"})
		var settings: Dictionary = (meta["settings"] as Dictionary).duplicate(true)
		if match_settings != null:
			for k: Variant in (match_settings as Dictionary).keys():
				settings[k] = (match_settings as Dictionary)[k]
			if (settings.get("teams", []) as Array).is_empty():
				settings.erase("teams")
		var teams: Array = settings.get("teams", []) as Array
		if not teams.is_empty():
			var seen: int = 0
			for t: Variant in teams:
				if int(t) < 0 or int(t) > 3:
					return NetResult.failure(NetError.Code.INVALID, "bad_teams")
				seen |= 1 << int(t)
			if teams.size() != next_seats.size() or (seen & (seen - 1)) == 0:
				return NetResult.failure(NetError.Code.INVALID, "bad_teams")
		meta["seats"] = next_seats
		meta["settings"] = _settings_for(settings, next_seats)
		if match_timers != null:
			meta["timers"] = (match_timers as Dictionary).duplicate()
		_emit(match_id)
		return NetResult.success({"seats": next_seats})

	static func _name_of(meta: Dictionary, uid: String) -> String:
		for s: Variant in LobbyModel.seats_of(meta):
			if str((s as Dictionary).get("uid", "")) == uid:
				return str((s as Dictionary).get("name", "P"))
		return "P"

	func join(code: String, seat_count: int = 1, names: Array = []) -> NetResult:
		sc.rec("join", [code, seat_count, names])
		if sc.replies.has("join"):
			return sc.reply("join")
		for id: String in metas.keys():
			var meta: Dictionary = metas[id]
			if str(meta.get("code", "")) != code:
				continue
			var taken: Array = []
			var seats: Array = LobbyModel.seats_of(meta)
			for i: int in range(seats.size()):
				if LobbyModel.is_open(seats[i]) and taken.size() < seat_count:
					seats[i] = {"kind": "human", "uid": net_uid, "name": (names[taken.size()] if taken.size() < names.size() and names[taken.size()] != "" else "ME")}
					taken.append(i)
			if taken.size() < seat_count:
				return NetResult.failure(NetError.Code.EXHAUSTED, "match_full")
			meta["seats"] = seats
			_emit(id)
			return NetResult.success({"matchId": id, "seats": taken, "alreadyJoined": false})
		return NetResult.failure(NetError.Code.NOT_FOUND, "unknown_code")

	func leave(match_id: String) -> NetResult:
		sc.rec("leave", [match_id])
		return sc.reply("leave", {"status": "left"})

	func start(match_id: String) -> NetResult:
		sc.rec("start", [match_id])
		if sc.replies.has("start"):
			return sc.reply("start")
		var meta: Dictionary = metas[match_id]
		if LobbyModel.open_count(meta) > 0:
			return NetResult.failure(NetError.Code.PRECONDITION, "seats_not_filled")
		meta["status"] = NetProtocol.STATUS_PLAYING
		meta["seed"] = 4242
		(meta["settings"] as Dictionary)["seed"] = 4242
		_emit(match_id)
		return NetResult.success({"seed": 4242})

	func invite(friend_uid: String, match_id: String) -> NetResult:
		sc.rec("invite", [friend_uid, match_id])
		return sc.reply("invite", {"invited": true})

	func fetch_meta(match_id: String) -> NetResult:
		sc.rec("fetch_meta", [match_id])
		if sc.replies.has("fetch_meta"):
			return sc.reply("fetch_meta")
		if not metas.has(match_id):
			return NetResult.success(null)
		return NetResult.success((metas[match_id] as Dictionary).duplicate(true))

	func watch(match_id: String) -> void:
		sc.rec("lobby_watch", [match_id])
		watching = match_id
		_last_status = (metas[match_id] as Dictionary).get("status", "") if metas.has(match_id) else ""

	func unwatch() -> void:
		watching = ""

	## Pushes the stored lobby through the same signals the stream would.
	func _emit(match_id: String) -> void:
		if watching != match_id:
			return
		var meta: Dictionary = NetLobby.normalize_meta((metas[match_id] as Dictionary).duplicate(true))
		lobby_changed.emit(meta)
		var status: String = meta.get("status", "")
		if status != _last_status:
			_last_status = status
			if status == NetProtocol.STATUS_PLAYING:
				lobby_started.emit(meta)
			elif status == NetProtocol.STATUS_ABANDONED:
				lobby_abandoned.emit(meta)

	## Test: something changed in the lobby behind the client's back (a joiner, the host's edit).
	func remote_change(match_id: String, change: Callable) -> void:
		change.call(metas[match_id])
		_emit(match_id)


class FakeNet:
	extends NetSession
	var sc: FakeScript = null
	var start_result: NetResult = null
	var fake_friends: FakeFriends = null
	var fake_lobby: FakeLobby = null
	var fake_matches: FakeMatches = null
	var fake_account: FakeAccount = null
	var fake_match: OnlineMatch = null
	var open_result: NetResult = null
	var closed_count: int = 0

	func _init(uid: String = ME) -> void:
		sc = FakeScript.new()
		config = NetConfig.new()
		auth = NetAuth.new(config, http, "user://test_fake_net_auth.cfg")
		auth.uid = uid
		auth._refresh_token = "fake-refresh-token"
		clock.fixed_ms = 1000000000
		fake_account = FakeAccount.new(sc, config, auth, clock)
		fake_account.profile = DEFAULT_PROFILE.duplicate()
		account = fake_account
		fake_friends = FakeFriends.new(sc)
		friends = fake_friends
		fake_lobby = FakeLobby.new(sc)
		fake_lobby.net_uid = uid
		lobby = fake_lobby
		fake_matches = FakeMatches.new(sc)
		matches = fake_matches

	func start() -> NetResult:
		sc.rec("start")
		if start_result != null:
			return start_result
		if account.profile.is_empty():
			account.profile = DEFAULT_PROFILE.duplicate()
		auth._refresh_token = "fake-refresh-token"
		return NetResult.success(account.profile)

	func open_match(match_id: String) -> NetResult:
		sc.rec("open_match", [match_id])
		if open_result != null:
			return open_result
		if fake_match != null:
			return NetResult.success(fake_match)
		return NetResult.failure(NetError.Code.NOT_FOUND, "unknown_match")

	func close() -> void:
		closed_count += 1

	func uid() -> String:
		return auth.uid


## An OnlineMatch driven by the test: no network. `submit_many` plans the batch with the real NetReplay (CPU entries
## included), applies it and emits `entry_applied` like the real class; `push_remote` does the same for an entry
## "another player wrote".
class FakeMatch:
	extends OnlineMatch
	var sc: FakeScript = null
	var fail_next: NetResult = null
	var online_uids: Dictionary = {}
	var fixed_now: int = 1000000000
	var sent_messages: Array[Dictionary] = []
	var abandoned: bool = false
	var hold_submit: bool = false

	func setup(m: Dictionary, my_uid: String, script: FakeScript = null) -> void:
		sc = script if script != null else FakeScript.new()
		uid = my_uid
		meta = m
		match_id = "match1"
		replay = NetReplay.create(m)
		status = NetProtocol.STATUS_PLAYING
		connection = OnlineMatch.Connection.LIVE
		_open = true
		_refresh_my_seats()
		_set_stored_turn(replay.expected_turn())

	func _refresh_my_seats() -> void:
		my_seats = replay.seats_of(uid)

	## The stored `meta/turn` the way the backend keeps it, for the expected turn `want` ({tank, uid}).
	func _set_stored_turn(want: Dictionary) -> void:
		if want.is_empty():
			_turn_raw = {}
			return
		var live: int = int(replay.timers.get("liveSec", 0))
		var t: Dictionary = {"tank": want["tank"], "uid": want["uid"], "deadline": fixed_now + 72 * 3600000,
				"index": (_turn_raw.get("index", 0) as int) + 1}
		if live > 0 and (want["tank"] as int) >= 0 and want["uid"] != NetProtocol.UID_CPU:
			t["liveDeadline"] = fixed_now + live * 1000
		_turn_raw = t

	func now_ms() -> int:
		return fixed_now

	func is_online(player_uid: String) -> bool:
		return player_uid == uid or online_uids.get(player_uid, true) == true

	func submit(action: Dictionary, wait_online_sec: float = 0.0) -> NetResult:
		return await submit_many([action], wait_online_sec)

	func submit_many(actions: Array, _wait_online_sec: float = 0.0) -> NetResult:
		sc.rec("submit_many", [actions])
		if hold_submit:
			await Engine.get_main_loop().process_frame
		if fail_next != null:
			var f: NetResult = fail_next
			fail_next = null
			return f
		var first: Array[Dictionary] = []
		for a: Variant in actions:
			var d: Dictionary = Simulation.normalize_action(a as Dictionary)
			if not my_seats.has(d.get("tank", -1)):
				return NetResult.failure(NetError.Code.ILLEGAL_ACTION, "not_your_seat")
			first.append(d)
		var plan: Dictionary = replay.plan_batch(first)
		if not (plan["ok"] as bool):
			return NetResult.failure(NetError.Code.ILLEGAL_ACTION, (plan["err"] as String).trim_prefix("invalid_"))
		var base: int = replay.count
		for e: Dictionary in plan["entries"] as Array:
			_apply_and_emit(e, true, false)
		if plan["over"] as bool:
			status = NetProtocol.STATUS_OVER
			status_changed.emit(status)
		else:
			_set_stored_turn(plan["turn"] as Dictionary)
			turn_changed.emit(turn_info())
		return NetResult.success({"index": base, "entries": plan["entries"]})

	func _apply_and_emit(entry: Dictionary, by_me: bool, catch_up: bool) -> Dictionary:
		var r: Dictionary = replay.apply_entry(entry)
		r["catch_up"] = catch_up
		r["by_me"] = by_me
		r["fingerprint"] = ""
		entry_applied.emit(replay.count - 1, r)
		return r

	## Another player's entries arrive (with the CPU entries that follow them, like a real writer appends).
	func push_remote(entries: Array, catch_up: bool = false) -> void:
		for e: Variant in entries:
			_apply_and_emit(e as Dictionary, false, catch_up)
		var more: Dictionary = replay.pending_cpu_entry()
		while not more.is_empty() and not replay.ended and not replay.disputed:
			_apply_and_emit(more, false, catch_up)
			more = replay.pending_cpu_entry()
		_set_stored_turn(replay.expected_turn())
		if replay.ended:
			status = NetProtocol.STATUS_OVER
			status_changed.emit(status)
		turn_changed.emit(turn_info())

	func send_message(msg: int, seat: int = -1) -> NetResult:
		sent_messages.append({"msg": msg, "seat": seat})
		if fail_next != null:
			var f: NetResult = fail_next
			fail_next = null
			return f
		return NetResult.success()

	func abandon() -> NetResult:
		abandoned = true
		status = NetProtocol.STATUS_ABANDONED
		return NetResult.success()

	func set_connection_state(c: int) -> void:
		connection = c
		connection_changed.emit(c)

	func trigger_dispute(reason: String) -> void:
		replay.disputed = true
		replay.dispute_reason = reason
		disputed.emit(reason, replay.count)

	## A player left: their seat is a computer now.
	func replace_with_cpu(tank: int) -> void:
		var seat: Dictionary = (replay.seats[tank] as Dictionary).duplicate()
		replay.seats[tank] = {"kind": "cpu", "level": 2, "name": seat.get("name", "CPU")}
		_refresh_my_seats()
		seats_changed.emit(replay.seats)


# --- builders ---------------------------------------------------------------------------------------------------------

static func net(uid: String = ME) -> FakeNet:
	return FakeNet.new(uid)


static func human_seat(uid: String, seat_name: String) -> Dictionary:
	return {"kind": "human", "uid": uid, "name": seat_name}


static func cpu_seat(level: int = 2, seat_name: String = "CPU") -> Dictionary:
	return {"kind": "cpu", "level": level, "name": seat_name}


## A running match for `me` (the uid of this phone) with the given seats; settings default to a short, quiet match.
static func match_for(me: String, seats: Array, overrides: Dictionary = {}, timers: Dictionary = {}, seed_value: int = 4242) -> FakeMatch:
	var m: Dictionary = NetTestUtil.meta(seats, overrides, timers, seed_value)
	m["hostUid"] = ME
	var fm := FakeMatch.new()
	fm.setup(m, me)
	return fm


static func friend(uid: String, shown: String) -> Dictionary:
	return {"uid": uid, "name": shown, "display": shown, "since": 1}


static func request(uid: String, shown: String) -> Dictionary:
	return {"uid": uid, "name": shown, "at": 5}


static func invite(match_id: String, from_name: String, code: String = "XYZ789", mode: int = 0) -> Dictionary:
	return {"matchId": match_id, "fromUid": OTHER, "fromName": from_name, "at": 9, "code": code, "mode": mode}


static func match_entry(match_id: String, status: String, your_turn: bool, host: String, updated: int = 1) -> Dictionary:
	return {"matchId": match_id, "updated": updated, "yourTurn": your_turn, "status": status, "hostName": host}


## A lobby meta as the database keeps it.
static func lobby_meta(seats: Array, overrides: Dictionary = {}, host_uid: String = ME) -> Dictionary:
	var controllers: Array = []
	for s: Variant in seats:
		controllers.append((s as Dictionary).get("level", 2) if (s as Dictionary).get("kind", "") == "cpu" else 0)
	var settings: Dictionary = {"num_tanks": seats.size(), "rounds": 3, "wind_max": 100, "start_money": 10000,
			"mode": 0, "friendly_fire": true, "controllers": controllers, "full_unlocked": true, "seed": 0}
	for k: Variant in overrides.keys():
		settings[k] = overrides[k]
	return {"hostUid": host_uid, "code": "ABC234", "status": "lobby", "protocol": NetProtocol.VERSION,
			"seats": seats, "settings": settings, "timers": {"liveSec": 60, "asyncHours": 72, "asyncTimeout": "auto"}}
