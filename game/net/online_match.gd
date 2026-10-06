class_name OnlineMatch
extends RefCounted
## One open online match: the sync engine between the database and the simulation (docs/ARCHITECTURE.md sections
## 46, 47 and 51; the contract with the rules is in firebase/README.md "The action log in the rules").
##
## Lifecycle: `NetSession.open_match(id)` (or `open(net, id)`) -> play -> `close()`.
##
## What it does for you
##  * Keeps a NetReplay (the simulation state, `state`) in step with the log: it catches up on open, follows the live
##    stream, and catches up again after a dropped connection.
##  * `submit(action)` simulates the action on a copy, then writes the entry plus the CPU entries that follow (up to the
##    next human turn, the end of the round or match, or 16 entries) and the new `meta/turn`, in ONE update. When the
##    database refuses because somebody else wrote first, it refetches, replays and retries if the action is still legal.
##  * Resolves "needs resolve" turns and continues CPU turns when a batch hit the cap (any member does it), writes
##    `timeout` entries after a deadline, keeps a presence heartbeat (every 30 s), reports fingerprints at turn ends and
##    compares them with the other players', and relays quick messages.
##  * Marks the match disputed (play stops, `disputed` is emitted once) when an entry is illegal, the stored turn
##    disagrees with the simulation, history changed, or two players' fingerprints differ.
##
## Signals (all on the main thread, from the scene tree's frame loop):
##   entry_applied(index, result)   every log entry, in order. `result` = NetReplay.apply_entry's result plus
##                                  `catch_up` (true while replaying history after open or a reconnect: skip animations),
##                                  `by_me` (we wrote it) and `fingerprint` ("" unless it ended a turn and was checked).
##                                  `result.steps` is the timeline for playback: [{action, events}].
##   turn_changed(turn)             see turn_info()
##   status_changed(status)         "playing" | "over" | "abandoned"
##   presence_changed(uid, online)  another player's heartbeat went stale or came back
##   message_received(seat, msg, uid)   a quick message (msg 0..NetProtocol.MSG_COUNT-1)
##   seats_changed(seats)           a player left (their seat is now a CPU)
##   connection_changed(connection) Connection.LIVE / RECONNECTING / OFFLINE / CLOSED
##   disputed(reason, index)        stop playing; the host may abandon()
##   failed(code, reason)           a background write (resolve, timeout) failed for a reason the player may care about
##   opened(), closed()
##
## Shared phone: `my_seats` holds every seat of this account; submit() accepts an action for any of them.

signal opened()
signal closed()
signal entry_applied(index: int, result: Dictionary)
signal turn_changed(turn: Dictionary)
signal status_changed(status: String)
signal presence_changed(uid: String, online: bool)
signal message_received(seat: int, msg: int, uid: String)
signal seats_changed(seats: Array)
signal connection_changed(connection: int)
signal disputed(reason: String, index: int)
signal failed(code: int, reason: String)

enum Connection { LIVE, RECONNECTING, OFFLINE, CLOSED }

const TICK_SEC: float = 0.5
## Reconnecting for this long counts as offline.
const OFFLINE_AFTER_MS: int = 20000
const WRITE_ATTEMPTS: int = 4
## Slack before writing a timeout, so latency never makes the rules see it as early.
const TIMEOUT_MARGIN_MS: int = 400
## How long a stored turn may disagree with the simulation before the match is called disputed.
const TURN_MISMATCH_MS: int = 2500
## Gap between the first writer and the next one, so members do not all race for the same job.
const STAGGER_MS: int = 250
const HOLDER_EXTRA_MS: int = 1500
const ACTION_KINDS_AIM: Array[String] = ["fire", "move", "use_item", "pass"]
const ACTION_KINDS_SHOP: Array[String] = ["buy", "sell", "ready"]

var match_id: String = ""
var uid: String = ""
var meta: Dictionary = {}
var replay: NetReplay = null
## The seats (tank indexes) this account controls. Several means a shared phone.
var my_seats: Array[int] = []
var status: String = ""
var connection: int = Connection.RECONNECTING
## uid -> {tank:int} etc. is not kept; presence is uid -> last heartbeat (server ms).
var presence: Dictionary = {}
## index -> fingerprint this client computed at the end of a turn (tests and the debug overlay compare them).
var fingerprints: Dictionary = {}
## How many writes the database refused because somebody else wrote first (each was followed by a refetch and a retry).
var write_retries: int = 0

## How often the presence heartbeat is written (NetProtocol.HEARTBEAT_SEC; tests shorten it).
var heartbeat_interval_ms: int = int(NetProtocol.HEARTBEAT_SEC * 1000.0)
## Tests only: when not null, new turns get `deadline = now + this` (negative = already due) and `liveDeadline = now + that`.
var debug_deadline_offset_ms: Variant = null
var debug_live_offset_ms: Variant = null

