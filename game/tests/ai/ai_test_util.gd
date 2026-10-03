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
