class_name NetReplay
extends RefCounted
## Replays an online match's action log through the real simulation (docs/ARCHITECTURE.md sections 46 and 51).
## Pure and deterministic: no networking, no clock, no randomness of its own. Every client that applies the same
## entries to the same meta gets the same MatchState, so the same fingerprints.
##
## A match is `meta` (settings, seed, seats, timers) plus an append-only list of entries. Entries are core actions
## (fire, move, use_item, pass, buy, sell, ready) or three net markers that are expanded here:
##   auto       {tank, level}   AiPlayer plays that tank's whole turn (shield, move... then the shot), like the offline game
##   auto_shop  {tank, level}   the CPU shop visit: AiPlayer's purchases, then `ready` (same as CpuShop offline)
##   timeout    {tank, async?}  a missed deadline: a live skip (pass), or with async: 1 the AI plays / the match ends
## `start_round` is never logged: it happens by itself when the shop is all ready, exactly like offline.
##
## Anything that does not fit (an entry the simulation refuses, an `auto` for a human seat, an entry after the end...)
## marks the replay `disputed`; nothing is applied after that.
##
## Each applied entry returns a result Dictionary:
##   {ok, err, index, entry, steps: [{action, events}], events (all steps flattened), turn_ended, over}
## `steps` is the timeline for playback: one step per real action (an `auto` entry may have several, a start_round is
## a step with action {"kind": "start_round"}).

## The AI promises a turn-ending action within 3 calls; the 4th forces a pass (same as CpuDriver.MAX_CALLS).
const MAX_CPU_CALLS: int = 4
## Hard stop for a runaway turn loop (never reached: the 4th call always ends the turn).
const MAX_TURN_STEPS: int = 12
const TIMEOUT_PASS: String = "pass"
const TIMEOUT_AUTO: String = "auto"

var session: MatchSession = null
var meta: Dictionary = {}
## One Dictionary per tank: {kind: "human"|"cpu", uid?, name?, level?}.
var seats: Array = []
var timers: Dictionary = {"liveSec": 60, "asyncHours": 72, "asyncTimeout": "auto"}
## Entries applied so far, as received.
var entries: Array[Dictionary] = []
var count: int = 0
var disputed: bool = false
var dispute_reason: String = ""
var dispute_index: int = -1
## True once the match is over: the simulation reached match_over, or a timeout ended it (asyncTimeout "end").
var ended: bool = false
var ended_by_timeout: bool = false


var state: MatchState:
	get:
		return session.state


# --- construction -----------------------------------------------------------------------------------------------------

## "" when `meta` has what a replay needs, else a short reason (missing_settings, bad_seats, seed_missing...).
static func meta_error(m: Dictionary) -> String:
	if typeof(m.get("settings", null)) != TYPE_DICTIONARY:
		return "missing_settings"
	var seat_list: Array = NetJson.as_list(m.get("seats", null))
	var s: Dictionary = m["settings"] as Dictionary
	if seat_list.size() < SimConstants.MIN_TANKS or seat_list.size() > SimConstants.MAX_TANKS:
		return "bad_seats"
	if s.has("num_tanks") and (s["num_tanks"] as int) != seat_list.size():
		return "bad_seats"
	if not m.has("seed") and not s.has("seed"):
		return "seed_missing"
	if (m.get("seed", s.get("seed", 0)) as int) == 0:
		return "seed_missing"  # 0 is the lobby placeholder: the match has not started
	return ""