var _net: NetSession = null
var _open: bool = false
var _turn_raw: Dictionary = {}
var _server_count: int = 0
var _pending: Dictionary = {}
var _writing: bool = false
var _streams: Array[NetStream] = []
var _meta_stream: NetStream = null
var _actions_stream: NetStream = null
var _presence_streams: Dictionary = {}
var _online_flags: Dictionary = {}
var _fp_remote: Dictionary = {}
var _fp_sent: Dictionary = {}
var _msgs_seen: Dictionary = {}
var _msgs_baseline: bool = false
var _last_msg_ms: int = -1000000
var _last_beat_ms: int = -1000000
var _offline_since: int = 0
var _drive_since: int = 0
var _drive_block_until: int = 0
var _timeout_since: int = 0
var _timeout_block_until: int = 0
var _turn_bad_since: int = 0
var _mine_flag: bool = false
var _dispute_emitted: bool = false

signal _unlocked()


# --- opening and closing -----------------------------------------------------------------------------------------------

## Reads the match, replays the log and starts the streams. `value` = this OnlineMatch.
func open(net: NetSession, id: String) -> NetResult:
	_net = net
	match_id = id
	uid = net.auth.uid
	var meta_res: NetResult = await net.db.get_value("matches/%s/meta" % id)
	if not meta_res.ok:
		return meta_res
	if typeof(meta_res.value) != TYPE_DICTIONARY:
		return NetResult.failure(NetError.Code.NOT_FOUND, "unknown_match")
	var m: Dictionary = NetLobby.normalize_meta(meta_res.dict())
	var protocol: int = m.get("protocol", 0)
	if protocol != NetProtocol.VERSION:
		return NetResult.failure(NetError.Code.PROTOCOL_MISMATCH, "protocol_mismatch",
				{"hostProtocol": protocol, "yourProtocol": NetProtocol.VERSION})
	var st: String = m.get("status", "")
	if st == NetProtocol.STATUS_LOBBY:
		return NetResult.failure(NetError.Code.NOT_STARTED, "not_started")
	var r: NetReplay = NetReplay.create(m)
	if r == null:
		return NetResult.failure(NetError.Code.BAD_RESPONSE, NetReplay.meta_error(m))
	replay = r
	meta = m
	status = st
	_turn_raw = m.get("turn", {}) as Dictionary if typeof(m.get("turn", null)) == TYPE_DICTIONARY else {}
	_server_count = m.get("actionCount", 0)
	_refresh_my_seats()
	_open = true
	await _send_heartbeat()  # also tells us the server's clock before we write any deadline
	var actions_res: NetResult = await net.db.get_value("matches/%s/actions" % id, NetDb.from_index(0))
	if not actions_res.ok:
		_open = false
		return actions_res
	_ingest_snapshot(actions_res.value)
	_start_streams()
	_run_loop()
	opened.emit()
	return NetResult.success(self)


func close() -> void:
	if not _open and connection == Connection.CLOSED:
		return
	_open = false
	for s: NetStream in _streams:
		if is_instance_valid(s):
			s.close()
	_streams.clear()
	for s2: Variant in _presence_streams.values():
		if is_instance_valid(s2):
			(s2 as NetStream).close()
	_presence_streams.clear()
	_set_connection(Connection.CLOSED)
	closed.emit()


func is_open() -> bool:
	return _open


## The authoritative state after every entry received so far. The simulation is only ever changed by this class.
var state: MatchState:
	get:
		return replay.state


## A private copy of the state for previews and the shop (the game UI can try things on it freely).
func fork_state() -> MatchState:
	return replay.state.duplicate_state()


func is_disputed() -> bool:
	return replay != null and replay.disputed


func seats() -> Array:
	return replay.seats if replay != null else []


func seat_name(tank: int) -> String:
	var s: Array = seats()
	if tank < 0 or tank >= s.size():
		return ""
	var d: Dictionary = s[tank] as Dictionary
	return d.get("name", "CPU" if d.get("kind", "") == "cpu" else "")


# --- the turn ------------------------------------------------------------------------------------------------------------

