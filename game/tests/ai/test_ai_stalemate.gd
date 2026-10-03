@warning_ignore_start("integer_division")
extends GutTest
## M5 stalemate fix: two computers that cannot reach each other must not fire the same lost shot for
## ever. When nothing reaches, every level walks closer (fuel allowing) or fires at full power at the
## best angle (see AiPlayer._out_of_reach); a CPU that spent a round out of range buys Fuel Cells.

const LEFT: int = 0
const RIGHT: int = 1


## A flat 2-tank field, `gap` cells apart, both tanks computer-controlled at `level`, Spark Dart only.
func _field(level: int, gap: int, cells: int) -> MatchState:
	var state: MatchState = SimTestUtil.flat_state(2)
	state.settings.controllers = PackedInt32Array([level, level])
	state.tanks[LEFT].x = 100
	state.tanks[RIGHT].x = 100 + gap
	for t: TankState in state.tanks:
		t.set_stock("pulse_missile", 0)
		t.set_stock("fuel_cell", cells)
	return state


## The wind that blows against whoever is about to shoot.
static func _headwind(state: MatchState, strength: int) -> int:
	return -strength if state.current_tank == LEFT else strength


## Plays `turns` turns (alternating) under a constant headwind. Returns per tank
## {xs: x at the start of each own turn, shots: [{angle, power, land_x}], kinds: action kinds, max_calls}.
func _play(state: MatchState, turns: int, wind: int, vary_wind: bool = false) -> Array[Dictionary]:
	var logs: Array[Dictionary] = [
		{"xs": [] as Array[int], "shots": [] as Array[Dictionary], "max_calls": 0},
		{"xs": [] as Array[int], "shots": [] as Array[Dictionary], "max_calls": 0}]
	for _i: int in range(turns):
		if state.phase != SimConstants.PHASE_AIM:
			break
		var id: int = state.current_tank
		if not vary_wind:
			state.wind = _headwind(state, wind)
		(logs[id]["xs"] as Array[int]).append(state.tanks[id].x)
		var turn: Dictionary = AiTestUtil.play_turn(state, id)
		var action: Dictionary = turn["action"]
		logs[id]["max_calls"] = maxi(logs[id]["max_calls"] as int, turn["calls"] as int)
		if action.get("kind", "") == "fire":
			var land: int = -1
			for e: Dictionary in (turn["events"] as Array[Dictionary]):
				if e["type"] == "projectile_end":
					land = e["x"]
					break
			(logs[id]["shots"] as Array[Dictionary]).append(
					{"angle": action["angle"], "power": action["power"], "land_x": land})
	return logs


## A full-height ridge in the middle: with the headwind no Spark Dart from the far end reaches over it
## from the usual angles at the usual power (a stand-in for the QA stalemate: far apart, strong headwind).
func _ridge(state: MatchState, top: int) -> void:
	state.terrain.flatten(740, 860, top)
	for t: TankState in state.tanks:
		t.y = TankState.rest_y(state.terrain, t.x)


func _hopeless_field(level: int, cells: int) -> MatchState:
	var state: MatchState = _field(level, 1400, cells)
	_ridge(state, 80)
	return state


func _distance(state: MatchState) -> int:
	return absi(state.tanks[RIGHT].x - state.tanks[LEFT].x)


## Landing distance (cells) from the shooter's shell to the other tank, per shot.
func _miss(land_x: int, other_x: int) -> int:
	return absi(land_x - other_x)


func test_far_apart_with_fuel_each_cpu_moves_closer_or_lands_near() -> void:
	for level: int in range(SimConstants.CTRL_EASY, SimConstants.CTRL_EXPERT + 1):
		var state: MatchState = _hopeless_field(level, 1)
		var start_gap: int = _distance(state)
		var logs: Array[Dictionary] = _play(state, 24, 100)
		for id: int in [LEFT, RIGHT]:
			var xs: Array[int] = logs[id]["xs"]
			var walked: bool = xs.size() > 1 and xs[xs.size() - 1] != xs[0]
			var best_miss: int = 1 << 30
			for shot: Dictionary in (logs[id]["shots"] as Array[Dictionary]):
				var other_x: int = state.tanks[1 - id].x
				best_miss = mini(best_miss, _miss(shot["land_x"] as int, other_x))
			assert_true(walked or best_miss <= 150, "level %d tank %d neither moved (%s) nor landed near (%d)" % [level, id, str(xs.slice(0, 4)), best_miss])
			assert_lte(logs[id]["max_calls"] as int, 3, "turn within 3 calls")
		assert_lt(_distance(state), start_gap, "level %d: the pair ended closer than it started" % level)


