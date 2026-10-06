class_name NetTestUtil
extends RefCounted
## Builders shared by the net tests: a match `meta` as the database holds it, and offline sessions to compare against.

const HUMAN_A: String = "uidA"
const HUMAN_B: String = "uidB"


static func human(uid: String, seat_name: String = "P") -> Dictionary:
	return {"kind": "human", "uid": uid, "name": seat_name}


static func cpu(level: int = 2) -> Dictionary:
	return {"kind": "cpu", "level": level, "name": "CPU"}


## Meta for `seats` (Array of seat dictionaries). `overrides` go into settings; `timers` replace the defaults.
static func meta(seats: Array, overrides: Dictionary = {}, timers: Dictionary = {}, seed_value: int = 4242) -> Dictionary:
	var controllers: Array = []
	for s: Variant in seats:
		var d: Dictionary = s as Dictionary
		controllers.append(d.get("level", 2) if d["kind"] == "cpu" else 0)
	var settings: Dictionary = {"seed": seed_value, "num_tanks": seats.size(), "rounds": 1, "wind_max": 40,
			"start_money": 10000, "full_unlocked": true, "controllers": controllers, "mode": 0, "friendly_fire": true}
	for k: Variant in overrides.keys():
		settings[k] = overrides[k]
	var t: Dictionary = {"liveSec": 60, "asyncHours": 72, "asyncTimeout": "auto"}
	for k2: Variant in timers.keys():
		t[k2] = timers[k2]
	return {"hostUid": HUMAN_A, "protocol": NetProtocol.VERSION, "status": "playing", "seed": seed_value, "settings": settings,
			"seats": seats, "timers": t, "actionCount": 0}


## What a human (played by the AI here, only to get sensible legal actions) does next for `tank`.
static func scripted_action(state: MatchState, tank: int) -> Dictionary:
	if state.phase == SimConstants.PHASE_SHOP:
		return {"kind": "ready", "tank": tank}
	return AiPlayer.next_action(state, tank)


## Plays the whole match through NetReplay by always asking the replay what is pending: CPU entries are generated like a
## writer client would, humans act through `scripted_action`. Returns the entries written, with the fingerprint after every
## entry that ended a turn: [{entry, fp}].
static func play_through(replay: NetReplay, max_entries: int = 400) -> Array[Dictionary]:
	var log: Array[Dictionary] = []
	while replay.count < max_entries and not replay.ended and not replay.disputed:
		var entry: Dictionary = replay.pending_cpu_entry()
		if entry.is_empty():
			entry = next_human_entry(replay)
		var r: Dictionary = replay.apply_entry(entry)
		if not (r["ok"] as bool):
			break
		log.append({"entry": entry, "fp": replay.fingerprint() if (r["turn_ended"] as bool) else ""})
	return log


static func next_human_entry(replay: NetReplay) -> Dictionary:
	var state: MatchState = replay.state
	if state.phase == SimConstants.PHASE_SHOP:
		for t: TankState in state.tanks:
			if not t.ready and not replay.seat_is_cpu(t.id):
				return {"kind": "ready", "tank": t.id}
	return scripted_action(state, state.current_tank)