## The stored turn, decorated for the UI: {tank, uid, deadline, liveDeadline?, index, mine, shop, resolving, cpu, name}.
##  tank >= 0   that seat's aim turn; `mine` when this account holds it
##  shop        the shop phase (tank -2): every human seat may buy and ready; `mine` while one of mine is not ready
##  resolving   a CPU turn or "needs resolve" is being worked on (some member's client writes it within moments)
func turn_info() -> Dictionary:
	var t: Dictionary = _turn_raw.duplicate()
	var tank: int = t.get("tank", NetProtocol.TURN_NEEDS_RESOLVE)
	var holder: String = str(t.get("uid", ""))
	t["shop"] = tank == NetProtocol.TURN_SHOP
	t["resolving"] = tank == NetProtocol.TURN_NEEDS_RESOLVE or holder == NetProtocol.UID_CPU
	t["cpu"] = holder == NetProtocol.UID_CPU
	t["mine"] = _is_mine(tank)
	t["name"] = seat_name(tank) if tank >= 0 else ""
	return t


func _is_mine(tank: int) -> bool:
	if tank >= 0:
		return my_seats.has(tank)
	if tank == NetProtocol.TURN_SHOP and replay != null:
		for s: int in my_seats:
			if not replay.state.tanks[s].ready and replay.state.phase == SimConstants.PHASE_SHOP:
				return true
	return false


func is_my_turn() -> bool:
	return status == NetProtocol.STATUS_PLAYING and not is_disputed() and _is_mine(_turn_raw.get("tank", -1))


## Server-time estimate in ms (for countdowns: `turn.deadline - now_ms()`).
func now_ms() -> int:
	return _net.clock.now_ms()


## Seconds left on the live timer of the current turn (-1 when there is none).
func live_seconds_left() -> float:
	if not _turn_raw.has("liveDeadline"):
		return -1.0
	return maxf(0.0, float((_turn_raw["liveDeadline"] as int) - now_ms()) / 1000.0)


func is_online(player_uid: String) -> bool:
	if player_uid == uid:
		return true
	return presence.has(player_uid) and now_ms() - (presence[player_uid] as int) < NetProtocol.PRESENCE_FRESH_MS


# --- submitting ----------------------------------------------------------------------------------------------------------

## Plays one action for one of `my_seats`. See submit_many.
func submit(action: Dictionary, wait_online_sec: float = 0.0) -> NetResult:
	return await submit_many([action], wait_online_sec)


## Plays several actions in one update: shop actions only (buy, sell, ready) or a single aim action (fire, move,
## use_item, pass). `value` = {index (of the first entry), entries (everything written, CPU entries included)}.
## Failure codes: ILLEGAL_ACTION (reason = the simulation's key, e.g. not_your_turn, bad_phase, funds), STALE (it was legal
## when chosen but the log moved on; the reason says why not any more), DISPUTED, CLOSED, PRECONDITION `match_over`,
## OFFLINE/TIMEOUT (nothing was written, or the answer was lost: submitting again is safe).
## `wait_online_sec` > 0 keeps retrying while offline for that long (the "actions queued" behaviour).
func submit_many(actions: Array, wait_online_sec: float = 0.0) -> NetResult:
	if not _open:
		return NetResult.failure(NetError.Code.CLOSED, "closed")
	if replay.disputed:
		return NetResult.failure(NetError.Code.DISPUTED, replay.dispute_reason)
	if status != NetProtocol.STATUS_PLAYING:
		return NetResult.failure(NetError.Code.PRECONDITION, "match_over")
	var first: Array[Dictionary] = []
	var shape: String = _check_shape(actions, first)
	if shape != "":
		return NetResult.failure(NetError.Code.ILLEGAL_ACTION, shape)
	await _lock()
	var out: NetResult = await _submit_locked(first, wait_online_sec)
	_unlock()
	return out


func _check_shape(actions: Array, out: Array[Dictionary]) -> String:
	if actions.is_empty():
		return "no_action"
	var aim: bool = false
	for a: Variant in actions:
		if typeof(a) != TYPE_DICTIONARY:
			return "bad_action"
		var d: Dictionary = Simulation.normalize_action(a as Dictionary)
		var kind: String = str(d.get("kind", ""))
		if kind in ACTION_KINDS_AIM:
			aim = true
		elif not kind in ACTION_KINDS_SHOP:
			return "unknown_kind"
		if not d.has("tank") or typeof(d["tank"]) != TYPE_INT or not my_seats.has(d["tank"] as int):
			return "not_your_seat"
		out.append(d)
	if aim and actions.size() > 1:
		return "one_aim_action_per_update"
	if not aim:
		for d2: Dictionary in out:
			if not str(d2["kind"]) in ACTION_KINDS_SHOP:
				return "mixed_kinds"
	return ""