func test_walk_is_one_move_of_at_most_200_cells_towards_the_enemy_then_the_shot() -> void:
	for level: int in range(SimConstants.CTRL_NORMAL, SimConstants.CTRL_EXPERT + 1):
		var state: MatchState = _hopeless_field(level, 2)
		state.wind = -100
		var first: Dictionary = AiPlayer.next_action(state, LEFT)
		assert_eq(first["kind"], "move", "level %d walks when nothing reaches" % level)
		assert_eq(first["dx"], 200, "level %d: the longest walk, towards the enemy on the right" % level)
		assert_eq(Simulation.validate_action(state, first), "")
		Simulation.apply_action(state, first)
		assert_eq(state.tanks[LEFT].x, 300, "walked the whole 200 cells on flat ground")
		var second: Dictionary = AiPlayer.next_action(state, LEFT)
		assert_ne(second["kind"], "move", "level %d: fuel is spent, so now it shoots" % level)
		assert_eq(second["kind"], "fire")


func test_easy_also_walks_once_a_full_power_shot_has_fallen_short() -> void:
	var state: MatchState = _hopeless_field(SimConstants.CTRL_EASY, 1)
	state.wind = -100
	# Easy believes there is no wind, so the first shot is an honest-looking attempt at full power.
	var turn: Dictionary = AiTestUtil.play_turn(state, LEFT)
	assert_eq(turn["action"]["kind"], "fire")
	assert_gte(turn["action"]["power"] as int, AiPlayer.FULL_POWER, "capped at full power")
	var xs: Array[int] = []
	for _i: int in range(4):
		state.wind = _headwind(state, 100)
		var id: int = state.current_tank
		if id == LEFT:
			xs.append(state.tanks[LEFT].x)
		AiTestUtil.play_turn(state, id)
	assert_gt(xs[xs.size() - 1], 100, "Easy walked closer after its shot fell short: %s" % str(xs))


func test_without_fuel_it_fires_full_power_at_the_angle_that_lands_closest() -> void:
	for level: int in range(SimConstants.CTRL_NORMAL, SimConstants.CTRL_EXPERT + 1):
		var state: MatchState = _hopeless_field(level, 0)
		state.wind = -100
		var action: Dictionary = AiPlayer.next_action(state, LEFT)
		assert_eq(action["kind"], "fire", "level %d" % level)
		assert_eq(action["power"], SimConstants.MAX_POWER, "level %d: the best attempt is full power" % level)
		assert_eq(action["weapon"], "spark_dart")
		# Judged with the wind this level believes in (it aims with a share of the real one).
		var wind: int = -100 * (AiProfile.for_level(level)["wind_use"] as int) / 1000
		var landed: int = (Ballistics.trace(state, LEFT, action["angle"], action["power"], "spark_dart", wind, 600) as Dictionary)["end_x"]
		var target_x: int = state.tanks[RIGHT].x
		for angle: int in [300, 450, 600, 750]:
			var other: int = (Ballistics.trace(state, LEFT, angle, SimConstants.MAX_POWER, "spark_dart", wind, 600) as Dictionary)["end_x"]
			# Within a few cells: the AI judges with its own (partly believed) wind, and anything past the target is no better.
			assert_lte(absi(landed - target_x), absi(other - target_x) + 40, "level %d: angle %d would land closer" % [level, angle])


func test_without_fuel_the_shots_still_change_with_the_wind_and_get_closer() -> void:
	for level: int in range(SimConstants.CTRL_NORMAL, SimConstants.CTRL_EXPERT + 1):
		var state: MatchState = _hopeless_field(level, 0)
		var logs: Array[Dictionary] = _play(state, 40, 0, true)
		var landings: Dictionary = {}
		for shot: Dictionary in (logs[LEFT]["shots"] as Array[Dictionary]):
			landings[shot["land_x"]] = true
		assert_gt(landings.size(), 3, "level %d: not the same lost shot every turn (%d distinct landings)" % [level, landings.size()])


func test_an_unreachable_enemy_with_ordinary_ground_is_not_treated_as_hopeless() -> void:
	# Flat ground, 700 apart: everything reaches, nobody walks even with fuel in the tank.
	for level: int in range(SimConstants.CTRL_EASY, SimConstants.CTRL_EXPERT + 1):
		var state: MatchState = _field(level, 700, 2)
		state.wind = 0
		var action: Dictionary = AiPlayer.next_action(state, LEFT)
		assert_eq(action["kind"], "fire", "level %d just shoots" % level)


func test_no_walk_with_more_fuel_than_one_walk_burns() -> void:
	var state: MatchState = _hopeless_field(SimConstants.CTRL_NORMAL, 3)
	state.wind = -100
	assert_ne(AiPlayer.next_action(state, LEFT)["kind"], "move", "3 cells: a walk could not be limited to one call")


