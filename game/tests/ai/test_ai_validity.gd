extends GutTest
## Every action the AI returns is legal, a turn ends within 3 calls, and a decision never uses
## more than the real-trace budget. Fuzzed over hundreds of random states.

const STATES: int = 300


func test_every_action_is_valid_and_the_turn_ends_within_three_calls() -> void:
	var worst_calls: int = 0
	var worst_traces: int = 0
	var kinds: Dictionary = {}
	var bad: Array[String] = []
	for i: int in range(STATES):
		var state: MatchState = AiTestUtil.random_state(i)
		var tank: int = state.current_tank
		var ended: bool = false
		for call: int in range(1, 6):
			var action: Dictionary = AiPlayer.next_action(state, tank)
			worst_traces = maxi(worst_traces, AimSolver.trace_count)
			var err: String = Simulation.validate_action(state, action)
			if err != "":
				bad.append("state %d call %d: %s -> %s" % [i, call, str(action), err])
				break
			kinds[action["kind"]] = (kinds.get(action["kind"], 0) as int) + 1
			Simulation.apply_action(state, action)
			var kind: String = action["kind"]
			if kind == "fire" or kind == "pass" or (kind == "use_item" and action["item"] == "nanorepair_kit"):
				ended = true
				worst_calls = maxi(worst_calls, call)
				break
		if not ended and bad.is_empty():
			bad.append("state %d: no turn-ending action within 5 calls" % i)
	gut.p("VALIDITY  %d states: all actions valid, worst case %d calls per turn, worst %d real traces/decision, kinds %s" % [
			STATES, worst_calls, worst_traces, str(kinds)])
	assert_eq(bad, [], "illegal or endless: %s" % str(bad.slice(0, 5)))
	assert_lte(worst_calls, 3, "a turn ends within 3 calls")
	assert_lte(worst_traces, AimSolver.TRACE_BUDGET, "trace budget")


func test_the_fuzz_reaches_every_difficulty_and_most_weapons() -> void:
	var levels: Dictionary = {}
	var weapons: Dictionary = {}
	for i: int in range(120):
		var state: MatchState = AiTestUtil.random_state(i)
		var level: int = AiProfile.level_of(state, state.current_tank)
		levels[level] = true
		var action: Dictionary = AiPlayer.next_action(state, state.current_tank)
		if action["kind"] == "fire":
			weapons[action["weapon"]] = true
	gut.p("COVERAGE  difficulties %s, weapons fired: %s" % [str(levels.keys()), str(weapons.keys())])
	assert_eq(levels.size(), 4)
	assert_gte(weapons.size(), 5, "the fuzz exercises a variety of weapons")


func test_a_human_slot_handed_to_the_ai_plays_as_normal() -> void:
	var state: MatchState = AiTestUtil.duel(4, SimConstants.CTRL_EXPERT, 700, 0)
	state.settings.controllers[0] = SimConstants.CTRL_HUMAN
	assert_eq(AiProfile.level_of(state, 0), SimConstants.CTRL_NORMAL)
	var action: Dictionary = AiPlayer.next_action(state, 0)
	assert_eq(Simulation.validate_action(state, action), "")


func test_wrong_phase_or_wrong_tank_falls_back_to_a_legal_looking_spark_dart() -> void:
	var state: MatchState = AiTestUtil.duel(4, SimConstants.CTRL_EXPERT, 700, 0)
	var other: Dictionary = AiPlayer.next_action(state, 1)  # not tank 1's turn
	assert_eq(other["kind"], "fire")
	assert_eq(other["weapon"], "spark_dart")
	assert_eq(other["tank"], 1)
	var shop: MatchState = SimTestUtil.shop_state(2)
	var in_shop: Dictionary = AiPlayer.next_action(shop, 0)
	assert_eq(in_shop["weapon"], "spark_dart", "never crashes outside the aim phase")
	var nobody: Dictionary = AiPlayer.next_action(state, 99)
	assert_eq(nobody["kind"], "fire")
	state.tanks[0].alive = false
	assert_eq(AiPlayer.next_action(state, 0)["weapon"], "spark_dart")


func test_with_no_enemy_left_it_passes() -> void:
	var state: MatchState = AiTestUtil.duel(4, SimConstants.CTRL_HARD, 700, 0)
	state.tanks[1].alive = false  # (the round has not been closed yet)
	var action: Dictionary = AiPlayer.next_action(state, 0)
	assert_eq(action["kind"], "pass")
	assert_eq(Simulation.validate_action(state, action), "")


func test_with_no_ammo_it_still_fires_a_spark_dart() -> void:
	for level: int in [1, 2, 3, 4]:
		var state: MatchState = AiTestUtil.duel(11, level, 700, 20)
		for id: String in Catalog.IDS:
			state.tanks[0].set_stock(id, 0)
		var action: Dictionary = AiPlayer.next_action(state, 0)
		assert_eq(action["kind"], "fire")
		assert_eq(action["weapon"], "spark_dart", "level %d" % level)
		assert_eq(Simulation.validate_action(state, action), "")


func test_a_locked_free_version_match_never_uses_full_tier_weapons() -> void:
	var settings := MatchSettings.new()
	settings.seed = 17
	settings.num_tanks = 2
	settings.full_unlocked = false
	settings.controllers = PackedInt32Array([4, 3])  # clamped to Normal by new_match
	var state: MatchState = Simulation.new_match(settings)
	assert_eq(state.settings.controllers[0], SimConstants.CTRL_NORMAL)
	for t: TankState in state.tanks:
		for a: Dictionary in AiPlayer.shop_actions(state, t.id):
			assert_eq(Simulation.validate_action(state, a), "", str(a))
			Simulation.apply_action(state, a)
		for id: String in Catalog.IDS:
			if Catalog.get_def(id)["tier"] == "full":
				assert_eq(t.stock_of(id), 0, "tank %d bought locked %s" % [t.id, id])


func test_every_weapon_and_item_in_the_catalog_gives_a_valid_action() -> void:
	# One scenario per catalog weapon, owned alone (plus the free spark dart), at every level.
	var fired: Dictionary = {}
	for id: String in Catalog.IDS:
		if not Catalog.is_weapon(id):
			continue
		for level: int in [1, 2, 3, 4]:
			var state: MatchState = AiTestUtil.duel(40 + level, level, 800, 30, {id: 3})
			state.tanks[1].shield_type = Catalog.index_of("glow_shield") if level % 2 == 0 else -1
			state.tanks[1].shield_hp = 20 if level % 2 == 0 else 0
			var turn: Dictionary = AiTestUtil.play_turn(state, 0)
			assert_lte(turn["calls"], 3)
			assert_false((turn["events"] as Array).is_empty(), "%s level %d: the turn was played" % [id, level])
			if turn["action"]["kind"] == "fire":
				fired[turn["action"]["weapon"]] = true
	gut.p("CATALOG  weapons actually fired across the per-weapon scenarios: %d" % fired.size())
	assert_gte(fired.size(), 8)
