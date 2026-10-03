@warning_ignore_start("integer_division")
extends GutTest
## Golden replays for Love Edition (M5). Six seeded love matches (CPU vs CPU of several levels and a scripted
## human vs a CPU) were recorded to game/tests/qa/fixtures/m5_love_*.json: every action, the full fingerprint
## after it, the event-type sequence and a payload digest.
##  * test_replay_*: the recorded actions (the AI is NOT consulted) must reproduce all of it. A failure means the
##    simulation changed (heart physics, love amounts, serialization, wind, terrain generation).
##  * test_ai_*: the CPU must still choose exactly the recorded actions. A failure means the AI changed; if that
##    is deliberate, regenerate.
## To accept an intentional change run `tools/qa/regen_golden.sh love`.

const QaUtil = preload("res://tests/qa/qa_util.gd")
const M5 = preload("res://tests/qa/qa_m5.gd")

const SCENARIOS: Array[Dictionary] = [
	{"name": "m5_love_l2_vs_l2", "seed": 101, "c0": 2, "c1": 2, "wind": 30, "human": -1},
	{"name": "m5_love_l1_vs_l4", "seed": 202, "c0": 1, "c1": 4, "wind": 30, "human": -1},
	{"name": "m5_love_l3_vs_l3_wind12", "seed": 303, "c0": 3, "c1": 3, "wind": 12, "human": -1},
	{"name": "m5_love_l4_vs_l4_calm", "seed": 404, "c0": 4, "c1": 4, "wind": 0, "human": -1},
	{"name": "m5_love_l1_vs_l1_wind100_clamped", "seed": 505, "c0": 1, "c1": 1, "wind": 100, "human": -1},
	{"name": "m5_love_scripted_vs_l2", "seed": 606, "c0": 0, "c1": 2, "wind": 30, "human": 0},
]


func _settings(sc: Dictionary) -> MatchSettings:
	return M5.love_settings(sc["seed"] as int, sc["c0"] as int, sc["c1"] as int, sc["wind"] as int)


## Plays the scenario with the live AI / scripted human and records it.
func _generate(sc: Dictionary) -> Dictionary:
	var state: MatchState = Simulation.new_match(_settings(sc))
	var rng: Rng = Rng.derive(sc["seed"] as int, 6060)
	var steps: Array[Dictionary] = []
	var guard: int = 0
	while state.phase == SimConstants.PHASE_AIM and guard < 400:
		guard += 1
		var a: Dictionary
		if state.current_tank == (sc["human"] as int):
			a = M5.scripted_action(state, rng)
		else:
			a = AiPlayer.next_action(state, state.current_tank)
		var ev: Array[Dictionary] = Simulation.apply_action(state, a)
		var step: Dictionary = {"kind": a["kind"], "tank": a["tank"], "fp": Simulation.fingerprint(state),
				"ev": ",".join(QaUtil.types(ev)), "evh": QaUtil.events_digest(ev)}
		if a["kind"] == "fire":
			step["angle"] = a["angle"]
			step["power"] = a["power"]
			step["weapon"] = a["weapon"]
		steps.append(step)
	var winner: int = -1
	for t: TankState in state.tanks:
		if t.round_wins > 0:
			winner = t.id
	return {"scenario": sc, "initial_fp": Simulation.fingerprint(Simulation.new_match(_settings(sc))), "steps": steps,
			"final_phase": state.phase, "winner": winner, "final_fp": Simulation.fingerprint(state),
			"love": [state.tanks[0].love, state.tanks[1].love]}


func _action_of(step: Dictionary) -> Dictionary:
	if step["kind"] == "pass":
		return {"kind": "pass", "tank": int(step["tank"])}
	return M5.heart(int(step["tank"]), int(step["angle"]), int(step["power"]))