# --- shop ---------------------------------------------------------------------------------------------

func _shop_state(level: int, turns: int, last_x: int, money: int = 5000) -> MatchState:
	var settings := MatchSettings.new()
	settings.seed = 11
	settings.num_tanks = 2
	settings.rounds = 3
	settings.start_money = money
	settings.controllers = PackedInt32Array([level, level])
	var state: MatchState = Simulation.new_match(settings)
	state.turn_number = turns
	state.tanks[LEFT].x = 100
	state.tanks[RIGHT].x = 1400
	state.tanks[LEFT].last_fire_weapon = 0
	state.tanks[LEFT].last_fire_x = last_x
	return state


func _cells_bought(state: MatchState, tank: int = LEFT) -> int:
	var n: int = 0
	for a: Dictionary in AiPlayer.shop_actions(state, tank):
		if a["kind"] == "buy" and a["item"] == "fuel_cell":
			n += a["qty"] as int
	return n


func test_a_cpu_that_spent_the_round_out_of_range_buys_a_fuel_cell() -> void:
	for level: int in range(SimConstants.CTRL_EASY, SimConstants.CTRL_EXPERT + 1):
		var state: MatchState = _shop_state(level, 40, 700)  # long round, last shot 700 from anyone
		assert_true(AiShop.was_out_of_range(state, LEFT))
		assert_eq(_cells_bought(state), 1, "level %d: one cell" % level)
		var lost: MatchState = _shop_state(level, 40, -1)  # last shell lost off the map
		assert_eq(_cells_bought(lost), 1, "level %d: lost shells count too" % level)


func test_a_very_long_round_buys_two_cells_and_the_actions_are_legal() -> void:
	var state: MatchState = _shop_state(SimConstants.CTRL_NORMAL, 80, 700)
	assert_eq(_cells_bought(state), 2)
	for a: Dictionary in AiPlayer.shop_actions(state, LEFT):
		assert_eq(Simulation.validate_action(state, a), "", str(a))
		Simulation.apply_action(state, a)
	assert_eq(state.tanks[LEFT].stock_of("fuel_cell"), 2)


func test_no_fuel_after_a_short_round_a_close_shot_or_when_broke_or_already_stocked() -> void:
	assert_eq(_cells_bought(_shop_state(SimConstants.CTRL_NORMAL, 8, 700)), 0, "short round")
	assert_eq(_cells_bought(_shop_state(SimConstants.CTRL_NORMAL, 40, 1350)), 0, "last shot landed near the enemy")
	assert_false(AiShop.was_out_of_range(_shop_state(SimConstants.CTRL_NORMAL, 40, 1350), LEFT))
	assert_eq(_cells_bought(_shop_state(SimConstants.CTRL_NORMAL, 40, 700, 800)), 0, "cannot afford 1000")
	var stocked: MatchState = _shop_state(SimConstants.CTRL_NORMAL, 40, 700)
	stocked.tanks[LEFT].set_stock("fuel_cell", 2)
	assert_eq(_cells_bought(stocked), 0, "never more fuel than one walk burns")


func test_the_fuel_shopping_is_deterministic() -> void:
	var a: Array[Dictionary] = AiPlayer.shop_actions(_shop_state(SimConstants.CTRL_EASY, 40, 700), LEFT)
	var b: Array[Dictionary] = AiPlayer.shop_actions(_shop_state(SimConstants.CTRL_EASY, 40, 700), LEFT)
	assert_eq(a, b)


# --- whole matches ------------------------------------------------------------------------------------------

const QA_AI = preload("res://tests/qa/qa_ai.gd")
const FUZZ_MATCHES: int = 40
const FUZZ_SEED: int = 0xA1F00D
const MAX_ROUND_TURNS: int = 250


func test_no_round_of_the_fuzz_matches_exceeds_250_turns() -> void:
	var rounds: Array[int] = []
	for m: int in range(FUZZ_MATCHES):
		var settings: MatchSettings = QA_AI.random_settings(m, FUZZ_SEED)
		var res: Dictionary = QA_AI.play_match(settings, 1000000, 1000000, 1000000)
		for n: int in (res["turns_per_round"] as Array[int]):
			rounds.append(n)
		assert_false(res["stalled"], "match %d stalled: %s" % [m, str(res.get("stall_info", ""))])
	var worst: int = 0
	for n: int in rounds:
		worst = maxi(worst, n)
	gut.p("STALEMATE fuzz subset: %d matches, %d rounds, turns per round median %d, p95 %d, max %d" % [
			FUZZ_MATCHES, rounds.size(), QA_AI.percentile(rounds, 50), QA_AI.percentile(rounds, 95), worst])
	assert_lte(worst, MAX_ROUND_TURNS)
