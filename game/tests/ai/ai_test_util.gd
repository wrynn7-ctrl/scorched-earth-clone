class_name AiTestUtil
extends RefCounted
## Helpers shared by the AI tests (not a test file itself): scenario builders, a "shoot until
## it hits" loop and small statistics helpers.

const SHOOTER: int = 0
const TARGET: int = 1


## A started 2-tank match on a generated map. Tank 0 is the AI shooter (`level`, a
## SimConstants.CTRL_* value) and stands `dist` cells from the stationary target (tank 1,
## human-controlled, so it never acts). The pair is placed at a random spot (and mirrored at
## random) from `seed`; the wind is forced to `wind`. `stock` is {weapon_id: units} for the
## shooter (Pulse Missiles by default).
static func duel(seed_value: int, level: int, dist: int, wind: int, stock: Dictionary = {}) -> MatchState:
	var settings := MatchSettings.new()
	settings.seed = seed_value
	settings.num_tanks = 2
	settings.rounds = 3
	settings.controllers = PackedInt32Array([level, SimConstants.CTRL_HUMAN])
	var state: MatchState = Simulation.new_match(settings)
	SimTestUtil.begin_round(state)
	var rng: Rng = Rng.derive(seed_value, 777)
	var left: int = rng.range_int(40, SimConstants.WORLD_W - 40 - dist)
	var right: int = left + dist
	var mirrored: bool = rng.chance(1, 2)
	_place(state, SHOOTER, right if mirrored else left)
	_place(state, TARGET, left if mirrored else right)
	state.wind = wind
	state.current_tank = SHOOTER
	var s: Dictionary = stock if not stock.is_empty() else {"pulse_missile": 50}
	for id: String in s.keys():
		state.tanks[SHOOTER].set_stock(id, s[id])
	return state


## A hand-built duel on perfectly flat ground (see SimTestUtil.flat_state): the AI shooter
## (tank 0) at x = 300 and the idle target (tank 1) `dist` cells to its right. `stock` as in duel().
static func flat_duel(level: int, dist: int, wind: int, stock: Dictionary) -> MatchState:
	var state: MatchState = SimTestUtil.flat_state(2)
	state.settings.controllers = PackedInt32Array([level, SimConstants.CTRL_HUMAN])
	state.tanks[SHOOTER].x = 300
	state.tanks[TARGET].x = 300 + dist
	state.tanks[SHOOTER].set_stock("pulse_missile", 0)
	state.tanks[TARGET].set_stock("pulse_missile", 0)
	for id: String in stock.keys():
		state.tanks[SHOOTER].set_stock(id, stock[id])
	state.wind = wind
	state.current_tank = SHOOTER
	return state


static func _place(state: MatchState, tank_id: int, cx: int) -> void:
	var terrain: Terrain = state.terrain
	terrain.flatten(cx - 14, cx + 13, terrain.surface_y(cx))
	var t: TankState = state.tanks[tank_id]
	t.x = cx
	t.y = TankState.rest_y(terrain, cx)
	t.health = SimConstants.MAX_HEALTH


## Calls the AI until it ends the turn (fire / pass / repair), applying each action.
## Returns {action, events, calls}: the turn-ending action, its timeline, and how many
## calls it took. Gives up (action = {}) after 6 calls.
static func play_turn(state: MatchState, tank_id: int) -> Dictionary:
	for call: int in range(1, 7):
		var action: Dictionary = AiPlayer.next_action(state, tank_id)
		var events: Array[Dictionary] = Simulation.apply_action(state, action)
		var kind: String = action["kind"]
		var ends: bool = kind == "fire" or kind == "pass" or \
				(kind == "use_item" and action["item"] == "nanorepair_kit")
		if ends:
			return {"action": action, "events": events, "calls": call}
	return {"action": {}, "events": [], "calls": 6}


## Lets the idle target tank pass so the shooter has the turn again.
static func give_turn_back(state: MatchState) -> void:
	var guard: int = 0
	while state.phase == SimConstants.PHASE_AIM and state.current_tank != SHOOTER and guard < 8:
		Simulation.apply_action(state, SimTestUtil.pass_turn(state.current_tank))
		guard += 1