## The MatchSettings a match's meta describes. `meta` may come straight from the database (lists as Arrays or keyed
## Dictionaries). Unknown keys (theme) are ignored: they are show-layer only.
static func settings_from_meta(m: Dictionary) -> MatchSettings:
	var s: Dictionary = m.get("settings", {}) as Dictionary
	var seat_list: Array = NetJson.as_list(m.get("seats", null))
	var ms := MatchSettings.new()
	ms.seed = m.get("seed", s.get("seed", 0))
	ms.num_tanks = s.get("num_tanks", seat_list.size())
	ms.rounds = s.get("rounds", 1)
	ms.wind_max = s.get("wind_max", SimConstants.WIND_MAX)
	ms.start_money = s.get("start_money", SimConstants.DEFAULT_START_MONEY)
	ms.full_unlocked = s.get("full_unlocked", true)
	ms.mode = s.get("mode", SimConstants.MODE_STANDARD)
	ms.friendly_fire = s.get("friendly_fire", true)
	var controllers: PackedInt32Array = PackedInt32Array()
	if s.has("controllers"):
		for v: Variant in NetJson.as_list(s["controllers"]):
			controllers.append(v as int)
	else:
		for seat: Variant in seat_list:
			var d: Dictionary = seat as Dictionary
			controllers.append((d.get("level", SimConstants.CTRL_NORMAL) as int) if d.get("kind", "human") == "cpu" else SimConstants.CTRL_HUMAN)
	ms.controllers = controllers
	var teams: PackedInt32Array = PackedInt32Array()
	if s.has("teams"):
		for v: Variant in NetJson.as_list(s["teams"]):
			teams.append(v as int)
	ms.teams = teams
	return ms


## A fresh replay at the start of the match, or null when the meta is unusable (see meta_error).
static func create(m: Dictionary) -> NetReplay:
	if meta_error(m) != "":
		return null
	var r := NetReplay.new()
	r.meta = m
	r.seats = NetJson.as_list(m.get("seats", null))
	var t: Variant = m.get("timers", null)
	if typeof(t) == TYPE_DICTIONARY:
		for k: Variant in (t as Dictionary).keys():
			r.timers[k] = (t as Dictionary)[k]
	r.session = MatchSession.create(settings_from_meta(m))
	r.ended = r.state.phase == SimConstants.PHASE_MATCH_OVER
	return r


## An independent copy (state included) for "what would happen if": entry batches are computed on a fork and only
## written when the database accepts them. The fork's `entries` start empty.
func fork() -> NetReplay:
	var f := NetReplay.new()
	f.meta = meta
	f.seats = seats
	f.timers = timers
	f.session = MatchSession.new()
	f.session.state = state.duplicate_state()
	f.count = count
	f.disputed = disputed
	f.dispute_reason = dispute_reason
	f.dispute_index = dispute_index
	f.ended = ended
	f.ended_by_timeout = ended_by_timeout
	return f


## The seats changed (a player left: their seat is now a CPU). History is unaffected.
func set_seats(list: Array) -> void:
	seats = list


func fingerprint() -> String:
	return Simulation.fingerprint(state)


# --- seats and turns --------------------------------------------------------------------------------------------------

func seat_is_cpu(tank: int) -> bool:
	return tank >= 0 and tank < seats.size() and (seats[tank] as Dictionary).get("kind", "human") == "cpu"


func seat_uid(tank: int) -> String:
	if tank < 0 or tank >= seats.size():
		return ""
	return (seats[tank] as Dictionary).get("uid", "")


func seat_level(tank: int) -> int:
	if tank < 0 or tank >= seats.size():
		return SimConstants.CTRL_NORMAL
	return clampi((seats[tank] as Dictionary).get("level", SimConstants.CTRL_NORMAL), SimConstants.CTRL_EASY, SimConstants.CTRL_EXPERT)


## Seat indexes held by `uid` (several on a shared phone).
func seats_of(uid: String) -> Array[int]:
	var out: Array[int] = []
	for i: int in range(seats.size()):
		if (seats[i] as Dictionary).get("uid", "") == uid and uid != "":
			out.append(i)
	return out


## Identifies "which turn is it" so a caller can tell that a turn ended: it changes with every turn, round and phase.
func turn_key() -> String:
	return "%s:%d:%d:%d" % [state.phase, state.round_index, state.turn_number, state.current_tank]


