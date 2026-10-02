class_name WeaponTestUtil
extends RefCounted
## Shared helpers for the weapon behaviour tests (not a test file itself).

const U = preload("res://tests/core/sim_test_util.gd")


## Fires `weapon` for the current tank (stock is topped up first) and returns the timeline.
static func fire(state: MatchState, weapon: String, angle: int, power: int) -> Array[Dictionary]:
	var tank: TankState = state.tanks[state.current_tank]
	if not (WeaponDefs.get_def(weapon).get("unlimited", false) as bool):
		tank.set_stock(weapon, maxi(1, tank.stock_of(weapon)))
	return Simulation.apply_action(state, {"kind": "fire", "tank": tank.id, "angle": angle, "power": power,
			"weapon": weapon})


## Power (1..1000) at which a plain shell fired by `tank_id` at `angle` lands closest to
## `target_x` (coarse scan, then a fine one; ~60 traces).
static func power_for_landing(state: MatchState, angle: int, target_x: int, tank_id: int = 0) -> int:
	var best: int = 1
	var best_d: int = 1 << 40
	for p: int in range(20, 1001, 20):
		var d: int = _miss(state, tank_id, angle, p, target_x)
		if d < best_d:
			best_d = d
			best = p
	for p: int in range(maxi(1, best - 20), mini(1000, best + 20) + 1):
		var d: int = _miss(state, tank_id, angle, p, target_x)
		if d < best_d:
			best_d = d
			best = p
	return best


static func _miss(state: MatchState, tank_id: int, angle: int, power: int, target_x: int) -> int:
	var tr: Dictionary = Ballistics.trace(state, tank_id, angle, power, "pulse_missile", SimConstants.WIND_USE_STATE,
			SimConstants.MAX_FLIGHT_TICKS)
	return absi((tr["end_x"] as int) - target_x)


## Where a plain shell of tank 0 lands (trace dictionary).
static func plain_trace(state: MatchState, angle: int, power: int, tank_id: int = 0) -> Dictionary:
	return Ballistics.trace(state, tank_id, angle, power, "pulse_missile", SimConstants.WIND_USE_STATE,
			SimConstants.MAX_FLIGHT_TICKS)


## Terrain whose surface at column x is `ground(x)` (every column flattened).
static func shaped_state(num_tanks: int, ground: Callable) -> MatchState:
	var s: MatchState = U.flat_state(num_tanks)
	for x: int in range(SimConstants.WORLD_W):
		s.terrain.flatten(x, x, ground.call(x))
	for t: TankState in s.tanks:
		t.y = TankState.rest_y(s.terrain, t.x)
	return s


## Puts tank `id` at column x on a flat pad (the ground under it is levelled to the lowest
## surface in its box so it rests exactly there).
static func place_tank(state: MatchState, id: int, x: int) -> void:
	var t: TankState = state.tanks[id]
	t.x = x
	var half: int = SimConstants.TANK_W / 2
	var y: int = state.terrain.surface_y(x)
	state.terrain.flatten(x - half, x + half - 1, y)
	t.y = TankState.rest_y(state.terrain, x)


static func solid_count(terrain: Terrain) -> int:
	var n: int = 0
	for b: int in terrain.cells:
		if b != 0:
			n += 1
	return n


## Number of solid cells inside the hit box of `t`.
static func solid_in_box(terrain: Terrain, t: TankState) -> int:
	var n: int = 0
	var half: int = SimConstants.TANK_W / 2
	for x: int in range(t.x - half, t.x + half):
		for y: int in range(t.y - SimConstants.TANK_H, t.y):
			if terrain.is_solid(x, y):
				n += 1
	return n


## The show layer's job: re-applies the terrain events of a timeline, in order, to a copy of the
## pre-action terrain, using the same Terrain functions.
static func replay_terrain(before: Terrain, events: Array[Dictionary]) -> Terrain:
	var t: Terrain = before.duplicate_terrain()
	for e: Dictionary in events:
		match e["type"]:
			"terrain_carve":
				t.carve_circle(e["x"], e["y"], e["radius"])
			"tunnel":
				t.carve_tunnel(e["x0"], e["y0"], e["x1"], e["y1"], e["radius"])
			"terrain_add":
				t.add_circle_skipping(e["x"], e["y"], e["radius"], e["material"], e["skip"])
			"terrain_pour":
				t.pour(e["cells"], e["material"])
			"terrain_settle":
				t.settle(e["x0"], e["x1"])
	return t


## True if replaying the events on `before` reproduces `after` byte for byte.
static func replay_matches(before: Terrain, events: Array[Dictionary], after: Terrain) -> bool:
	return replay_terrain(before, events).cells == after.cells


## Stable digest of a timeline (types, ticks and payloads).
static func events_digest(events: Array[Dictionary]) -> String:
	return str(events).sha256_text().substr(0, 16)


## Total damage events (cause filter "" = all) per tank id as a Dictionary.
static func damage_by_tank(events: Array[Dictionary], cause: String = "") -> Dictionary:
	var out: Dictionary = {}
	for e: Dictionary in events:
		if e["type"] == "damage" and (cause == "" or e["cause"] == cause):
			out[e["tank"]] = (out.get(e["tank"], 0) as int) + (e["amount"] as int)
	return out


## Index of the first event of `type` in the timeline, or -1.
static func index_of(events: Array[Dictionary], type: String) -> int:
	for i: int in range(events.size()):
		if events[i]["type"] == type:
			return i
	return -1


## A fresh 4-tank match on generated terrain (seed `seed_value`), every tank stocked with
## 5 units of every weapon.
static func random_match(seed_value: int, tanks: int = 4) -> MatchState:
	var st := MatchSettings.new()
	st.seed = seed_value
	st.num_tanks = tanks
	st.rounds = 3
	var s: MatchState = U.started_match(st)
	for t: TankState in s.tanks:
		for id: String in WeaponDefs.DEFS:
			t.set_stock(id, 5)
	return s
