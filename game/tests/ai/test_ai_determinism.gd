extends GutTest
## The AI is a pure function of the match state: same state, same action, on every device and
## after a save/load round trip. It never touches the global RNG, the clock, or the state.


func _round_trip(state: MatchState) -> MatchState:
	var bytes: PackedByteArray = SaveCodec.encode(state, [])
	var res: Dictionary = SaveCodec.decode(bytes)
	assert_true(res["ok"], "save round trip: %s" % str(res["error"]))
	return res["state"]


func test_same_state_same_action_copy_and_save_round_trip() -> void:
	var checked: int = 0
	for i: int in range(60):
		var state: MatchState = AiTestUtil.random_state(i)
		var tank: int = state.current_tank
		var first: Dictionary = AiPlayer.next_action(state, tank)
		assert_eq(AiPlayer.next_action(state, tank), first, "state %d: calling twice" % i)
		assert_eq(AiPlayer.next_action(state.duplicate_state(), tank), first, "state %d: deep copy" % i)
		assert_eq(AiPlayer.next_action(_round_trip(state), tank), first, "state %d: after SaveCodec" % i)
		checked += 1
	gut.p("DETERMINISM  %d states: identical actions for the original, a copy and a decoded save" % checked)
	assert_eq(checked, 60)


func test_the_whole_decision_chain_of_a_turn_is_reproducible() -> void:
	# Play the same turn on a state and on its decoded copy: every call matches.
	for i: int in range(20):
		var a: MatchState = AiTestUtil.random_state(100 + i)
		var b: MatchState = _round_trip(a)
		var tank: int = a.current_tank
		var ta: Dictionary = AiTestUtil.play_turn(a, tank)
		var tb: Dictionary = AiTestUtil.play_turn(b, tank)
		assert_eq(ta["action"], tb["action"], "state %d" % i)
		assert_eq(ta["calls"], tb["calls"])
		assert_eq(Simulation.fingerprint(a), Simulation.fingerprint(b), "state %d: same resulting state" % i)


func test_a_whole_match_is_reproducible() -> void:
	var ctrl := PackedInt32Array([1, 2, 3, 4])
	var one: Dictionary = AiTestUtil.run_match(8123, ctrl, 2)
	var two: Dictionary = AiTestUtil.run_match(8123, ctrl, 2)
	assert_eq(Simulation.fingerprint(one["state"]), Simulation.fingerprint(two["state"]))
	assert_eq(one["turns"], two["turns"])


func test_it_does_not_change_the_state() -> void:
	for i: int in range(25):
		var state: MatchState = AiTestUtil.random_state(300 + i)
		var before: String = Simulation.fingerprint(state)
		AiPlayer.next_action(state, state.current_tank)
		assert_eq(Simulation.fingerprint(state), before, "next_action left state %d untouched" % i)
	var shop: MatchState = SimTestUtil.shop_state(3, 2, 5)
	shop.settings.controllers = PackedInt32Array([1, 2, 4])
	var shop_before: String = Simulation.fingerprint(shop)
	for t: TankState in shop.tanks:
		AiPlayer.shop_actions(shop, t.id)
	assert_eq(Simulation.fingerprint(shop), shop_before, "shop_actions leaves the state untouched")


func test_the_global_rng_is_not_used() -> void:
	var state: MatchState = AiTestUtil.random_state(5)
	var expected: Dictionary = AiPlayer.next_action(state, state.current_tank)
	for s: int in [1, 2, 99]:
		seed(s)
		randomize()
		assert_eq(AiPlayer.next_action(state, state.current_tank), expected)


func test_randomness_comes_from_the_match_seed() -> void:
	# A different match seed gives a different stream: across a few seeds the Easy AI's very
	# first shot (angle jitter, bias, noise) is not always the same.
	var seen: Dictionary = {}
	for s: int in range(8):
		var state: MatchState = AiTestUtil.duel(60, SimConstants.CTRL_EASY, 700, 0)
		state.seed = 7000 + s
		var a: Dictionary = AiPlayer.next_action(state, 0)
		seen["%d/%d" % [a["angle"], a["power"]]] = true
	assert_gt(seen.size(), 4, "different seeds give different (human-like) shots")


func test_the_rng_stream_is_the_documented_one() -> void:
	var state: MatchState = AiTestUtil.duel(8, SimConstants.CTRL_NORMAL, 600, 0)
	state.turn_number = 7
	var expected: Rng = Rng.derive(state.seed, SimConstants.TAG_AI + 0).fork(
			state.round_index * 100000 + state.turn_number * 16 + 0)
	var actual: Rng = AiPlayer.turn_rng(state, 0)
	assert_eq(actual.next_u32(), expected.next_u32())
	assert_eq(actual.next_u32(), expected.next_u32())
	var other: Rng = AiPlayer.turn_rng(state, 1)
	assert_ne(other.get_state(), AiPlayer.turn_rng(state, 0).get_state(), "one stream per tank")
