@warning_ignore_start("integer_division")
class_name WeaponResolver
extends RefCounted
## Resolves a fire action into timeline events (docs/ARCHITECTURE.md section 21).
## `resolve` dispatches on the weapon's `behavior`; every behaviour reuses
## Simulation.apply_damage and Settle for damage, falls and chutes.
##
## `explode` and the shared helpers live here; every other behaviour has its own script in
## this folder (SplitterBehavior, RollerBehavior, ...), each with a static `resolve`.

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
		"explode", "seeker":
			# The seeker is a plain explosion; its homing lives in Ballistics.trace.
			return _explode(state, tank_id, action, def, events)
		"splitter":
			return SplitterBehavior.resolve(state, tank_id, action, def, events)
		"roller":
			return RollerBehavior.resolve(state, tank_id, action, def, events)
		"tunneler":
			return TunnelerBehavior.resolve(state, tank_id, action, def, events)
		"dirt":
			return DirtBehavior.resolve(state, tank_id, action, def, events)
		"sludge":
			return SludgeBehavior.resolve(state, tank_id, action, def, events)
		"fire":
			return FireBehavior.resolve(state, tank_id, action, def, events)
		"beam":
			return BeamBehavior.resolve(state, tank_id, action, def, events)
		"static":
			return StaticBehavior.resolve(state, tank_id, action, def, events)
		"well":
			return WellBehavior.resolve(state, tank_id, action, def, events)
		"anchor":
			return AnchorBehavior.resolve(state, tank_id, action, def, events)
	return _explode_fallback(state, tank_id, action, def, events)


# --- explode ---------------------------------------------------------------------