func _replay(rec: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var sc: Dictionary = rec["scenario"]
	var state: MatchState = Simulation.new_match(_settings({"seed": int(sc["seed"]), "c0": int(sc["c0"]), "c1": int(sc["c1"]),
			"wind": int(sc["wind"])}))
	if Simulation.fingerprint(state) != rec["initial_fp"]:
		problems.append("initial fingerprint %s != golden %s" % [Simulation.fingerprint(state), rec["initial_fp"]])
		return problems
	var steps: Array = rec["steps"]
	for i: int in range(steps.size()):
		var step: Dictionary = steps[i]
		var a: Dictionary = _action_of(step)
		var err: String = Simulation.validate_action(state, a)
		if err != "":
			problems.append("step %d: recorded action rejected '%s'" % [i, err])
			return problems
		var ev: Array[Dictionary] = Simulation.apply_action(state, a)
		if Simulation.fingerprint(state) != step["fp"]:
			problems.append("step %d: fingerprint %s != golden %s" % [i, Simulation.fingerprint(state), step["fp"]])
			return problems
		if ",".join(QaUtil.types(ev)) != step["ev"]:
			problems.append("step %d: event types %s != golden %s" % [i, ",".join(QaUtil.types(ev)), step["ev"]])
			return problems
		if QaUtil.events_digest(ev) != step["evh"]:
			problems.append("step %d: event payloads differ (same types)" % i)
			return problems
	if state.phase != rec["final_phase"] or Simulation.fingerprint(state) != rec["final_fp"]:
		problems.append("final state differs (phase %s)" % state.phase)
	return problems


func _check(index: int) -> void:
	var sc: Dictionary = SCENARIOS[index]
	var name: String = sc["name"]
	if QaUtil.regen_enabled():
		var rec: Dictionary = _generate(sc)
		assert_true(QaUtil.save_fixture(name, rec), "wrote %s" % QaUtil.fixture_path(name))
		gut.p("REGENERATED %s: %d steps, winner %d, love %s" % [name, (rec["steps"] as Array).size(), rec["winner"], str(rec["love"])])
		return
	var rec: Dictionary = QaUtil.load_fixture(name)
	if rec.is_empty():
		fail_test("GOLDEN FIXTURE MISSING: %s. Run tools/qa/regen_golden.sh love (only if the change is intentional)."
				% ProjectSettings.globalize_path(QaUtil.fixture_path(name)))
		return
	assert_eq(rec["final_phase"], "match_over", "%s fixture plays to the end" % name)
	assert_gt((rec["steps"] as Array).size(), 3, name)
	var problems: Array[String] = _replay(rec)
	assert_eq(problems.size(), 0, "GOLDEN MISMATCH in %s (if intentional run tools/qa/regen_golden.sh love):\n%s" % [name, "\n".join(problems)])


func test_replay_l2_vs_l2() -> void:
	_check(0)


func test_replay_l1_vs_l4() -> void:
	_check(1)


func test_replay_l3_vs_l3_wind12() -> void:
	_check(2)


func test_replay_l4_vs_l4_calm() -> void:
	_check(3)


func test_replay_l1_vs_l1_wind100_clamped() -> void:
	_check(4)


func test_replay_scripted_vs_l2() -> void:
	_check(5)


func test_ai_still_chooses_the_recorded_actions() -> void:
	if QaUtil.regen_enabled():
		pass_test("regenerating fixtures")
		return
	var diffs: Array[String] = []
	for sc: Dictionary in SCENARIOS:
		var rec: Dictionary = QaUtil.load_fixture(sc["name"] as String)
		if rec.is_empty():
			diffs.append("%s: fixture missing" % sc["name"])
			continue
		var live: Dictionary = _generate(sc)
		var a: Array = live["steps"]
		var b: Array = rec["steps"]
		if a.size() != b.size():
			diffs.append("%s: %d steps now, golden has %d" % [sc["name"], a.size(), b.size()])
			continue
		for i: int in range(a.size()):
			var x: Dictionary = a[i]
			var y: Dictionary = b[i]
			if x["kind"] != y["kind"] or x["tank"] != int(y["tank"]) or x.get("angle", -1) != int(y.get("angle", -1)) \
					or x.get("power", -1) != int(y.get("power", -1)):
				diffs.append("%s: step %d differs: now %s, golden %s" % [sc["name"], i, str(x), str(y)])
				break
	assert_eq(diffs.size(), 0, "AI GOLDEN MISMATCH (a deliberate AI change needs tools/qa/regen_golden.sh love):\n" + "\n".join(diffs))


func test_the_scenario_table_is_part_of_the_contract() -> void:
	assert_eq(SCENARIOS.size(), 6)
	var seeds: Array[int] = []
	for sc: Dictionary in SCENARIOS:
		seeds.append(sc["seed"] as int)
	assert_eq(seeds, [101, 202, 303, 404, 505, 606] as Array[int])