## What `meta/turn` must say now: {tank, uid} with tank -2 (shop, uid "any"), a seat (uid of the holder, or "cpu"), or {}
## when the match is over (nothing to wait for).
func expected_turn() -> Dictionary:
	if ended or state.phase == SimConstants.PHASE_MATCH_OVER:
		return {}
	if state.phase == SimConstants.PHASE_SHOP:
		return {"tank": NetProtocol.TURN_SHOP, "uid": NetProtocol.UID_ANY}
	var t: int = state.current_tank
	return {"tank": t, "uid": NetProtocol.UID_CPU if seat_is_cpu(t) else seat_uid(t)}


## "" when the stored `meta/turn` agrees with the simulation, else why not. A stored tank of -1 ("needs resolve") is
## always acceptable: it only says a client has to append the CPU entries and set the real turn.
func check_turn(stored: Dictionary) -> String:
	var want: Dictionary = expected_turn()
	if want.is_empty() or not stored.has("tank"):
		return "" if want.is_empty() else "turn_missing"
	var tank: int = stored.get("tank", -99)
	if tank == NetProtocol.TURN_NEEDS_RESOLVE:
		return ""
	if tank != (want["tank"] as int):
		return "turn_tank"
	if str(stored.get("uid", "")) != (want["uid"] as String):
		return "turn_uid"
	return ""


## The next CPU entry the log needs ({} when the next move belongs to a human, or the match is over): `auto` for a CPU
## tank's aim turn, `auto_shop` for a CPU tank that has not shopped yet.
func pending_cpu_entry() -> Dictionary:
	if disputed or ended:
		return {}
	if state.phase == SimConstants.PHASE_AIM:
		var t: int = state.current_tank
		if seat_is_cpu(t):
			return {"kind": "auto", "tank": t, "level": seat_level(t)}
	elif state.phase == SimConstants.PHASE_SHOP:
		for tank: TankState in state.tanks:
			if seat_is_cpu(tank.id) and not tank.ready:
				return {"kind": "auto_shop", "tank": tank.id, "level": seat_level(tank.id)}
	return {}


## The entries a client appends for `first` (the player's own entries, possibly none) plus the CPU entries that follow up
## to the next human decision, the end of the round or the match, or the batch cap. Computed on a fork; nothing changes
## here. Returns {ok, err, entries, turn_changed, turn (expected_turn after the batch), over, more_cpu} where
## `more_cpu` says the cap stopped the batch with CPU work left (the turn is then a CPU's or the shop with CPUs waiting).
func plan_batch(first: Array[Dictionary], cap: int = NetProtocol.MAX_BATCH) -> Dictionary:
	var f: NetReplay = fork()
	var before: String = f.turn_key()
	var out: Array[Dictionary] = []
	for e: Dictionary in first:
		var r: Dictionary = f.apply_entry(e)
		if not (r["ok"] as bool):
			return {"ok": false, "err": r["err"], "entries": out}
		out.append(e)
	while out.size() < cap:
		var nxt: Dictionary = f.pending_cpu_entry()
		if nxt.is_empty():
			break
		var r2: Dictionary = f.apply_entry(nxt)
		if not (r2["ok"] as bool):
			return {"ok": false, "err": r2["err"], "entries": out}
		out.append(nxt)
	return {
		"ok": true, "err": "", "entries": out,
		"turn_changed": f.turn_key() != before,
		"turn": f.expected_turn(),
		"over": f.ended,
		"more_cpu": not f.pending_cpu_entry().is_empty(),
		"fingerprint": f.fingerprint(),
	}


# --- applying entries -------------------------------------------------------------------------------------------------

