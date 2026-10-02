@warning_ignore_start("integer_division")
class_name WeaponResolver
extends RefCounted
## Resolves a fire action into timeline events (docs/ARCHITECTURE.md section 21).
## `resolve` dispatches on the weapon's `behavior`; every behaviour reuses
## Simulation.apply_damage and Settle for damage, falls and chutes.
##
## M3-C1 ships only `explode`. The other behaviours are stubs that resolve as a plain
## explosion until M3-C2 replaces them one by one.

const FALLBACK_RADIUS: int = 28
const FALLBACK_DAMAGE: int = 55


## Fires `action` (already validated) for `tank_id`: records the aim, consumes one unit of
## stock, then runs the behaviour. Returns the tick of the last event (the turn change
## uses it). Emits `fire` ... `tank_destroyed*`, but not the turn/round events.
static func resolve(state: MatchState, tank_id: int, action: Dictionary, events: Array[Dictionary]) -> int:
	var weapon: String = action["weapon"]
	var def: Dictionary = WeaponDefs.get_def(weapon)
	var tank: TankState = state.tanks[tank_id]
	var angle: int = action["angle"]
	var power: int = action["power"]
	tank.angle = angle
	tank.power = power
	events.append({"type": "fire", "tick": 0, "tank": tank_id, "angle": angle, "power": power,
			"weapon": weapon})
	var unlimited: bool = def.get("unlimited", false)
	if not unlimited:
		var idx: int = Catalog.index_of(weapon)
		tank.inventory[idx] -= 1

	var was_alive: Array[bool] = []
	for t: TankState in state.tanks:
		was_alive.append(t.alive)
	var tick: int = _dispatch(state, tank_id, action, def, events)
	Simulation.emit_destroyed(state, was_alive, tick, events)
	return tick


static func _dispatch(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	match def["behavior"]:
		"explode":
			return _explode(state, tank_id, action, def, events)
		"splitter":
			return _splitter(state, tank_id, action, def, events)
		"roller":
			return _roller(state, tank_id, action, def, events)
		"tunneler":
			return _tunneler(state, tank_id, action, def, events)
		"dirt":
			return _dirt(state, tank_id, action, def, events)
		"sludge":
			return _sludge(state, tank_id, action, def, events)
		"fire":
			return _fire(state, tank_id, action, def, events)
		"seeker":
			return _seeker(state, tank_id, action, def, events)
		"beam":
			return _beam(state, tank_id, action, def, events)
		"static":
			return _static(state, tank_id, action, def, events)
		"well":
			return _well(state, tank_id, action, def, events)
		"anchor":
			return _anchor(state, tank_id, action, def, events)
	return _explode_fallback(state, tank_id, action, def, events)


# --- explode ---------------------------------------------------------------------

static func _explode(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	var radius: int = def["r"]
	var dmg: int = def["dmg"]
	return _fly_and_blast(state, tank_id, action, radius, dmg, events)


## Plain explosion for behaviours that are not implemented yet: the def's r/dmg if present,
## else 28/55.
static func _explode_fallback(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	var radius: int = def.get("r", FALLBACK_RADIUS)
	var dmg: int = def.get("dmg", FALLBACK_DAMAGE)
	return _fly_and_blast(state, tank_id, action, radius, dmg, events)


## One flight (projectile, repulsor_down*, projectile_end), then a blast where the shell
## ended if it hit terrain, a tank or a shield bubble.
static func _fly_and_blast(state: MatchState, tank_id: int, action: Dictionary, radius: int, dmg: int,
		events: Array[Dictionary]) -> int:
	var weapon: String = action["weapon"]
	var angle: int = action["angle"]
	var power: int = action["power"]
	var tr: Dictionary = Ballistics.trace(state, tank_id, angle, power, weapon,
			SimConstants.WIND_USE_STATE, SimConstants.MAX_FLIGHT_TICKS)
	var ticks: int = tr["ticks"]
	var reason: String = tr["end_reason"]
	events.append({"type": "projectile", "tick": 0, "id": 0, "weapon": weapon, "path": tr["path"]})
	_apply_repulsor_use(state, tr, events)
	var ex: int = tr["end_x"]
	var ey: int = tr["end_y"]
	events.append({"type": "projectile_end", "tick": ticks, "id": 0, "reason": reason, "x": ex, "y": ey})
	if reason == "terrain" or reason == "tank" or reason == "shield":
		blast(state, tank_id, ex, ey, radius, dmg, weapon, ticks, events)
	return ticks


## Charges consumed by a flight (Ballistics is pure, so the resolver books them).
static func _apply_repulsor_use(state: MatchState, tr: Dictionary, events: Array[Dictionary]) -> void:
	var used: PackedInt32Array = tr["repulsor_ticks"]
	var down: PackedInt32Array = tr["repulsor_down_tick"]
	for t: TankState in state.tanks:
		if used[t.id] <= 0:
			continue
		t.repulsor_charge = maxi(0, t.repulsor_charge - used[t.id])
		if t.repulsor_charge == 0:
			events.append({"type": "repulsor_down", "tick": down[t.id], "tank": t.id})


## explosion -> terrain_carve -> damage* -> terrain_settle -> (tank_fall -> chute/damage)*.
## Damage and money are attributed to `attacker`.
static func blast(state: MatchState, attacker: int, ex: int, ey: int, radius: int, max_damage: int,
		weapon: String, tick: int, events: Array[Dictionary]) -> void:
	events.append({"type": "explosion", "tick": tick, "x": ex, "y": ey, "radius": radius, "weapon": weapon})
	var rect: Rect2i = state.terrain.carve_circle(ex, ey, radius)
	events.append({"type": "terrain_carve", "tick": tick, "x": ex, "y": ey, "radius": radius})
	for d: Dictionary in Damage.compute(state, ex, ey, radius, max_damage):
		var target: int = d["tank"]
		var amount: int = d["amount"]
		Simulation.apply_damage(state, attacker, target, amount, "explosion", tick, events)
	if rect.size.x <= 0:
		return
	Settle.settle_region(state, rect.position.x, rect.end.x - 1, attacker, tick, events)


# --- stubs: one per behaviour, replaced in M3-C2 -------------------------------------

static func _splitter(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	return _explode_fallback(state, tank_id, action, def, events)  # M3-C2


static func _roller(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	return _explode_fallback(state, tank_id, action, def, events)  # M3-C2


static func _tunneler(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	return _explode_fallback(state, tank_id, action, def, events)  # M3-C2


static func _dirt(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	return _explode_fallback(state, tank_id, action, def, events)  # M3-C2


static func _sludge(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	return _explode_fallback(state, tank_id, action, def, events)  # M3-C2


static func _fire(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	return _explode_fallback(state, tank_id, action, def, events)  # M3-C2


static func _seeker(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	return _explode_fallback(state, tank_id, action, def, events)  # M3-C2


static func _beam(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	return _explode_fallback(state, tank_id, action, def, events)  # M3-C2


static func _static(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	return _explode_fallback(state, tank_id, action, def, events)  # M3-C2


static func _well(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	return _explode_fallback(state, tank_id, action, def, events)  # M3-C2


static func _anchor(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	return _explode_fallback(state, tank_id, action, def, events)  # M3-C2
