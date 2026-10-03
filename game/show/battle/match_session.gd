class_name MatchSession
extends RefCounted
## A match in progress as the show layer sees it: the authoritative MatchState, the log of
## every action applied to it (after normalize_action), and the extra show-layer data that is
## saved alongside (`meta`). All rule decisions stay in Simulation; this class only keeps the
## books and does the save/restore plumbing.
##
## The log holds real actions only. `start_round` is not an action: it happens automatically
## once every tank is ready in the shop, so a replayer can infer it from `Simulation.all_ready`.

var state: MatchState = null
var actions: Array[Dictionary] = []
## Show-layer extras saved with the match: "looks" (PlayerLooks), "round_money" (credits each
## player earned this round) and "summary_pending" (the round summary was still on screen).
var meta: Dictionary = {}


static func create(settings: MatchSettings) -> MatchSession:
	var s := MatchSession.new()
	s.state = Simulation.new_match(settings)
	return s


## Normalizes, validates, logs and applies `action`. Returns {err, events, action}; `err` is
## "" on success. Rejected actions are neither logged nor applied.
func submit(action: Dictionary) -> Dictionary:
	var a: Dictionary = Simulation.normalize_action(action)
	var err: String = Simulation.validate_action(state, a)
	if err != "":
		return {"err": err, "events": [] as Array[Dictionary], "action": a}
	actions.append(a)
	return {"err": "", "events": Simulation.apply_action(state, a), "action": a}


## Starts the next round (shop with every tank ready). [] if not allowed.
func start_round() -> Array[Dictionary]:
	return Simulation.start_round(state)


func save(path: String) -> bool:
	if path == "":
		return false
	return SaveStore.save(state, actions, path, meta)


## True when the save at `path` was made with the full game but this device does not own it now
## (a refund, a debug toggle, a restored phone). Such a save would hand out the full game for
## free, so restore() refuses it; the title explains why instead (Unlock screen, "save" reason).
static func needs_full(path: String) -> bool:
	if Entitlement.is_full():
		return false
	var res: Dictionary = SaveStore.load_save(path)
	return (res["ok"] as bool) and (res["state"] as MatchState).settings.full_unlocked


## Restores a session from `path`, or null if there is no valid save (or it needs the full game).
static func restore(path: String) -> MatchSession:
	var res: Dictionary = SaveStore.load_save(path)
	if not (res["ok"] as bool):
		return null
	if not Entitlement.is_full() and (res["state"] as MatchState).settings.full_unlocked:
		return null
	var s := MatchSession.new()
	s.state = res["state"] as MatchState
	s.actions = res["actions"] as Array[Dictionary]
	s.meta = res["meta"] as Dictionary
	return s