## Applies the next log entry. See the class comment for the result.
func apply_entry(entry: Dictionary) -> Dictionary:
	var result: Dictionary = {"ok": true, "err": "", "index": count, "entry": entry, "steps": [] as Array[Dictionary],
			"events": [] as Array[Dictionary], "turn_ended": false, "over": false}
	if disputed:
		return _fail(result, "disputed")
	if ended:
		return _fail(result, "entry_after_end")
	var before: String = turn_key()
	var kind: String = str(entry.get("kind", ""))
	var err: String = ""
	match kind:
		"auto":
			err = _apply_auto(entry, result)
		"auto_shop":
			err = _apply_auto_shop(entry, result)
		"timeout":
			err = _apply_timeout(entry, result)
		_:
			err = _apply_real(Simulation.normalize_action(entry), result)
	if err != "":
		return _fail(result, err)
	_maybe_start_round(result)
	for step: Dictionary in result["steps"] as Array[Dictionary]:
		(result["events"] as Array[Dictionary]).append_array(step["events"] as Array[Dictionary])
	result["turn_ended"] = turn_key() != before
	if state.phase == SimConstants.PHASE_MATCH_OVER:
		ended = true
	result["over"] = ended
	entries.append(entry)
	count += 1
	return result


func _fail(result: Dictionary, err: String) -> Dictionary:
	if not disputed:
		disputed = true
		dispute_reason = err
		dispute_index = count
	result["ok"] = false
	result["err"] = err
	return result


func _maybe_start_round(result: Dictionary) -> void:
	if Simulation.all_ready(state):
		var events: Array[Dictionary] = session.start_round()
		if not events.is_empty():
			(result["steps"] as Array[Dictionary]).append({"action": {"kind": "start_round"}, "events": events})


## Submits one real action through the session; "" or an error key.
func _submit(action: Dictionary, result: Dictionary) -> String:
	var r: Dictionary = session.submit(action)
	if (r["err"] as String) != "":
		return r["err"]
	(result["steps"] as Array[Dictionary]).append({"action": r["action"], "events": r["events"]})
	return ""


func _apply_real(action: Dictionary, result: Dictionary) -> String:
	var err: String = _submit(action, result)
	return "invalid_" + err if err != "" else ""


func _int_field(entry: Dictionary, key: String) -> int:
	return entry[key] if entry.has(key) and typeof(entry[key]) == TYPE_INT else -1


func _apply_auto(entry: Dictionary, result: Dictionary) -> String:
	var tank: int = _int_field(entry, "tank")
	var level: int = _int_field(entry, "level")
	if level < SimConstants.CTRL_EASY or level > SimConstants.CTRL_EXPERT:
		return "bad_auto_level"
	if state.phase != SimConstants.PHASE_AIM or tank != state.current_tank or not seat_is_cpu(tank):
		return "bad_auto"
	return _play_ai_turn(tank, level, result)


func _apply_auto_shop(entry: Dictionary, result: Dictionary) -> String:
	var tank: int = _int_field(entry, "tank")
	var level: int = _int_field(entry, "level")
	if level < SimConstants.CTRL_EASY or level > SimConstants.CTRL_EXPERT:
		return "bad_auto_level"
	if state.phase != SimConstants.PHASE_SHOP or tank < 0 or tank >= state.tanks.size() \
			or state.tanks[tank].ready or not seat_is_cpu(tank):
		return "bad_auto_shop"
	return _shop_ai(tank, level, result)


## What a `timeout` means (docs/ARCHITECTURE.md section 52): `{kind: "timeout", tank, async?: 1}`.
##   async: 1   written after the hard deadline: the AI plays the turn at level TIMEOUT_AI_LEVEL (in the shop it buys and
##              readies), or the match ends when the timers say asyncTimeout "end"
##   otherwise  a live skip: the player passes (in the shop: is marked ready)
static func timeout_mode(entry: Dictionary) -> String:
	return TIMEOUT_AUTO if entry.get("async", 0) == 1 else TIMEOUT_PASS