func _submit_locked(first: Array[Dictionary], wait_online_sec: float) -> NetResult:
	var waited: float = 0.0
	var attempt: int = 0
	var synced: bool = false
	while attempt < WRITE_ATTEMPTS:
		if not _open:
			return NetResult.failure(NetError.Code.CLOSED, "closed")
		if replay.disputed:
			return NetResult.failure(NetError.Code.DISPUTED, replay.dispute_reason)
		if status != NetProtocol.STATUS_PLAYING:
			return NetResult.failure(NetError.Code.PRECONDITION, "match_over")
		if _needs_resolve() or replay.count < _server_count:
			await _catch_up_and_resolve()
		var plan: Dictionary = replay.plan_batch(first)
		if not (plan["ok"] as bool) and not synced:
			# Maybe we are simply behind (a dropped connection): look at the log once before saying no.
			synced = true
			await sync_now()
			continue
		if not (plan["ok"] as bool):
			var why: String = (plan["err"] as String).trim_prefix("invalid_")
			return NetResult.failure(NetError.Code.ILLEGAL_ACTION if attempt == 0 else NetError.Code.STALE, why)
		var base: int = replay.count
		var res: NetResult = await _commit(plan)
		if res.ok:
			return NetResult.success({"index": base, "entries": plan["entries"]})
		if res.is_transient():
			if waited < wait_online_sec:
				await NetHttp.wait_seconds(1.0)
				waited += 1.0
				await sync_now()
				if _landed(first, base):
					return NetResult.success({"index": base, "entries": first})
				continue
			return res
		if res.code != NetError.Code.PERMISSION:
			return res
		# Refused: somebody else wrote first (or it is no longer our turn). Look at the log again.
		attempt += 1
		write_retries += 1
		await sync_now()
		if _landed(first, base):
			return NetResult.success({"index": base, "entries": first})
	return NetResult.failure(NetError.Code.STALE, "contention")


## True when the entries we tried to write are in the log at `base` (a lost answer, or an identical retry that raced).
func _landed(first: Array[Dictionary], base: int) -> bool:
	if replay.count < base + first.size():
		return false
	for i: int in range(first.size()):
		if replay.entries[base + i] != first[i]:
			return false
	return true


func _needs_resolve() -> bool:
	var tank: int = _turn_raw.get("tank", -1)
	return tank == NetProtocol.TURN_NEEDS_RESOLVE or str(_turn_raw.get("uid", "")) == NetProtocol.UID_CPU


## Brings the log up to date and carries out a pending resolve (the lock is already held by the caller).
func _catch_up_and_resolve() -> void:
	await sync_now()
	if _needs_resolve() and _server_count == replay.count:
		var plan: Dictionary = replay.plan_batch([])
		if plan["ok"] as bool:
			await _commit(plan)
			await sync_now()


## Writes `plan` as one multi-path update. On success the entries are applied locally at once (the stream's copies
## are recognised by index and ignored).
func _commit(plan: Dictionary) -> NetResult:
	var base: int = replay.count
	var entries: Array = plan["entries"] as Array
	var update: Dictionary = _build_update(plan, base)
	if update.is_empty():
		return NetResult.success()
	var res: NetResult = await _net.db.patch("matches/%s" % match_id, update)
	if not res.ok:
		return res
	_mine_flag = true
	for i: int in range(entries.size()):
		_receive(base + i, entries[i] as Dictionary, false, i == entries.size() - 1)
	_mine_flag = false
	if entries.size() > 0:
		_server_count = maxi(_server_count, base + entries.size())
	if update.has("meta/turn"):
		_set_turn(update["meta/turn"] as Dictionary)
	if update.has("meta/status"):
		_set_status(update["meta/status"] as String)
	return res


func _build_update(plan: Dictionary, base: int) -> Dictionary:
	var update: Dictionary = {}
	var entries: Array = plan["entries"] as Array
	for i: int in range(entries.size()):
		update["actions/%d" % (base + i)] = entries[i]
	if not entries.is_empty():
		update["meta/actionCount"] = base + entries.size()
	if plan["over"] as bool:
		if not entries.is_empty():
			update["meta/status"] = NetProtocol.STATUS_OVER
	elif _turn_must_change(plan):
		update["meta/turn"] = _make_turn(plan["turn"] as Dictionary)
	return update


func _turn_must_change(plan: Dictionary) -> bool:
	var want: Dictionary = plan["turn"] as Dictionary
	if want.is_empty():
		return false
	if plan.get("turn_changed", false) == true:
		return true
	return _turn_raw.get("tank", -99) != want["tank"] or str(_turn_raw.get("uid", "")) != (want["uid"] as String)


