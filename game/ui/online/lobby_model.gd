class_name LobbyModel
extends RefCounted
## The rules of an online lobby as plain functions (ARCHITECTURE sections 45 and 48), so the lobby screen stays thin and
## every decision is testable without a scene: who is host, which seats are open, whether START is allowed (and if not,
## why), and how a host edit becomes the `seats` / `settings` / `timers` of an `updateLobby` call.
##
## A `meta` here is what NetLobby.normalize_meta gives: {hostUid, code, status, seats: [..], settings, timers}. Seats are
## {kind: "human", uid?, name?} (no uid = open, waiting for a joiner) or {kind: "cpu", level, name}.

const LIVE_PRESETS: Array[int] = [30, 60, 120]
const ASYNC_PRESETS: Array[int] = [24, 72]
const ASYNC_TIMEOUTS: Array[String] = ["auto", "end"]
const ROUND_CHOICES: Array[int] = [1, 3, 5, 10, 20]
const MONEY_CHOICES: Array[int] = [5000, 10000, 25000]
const WIND_CHOICES: Array[int] = [0, 40, 70, 100]
const MIN_SEATS: int = SimConstants.MIN_TANKS
const MAX_SEATS: int = SimConstants.MAX_TANKS


static func seats_of(meta: Dictionary) -> Array:
	return NetJson.as_list(meta.get("seats", []))


static func settings_of(meta: Dictionary) -> Dictionary:
	var s: Variant = meta.get("settings", {})
	return s as Dictionary if typeof(s) == TYPE_DICTIONARY else {}


static func is_host(meta: Dictionary, uid: String) -> bool:
	return uid != "" and meta.get("hostUid", "") == uid


static func is_love(meta: Dictionary) -> bool:
	return settings_of(meta).get("mode", 0) == SimConstants.MODE_LOVE


static func is_cpu(seat: Variant) -> bool:
	return typeof(seat) == TYPE_DICTIONARY and (seat as Dictionary).get("kind", "") == "cpu"


static func is_open(seat: Variant) -> bool:
	if typeof(seat) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = seat
	return d.get("kind", "") == "human" and str(d.get("uid", "")) == ""


static func open_count(meta: Dictionary) -> int:
	var n: int = 0
	for s: Variant in seats_of(meta):
		if is_open(s):
			n += 1
	return n


static func human_count(meta: Dictionary) -> int:
	var n: int = 0
	for s: Variant in seats_of(meta):
		if not is_cpu(s):
			n += 1
	return n


static func cpu_count(meta: Dictionary) -> int:
	return seats_of(meta).size() - human_count(meta)


## The seat indexes held by `uid` (several = a shared phone).
static func seats_held_by(meta: Dictionary, uid: String) -> Array[int]:
	var out: Array[int] = []
	var seats: Array = seats_of(meta)
	for i: int in range(seats.size()):
		var d: Dictionary = seats[i] as Dictionary
		if uid != "" and str(d.get("uid", "")) == uid:
			out.append(i)
	return out


## Whether `uid` has a seat in the lobby.
static func is_member(meta: Dictionary, uid: String) -> bool:
	return not seats_held_by(meta, uid).is_empty()


# --- teams ----------------------------------------------------------------------------------------------------------

## The teams of the lobby as one value per seat (TeamStyle.NONE where there are none).
static func teams_of(meta: Dictionary) -> PackedInt32Array:
	var n: int = seats_of(meta).size()
	var out := PackedInt32Array()
	var raw: Array = NetJson.as_list(settings_of(meta).get("teams", []))
	for i: int in range(n):
		var v: int = int(raw[i]) if i < raw.size() else TeamStyle.NONE
		out.append(v if TeamStyle.is_team(v) else TeamStyle.NONE)
	return out


static func teams_on(teams: PackedInt32Array) -> bool:
	for t: int in teams:
		if t != TeamStyle.NONE:
			return true
	return false


## "" (usable: no teams, or every seat has one and at least two are used), "need_all" or "need_two". The same rule as the
## local setup screen (MatchSettings.teams_error).
static func teams_error(teams: PackedInt32Array) -> String:
	if not teams_on(teams):
		return ""
	if teams.has(TeamStyle.NONE):
		return "need_all"
	return "need_two" if MatchSettings.teams_error(teams, teams.size()) != "" else ""


## What to send as `settings.teams`: the list when it is usable, an empty list (no teams) otherwise.
static func teams_param(teams: PackedInt32Array) -> Array:
	var out: Array = []
	if teams_on(teams) and teams_error(teams) == "":
		for t: int in teams:
			out.append(t)
	return out


