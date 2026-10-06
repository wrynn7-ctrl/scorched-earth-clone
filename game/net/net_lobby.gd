class_name NetLobby
extends RefCounted
## Creating, joining and starting a match (docs/ARCHITECTURE.md section 45, firebase/README.md "Callable functions").
##
## Typical host flow:
##   var r := await lobby.create(NetLobby.settings({"rounds": 3}), [NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_cpu(2)])
##   lobby.watch(r.dict()["matchId"])                    # lobby_changed(meta) on every join / leave / settings change
##   await lobby.invite(friend_uid, match_id)            # or share the code
##   await lobby.start(match_id)                         # when every human seat is filled; then open an OnlineMatch
## Typical guest flow: `await lobby.join(code)`, `lobby.watch(match_id)`, wait for `lobby_started`.

signal lobby_changed(meta: Dictionary)
signal lobby_started(meta: Dictionary)
signal lobby_abandoned(meta: Dictionary)

var _auth: NetAuth = null
var _db: NetDb = null
var _fn: NetFunctions = null
var _stream: NetStream = null
var _last_status: String = ""


func _init(auth: NetAuth, db: NetDb, functions: NetFunctions) -> void:
	_auth = auth
	_db = db
	_fn = functions


# --- argument builders (no network) ---------------------------------------------------------------------------------

## A human seat. `mine` marks a seat played on the host's own phone (shared phone); other human seats stay open for joiners.
static func seat_human(mine: bool = false, seat_name: String = "") -> Dictionary:
	var s: Dictionary = {"kind": "human"}
	if mine:
		s["mine"] = true
	if seat_name != "":
		s["name"] = seat_name
	return s


## A computer seat, level 1..4 (SimConstants.CTRL_EASY..CTRL_EXPERT).
static func seat_cpu(level: int = SimConstants.CTRL_NORMAL, seat_name: String = "") -> Dictionary:
	var s: Dictionary = {"kind": "cpu", "level": clampi(level, SimConstants.CTRL_EASY, SimConstants.CTRL_EXPERT)}
	if seat_name != "":
		s["name"] = seat_name
	return s


## Settings for createMatch with defaults filled in; `overrides` may hold rounds, wind_max, start_money, mode, teams
## (Array of 0..3 per seat), friendly_fire, theme. The server derives controllers and num_tanks from the seats.
static func settings(overrides: Dictionary = {}) -> Dictionary:
	var s: Dictionary = {"rounds": 3, "wind_max": SimConstants.WIND_MAX, "start_money": SimConstants.DEFAULT_START_MONEY,
			"mode": SimConstants.MODE_STANDARD, "friendly_fire": true}
	for k: Variant in overrides.keys():
		s[k] = overrides[k]
	return s


## Timers for createMatch: liveSec 0 (no live timer) or 10..600, asyncHours 1..168, asyncTimeout "auto" | "end".
static func timers(live_sec: int = 60, async_hours: int = 72, async_timeout: String = "auto") -> Dictionary:
	return {"liveSec": live_sec, "asyncHours": async_hours, "asyncTimeout": async_timeout}


# --- calls ---------------------------------------------------------------------------------------------------------

## Full owners only (reason full_required). `value` = {matchId, code}.
func create(match_settings: Dictionary, seats: Array, match_timers: Dictionary = {}) -> NetResult:
	var data: Dictionary = {"settings": match_settings, "seats": seats}
	if not match_timers.is_empty():
		data["timers"] = match_timers
	return await _fn.call_function("createMatch", data)


## Host only, lobby only. Pass only what changes. `value` = {seats}.
func update(match_id: String, match_settings: Variant = null, seats: Variant = null, match_timers: Variant = null) -> NetResult:
	var data: Dictionary = {"matchId": match_id}
	if match_settings != null:
		data["settings"] = match_settings
	if seats != null:
		data["seats"] = seats
	if match_timers != null:
		data["timers"] = match_timers
	return await _fn.call_function("updateLobby", data)


## Joins by 6-character code (any case; spaces and hyphens ignored). `seat_count` > 1 takes several seats for a shared
## phone. `value` = {matchId, seats: [index], alreadyJoined}. Reasons: bad_code, unknown_code, match_full,
## not_enough_seats, not_joinable, protocol_mismatch (code PROTOCOL_MISMATCH, details {hostProtocol, yourProtocol}).
func join(code: String, seat_count: int = 1, names: Array = []) -> NetResult:
	var normalized: String = DeepLinks.normalize_code(code)
	if normalized == "":
		return NetResult.failure(NetError.Code.INVALID, "bad_code")
	var data: Dictionary = {"code": normalized, "seatCount": seat_count}
	if not names.is_empty():
		data["names"] = names
	return await _fn.call_function("joinMatch", data)


func leave(match_id: String) -> NetResult:
	return await _fn.call_function("leaveMatch", {"matchId": match_id})


## Host only. `value` = {seed}. Reasons: seats_not_filled, not_in_lobby, not_host.
func start(match_id: String) -> NetResult:
	return await _fn.call_function("startMatch", {"matchId": match_id})


func invite(friend_uid: String, match_id: String) -> NetResult:
	return await _fn.call_function("invite", {"friendUid": friend_uid, "matchId": match_id})


## One-shot read of the match meta (members only).
func fetch_meta(match_id: String) -> NetResult:
	return await _db.get_value("matches/%s/meta" % match_id)


# --- watching the lobby --------------------------------------------------------------------------------------------

## Streams the match meta: `lobby_changed(meta)` on every change, `lobby_started` when status becomes playing and
## `lobby_abandoned` when the host (or the housekeeping) abandoned it. One watch at a time.
func watch(match_id: String) -> void:
	unwatch()
	_last_status = ""
	_stream = _db.stream("matches/%s/meta" % match_id)
	_stream.value_changed.connect(_on_meta)


func unwatch() -> void:
	if _stream != null and is_instance_valid(_stream):
		_stream.close()
	_stream = null


func _on_meta(v: Variant) -> void:
	if typeof(v) != TYPE_DICTIONARY:
		return
	var meta: Dictionary = normalize_meta(v as Dictionary)
	lobby_changed.emit(meta)
	var status: String = meta.get("status", "")
	if status != _last_status:
		_last_status = status
		if status == NetProtocol.STATUS_PLAYING:
			lobby_started.emit(meta)
		elif status == NetProtocol.STATUS_ABANDONED:
			lobby_abandoned.emit(meta)


## The meta as the UI wants it: `seats` is a real Array (the stream cache keeps it keyed by index).
static func normalize_meta(meta: Dictionary) -> Dictionary:
	var out: Dictionary = meta.duplicate(true)
	if out.has("seats"):
		out["seats"] = NetJson.as_list(out["seats"])
	if out.has("settings") and typeof(out["settings"]) == TYPE_DICTIONARY:
		var s: Dictionary = out["settings"] as Dictionary
		for key: String in ["controllers", "teams"]:
			if s.has(key):
				s[key] = NetJson.as_list(s[key])
	return out
