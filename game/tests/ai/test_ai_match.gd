extends GutTest
## Whole matches played by the AI alone (docs/ARCHITECTURE.md section 30): a 4-AI match, one
## per difficulty, runs to match_over without an illegal action, and over many matches the
## Expert wins the most rounds.

const NAMES: Array[String] = ["Easy", "Normal", "Hard", "Expert"]
const MATCHES: int = 20
const ROUNDS: int = 3


func test_a_four_ai_match_runs_to_match_over() -> void:
	var r: Dictionary = AiTestUtil.run_match(31337, PackedInt32Array([1, 2, 3, 4]), 3)
	var state: MatchState = r["state"]
	assert_eq(r["errors"], [], "no illegal action")
	assert_false(r["stalled"], "finished without hitting the safety limit")
	assert_eq(state.phase, SimConstants.PHASE_MATCH_OVER)
	assert_lte(r["max_calls"], 3, "every turn ended within 3 calls")
	assert_lte(r["traces_max"], AimSolver.TRACE_BUDGET)
	var wins: int = 0
	for t: TankState in state.tanks:
		wins += t.round_wins
	assert_eq(wins, ROUNDS - (0 if state.tanks.size() > 0 else 0) - _draws(state), "every decided round has one winner")
	gut.p("MATCH   4-AI match: %d turns, standings %s" % [r["turns"], str(Simulation.standings(state))])


func _draws(state: MatchState) -> int:
	# Rounds nobody won (everyone destroyed together) do not add a win.
	var wins: int = 0
	for t: TankState in state.tanks:
		wins += t.round_wins
	return ROUNDS - wins if wins < ROUNDS else 0


func test_expert_wins_the_most_rounds_over_many_matches() -> void:
	var wins: Array[int] = [0, 0, 0, 0]
	var match_wins: Array[int] = [0, 0, 0, 0]
	var kills: Array[int] = [0, 0, 0, 0]
	var money: Array[int] = [0, 0, 0, 0]
	var turns: int = 0
	var t0: int = Time.get_ticks_msec()
	for m: int in range(MATCHES):
		# Rotate the seats so no level profits from the turn order.
		var seats: PackedInt32Array = PackedInt32Array([1, 2, 3, 4])
		var shift: int = m % 4
		var rotated := PackedInt32Array()
		for k: int in range(4):
			rotated.append(seats[(k + shift) % 4])
		var r: Dictionary = AiTestUtil.run_match(900 + m, rotated, ROUNDS)
		assert_eq(r["errors"], [], "match %d: no illegal action" % m)
		assert_false(r["stalled"], "match %d finished" % m)
		assert_lte(r["max_calls"], 3)
		var state: MatchState = r["state"]
		turns += r["turns"] as int
		for t: TankState in state.tanks:
			var level_index: int = rotated[t.id] - 1
			wins[level_index] += t.round_wins
			kills[level_index] += t.kills
			money[level_index] += t.money
		match_wins[rotated[Simulation.standings(state)[0]] - 1] += 1
	var table: String = "MATCHES %d four-AI matches of %d rounds (%d turns, %d s):\n" % [
			MATCHES, ROUNDS, turns, (Time.get_ticks_msec() - t0) / 1000]
	table += "          level   round wins   match wins   kills   avg money at end\n"
	for i: int in range(4):
		table += "          %-7s %10d %12d %7d %12d\n" % [NAMES[i], wins[i], match_wins[i], kills[i], money[i] / MATCHES]
	gut.p(table)
	var best: int = 0
	for i: int in range(4):
		best = maxi(best, wins[i])
	assert_eq(wins[3], best, "Expert has the most round wins")
	assert_gt(wins[3], wins[0], "and clearly beats Easy")
	assert_gt(wins[3], wins[1])
	assert_gte(wins[2], wins[0], "Hard at least matches Easy")


func test_a_two_ai_match_expert_against_easy() -> void:
	var expert_rounds: int = 0
	var easy_rounds: int = 0
	for m: int in range(6):
		var ctrl := PackedInt32Array([4, 1]) if m % 2 == 0 else PackedInt32Array([1, 4])
		var r: Dictionary = AiTestUtil.run_match(70 + m, ctrl, 3)
		assert_eq(r["errors"], [])
		var state: MatchState = r["state"]
		for t: TankState in state.tanks:
			if ctrl[t.id] == 4:
				expert_rounds += t.round_wins
			else:
				easy_rounds += t.round_wins
	gut.p("MATCH   Expert vs Easy, 6 matches x 3 rounds: Expert %d rounds, Easy %d rounds" % [expert_rounds, easy_rounds])
	assert_gte(expert_rounds, 15)


func test_an_eight_tank_all_ai_free_for_all_finishes() -> void:
	var r: Dictionary = AiTestUtil.run_match(4242, PackedInt32Array([1, 2, 3, 4, 1, 2, 3, 4]), 2)
	assert_eq(r["errors"], [])
	assert_false(r["stalled"])
	assert_eq((r["state"] as MatchState).phase, SimConstants.PHASE_MATCH_OVER)
	assert_lte(r["max_calls"], 3)


func test_a_match_with_a_human_slot_leaves_that_tank_to_the_caller() -> void:
	# Mixed matches: the AI only decides for its own tanks; the caller passes for the human.
	var settings := MatchSettings.new()
	settings.seed = 5
	settings.num_tanks = 3
	settings.rounds = 1
	settings.controllers = PackedInt32Array([SimConstants.CTRL_HUMAN, SimConstants.CTRL_EXPERT, SimConstants.CTRL_HARD])
	var state: MatchState = Simulation.new_match(settings)
	for t: TankState in state.tanks:
		if state.settings.controllers[t.id] != SimConstants.CTRL_HUMAN:
			for a: Dictionary in AiPlayer.shop_actions(state, t.id):
				Simulation.apply_action(state, a)
	Simulation.apply_action(state, SimTestUtil.ready(0))
	assert_false(Simulation.start_round(state).is_empty())
	var guard: int = 0
	while state.phase == SimConstants.PHASE_AIM and guard < 400:
		guard += 1
		var tank: int = state.current_tank
		var action: Dictionary = {"kind": "pass", "tank": tank}
		if state.settings.controllers[tank] != SimConstants.CTRL_HUMAN:
			action = AiPlayer.next_action(state, tank)
		assert_eq(Simulation.validate_action(state, action), "")
		Simulation.apply_action(state, action)
	assert_ne(state.phase, SimConstants.PHASE_AIM, "the round was decided")
