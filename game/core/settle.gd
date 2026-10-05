@warning_ignore_start("integer_division")
class_name Settle
extends RefCounted
## Shared terrain-settle / tank-fall / chute helper used by every weapon behaviour and by
## movement (docs/ARCHITECTURE.md sections 10 and 20).


## Settles terrain columns [x0, x1], emits `terrain_settle`, then drops every alive tank
## standing in that range onto the new surface (`tank_fall`, chute, fall damage).
## Damage and money are attributed to `attacker` (-1 for none).
static func settle_region(state: MatchState, x0: int, x1: int, attacker: int, tick: int,
		events: Array[Dictionary]) -> void:
	var falls: Array[Dictionary] = state.terrain.settle(x0, x1)
	events.append({"type": "terrain_settle", "tick": tick, "x0": x0, "x1": x1, "falls": falls})
	drop_tanks(state, x0, x1, attacker, tick, events)


## Lets alive tanks overlapping columns [x0, x1] fall to the surface below them.
static func drop_tanks(state: MatchState, x0: int, x1: int, attacker: int, tick: int,
		events: Array[Dictionary]) -> void:
	var half: int = SimConstants.TANK_W / 2
	for t: TankState in state.tanks:
		if not t.alive or t.x + half <= x0 or t.x - half > x1:
			continue
		var new_y: int = TankState.rest_y(state.terrain, t.x)
		if new_y <= t.y:
			continue
		var from_y: int = t.y
		t.y = new_y
		apply_fall(state, t.id, from_y, new_y, attacker, tick, events)


## Emits `tank_fall` for a drop from `from_y` to `to_y`, then either consumes a Drift
## Chute (`chute`, no damage) or applies fall damage (which ignores shields). A chute is only
## spent when the fall would actually cost at least 1 HP. The caller has already moved the tank.
static func apply_fall(state: MatchState, tank_id: int, from_y: int, to_y: int, attacker: int, tick: int,
		events: Array[Dictionary]) -> void:
	events.append({"type": "tank_fall", "tick": tick, "tank": tank_id, "from_y": from_y, "to_y": to_y})
	var amt: int = (to_y - from_y - SimConstants.FALL_SAFE) / SimConstants.FALL_DMG_DIV
	if amt <= 0:
		return
	# Friendly fire off: a teammate's shot made this tank fall, which costs nothing and keeps the chute.
	if Simulation.is_friendly_fire_immune(state, attacker, tank_id):
		return
	var t: TankState = state.tanks[tank_id]
	var chute: int = Catalog.index_of("drift_chute")
	if t.inventory[chute] > 0:
		t.inventory[chute] -= 1
		events.append({"type": "chute", "tick": tick, "tank": tank_id})
		return
	Simulation.apply_damage(state, attacker, tank_id, amt, "fall", tick, events)
