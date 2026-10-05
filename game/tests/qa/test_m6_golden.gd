@warning_ignore_start("integer_division")
extends GutTest
## Golden replays for M6 (teams, friendly fire, sudden death). A seeded scripted bot (core only: no AI, so
## this pins the SIMULATION and nothing else) played five scenarios; every action, the full fingerprint after
## it, the event-type sequence and a payload digest were recorded to game/tests/qa/fixtures/m6_*.json (one
## step per line). Replaying the recorded actions must reproduce all of it, and replaying twice, and
## continuing from a SaveCodec snapshot taken in the middle, must too.
##
## A change that alters simulation results trips these tests on purpose. To accept an intentional change run
## `tools/qa/regen_golden.sh m6` and commit the fixtures with the change.
##   m6_2v2_ff_on        4 tanks [A,B,A,B], friendly fire on, 2 rounds
##   m6_2v2_ff_off       the same with friendly fire off
##   m6_3v1_sudden       4 tanks [A,A,A,B], passes until sudden death, 2 rounds (drains, draws)
##   m6_ffa_sudden       3 tanks without teams, passes until sudden death, 2 rounds
##   m6_7v1_ff_off       8 tanks [A x7, B], friendly fire off, 1 round

const QaUtil = preload("res://tests/qa/qa_util.gd")
const M6 = preload("res://tests/qa/qa_m6.gd")

const SCENARIOS: Array = [
	{"name": "m6_2v2_ff_on", "seed": 60601, "teams": [0, 1, 0, 1], "ff": true, "rounds": 2, "pass_pct": 20, "bot_seed": 11, "max_actions": 160},
	{"name": "m6_2v2_ff_off", "seed": 60601, "teams": [0, 1, 0, 1], "ff": false, "rounds": 2, "pass_pct": 20, "bot_seed": 12, "max_actions": 160},
	{"name": "m6_3v1_sudden", "seed": 60603, "teams": [0, 0, 0, 1], "ff": true, "rounds": 2, "pass_pct": 80, "bot_seed": 13, "max_actions": 260},
	{"name": "m6_ffa_sudden", "seed": 60604, "teams": [], "ff": true, "rounds": 2, "pass_pct": 85, "bot_seed": 14, "max_actions": 220},
	{"name": "m6_7v1_ff_off", "seed": 60607, "teams": [0, 0, 0, 0, 0, 0, 0, 1], "ff": false, "rounds": 1, "pass_pct": 30, "bot_seed": 15, "max_actions": 240},
]

var _checked: Dictionary = {}


func _settings(sc: Dictionary) -> MatchSettings:
	var s := MatchSettings.new()
	s.seed = sc["seed"]
	var teams: Array = sc["teams"]
	s.num_tanks = teams.size() if not teams.is_empty() else 3
	s.rounds = sc["rounds"]
	s.wind_max = 100
	s.friendly_fire = sc["ff"]
	if not teams.is_empty():
		var t := PackedInt32Array()
		for v: int in teams:
			t.append(v)
		s.teams = t
	return s


func _path(name: String) -> String:
	return QaUtil.FIXTURE_DIR + name + ".json"


## Plays the scenario with the bot; returns {head, steps}. Each step: {op, a?, fp, ev, evh}.
func _generate(sc: Dictionary) -> Dictionary:
	var state: MatchState = Simulation.new_match(_settings(sc))
	var head: Dictionary = {"scenario": sc, "initial_fp": Simulation.fingerprint(state)}
	var rng := Rng.new(sc["bot_seed"])
	var steps: Array[Dictionary] = []
	var fires: int = 0
	var guard: int = 0
	while state.phase != SimConstants.PHASE_MATCH_OVER and fires < (sc["max_actions"] as int) and guard < 4000:
		guard += 1
		if state.phase == SimConstants.PHASE_SHOP:
			var log: Array[Dictionary] = []
			M6.shop_phase(state, rng, log)
			# The shop actions were applied one by one; record the end state of the shop as one step per action by
			# replaying them on a copy is not needed: only the final fingerprint of the phase is pinned.
			steps.append({"op": "shop", "n": log.size(), "fp": Simulation.fingerprint(state), "ev": "", "evh": "",
					"acts": log})
			var ev: Array[Dictionary] = Simulation.start_round(state)
			steps.append(_step("start_round", {}, ev, state))
			continue
		var action: Dictionary = M6.human_action(state, rng, sc["pass_pct"], 35)
		if Simulation.validate_action(state, action) != "":
			action = {"kind": "pass", "tank": state.current_tank}
		var events: Array[Dictionary] = Simulation.apply_action(state, action)
		steps.append(_step(action["kind"], action, events, state))
		fires += 1
	head["final_phase"] = state.phase
	head["final_fp"] = Simulation.fingerprint(state)
	return {"head": head, "steps": steps}


