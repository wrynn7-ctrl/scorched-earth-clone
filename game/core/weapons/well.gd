@warning_ignore_start("integer_division")
class_name WellBehavior
extends RefCounted
## Singularity Seed (docs/ARCHITECTURE.md section 21): on any impact (terrain, tank, shield) a
## gravity well {owner, x, y, expires_turn} appears at the impact cell, with
## expires_turn = turn_number + cycles * alive_tank_count. A new well by the same owner replaces
## the old one (`well_off` for the old, then `well_on`). state.wells stays sorted by owner.
## The pull itself is applied by Ballistics (every later flight, trace included); expiry is
## handled by Simulation at turn change and wells are cleared at round start.
## Events: well_off {owner}? then well_on {owner, x, y, expires_turn}.


static func resolve(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	var tr: Dictionary = WeaponResolver.fly(state, tank_id, action, events)
	var ticks: int = tr["ticks"]
	if not WeaponResolver.is_impact(tr["end_reason"]):
		return ticks
	var alive: int = 0
	for t: TankState in state.tanks:
		if t.alive:
			alive += 1
	var well: Dictionary = {"owner": tank_id, "x": tr["end_x"], "y": tr["end_y"],
			"expires_turn": state.turn_number + (def["cycles"] as int) * alive}
	var at: int = state.wells.size()
	for i: int in range(state.wells.size()):
		var owner: int = state.wells[i]["owner"]
		if owner == tank_id:
			events.append({"type": "well_off", "tick": ticks, "owner": tank_id})
			state.wells[i] = well
			at = -1
			break
		if owner > tank_id:
			at = i
			break
	if at >= 0:
		state.wells.insert(at, well)
	events.append({"type": "well_on", "tick": ticks, "owner": tank_id, "x": well["x"], "y": well["y"],
			"expires_turn": well["expires_turn"]})
	return ticks
