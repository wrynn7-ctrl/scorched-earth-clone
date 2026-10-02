@warning_ignore_start("integer_division")
class_name Simulation
extends RefCounted
## Rules entry point. Only this class mutates MatchState (docs/ARCHITECTURE.md sections 9-14).


## Creates a match with round 0 already started (terrain, placement, wind).
static func new_match(settings: MatchSettings) -> MatchState:
	var state := MatchState.new()
	state.settings = settings.duplicate_settings()
	state.seed = settings.seed
	state.round_index = -1  # _begin_round advances it to 0
	_begin_round(state)
	return state


## Starts the next round after one has ended. Returns [round_start, wind, turn] events,
## or [] if a round is still running or the match is over.
static func start_round(state: MatchState) -> Array[Dictionary]:
	if state.phase != SimConstants.PHASE_ROUND_OVER:
		return []
	return _begin_round(state)


static func _begin_round(state: MatchState) -> Array[Dictionary]:
	state.round_index += 1
	var r: int = state.round_index
	var n: int = clampi(state.settings.num_tanks, SimConstants.MIN_TANKS, SimConstants.MAX_TANKS)
	state.terrain = Terrain.generate(SimConstants.WORLD_W, SimConstants.WORLD_H,
			Rng.derive(state.seed, SimConstants.TAG_TERRAIN + r))
	_place_tanks(state, n, Rng.derive(state.seed, SimConstants.TAG_PLACEMENT + r))
	var wind_rng: Rng = Rng.derive(state.seed, SimConstants.TAG_WIND + r)
	var wm: int = state.settings.wind_max
	state.wind = wind_rng.range_int(-wm, wm)
	state.wind_rng_state = wind_rng.get_state()
	state.current_tank = r % n
	state.turn_number = 0
	state.phase = SimConstants.PHASE_AIM
	var events: Array[Dictionary] = []
	events.append({"type": "round_start", "tick": 0, "round": r})
	events.append({"type": "wind", "tick": 0, "wind": state.wind})
	events.append({"type": "turn", "tick": 0, "tank": state.current_tank})
	return events


## n equal segments; one tank per segment at its centre +- seg/5, on a flattened pad.
static func _place_tanks(state: MatchState, n: int, rng: Rng) -> void:
	state.tanks = []
	var terrain: Terrain = state.terrain
	var seg: int = terrain.width / n
	var half_pad: int = (SimConstants.TANK_W + 4) / 2
	for i: int in range(n):
		var cx: int = i * seg + seg / 2 + rng.range_int(-seg / 5, seg / 5)
		var sy: int = terrain.surface_y(cx)
		terrain.flatten(cx - half_pad, cx + half_pad - 1, sy)
		var t := TankState.new()
		t.id = i
		t.team = i
		t.color_index = i
		t.x = cx
		t.y = TankState.rest_y(terrain, cx)
		t.angle = SimConstants.DEFAULT_ANGLE_LEFT if cx < terrain.width / 2 else SimConstants.DEFAULT_ANGLE_RIGHT
		t.power = SimConstants.DEFAULT_POWER
		state.tanks.append(t)


## "" if the action is legal, otherwise an error key. Never mutates state.
static func validate_action(state: MatchState, action: Dictionary) -> String:
	if not action.has("kind") or typeof(action["kind"]) != TYPE_STRING:
		return "bad_action"
	var kind: String = action["kind"]
	if kind != "fire":
		return "unknown_kind"
	if state.phase != SimConstants.PHASE_AIM:
		return "bad_phase"
	for key: String in ["tank", "angle", "power"]:
		if not action.has(key) or typeof(action[key]) != TYPE_INT:
			return "bad_field"
	if not action.has("weapon") or typeof(action["weapon"]) != TYPE_STRING:
		return "bad_field"
	var tank_id: int = action["tank"]
	if tank_id < 0 or tank_id >= state.tanks.size():
		return "bad_tank"
	if tank_id != state.current_tank:
		return "not_your_turn"
	if not state.tanks[tank_id].alive:
		return "tank_dead"
	var angle: int = action["angle"]
	if angle < 0 or angle > SimConstants.MAX_ANGLE:
		return "bad_angle"
	var power: int = action["power"]
	if power < SimConstants.MIN_POWER or power > SimConstants.MAX_POWER:
		return "bad_power"
	var weapon: String = action["weapon"]
	if not WeaponDefs.has(weapon):
		return "unknown_weapon"
	return ""