func _step(op: String, action: Dictionary, events: Array[Dictionary], state: MatchState) -> Dictionary:
	var rec: Dictionary = {"op": op, "fp": Simulation.fingerprint(state), "ev": ",".join(QaUtil.types(events)),
			"evh": QaUtil.events_digest(events)}
	if not action.is_empty():
		rec["a"] = action
	return rec


func _save(name: String, rec: Dictionary) -> bool:
	var f: FileAccess = FileAccess.open(_path(name), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string('{"head": ' + JSON.stringify(rec["head"], "", true) + ',\n"steps": [\n')
	var steps: Array = rec["steps"]
	for i: int in range(steps.size()):
		f.store_string(JSON.stringify(steps[i], "", true) + (",\n" if i < steps.size() - 1 else "\n"))
	f.store_string("]}\n")
	return true


func _load(name: String) -> Dictionary:
	if not FileAccess.file_exists(_path(name)):
		return {}
	var f: FileAccess = FileAccess.open(_path(name), FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


## Replays the recorded actions; returns mismatch descriptions. `snapshot_at` (a step index, or -1) also takes a
## SaveCodec snapshot there and, at the end, continues from it with the remaining steps.
func _replay(rec: Dictionary, snapshot_at: int) -> Array[String]:
	var problems: Array[String] = []
	var head: Dictionary = rec["head"]
	var sc: Dictionary = head["scenario"]
	var state: MatchState = Simulation.new_match(_settings(sc))
	if Simulation.fingerprint(state) != head["initial_fp"]:
		problems.append("initial fingerprint %s != golden %s" % [Simulation.fingerprint(state), head["initial_fp"]])
		return problems
	var steps: Array = rec["steps"]
	var snap_bytes: PackedByteArray = PackedByteArray()
	for i: int in range(steps.size()):
		var err: String = _apply_step(state, steps[i] as Dictionary, i)
		if err != "":
			problems.append(err)
			return problems
		if i == snapshot_at and state.phase == SimConstants.PHASE_AIM:
			snap_bytes = SaveCodec.encode(state, [] as Array[Dictionary])
	if state.phase != head["final_phase"] or Simulation.fingerprint(state) != head["final_fp"]:
		problems.append("final state differs: phase %s fp %s, golden %s %s" % [state.phase, Simulation.fingerprint(state),
				head["final_phase"], head["final_fp"]])
	if not snap_bytes.is_empty():
		var dec: Dictionary = SaveCodec.decode(snap_bytes)
		if not dec["ok"]:
			problems.append("the mid-replay snapshot does not decode: %s" % str(dec["error"]))
			return problems
		var resumed: MatchState = dec["state"]
		for i: int in range(snapshot_at + 1, steps.size()):
			var err2: String = _apply_step(resumed, steps[i] as Dictionary, i)
			if err2 != "":
				problems.append("after a save/load at step %d: %s" % [snapshot_at, err2])
				return problems
		if Simulation.fingerprint(resumed) != head["final_fp"]:
			problems.append("continuing from the snapshot at step %d ends in a different state" % snapshot_at)
	return problems


func _apply_step(state: MatchState, step: Dictionary, i: int) -> String:
	var events: Array[Dictionary] = []
	var op: String = step["op"]
	if op == "shop":
		for a: Dictionary in (step["acts"] as Array):
			var act: Dictionary = Simulation.normalize_action(a)
			if Simulation.validate_action(state, act) != "":
				return "step %d: shop action %s rejected (%s)" % [i, str(act), Simulation.validate_action(state, act)]
			Simulation.apply_action(state, act)
		if Simulation.fingerprint(state) != step["fp"]:
			return "step %d (shop): fingerprint %s != golden %s" % [i, Simulation.fingerprint(state), step["fp"]]
		return ""
	if op == "start_round":
		events = Simulation.start_round(state)
	else:
		var action: Dictionary = Simulation.normalize_action(step["a"] as Dictionary)
		var verr: String = Simulation.validate_action(state, action)
		if verr != "":
			return "step %d: recorded action %s rejected with '%s'" % [i, str(action), verr]
		events = Simulation.apply_action(state, action)
	if Simulation.fingerprint(state) != step["fp"]:
		return "step %d (%s): fingerprint %s != golden %s" % [i, op, Simulation.fingerprint(state), step["fp"]]
	if ",".join(QaUtil.types(events)) != step["ev"]:
		return "step %d (%s): event types differ\n  got:    %s\n  golden: %s" % [i, op, ",".join(QaUtil.types(events)), step["ev"]]
	if QaUtil.events_digest(events) != step["evh"]:
		return "step %d (%s): event payload digest differs (same types, different values)" % [i, op]
	return ""


func _check(index: int) -> void:
	var sc: Dictionary = SCENARIOS[index]
	var name: String = sc["name"]
	if QaUtil.regen_enabled():
		var rec: Dictionary = _generate(sc)
		assert_true(_save(name, rec), "wrote %s" % ProjectSettings.globalize_path(_path(name)))
		gut.p("REGENERATED %s: %d steps, final phase %s" % [name, (rec["steps"] as Array).size(), (rec["head"] as Dictionary)["final_phase"]])
		return
	var rec2: Dictionary = _load(name)
	if rec2.is_empty():
		fail_test("GOLDEN FIXTURE MISSING or unreadable: %s. Run tools/qa/regen_golden.sh m6 (only if the simulation change is intentional)." % ProjectSettings.globalize_path(_path(name)))
		return
	var steps: Array = rec2["steps"]
	assert_gt(steps.size(), 20, "%s: the fixture has steps" % name)
	var mid: int = steps.size() / 2
	while mid < steps.size() and (steps[mid] as Dictionary)["op"] in ["shop", "start_round"]:
		mid += 1
	var problems: Array[String] = _replay(rec2, mid)
	assert_eq(problems.size(), 0, "GOLDEN MISMATCH in %s (if intentional run tools/qa/regen_golden.sh m6):\n%s" % [name, "\n".join(problems)])
	# The same replay a second time: nothing in the simulation depends on process state.
	var again: Array[String] = _replay(rec2, -1)
	assert_eq(again.size(), 0, "%s: the second replay differs: %s" % [name, "\n".join(again)])
	var head: Dictionary = rec2["head"]
	_checked[name] = {"steps": steps.size(), "phase": head["final_phase"]}
	# What the scenario is meant to exercise.
	var types: Dictionary = {}
	for st: Variant in steps:
		for t: String in str((st as Dictionary)["ev"]).split(","):
			types[t] = true
	if name.contains("sudden"):
		assert_true(types.has("sudden_death"), "%s: sudden death happens in this scenario" % name)
	assert_true(types.has("round_end"), "%s: a round ends" % name)


func test_golden_2v2_friendly_fire_on() -> void:
	_check(0)


func test_golden_2v2_friendly_fire_off() -> void:
	_check(1)


func test_golden_3v1_sudden_death() -> void:
	_check(2)


func test_golden_ffa_sudden_death() -> void:
	_check(3)


func test_golden_7v1_friendly_fire_off() -> void:
	_check(4)


func test_fixtures_are_distinct_runs() -> void:
	if QaUtil.regen_enabled():
		return
	var seen: Dictionary = {}
	for sc: Dictionary in SCENARIOS:
		var rec: Dictionary = _load(sc["name"])
		if rec.is_empty():
			continue
		var fp: String = (rec["head"] as Dictionary)["final_fp"]
		assert_false(seen.has(fp), "%s ends in a state no other scenario ends in" % sc["name"])
		seen[fp] = true