## The `meta/turn` value for an expected turn {tank, uid}: deadlines from the server clock, index + 1.
func _make_turn(want: Dictionary) -> Dictionary:
	var now: int = now_ms()
	var tank: int = want["tank"]
	var timers: Dictionary = replay.timers
	var hours: int = timers.get("asyncHours", 72)
	var deadline: int = now + hours * 3600000
	if debug_deadline_offset_ms != null:
		deadline = now + (debug_deadline_offset_ms as int)
	var t: Dictionary = {"tank": tank, "uid": want["uid"], "deadline": deadline, "index": (_turn_raw.get("index", 0) as int) + 1}
	var live_sec: int = timers.get("liveSec", 0)
	var live_ok: bool = tank >= 0 and want["uid"] != NetProtocol.UID_CPU
	if live_ok and (live_sec > 0 or debug_live_offset_ms != null):
		t["liveDeadline"] = now + (debug_live_offset_ms as int if debug_live_offset_ms != null else live_sec * 1000)
	return t


# --- messages ----------------------------------------------------------------------------------------------------------

## Sends quick message `msg` (0..MSG_COUNT-1) as `seat` (default: the first of my seats). Failure codes: RATE_LIMITED
## (one per 3 s; checked here first and by the rules), INVALID, ILLEGAL_ACTION `not_your_seat`.
func send_message(msg: int, seat: int = -1) -> NetResult:
	if not _open:
		return NetResult.failure(NetError.Code.CLOSED, "closed")
	if msg < 0 or msg >= NetProtocol.MSG_COUNT:
		return NetResult.failure(NetError.Code.INVALID, "bad_msg")
	var use_seat: int = seat if seat >= 0 else (my_seats[0] if not my_seats.is_empty() else -1)
	if use_seat < 0 or not my_seats.has(use_seat):
		return NetResult.failure(NetError.Code.ILLEGAL_ACTION, "not_your_seat")
	var now: int = now_ms()
	if now - _last_msg_ms < NetProtocol.MSG_INTERVAL_MS:
		return NetResult.failure(NetError.Code.RATE_LIMITED, "rate_limited")
	_last_msg_ms = now
	var key: String = "m%013d_%04x" % [now, randi() & 0xffff]
	var update: Dictionary = {
		"msgs/" + key: {"uid": uid, "seat": use_seat, "msg": msg, "at": NetDb.server_timestamp()},
		"lastMsg/" + uid: NetDb.server_timestamp(),
	}
	var res: NetResult = await _net.db.patch("matches/%s" % match_id, update)
	if not res.ok and res.code == NetError.Code.PERMISSION:
		return NetResult.failure(NetError.Code.RATE_LIMITED, "rate_limited")
	return res


## The host gives the match up (status abandoned). Anyone else gets PERMISSION.
func abandon() -> NetResult:
	return await _net.db.put("matches/%s/meta/status" % match_id, NetProtocol.STATUS_ABANDONED)


# --- syncing ---------------------------------------------------------------------------------------------------------------

## Re-reads meta and the log from where we are (used after a refused write and after a reconnect).
func sync_now() -> void:
	var m: NetResult = await _net.db.get_value("matches/%s/meta" % match_id)
	if m.ok and typeof(m.value) == TYPE_DICTIONARY:
		_on_meta(m.value)
	var a: NetResult = await _net.db.get_value("matches/%s/actions" % match_id, NetDb.from_index(replay.count))
	if a.ok:
		_ingest_snapshot(a.value)


func _ingest_snapshot(value: Variant) -> void:
	var idx: Dictionary = NetJson.indexed(value)
	var keys: Array = idx.keys()
	keys.sort()
	for i: int in range(keys.size()):
		if typeof(idx[keys[i]]) == TYPE_DICTIONARY:
			_receive(keys[i] as int, idx[keys[i]] as Dictionary, true, i == keys.size() - 1)


## Takes entry `index`: applies it when it is the next one, remembers it when it is early, checks it when we have it.
func _receive(index: int, entry: Dictionary, catch_up: bool, last_of_batch: bool) -> void:
	if replay.disputed:
		return
	if index < replay.count:
		if replay.entries[index] != entry:
			_dispute("history_changed", index)
		return
	if index > replay.count:
		_pending[index] = entry
		return
	_apply_one(index, entry, catch_up, last_of_batch and _pending.is_empty())
	while _pending.has(replay.count) and not replay.disputed:
		var next_index: int = replay.count
		var next_entry: Dictionary = _pending[next_index] as Dictionary
		_pending.erase(next_index)
		_apply_one(next_index, next_entry, catch_up, last_of_batch and _pending.is_empty())


func _apply_one(index: int, entry: Dictionary, catch_up: bool, report_fp: bool) -> void:
	var result: Dictionary = replay.apply_entry(entry)
	if not (result["ok"] as bool):
		_dispute(result["err"] as String, index)
		return
	result["catch_up"] = catch_up
	result["by_me"] = _mine_flag
	result["fingerprint"] = ""
	if (result["turn_ended"] as bool) and (report_fp or not catch_up):
		var fp: String = replay.fingerprint()
		result["fingerprint"] = fp
		fingerprints[index] = fp
		_report_fingerprint(index, fp)
		_compare_fingerprints(index)
	entry_applied.emit(index, result)


