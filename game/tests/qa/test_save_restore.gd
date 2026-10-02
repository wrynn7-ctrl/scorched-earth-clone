extends GutTest
## duplicate_state() mid-match: original and copy, fed identical actions, stay identical.

const QaUtil = preload("res://tests/qa/qa_util.gd")


## Plays `steps` bot steps, snapshots, then drives original and copy with the same actions.
func _run_split(sc: Dictionary, split_after: int, tail_steps: int) -> void:
	var state: MatchState = Simulation.new_match(QaUtil.make_settings(sc))
	var rng := Rng.new(sc["bot_seed"])
	for i: int in range(split_after):
		if QaUtil.play_bot_step(state, rng).is_empty():
			break
	var copy: MatchState = state.duplicate_state()
	assert_eq(Simulation.fingerprint(copy), Simulation.fingerprint(state), "%s: copy equals original at split" % sc["name"])
	var steps_done: int = 0
	for i: int in range(tail_steps):
		if state.phase == SimConstants.PHASE_MATCH_OVER:
			break
		var ev_a: Array[Dictionary] = []
		var ev_b: Array[Dictionary] = []
		if state.phase == SimConstants.PHASE_SHOP:
			ev_a = QaUtil.enter_round(state)
			ev_b = QaUtil.enter_round(copy)
		else:
			var action: Dictionary = QaUtil.bot_action(state, rng)
			ev_a = Simulation.apply_action(state, action)
			ev_b = Simulation.apply_action(copy, action)
		steps_done += 1
		assert_eq(QaUtil.events_digest(ev_a), QaUtil.events_digest(ev_b), "%s step %d: identical timelines" % [sc["name"], i])
		var fa: String = Simulation.fingerprint(state)
		var fb: String = Simulation.fingerprint(copy)
		if fa != fb:
			fail_test("%s: fingerprints diverge %d steps after the snapshot (%s vs %s)" % [sc["name"], i, fa, fb])
			return
	assert_eq(copy.phase, state.phase)
	assert_gt(steps_done, 0, "%s: tail ran" % sc["name"])


func test_copy_continues_identically_every_scenario() -> void:
	for sc: Dictionary in QaUtil.scenarios():
		_run_split(sc, 4, 25)


func test_copy_continues_identically_across_round_boundaries() -> void:
	# Split just before the first round end of the multi-round scenario.
	var sc: Dictionary = QaUtil.scenarios()[5]
	var state: MatchState = Simulation.new_match(QaUtil.make_settings(sc))
	var rng := Rng.new(sc["bot_seed"])
	var n: int = 0
	QaUtil.play_bot_step(state, rng)  # shop -> round 0
	n += 1
	while state.phase == SimConstants.PHASE_AIM and n < 200:
		n += 1
		QaUtil.play_bot_step(state, rng)
	assert_eq(state.phase, SimConstants.PHASE_SHOP, "first round ended")
	_run_split(sc, n - 1, 30)
	_run_split(sc, n, 30)


func test_copy_does_not_alias_original() -> void:
	var sc: Dictionary = QaUtil.scenarios()[2]
	var state: MatchState = Simulation.new_match(QaUtil.make_settings(sc))
	var rng := Rng.new(sc["bot_seed"])
	QaUtil.play_bot_step(state, rng)
	var before: String = Simulation.fingerprint(state)
	var copy: MatchState = state.duplicate_state()
	# mutate the copy hard
	for i: int in range(5):
		QaUtil.play_bot_step(copy, rng)
	copy.terrain.carve_circle(800, 700, 100)
	copy.tanks[0].health = 1
	copy.settings.rounds = 99
	copy.wind_rng_state[0] = 12345
	assert_eq(Simulation.fingerprint(state), before, "original untouched by changes to the copy")
	assert_ne(Simulation.fingerprint(copy), before)


func test_copy_of_fresh_and_finished_matches() -> void:
	var sc: Dictionary = QaUtil.scenarios()[0]
	var fresh: MatchState = Simulation.new_match(QaUtil.make_settings(sc))
	assert_eq(Simulation.fingerprint(fresh.duplicate_state()), Simulation.fingerprint(fresh))
	var rng := Rng.new(sc["bot_seed"])
	var n: int = 0
	while n < 500 and not QaUtil.play_bot_step(fresh, rng).is_empty():
		n += 1
	assert_eq(fresh.phase, SimConstants.PHASE_MATCH_OVER)
	var done_copy: MatchState = fresh.duplicate_state()
	assert_eq(Simulation.fingerprint(done_copy), Simulation.fingerprint(fresh))
	assert_eq(Simulation.apply_action(done_copy, QaUtil.fire(0, 450, 500)).size(), 0, "no actions after match_over")
	assert_eq(Simulation.start_round(done_copy).size(), 0, "no start_round after match_over")


## A copy taken from a snapshot rebuilt through the Terrain byte serialisation behaves the same.
func test_terrain_byte_roundtrip_midmatch() -> void:
	var sc: Dictionary = QaUtil.scenarios()[3]
	var state: MatchState = Simulation.new_match(QaUtil.make_settings(sc))
	var rng := Rng.new(sc["bot_seed"])
	for i: int in range(6):
		QaUtil.play_bot_step(state, rng)
	var buf := StreamPeerBuffer.new()
	state.terrain.write_bytes(buf)
	buf.seek(0)
	var t2: Terrain = Terrain.read_bytes(buf)
	assert_eq(t2.width, state.terrain.width)
	assert_eq(t2.height, state.terrain.height)
	assert_true(t2.cells == state.terrain.cells, "terrain bytes survive write/read")
	var copy: MatchState = state.duplicate_state()
	copy.terrain = t2
	for i: int in range(10):
		var action: Dictionary = QaUtil.bot_action(state, rng)
		Simulation.apply_action(state, action)
		Simulation.apply_action(copy, action)
		assert_eq(Simulation.fingerprint(copy), Simulation.fingerprint(state), "step %d" % i)
