@warning_ignore_start("integer_division")
extends GutTest
## M6 changed the save layout (teams, friendly_fire, sudden_death_cycles) and therefore every fingerprint,
## so all golden fixtures were regenerated. This test proves the regeneration changed NOTHING about play:
## it replays every golden log and, after every step, cuts the three new fields out of the serialization
## (SimTestUtil.pre_m6_fingerprint) and compares the result with the fingerprint recorded BEFORE M6
## (fixtures/pre_m6_fingerprints.json, taken from the previous commit's fixtures). A no-teams match is
## therefore bit-identical to before, state and all, at every step of all 16 recorded matches.
## (None of those matches reaches the sudden-death turn; sudden death itself is covered in
## tests/core/test_sudden_death.gd.)

const QaUtil = preload("res://tests/qa/qa_util.gd")
const M3 = preload("res://tests/qa/qa_m3.gd")
const M5 = preload("res://tests/qa/qa_m5.gd")

var _old: Dictionary = {}


func before_all() -> void:
	_old = QaUtil.load_fixture("pre_m6_fingerprints")


func _check(name: String, state: MatchState, step_index: int, problems: Array[String]) -> void:
	var want: String = (_old[name]["steps"] as Array)[step_index]
	var got: String = SimTestUtil.pre_m6_fingerprint(state)
	if got != want:
		problems.append("%s step %d: pre-M6 fingerprint %s != recorded %s" % [name, step_index, got, want])


func _m2(name: String) -> Array[String]:
	var problems: Array[String] = []
	var rec: Dictionary = QaUtil.load_fixture(name)
	var sc: Dictionary = rec["scenario"]
	var state: MatchState = Simulation.new_match(QaUtil.settings(int(sc["seed"]), int(sc["tanks"]), int(sc["rounds"]),
			int(sc["wind_max"])))
	if SimTestUtil.pre_m6_fingerprint(state) != _old[name]["initial"]:
		problems.append("%s: initial state differs from the pre-M6 one" % name)
	var steps: Array = rec["steps"]
	for i: int in range(steps.size()):
		var step: Dictionary = steps[i]
		if step["op"] == "start_round":
			QaUtil.enter_round(state)
		else:
			var action: Dictionary = QaUtil.fire(int(step["tank"]), int(step["angle"]), int(step["power"]))
			action["weapon"] = str(step["weapon"])
			Simulation.apply_action(state, action)
		_check(name, state, i, problems)
	if SimTestUtil.pre_m6_fingerprint(state) != _old[name]["final"]:
		problems.append("%s: final state differs from the pre-M6 one" % name)
	return problems


func _m3(name: String) -> Array[String]:
	var problems: Array[String] = []
	var rec: Dictionary = M3.load_fixture(name)
	var idx: Array[int] = [0]
	var hook: Callable = func(state: MatchState, _action: Dictionary, _events: Array[Dictionary],
			_inv: Array[PackedInt32Array], _terrain: Terrain) -> void:
		_check(name, state, idx[0], problems)
		idx[0] += 1
	problems.append_array(M3.replay_record(rec, hook))
	assert_eq(idx[0], (rec["steps"] as Array).size(), "%s: every step visited" % name)
	return problems


func _love(name: String) -> Array[String]:
	var problems: Array[String] = []
	var rec: Dictionary = QaUtil.load_fixture(name)
	var sc: Dictionary = rec["scenario"]
	var state: MatchState = Simulation.new_match(M5.love_settings(int(sc["seed"]), int(sc["c0"]), int(sc["c1"]),
			int(sc["wind"])))
	if SimTestUtil.pre_m6_fingerprint(state) != _old[name]["initial"]:
		problems.append("%s: initial state differs from the pre-M6 one" % name)
	var steps: Array = rec["steps"]
	for i: int in range(steps.size()):
		var step: Dictionary = steps[i]
		var a: Dictionary = {"kind": "pass", "tank": int(step["tank"])}
		if step["kind"] != "pass":
			a = M5.heart(int(step["tank"]), int(step["angle"]), int(step["power"]))
		Simulation.apply_action(state, a)
		_check(name, state, i, problems)
	if SimTestUtil.pre_m6_fingerprint(state) != _old[name]["final"]:
		problems.append("%s: final state differs from the pre-M6 one" % name)
	return problems


func _report(name: String, problems: Array[String]) -> void:
	assert_eq(problems.size(), 0, "%s no longer plays like before M6:\n%s" % [name, "\n".join(problems.slice(0, 5))])


func test_the_pre_m6_fingerprint_table_covers_every_golden_fixture() -> void:
	assert_eq(_old.size(), 16)
	for sc: Dictionary in QaUtil.scenarios():
		assert_true(_old.has(sc["name"]), sc["name"])
	for sc: Dictionary in M3.scenarios():
		assert_true(_old.has(sc["name"]), sc["name"])


func test_m2_golden_logs_replay_to_the_pre_m6_fingerprints() -> void:
	for sc: Dictionary in QaUtil.scenarios():
		_report(sc["name"], _m2(sc["name"]))


func test_m3_golden_logs_replay_to_the_pre_m6_fingerprints() -> void:
	for sc: Dictionary in M3.scenarios():
		_report(sc["name"], _m3(sc["name"]))


func test_love_golden_logs_replay_to_the_pre_m6_fingerprints() -> void:
	for name: String in ["m5_love_l2_vs_l2", "m5_love_l1_vs_l4", "m5_love_l3_vs_l3_wind12", "m5_love_l4_vs_l4_calm",
			"m5_love_l1_vs_l1_wind100_clamped", "m5_love_scripted_vs_l2"]:
		_report(name, _love(name))


func test_the_golden_fixtures_never_reach_sudden_death() -> void:
	# If a fixture ever crosses the threshold its pre-M6 fingerprint cannot match any more (and should be listed
	# when regenerated); today none does.
	for name: String in _old.keys():
		var rec: Dictionary = QaUtil.load_fixture(name)
		var steps: Array = rec["steps"] if rec.has("steps") else []
		for s: Dictionary in steps:
			assert_false(str(s.get("ev", "")).contains("sudden_death"), name)