func _dispute(reason: String, index: int) -> void:
	if replay.dispute_reason == "":
		replay.disputed = true
		replay.dispute_reason = reason
		replay.dispute_index = index
	if not _dispute_emitted:
		_dispute_emitted = true
		disputed.emit(replay.dispute_reason, replay.dispute_index)


# --- fingerprints ------------------------------------------------------------------------------------------------------

func _report_fingerprint(index: int, fp: String) -> void:
	if my_seats.is_empty() or _fp_sent.has(index):
		return
	_fp_sent[index] = true
	var res: NetResult = await _net.db.put("matches/%s/fp/%d/%s" % [match_id, index, uid], fp)
	if not res.ok and res.code != NetError.Code.PERMISSION:
		_fp_sent.erase(index)


func _on_fp(v: Variant) -> void:
	_fp_remote.clear()
	if typeof(v) != TYPE_DICTIONARY:
		return
	for k: Variant in (v as Dictionary).keys():
		if str(k).is_valid_int() and typeof((v as Dictionary)[k]) == TYPE_DICTIONARY:
			_fp_remote[str(k).to_int()] = (v as Dictionary)[k]
	for index: Variant in _fp_remote.keys():
		_compare_fingerprints(index as int)


func _compare_fingerprints(index: int) -> void:
	if not fingerprints.has(index) or not _fp_remote.has(index):
		return
	var theirs: Dictionary = _fp_remote[index] as Dictionary
	for other: Variant in theirs.keys():
		if str(other) != uid and str(theirs[other]) != (fingerprints[index] as String):
			_dispute("fingerprint", index)
			return


# --- meta, turn, status, seats ------------------------------------------------------------------------------------------

func _on_meta(v: Variant) -> void:
	if typeof(v) != TYPE_DICTIONARY:
		return
	var m: Dictionary = NetLobby.normalize_meta(v as Dictionary)
	meta = m
	if m.has("actionCount"):
		_server_count = maxi(_server_count, m["actionCount"] as int)
	var seat_list: Array = m.get("seats", []) as Array
	if not seat_list.is_empty() and seat_list != replay.seats:
		replay.set_seats(seat_list)
		_refresh_my_seats()
		seats_changed.emit(seat_list)
		_sync_presence_streams()
	if typeof(m.get("turn", null)) == TYPE_DICTIONARY:
		_set_turn(m["turn"] as Dictionary)
	_set_status(m.get("status", status))


func _set_turn(t: Dictionary) -> void:
	if t == _turn_raw:
		return
	# An older turn (a late event) must not replace a newer one we wrote ourselves.
	if (t.get("index", 0) as int) < (_turn_raw.get("index", 0) as int):
		return
	_turn_raw = t
	turn_changed.emit(turn_info())


func _set_status(s: String) -> void:
	if s != "" and s != status:
		status = s
		status_changed.emit(s)


func _refresh_my_seats() -> void:
	my_seats = replay.seats_of(uid)


# --- streams --------------------------------------------------------------------------------------------------------------

func _start_streams() -> void:
	var db: NetDb = _net.db
	_meta_stream = db.stream("matches/%s/meta" % match_id)
	_meta_stream.value_changed.connect(_on_meta)
	_meta_stream.connected.connect(_on_stream_state)
	_meta_stream.disconnected.connect(_on_stream_state)
	_actions_stream = db.stream("matches/%s/actions" % match_id, Callable(self, "_actions_params"), false)
	_actions_stream.event_received.connect(_on_actions_event)
	_actions_stream.connected.connect(_on_stream_state)
	_actions_stream.disconnected.connect(_on_stream_state)
	var fp_stream: NetStream = db.stream("matches/%s/fp" % match_id)
	fp_stream.value_changed.connect(_on_fp)
	var msg_stream: NetStream = db.stream("matches/%s/msgs" % match_id, NetDb.last_n(5), false)
	msg_stream.event_received.connect(_on_msgs_event)
	_streams = [_meta_stream, _actions_stream, fp_stream, msg_stream]
	_sync_presence_streams()


func _actions_params() -> Dictionary:
	return NetDb.from_index(replay.count)


func _on_actions_event(kind: String, path: String, data: Variant) -> void:
	if not _open:
		return
	if path == "/":
		if kind == "put":
			_ingest_snapshot(data)
		elif typeof(data) == TYPE_DICTIONARY:
			var keys: Array = (data as Dictionary).keys()
			keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a).to_int() < str(b).to_int())
			for i: int in range(keys.size()):
				if typeof((data as Dictionary)[keys[i]]) == TYPE_DICTIONARY:
					_receive(str(keys[i]).to_int(), (data as Dictionary)[keys[i]] as Dictionary, false, i == keys.size() - 1)
		return
	var parts: PackedStringArray = path.split("/", false)
	if parts.size() == 1 and parts[0].is_valid_int() and typeof(data) == TYPE_DICTIONARY:
		_receive(parts[0].to_int(), data as Dictionary, false, true)