## Resizes a team list to `n` seats (new seats get no team).
static func fit_teams(teams: PackedInt32Array, n: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i: int in range(n):
		out.append(teams[i] if i < teams.size() else TeamStyle.NONE)
	return out


# --- START ----------------------------------------------------------------------------------------------------------

## Whether the host may press START: {ok, reason}. Reasons: "not_host", "open_seats" (a human seat waits for a joiner),
## "need_all", "need_two" (the teams), "too_few". The reason is the key the screen turns into a hint.
static func start_check(meta: Dictionary, uid: String, teams: PackedInt32Array) -> Dictionary:
	if not is_host(meta, uid):
		return {"ok": false, "reason": "not_host"}
	if seats_of(meta).size() < MIN_SEATS:
		return {"ok": false, "reason": "too_few"}
	if open_count(meta) > 0:
		return {"ok": false, "reason": "open_seats"}
	var err: String = teams_error(teams)
	if err != "":
		return {"ok": false, "reason": err}
	return {"ok": true, "reason": ""}


# --- host edits -> updateLobby ---------------------------------------------------------------------------------------

## The `seats` argument for the lobby as it is now: held seats by uid (the server carries them over), open seats as plain
## human seats, CPUs with their level.
static func seat_specs(meta: Dictionary) -> Array:
	var out: Array = []
	for s: Variant in seats_of(meta):
		var d: Dictionary = s as Dictionary
		if is_cpu(d):
			out.append(NetLobby.seat_cpu(d.get("level", SimConstants.CTRL_NORMAL) as int))
		elif str(d.get("uid", "")) != "":
			out.append({"kind": "human", "uid": str(d["uid"])})
		else:
			out.append(NetLobby.seat_human())
	return out


## The specs with a CPU of `level` added at the end (unchanged when the table is full or the lobby is Love).
static func add_cpu(meta: Dictionary, level: int) -> Array:
	var out: Array = seat_specs(meta)
	if out.size() < MAX_SEATS and not is_love(meta):
		out.append(NetLobby.seat_cpu(level))
	return out


## The specs with an open human seat added.
static func add_human(meta: Dictionary, mine: bool = false) -> Array:
	var out: Array = seat_specs(meta)
	if out.size() < MAX_SEATS and not is_love(meta):
		out.append(NetLobby.seat_human(mine))
	return out


## The specs without seat `index`: only a CPU or an open human seat can go (a held seat never leaves this way), and
## never below the minimum.
static func remove_seat(meta: Dictionary, index: int) -> Array:
	var seats: Array = seats_of(meta)
	var out: Array = seat_specs(meta)
	if index < 0 or index >= seats.size() or out.size() <= MIN_SEATS or is_love(meta):
		return out
	var d: Dictionary = seats[index] as Dictionary
	if is_cpu(d) or is_open(d):
		out.remove_at(index)
	return out


## The specs with an open human seat of the host's own phone (shared phone) or back to open.
static func set_seat_mine(meta: Dictionary, index: int, mine: bool) -> Array:
	var out: Array = seat_specs(meta)
	if index >= 0 and index < out.size() and is_open(seats_of(meta)[index]):
		out[index] = NetLobby.seat_human(mine)
	return out


## The specs with CPU seat `index` set to `level`.
static func set_cpu_level(meta: Dictionary, index: int, level: int) -> Array:
	var out: Array = seat_specs(meta)
	if index >= 0 and index < out.size() and is_cpu(seats_of(meta)[index]):
		out[index] = NetLobby.seat_cpu(level)
	return out


## The next CPU level when a chip is tapped: Easy, Normal, Hard, Expert, Easy...
static func next_level(level: int) -> int:
	return level + 1 if level < SimConstants.CTRL_MAX else SimConstants.CTRL_EASY


## The value after `current` in `values` (wraps; the first when `current` is not in the list).
static func cycle(values: Array, current: Variant) -> Variant:
	var i: int = values.find(current)
	return values[(i + 1) % values.size()] if i >= 0 else values[0]


## The timers as the lobby shows them, with the defaults the server uses.
static func timers_of(meta: Dictionary) -> Dictionary:
	var t: Variant = meta.get("timers", {})
	var d: Dictionary = t as Dictionary if typeof(t) == TYPE_DICTIONARY else {}
	return {"liveSec": int(d.get("liveSec", 60)), "asyncHours": int(d.get("asyncHours", 72)),
			"asyncTimeout": str(d.get("asyncTimeout", "auto"))}


## A short line for the hint under START ("Waiting for 2 players", "Give every player a team").
static func start_hint_key(reason: String) -> String:
	match reason:
		"open_seats":
			return "NET_LOBBY_NEED_PLAYERS"
		"need_all":
			return "SETUP_TEAMS_NEED_ALL"
		"need_two":
			return "SETUP_TEAMS_NEED_TWO"
		"not_host":
			return "NET_LOBBY_WAIT_HOST"
	return ""