## Applies a legal action and returns the Timeline. Illegal actions change nothing and
## return [].
static func apply_action(state: MatchState, action: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if validate_action(state, action) != "":
		return events
	_apply_fire(state, action, events)
	return events


static func _apply_fire(state: MatchState, action: Dictionary, events: Array[Dictionary]) -> void:
	var tank_id: int = action["tank"]
	var angle: int = action["angle"]
	var power: int = action["power"]
	var weapon: String = action["weapon"]
	var def: Dictionary = WeaponDefs.get_def(weapon)
	var tank: TankState = state.tanks[tank_id]
	tank.angle = angle
	tank.power = power
	events.append({"type": "fire", "tick": 0, "tank": tank_id, "angle": angle, "power": power, "weapon": weapon})

	var tr: Dictionary = Ballistics.trace(state, tank_id, angle, power, weapon,
			SimConstants.WIND_USE_STATE, SimConstants.MAX_FLIGHT_TICKS)
	var ticks: int = tr["ticks"]
	var reason: String = tr["end_reason"]
	var ex: int = tr["end_x"]
	var ey: int = tr["end_y"]
	events.append({"type": "projectile", "tick": 0, "id": 0, "weapon": weapon, "path": tr["path"]})
	events.append({"type": "projectile_end", "tick": ticks, "id": 0, "reason": reason, "x": ex, "y": ey})

	var was_alive: Array[bool] = []
	for t: TankState in state.tanks:
		was_alive.append(t.alive)
	if reason == "terrain" or reason == "tank":
		_resolve_explosion(state, ex, ey, weapon, def, ticks, events)
	for t: TankState in state.tanks:
		if was_alive[t.id] and not t.alive:
			events.append({"type": "tank_destroyed", "tick": ticks, "tank": t.id})
	_finish_turn(state, ticks, events)


## explosion -> terrain_carve -> damage* -> terrain_settle -> tank_fall* -> damage(fall)*
static func _resolve_explosion(state: MatchState, ex: int, ey: int, weapon: String, def: Dictionary,
		tick: int, events: Array[Dictionary]) -> void:
	var radius: int = def["radius"]
	var max_damage: int = def["damage"]
	events.append({"type": "explosion", "tick": tick, "x": ex, "y": ey, "radius": radius, "weapon": weapon})
	var rect: Rect2i = state.terrain.carve_circle(ex, ey, radius)
	events.append({"type": "terrain_carve", "tick": tick, "x": ex, "y": ey, "radius": radius})
	for d: Dictionary in Damage.compute(state, ex, ey, radius, max_damage):
		_damage_tank(state, d["tank"], d["amount"], "explosion", tick, events)
	if rect.size.x <= 0:
		return
	var x0: int = rect.position.x
	var x1: int = rect.end.x - 1
	var falls: Array[Dictionary] = state.terrain.settle(x0, x1)
	events.append({"type": "terrain_settle", "tick": tick, "x0": x0, "x1": x1, "falls": falls})
	var half: int = SimConstants.TANK_W / 2
	for t: TankState in state.tanks:
		if not t.alive or t.x + half <= x0 or t.x - half > x1:
			continue
		var new_y: int = TankState.rest_y(state.terrain, t.x)
		if new_y <= t.y:
			continue
		var fall: int = new_y - t.y
		events.append({"type": "tank_fall", "tick": tick, "tank": t.id, "from_y": t.y, "to_y": new_y})
		t.y = new_y
		if fall > SimConstants.FALL_SAFE:
			var amt: int = (fall - SimConstants.FALL_SAFE) / SimConstants.FALL_DMG_DIV
			if amt > 0:
				_damage_tank(state, t.id, amt, "fall", tick, events)


static func _damage_tank(state: MatchState, tank_id: int, amt: int, cause: String, tick: int,
		events: Array[Dictionary]) -> void:
	var t: TankState = state.tanks[tank_id]
	t.health = maxi(0, t.health - amt)
	if t.health == 0:
		t.alive = false
	events.append({"type": "damage", "tick": tick, "tank": tank_id, "amount": amt, "health": t.health, "cause": cause})


## round_end, or the next alive tank's turn plus a wind drift.
static func _finish_turn(state: MatchState, tick: int, events: Array[Dictionary]) -> void:
	var alive_count: int = 0
	var last_alive: int = -1
	for t: TankState in state.tanks:
		if t.alive:
			alive_count += 1
			last_alive = t.id
	if alive_count <= 1:
		events.append({"type": "round_end", "tick": tick, "winner": last_alive})
		var last_round: bool = state.round_index + 1 >= state.settings.rounds
		state.phase = SimConstants.PHASE_MATCH_OVER if last_round else SimConstants.PHASE_ROUND_OVER
		return
	var n: int = state.tanks.size()
	var next: int = state.current_tank
	for step: int in range(1, n + 1):
		var cand: int = (state.current_tank + step) % n
		if state.tanks[cand].alive:
			next = cand
			break
	state.current_tank = next
	state.turn_number += 1
	var wind_rng: Rng = Rng.from_state(state.wind_rng_state)
	var wm: int = state.settings.wind_max
	state.wind = clampi(state.wind + wind_rng.range_int(-SimConstants.WIND_DRIFT, SimConstants.WIND_DRIFT), -wm, wm)
	state.wind_rng_state = wind_rng.get_state()
	events.append({"type": "wind", "tick": tick, "wind": state.wind})
	events.append({"type": "turn", "tick": tick, "tank": next})


## First 16 hex chars of SHA-256 over a fixed-order serialization of the state.
static func fingerprint(state: MatchState) -> String:
	var b := StreamPeerBuffer.new()
	b.put_64(state.settings.seed)
	b.put_32(state.settings.num_tanks)
	b.put_32(state.settings.rounds)
	b.put_32(state.settings.wind_max)
	b.put_64(state.seed)
	b.put_32(state.round_index)
	b.put_32(state.wind)
	for w: int in state.wind_rng_state:
		b.put_64(w)
	b.put_32(state.current_tank)
	b.put_32(state.turn_number)
	b.put_32(_phase_code(state.phase))
	b.put_32(state.tanks.size())
	for t: TankState in state.tanks:
		b.put_32(t.id)
		b.put_32(t.team)
		b.put_32(t.x)
		b.put_32(t.y)
		b.put_32(t.health)
		b.put_32(t.angle)
		b.put_32(t.power)
		b.put_32(1 if t.alive else 0)
		b.put_32(t.color_index)
	b.put_32(state.terrain.width)
	b.put_32(state.terrain.height)
	b.put_data(state.terrain.cells)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(b.data_array)
	return ctx.finish().hex_encode().substr(0, 16)


static func _phase_code(phase: String) -> int:
	if phase == SimConstants.PHASE_AIM:
		return 0
	if phase == SimConstants.PHASE_ROUND_OVER:
		return 1
	return 2