func _on_msgs_event(kind: String, path: String, data: Variant) -> void:
	if path == "/":
		if typeof(data) == TYPE_DICTIONARY:
			for key: Variant in (data as Dictionary).keys():
				_handle_message(str(key), (data as Dictionary)[key], kind == "put")
		if kind == "put":
			_msgs_baseline = true
		return
	var parts: PackedStringArray = path.split("/", false)
	if parts.size() == 1:
		_handle_message(parts[0], data, false)


func _handle_message(key: String, entry: Variant, from_snapshot: bool) -> void:
	if _msgs_seen.has(key) or typeof(entry) != TYPE_DICTIONARY:
		return
	_msgs_seen[key] = true
	var d: Dictionary = entry as Dictionary
	if from_snapshot and not _msgs_baseline:
		return  # what was said before we opened is history
	if from_snapshot and now_ms() - (d.get("at", 0) as int) > 10000:
		return
	message_received.emit(d.get("seat", 0) as int, d.get("msg", 0) as int, str(d.get("uid", "")))


## One presence stream per other human player.
func _sync_presence_streams() -> void:
	for seat: Variant in replay.seats:
		var other: String = (seat as Dictionary).get("uid", "")
		if other == "" or other == uid or _presence_streams.has(other):
			continue
		var s: NetStream = _net.db.stream("matches/%s/presence/%s" % [match_id, other])
		s.value_changed.connect(_on_presence.bind(other))
		s.denied.connect(func(_why: String) -> void: _presence_streams.erase(other))
		_presence_streams[other] = s


func _on_presence(v: Variant, other: String) -> void:
	if typeof(v) == TYPE_INT:
		presence[other] = v
		_refresh_presence(now_ms())


func _refresh_presence(now: int) -> void:
	for other: Variant in presence.keys():
		var online: bool = now - (presence[other] as int) < NetProtocol.PRESENCE_FRESH_MS
		if _online_flags.get(other, null) != online:
			_online_flags[other] = online
			presence_changed.emit(str(other), online)


func _on_stream_state() -> void:
	var live: bool = _meta_stream != null and _actions_stream != null and _meta_stream.is_connected_now and _actions_stream.is_connected_now
	if live:
		_offline_since = 0
		_set_connection(Connection.LIVE)
	else:
		if _offline_since == 0:
			_offline_since = now_ms()
		if connection == Connection.LIVE:
			_set_connection(Connection.RECONNECTING)


func _set_connection(c: int) -> void:
	if c != connection:
		connection = c
		connection_changed.emit(c)


## Tests: cuts every stream and keeps them down for `hold_sec` (the match keeps playing elsewhere meanwhile).
func debug_drop_streams(hold_sec: float = 0.05) -> void:
	for s: NetStream in _streams:
		if is_instance_valid(s):
			s.drop(hold_sec)
	for s2: Variant in _presence_streams.values():
		if is_instance_valid(s2):
			(s2 as NetStream).drop(hold_sec)


# --- the housekeeping loop ---------------------------------------------------------------------------------------------

func _run_loop() -> void:
	while _open:
		await NetHttp.wait_seconds(TICK_SEC)
		if not _open:
			break
		_tick()


func _tick() -> void:
	var now: int = now_ms()
	if now - _last_beat_ms >= heartbeat_interval_ms:
		_send_heartbeat()
	_refresh_presence(now)
	if connection == Connection.RECONNECTING and _offline_since > 0 and now - _offline_since > OFFLINE_AFTER_MS:
		_set_connection(Connection.OFFLINE)
	_check_turn(now)
	_maybe_drive(now)
	_maybe_timeout(now)


func _send_heartbeat() -> void:
	_last_beat_ms = now_ms()
	var res: NetResult = await _net.db.put("matches/%s/presence/%s" % [match_id, uid], NetDb.server_timestamp())
	if res.ok and typeof(res.value) == TYPE_INT:
		_net.clock.sync_to(res.value as int)  # the database answers with the timestamp it stored


## The stored turn must agree with the simulation once we are caught up; a short grace covers the moment between
## the log and the turn arriving as separate events.
func _check_turn(now: int) -> void:
	if replay.disputed or status != NetProtocol.STATUS_PLAYING or replay.count != _server_count or _turn_raw.is_empty():
		_turn_bad_since = 0
		return
	var why: String = replay.check_turn(_turn_raw)
	if why == "":
		_turn_bad_since = 0
	elif _turn_bad_since == 0:
		_turn_bad_since = now
	elif now - _turn_bad_since > TURN_MISMATCH_MS:
		_dispute(why, replay.count)