## The shooter fires up to `max_shots` times at the stationary target. Returns
## {first_hit (1-based shot number of the first hit, 0 if none), misses: Array[int] distance of
## each shot's impact to the target's box}. A hit is any damage event (or a shield hit) on the
## target.
static func shoot_until_hit(state: MatchState, max_shots: int) -> Dictionary:
	var misses: Array[int] = []
	for shot: int in range(1, max_shots + 1):
		give_turn_back(state)
		if state.phase != SimConstants.PHASE_AIM or not state.tanks[SHOOTER].alive:
			break
		var turn: Dictionary = play_turn(state, SHOOTER)
		var events: Array[Dictionary] = turn["events"]
		misses.append(impact_miss(state, events))
		if hit_target(events):
			return {"first_hit": shot, "misses": misses}
		if not state.tanks[TARGET].alive:
			break
	return {"first_hit": 0, "misses": misses}


static func hit_target(events: Array[Dictionary]) -> bool:
	for e: Dictionary in events:
		var type: String = e["type"]
		if (type == "damage" or type == "shield_hit") and (e["tank"] as int) == TARGET:
			return true
	return false


## Distance (cells) from the impact point of the shot in `events` to the target's hit box
## (0 when inside); 100000 when the shell was lost.
static func impact_miss(state: MatchState, events: Array[Dictionary]) -> int:
	var t: TankState = state.tanks[TARGET]
	for e: Dictionary in events:
		if e["type"] == "projectile_end" and e["reason"] != "lost" and e["reason"] != "timeout":
			var half: int = SimConstants.TANK_W / 2
			var dx: int = maxi(maxi(t.x - half - (e["x"] as int), (e["x"] as int) - (t.x + half - 1)), 0)
			var dy: int = maxi(maxi(t.y - SimConstants.TANK_H - (e["y"] as int), (e["y"] as int) - (t.y - 1)), 0)
			return FixedMath.isqrt(dx * dx + dy * dy)
	return 100000


## Median of a list of ints (lower middle for even sizes).
static func median(values: Array[int]) -> int:
	if values.is_empty():
		return 0
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	return sorted[(sorted.size() - 1) / 2]


## The p-th percentile (0..100) of a list of ints.
static func percentile(values: Array[int], p: int) -> int:
	if values.is_empty():
		return 0
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size() - 1, (sorted.size() * p + 99) / 100 - 1)]


## Scenario parameters for scenario number `i` of a batch: distance 300..1200, wind -100..100.
static func params(i: int, tag: int) -> Vector2i:
	var r: Rng = Rng.derive(i * 7919 + tag, 4242)
	return Vector2i(r.range_int(300, 1200), r.range_int(-100, 100))


## Plays a whole match where every tank is run by the AI (`controllers`, one SimConstants.CTRL_*
## per tank). Returns {state, errors: Array[String] (illegal actions / failed starts),
## turns, max_calls (most AI calls in one turn), stalled (hit the safety limit),
## traces_max (most real traces in one decision)}.
static func run_match(seed_value: int, controllers: PackedInt32Array, rounds: int) -> Dictionary:
	var settings := MatchSettings.new()
	settings.seed = seed_value
	settings.num_tanks = controllers.size()
	settings.rounds = rounds
	settings.controllers = controllers
	var state: MatchState = Simulation.new_match(settings)
	var errors: Array[String] = []
	var turns: int = 0
	var calls: int = 0
	var max_calls: int = 0
	var traces_max: int = 0
	var last_turn_key: int = -1
	var guard: int = 0
	while state.phase != SimConstants.PHASE_MATCH_OVER and guard < 6000:
		guard += 1
		if state.phase == SimConstants.PHASE_SHOP:
			for t: TankState in state.tanks:
				for a: Dictionary in AiPlayer.shop_actions(state, t.id):
					var err: String = Simulation.validate_action(state, a)
					if err != "":
						errors.append("shop %s: %s" % [str(a), err])
					Simulation.apply_action(state, a)
			if Simulation.start_round(state).is_empty():
				errors.append("start_round failed")
				break
			last_turn_key = -1
			continue
		var tank: int = state.current_tank
		var key: int = state.round_index * 100000 + state.turn_number
		calls = calls + 1 if key == last_turn_key else 1
		last_turn_key = key
		max_calls = maxi(max_calls, calls)
		var action: Dictionary = AiPlayer.next_action(state, tank)
		traces_max = maxi(traces_max, AimSolver.trace_count)
		var verr: String = Simulation.validate_action(state, action)
		if verr != "":
			errors.append("aim %s: %s" % [str(action), verr])
			break
		Simulation.apply_action(state, action)
		turns += 1
	return {"state": state, "errors": errors, "turns": turns, "max_calls": max_calls,
			"stalled": guard >= 6000, "traces_max": traces_max}


