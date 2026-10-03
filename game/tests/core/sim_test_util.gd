class_name SimTestUtil
extends RefCounted
## Shared helpers for core tests (not a test file itself).

const GROUND_Y: int = 600


## Multiplier for every wall-clock budget in the tests. Read from the PERF_BUDGET_SCALE
## environment variable (e.g. 3 on shared CI runners); 1.0 when unset or unparsable, and never
## below 1.0, so a budget can only be loosened, not tightened.
static func perf_scale() -> float:
	var raw: String = OS.get_environment("PERF_BUDGET_SCALE").strip_edges()
	if raw == "" or not raw.is_valid_float():
		return 1.0
	return maxf(1.0, raw.to_float())


## `base` (an integer budget in whatever unit the test measures) scaled by perf_scale(), rounded up.
static func perf_budget(base: int) -> int:
	return ceili(float(base) * perf_scale())


## Same for fractional budgets (milliseconds as floats).
static func perf_budget_f(base: float) -> float:
	return base * perf_scale()


## Hand-built match on perfectly flat ground (solid below GROUND_Y). Tanks stand on it at
## x = 300 + i * 1000 / (n - 1) spacing; wind 0; 3 rounds so a round end is not match end.
static func flat_state(num_tanks: int = 2) -> MatchState:
	var s := MatchState.new()
	s.settings.seed = 1
	s.settings.num_tanks = num_tanks
	s.settings.controllers.resize(num_tanks)
	s.settings.rounds = 3
	s.seed = 1
	s.round_index = 0
	s.terrain = Terrain.new(SimConstants.WORLD_W, SimConstants.WORLD_H)
	s.terrain.flatten(0, SimConstants.WORLD_W - 1, GROUND_Y)
	for i: int in range(num_tanks):
		var t := TankState.new()
		t.id = i
		t.team = i
		t.color_index = i
		t.x = 300 + (i * 1000) / maxi(1, num_tanks - 1)
		t.y = GROUND_Y
		t.set_stock("pulse_missile", 50)
		s.tanks.append(t)
	s.wind = 0
	s.wind_rng_state = Rng.derive(1, SimConstants.TAG_WIND).get_state()
	s.current_tank = 0
	s.phase = SimConstants.PHASE_AIM
	return s


## Marks every tank ready (through real actions) and starts the next round. Returns the
## start_round events ([] if it could not start).
static func begin_round(state: MatchState) -> Array[Dictionary]:
	for t: TankState in state.tanks:
		if not t.ready:
			Simulation.apply_action(state, {"kind": "ready", "tank": t.id})
	return Simulation.start_round(state)


## new_match + first round started. Every tank gets 50 Pulse Missiles (set directly).
static func started_match(settings: MatchSettings) -> MatchState:
	var s: MatchState = Simulation.new_match(settings)
	begin_round(s)
	for t: TankState in s.tanks:
		t.set_stock("pulse_missile", 50)
	return s


static func buy(tank: int, item: String, qty: int = 1) -> Dictionary:
	return {"kind": "buy", "tank": tank, "item": item, "qty": qty}


static func sell(tank: int, item: String, qty: int = 1) -> Dictionary:
	return {"kind": "sell", "tank": tank, "item": item, "qty": qty}


static func ready(tank: int) -> Dictionary:
	return {"kind": "ready", "tank": tank}


static func move(tank: int, dx: int) -> Dictionary:
	return {"kind": "move", "tank": tank, "dx": dx}


static func use_item(tank: int, item: String) -> Dictionary:
	return {"kind": "use_item", "tank": tank, "item": item}


static func pass_turn(tank: int) -> Dictionary:
	return {"kind": "pass", "tank": tank}


## A fresh new_match (shop phase) with `rounds` rounds.
static func shop_state(num_tanks: int = 2, rounds: int = 3, seed_value: int = 7) -> MatchState:
	var st := MatchSettings.new()
	st.seed = seed_value
	st.num_tanks = num_tanks
	st.rounds = rounds
	return Simulation.new_match(st)


static func types(events: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in events:
		out.append(e["type"])
	return out


static func find(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in events:
		if e["type"] == type:
			out.append(e)
	return out


## Kills every tank except `survivor` through the damage pipeline (no money for anyone).
static func kill_all_but(state: MatchState, survivor: int) -> void:
	var ev: Array[Dictionary] = []
	for t: TankState in state.tanks:
		if t.id != survivor and t.alive:
			Simulation.apply_damage(state, -1, t.id, 1000, "explosion", 0, ev)


## Lowers the terrain to `y` in every column of [x0, x1] (one column at a time).
static func lower_ground(state: MatchState, x0: int, x1: int, y: int) -> void:
	state.terrain.flatten(x0, x1, y)


static func fire(tank: int, angle: int, power: int) -> Dictionary:
	return {"kind": "fire", "tank": tank, "angle": angle, "power": power, "weapon": "pulse_missile"}


## Power (1..1000) whose landing x at `angle` is closest to target_x (shooter = tank 0).
static func power_for_target(state: MatchState, angle: int, target_x: int) -> int:
	var best_p: int = 1
	var best_d: int = 1 << 40
	for p: int in range(1, 1001):
		var tr: Dictionary = Ballistics.trace(state, 0, angle, p, "pulse_missile", 0, SimConstants.MAX_FLIGHT_TICKS)
		var ex: int = tr["end_x"]
		var d: int = absi(ex - target_x)
		if d < best_d:
			best_d = d
			best_p = p
	return best_p