func _can_write() -> bool:
	return _open and not _writing and not replay.disputed and status == NetProtocol.STATUS_PLAYING \
			and replay.count == _server_count and not my_seats.is_empty()


func _rank() -> int:
	return my_seats[0] if not my_seats.is_empty() else 0


## "Needs resolve", a CPU turn left by a batch that hit the cap, or a shop with CPUs that have not shopped: any member
## writes the next batch of CPU entries (after a small stagger, so the members do not all try at once).
func _maybe_drive(now: int) -> void:
	if not _can_write() or now < _drive_block_until:
		return
	var tank: int = _turn_raw.get("tank", 0)
	var needs: bool = tank == NetProtocol.TURN_NEEDS_RESOLVE or str(_turn_raw.get("uid", "")) == NetProtocol.UID_CPU \
			or (tank == NetProtocol.TURN_SHOP and not replay.pending_cpu_entry().is_empty())
	if not needs or _turn_raw.is_empty():
		_drive_since = 0
		return
	if _drive_since == 0:
		_drive_since = now
	if now - _drive_since < _rank() * STAGGER_MS:
		return
	_drive_since = 0
	_drive()


func _drive() -> void:
	await _lock()
	if _can_write_locked():
		var plan: Dictionary = replay.plan_batch([])
		if not (plan["ok"] as bool):
			_dispute(plan["err"] as String, replay.count)
		else:
			var res: NetResult = await _commit(plan)
			if not res.ok:
				_drive_block_until = now_ms() + 2000
				if res.code == NetError.Code.PERMISSION:
					await sync_now()  # somebody else did it
				elif not res.is_transient():
					failed.emit(res.code, res.reason)
	_unlock()


func _can_write_locked() -> bool:
	return _open and not replay.disputed and status == NetProtocol.STATUS_PLAYING and replay.count == _server_count


## After a deadline any member writes the `timeout` entry (section 52): `async: 1` after the hard deadline (the AI plays, or
## the match ends), a plain one for a live skip after the live deadline while the holder's heartbeat is fresh.
func _maybe_timeout(now: int) -> void:
	if not _can_write() or now < _timeout_block_until or _turn_raw.is_empty():
		return
	var tank: int = _turn_raw.get("tank", -1)
	if tank == NetProtocol.TURN_NEEDS_RESOLVE or str(_turn_raw.get("uid", "")) == NetProtocol.UID_CPU:
		return
	var deadline: int = _turn_raw.get("deadline", 0)
	var hard: bool = deadline > 0 and now > deadline + TIMEOUT_MARGIN_MS
	var live: bool = false
	if not hard and tank >= 0 and _turn_raw.has("liveDeadline"):
		live = now > (_turn_raw["liveDeadline"] as int) + TIMEOUT_MARGIN_MS and is_online(str(_turn_raw.get("uid", "")))
	if not hard and not live:
		_timeout_since = 0
		return
	if _timeout_since == 0:
		_timeout_since = now
	var wait: int = _rank() * STAGGER_MS + (HOLDER_EXTRA_MS if my_seats.has(tank) else 0)
	if now - _timeout_since < wait:
		return
	_timeout_since = 0
	_write_timeout(_timeout_tank(tank), hard)


## The seat a timeout entry names: the turn's tank, or in the shop the first human seat that is not ready.
func _timeout_tank(tank: int) -> int:
	if tank >= 0:
		return tank
	for t: TankState in replay.state.tanks:
		if not t.ready and not replay.seat_is_cpu(t.id):
			return t.id
	return -1


func _write_timeout(tank: int, hard_deadline: bool) -> void:
	if tank < 0:
		_timeout_block_until = now_ms() + 5000
		return
	await _lock()
	if _can_write_locked():
		var entry: Dictionary = {"kind": "timeout", "tank": tank}
		if hard_deadline:
			entry["async"] = 1
		var plan: Dictionary = replay.plan_batch([entry])
		if not (plan["ok"] as bool):
			_timeout_block_until = now_ms() + 3000
		else:
			var res: NetResult = await _commit(plan)
			if not res.ok:
				_timeout_block_until = now_ms() + 2000
				if res.code == NetError.Code.PERMISSION:
					await sync_now()
				elif not res.is_transient():
					failed.emit(res.code, res.reason)
	_unlock()


# --- write lock --------------------------------------------------------------------------------------------------------

func _lock() -> void:
	while _writing:
		await _unlocked
	_writing = true


func _unlock() -> void:
	_writing = false
	_unlocked.emit()