## A varied mid-round state for fuzzing: 2..6 tanks with random AI levels, random stock of every
## weapon and item, random shields, health, fuel and wells, a random wind, and a few AI turns
## already played (so TankState.last_fire_* is filled in). Always in the aim phase.
static func random_state(i: int) -> MatchState:
	for attempt: int in range(4):
		var s: MatchState = _random_state_try(i * 4 + attempt, attempt == 0)
		if s.phase == SimConstants.PHASE_AIM:
			return s
	return duel(9000 + i, SimConstants.CTRL_NORMAL, 600, 0)


static func _random_state_try(i: int, play: bool) -> MatchState:
	var r: Rng = Rng.derive(i * 31 + 5, 99)
	var n: int = r.range_int(2, 6)
	var settings := MatchSettings.new()
	settings.seed = 5000 + i
	settings.num_tanks = n
	settings.rounds = 3
	settings.start_money = r.range_int(0, 30000)
	var ctrl := PackedInt32Array()
	for _k: int in range(n):
		ctrl.append(r.range_int(1, 4))
	settings.controllers = ctrl
	var state: MatchState = Simulation.new_match(settings)
	SimTestUtil.begin_round(state)
	for t: TankState in state.tanks:
		for id: String in Catalog.IDS:
			if id != Catalog.SPARK_DART and r.chance(1, 2):
				t.set_stock(id, r.range_int(1, 4))
		t.fuel = r.range_int(0, 2) * 60
		t.health = r.range_int(8, 100)
	if play:
		for _k: int in range(r.range_int(0, 6)):
			if state.phase == SimConstants.PHASE_AIM:
				play_turn(state, state.current_tank)
	if state.phase != SimConstants.PHASE_AIM:
		return state
	for t: TankState in state.tanks:
		if t.alive and r.chance(1, 4):
			var shields: Array[String] = ["glow_shield", "ion_shield", "fortress_field"]
			var id: String = shields[r.range_int(0, 2)]
			t.shield_type = Catalog.index_of(id)
			t.shield_hp = r.range_int(5, ItemDefs.get_def(id)["hp"] as int)
		if r.chance(1, 8):
			t.repulsor_charge = r.range_int(10, 100)
	state.wind = r.range_int(-100, 100)
	if state.wells.is_empty() and r.chance(1, 4):
		state.wells.append({"owner": r.range_int(0, n - 1), "x": r.range_int(300, 1300), "y": r.range_int(200, 600),
				"expires_turn": state.turn_number + 5})
	return state


## Flat ground, `n` tanks spread along it (see SimTestUtil.flat_state); tank 0 is the AI at
## `level`, the others are human (idle). Tank 0 owns 20 Pulse Missiles.
static func flat_ffa(level: int, n: int) -> MatchState:
	var state: MatchState = SimTestUtil.flat_state(n)
	var ctrl := PackedInt32Array()
	for i: int in range(n):
		ctrl.append(level if i == 0 else SimConstants.CTRL_HUMAN)
	state.settings.controllers = ctrl
	state.tanks[0].set_stock("pulse_missile", 20)
	return state
