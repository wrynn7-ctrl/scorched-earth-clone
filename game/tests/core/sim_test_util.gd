class_name SimTestUtil
extends RefCounted
## Shared helpers for core tests (not a test file itself).

const GROUND_Y: int = 600


## Hand-built match on perfectly flat ground (solid below GROUND_Y). Tanks stand on it at
## x = 300 + i * 1000 / (n - 1) spacing; wind 0; 3 rounds so a round end is not match end.
static func flat_state(num_tanks: int = 2) -> MatchState:
	var s := MatchState.new()
	s.settings.seed = 1
	s.settings.num_tanks = num_tanks
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
		s.tanks.append(t)
	s.wind = 0
	s.wind_rng_state = Rng.derive(1, SimConstants.TAG_WIND).get_state()
	s.current_tank = 0
	return s


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