func _apply_timeout(entry: Dictionary, result: Dictionary) -> String:
	var tank: int = _int_field(entry, "tank")
	var mode: String = timeout_mode(entry)
	var ends: bool = mode == TIMEOUT_AUTO and str(timers.get("asyncTimeout", "auto")) == "end"
	if state.phase == SimConstants.PHASE_AIM:
		if tank != state.current_tank:
			return "bad_timeout"
		if ends:
			ended = true
			ended_by_timeout = true
			return ""
		if mode == TIMEOUT_PASS:
			return _apply_real({"kind": "pass", "tank": tank}, result)
		return _play_ai_turn(tank, NetProtocol.TIMEOUT_AI_LEVEL, result)
	if state.phase == SimConstants.PHASE_SHOP:
		if tank < 0 or tank >= state.tanks.size() or state.tanks[tank].ready:
			return "bad_timeout"
		if ends:
			ended = true
			ended_by_timeout = true
			return ""
		if mode == TIMEOUT_PASS:
			return _apply_real({"kind": "ready", "tank": tank}, result)
		return _shop_ai(tank, NetProtocol.TIMEOUT_AI_LEVEL, result)
	return "bad_timeout"


# --- the AI, exactly as the offline game runs it ------------------------------------------------------------------

## AiPlayer decides with `AiProfile.level_of`, which reads the match settings. The entry's level is authoritative, so the
## tank's controller is set to it for the duration of the call (and put back: the controllers are part of the fingerprint).
func _with_level(tank: int, level: int, work: Callable) -> Variant:
	var current: PackedInt32Array = state.settings.controllers
	if AiProfile.level_of(state, tank) == level:
		return work.call()
	var changed: PackedInt32Array = current.duplicate()
	changed[tank] = level
	state.settings.controllers = changed
	var out: Variant = work.call()
	state.settings.controllers = current
	return out


## One CPU turn: ask the AI, apply, repeat until the turn is over. Mirrors BattleController._cpu_decide: an action the
## simulation refuses, or a turn still going at the 4th call, becomes a pass.
func _play_ai_turn(tank: int, level: int, result: Dictionary) -> String:
	var start: String = turn_key()
	for call_no: int in range(1, MAX_TURN_STEPS + 1):
		var raw: Dictionary = _with_level(tank, level, func() -> Dictionary: return AiPlayer.next_action(state, tank)) as Dictionary
		var action: Dictionary = Simulation.normalize_action(raw)
		var err: String = Simulation.validate_action(state, action)
		if err == "" and call_no >= MAX_CPU_CALLS and not ends_turn(action):
			err = "cpu_runaway"
		if err != "":
			action = {"kind": "pass", "tank": tank}
		var failed: String = _submit(action, result)
		if failed != "":
			return "bad_auto_" + failed
		if turn_key() != start:
			return ""
	return "auto_never_ended"


## True for an action that ends the turn (same list as CpuDriver.ends_turn; a test keeps them in step).
static func ends_turn(a: Dictionary) -> bool:
	var kind: String = a.get("kind", "")
	return kind == "fire" or kind == "pass" or (kind == "use_item" and a.get("item", "") == "nanorepair_kit")


## One CPU shop visit, like CpuShop._shop_one: the AI's purchases (each validated), then `ready` if it is not ready yet.
func _shop_ai(tank: int, level: int, result: Dictionary) -> String:
	var plan: Array[Dictionary] = _with_level(tank, level, func() -> Array[Dictionary]: return AiPlayer.shop_actions(state, tank)) as Array[Dictionary]
	for a: Dictionary in plan:
		var action: Dictionary = Simulation.normalize_action(a)
		if Simulation.validate_action(state, action) == "":
			var err: String = _submit(action, result)
			if err != "":
				return "bad_shop_" + err
	if not state.tanks[tank].ready:
		var failed: String = _submit({"kind": "ready", "tank": tank}, result)
		if failed != "":
			return "bad_shop_" + failed
	return ""