static func _explode(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	var radius: int = def["r"]
	var dmg: int = def["dmg"]
	return _fly_and_blast(state, tank_id, action, radius, dmg, events)


## Plain explosion for a behaviour the resolver does not know: the def's r/dmg if present,
## else 28/55.
static func _explode_fallback(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	var radius: int = def.get("r", FALLBACK_RADIUS)
	var dmg: int = def.get("dmg", FALLBACK_DAMAGE)
	return _fly_and_blast(state, tank_id, action, radius, dmg, events)


## One flight, then a blast where the shell ended if it hit terrain, a tank or a shield bubble.
static func _fly_and_blast(state: MatchState, tank_id: int, action: Dictionary, radius: int, dmg: int,
		events: Array[Dictionary]) -> int:
	var tr: Dictionary = fly(state, tank_id, action, events)
	if is_impact(tr["end_reason"]):
		blast(state, tank_id, tr["end_x"], tr["end_y"], radius, dmg, action["weapon"], tr["ticks"], events)
	return tr["ticks"]


## True for the end reasons that make a shell strike something (terrain, tank, shield).
static func is_impact(reason: String) -> bool:
	return reason == "terrain" or reason == "tank" or reason == "shield"


## Flies the action's shell once and emits `projectile`, `repulsor_down*` and `projectile_end`
## (id 0). Returns the trace (see Ballistics.trace).
static func fly(state: MatchState, tank_id: int, action: Dictionary, events: Array[Dictionary]) -> Dictionary:
	var weapon: String = action["weapon"]
	var tr: Dictionary = Ballistics.trace(state, tank_id, action["angle"], action["power"], weapon,
			SimConstants.WIND_USE_STATE, SimConstants.MAX_FLIGHT_TICKS)
	emit_projectile(state, weapon, 0, 0, tr["path"], tr, events)
	emit_end(0, 0, tr["end_reason"], tr["ticks"], tr["end_x"], tr["end_y"], events)
	return tr


## `projectile` event starting at tick `start_tick` (path[i] is the position at tick
## start_tick + i + 1), and books the repulsor charge the flight `tr` used.
static func emit_projectile(state: MatchState, weapon: String, id: int, start_tick: int,
		path: PackedInt32Array, tr: Dictionary, events: Array[Dictionary]) -> void:
	events.append({"type": "projectile", "tick": start_tick, "id": id, "weapon": weapon, "path": path})
	_apply_repulsor_use(state, tr, start_tick, events)


## `projectile_end` of shell `id` that started at `start_tick` and flew `ticks` ticks.
static func emit_end(id: int, start_tick: int, reason: String, ticks: int, x: int, y: int,
		events: Array[Dictionary]) -> void:
	events.append({"type": "projectile_end", "tick": start_tick + ticks, "id": id, "reason": reason,
			"x": x, "y": y})


## Charges consumed by a flight (Ballistics is pure, so the resolver books them).
static func _apply_repulsor_use(state: MatchState, tr: Dictionary, start_tick: int,
		events: Array[Dictionary]) -> void:
	var used: PackedInt32Array = tr["repulsor_ticks"]
	var down: PackedInt32Array = tr["repulsor_down_tick"]
	for t: TankState in state.tanks:
		if used[t.id] <= 0:
			continue
		t.repulsor_charge = maxi(0, t.repulsor_charge - used[t.id])
		if t.repulsor_charge == 0:
			events.append({"type": "repulsor_down", "tick": start_tick + down[t.id], "tank": t.id})


## Material for dirt weapons: the surface material of the impact column (1 if it is empty).
static func surface_material(terrain: Terrain, x: int) -> int:
	var sy: int = terrain.surface_y(x)
	if sy >= terrain.height:
		return 1
	return terrain.get_cell(x, sy)


## explosion -> terrain_carve -> [strip] -> damage* -> terrain_settle -> (tank_fall -> chute/damage)*.
## Damage and money are attributed to `attacker`. `extra` is a terrain rectangle carved by the
## caller before the blast (a tunnel) that is settled together with the crater. `strip` removes
## the shields and repulsors of tanks whose centre is inside the blast, before damage is dealt.
static func blast(state: MatchState, attacker: int, ex: int, ey: int, radius: int, max_damage: int,
		weapon: String, tick: int, events: Array[Dictionary], extra: Rect2i = Rect2i(),
		strip: bool = false) -> void:
	events.append({"type": "explosion", "tick": tick, "x": ex, "y": ey, "radius": radius, "weapon": weapon})
	var rect: Rect2i = state.terrain.carve_circle(ex, ey, radius)
	events.append({"type": "terrain_carve", "tick": tick, "x": ex, "y": ey, "radius": radius})
	if strip:
		strip_fields(state, ex, ey, radius, tick, events)
	for d: Dictionary in Damage.compute(state, ex, ey, radius, max_damage):
		var target: int = d["tank"]
		var amount: int = d["amount"]
		Simulation.apply_damage(state, attacker, target, amount, "explosion", tick, events)
	var x0: int = 0
	var x1: int = -1
	if rect.size.x > 0:
		x0 = rect.position.x
		x1 = rect.end.x - 1
	if extra.size.x > 0:
		if x1 < x0:
			x0 = extra.position.x
			x1 = extra.end.x - 1
		else:
			x0 = mini(x0, extra.position.x)
			x1 = maxi(x1, extra.end.x - 1)
	if x1 < x0:
		return
	Settle.settle_region(state, x0, x1, attacker, tick, events)


## Removes the shield and the repulsor charge of every alive tank whose centre
## (x, y - SHIELD_CENTER_DY) is within `radius` of (ex, ey): `shield_down`, `repulsor_down`.
static func strip_fields(state: MatchState, ex: int, ey: int, radius: int, tick: int,
		events: Array[Dictionary]) -> void:
	var r2: int = radius * radius
	for t: TankState in state.tanks:
		if not t.alive:
			continue
		var dx: int = t.x - ex
		var dy: int = t.y - SimConstants.SHIELD_CENTER_DY - ey
		if dx * dx + dy * dy > r2:
			continue
		if t.has_shield():
			t.shield_type = -1
			t.shield_hp = 0
			events.append({"type": "shield_down", "tick": tick, "tank": t.id})
		if t.repulsor_charge > 0:
			t.repulsor_charge = 0
			events.append({"type": "repulsor_down", "tick": tick, "tank": t.id})
