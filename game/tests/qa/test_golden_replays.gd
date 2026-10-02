extends GutTest
## Golden replay fixtures: scripted bot matches recorded to JSON (fingerprint after every
## action + event-type sequence + payload digest). Any change in simulation results shows
## up here. To accept an intentional change run `tools/qa/regen_golden.sh`.

const QaUtil = preload("res://tests/qa/qa_util.gd")


func _check_scenario(sc: Dictionary) -> void:
	var name: String = sc["name"]
	if QaUtil.regen_enabled():
		var rec: Dictionary = QaUtil.generate_record(sc)
		assert_true(QaUtil.save_fixture(name, rec), "wrote fixture %s" % QaUtil.fixture_path(name))
		gut.p("REGENERATED %s: %d steps, final phase %s" % [name, (rec["steps"] as Array).size(), rec["final_phase"]])
		return
	var rec: Dictionary = QaUtil.load_fixture(name)
	if rec.is_empty():
		fail_test(("GOLDEN FIXTURE MISSING or unreadable: %s. Run tools/qa/regen_golden.sh to create it "
				+ "(only if the simulation change is intentional).") % ProjectSettings.globalize_path(QaUtil.fixture_path(name)))
		return
	assert_gt((rec["steps"] as Array).size(), 3, "%s fixture has steps" % name)
	var problems: Array[String] = QaUtil.replay_record(rec)
	assert_eq(problems.size(), 0, "GOLDEN MISMATCH in %s (if intentional run tools/qa/regen_golden.sh):\n%s"
			% [name, "\n".join(problems)])


func test_golden_duel_2_tanks() -> void:
	_check_scenario(QaUtil.scenarios()[0])


func test_golden_trio_3_tanks() -> void:
	_check_scenario(QaUtil.scenarios()[1])


func test_golden_five_tanks() -> void:
	_check_scenario(QaUtil.scenarios()[2])


func test_golden_eight_tanks() -> void:
	_check_scenario(QaUtil.scenarios()[3])


func test_golden_max_wind() -> void:
	_check_scenario(QaUtil.scenarios()[4])


func test_golden_multi_round() -> void:
	_check_scenario(QaUtil.scenarios()[5])


## The fixtures must actually exercise the interesting paths, or they guard nothing.
func test_golden_fixtures_cover_interesting_paths() -> void:
	if QaUtil.regen_enabled():
		pass_test("regenerating")
		return
	var saw_round_end: bool = false
	var saw_start_round: bool = false
	var saw_damage: bool = false
	var saw_destroyed: bool = false
	var saw_match_over: bool = false
	var saw_lost: bool = false
	for sc: Dictionary in QaUtil.scenarios():
		var rec: Dictionary = QaUtil.load_fixture(sc["name"])
		if rec.is_empty():
			fail_test("GOLDEN FIXTURE MISSING: %s. Run tools/qa/regen_golden.sh" % sc["name"])
			return
		for step: Dictionary in (rec["steps"] as Array):
			var ev: String = step["ev"]
			saw_round_end = saw_round_end or ev.contains("round_end")
			saw_start_round = saw_start_round or step["op"] == "start_round"
			saw_damage = saw_damage or ev.contains("damage")
			saw_destroyed = saw_destroyed or ev.contains("tank_destroyed")
			saw_lost = saw_lost or (ev.contains("projectile_end") and not ev.contains("explosion"))
		saw_match_over = saw_match_over or rec["final_phase"] == "match_over"
	assert_true(saw_round_end, "some fixture ends a round")
	assert_true(saw_start_round, "some fixture plays start_round")
	assert_true(saw_damage, "some fixture has damage")
	assert_true(saw_destroyed, "some fixture destroys a tank")
	assert_true(saw_match_over, "some fixture reaches match_over")
	assert_true(saw_lost, "some fixture has a shot without explosion")


## Same seed + same actions twice gives the same result (guards against hidden global state).
func test_replaying_twice_is_identical() -> void:
	var sc: Dictionary = QaUtil.scenarios()[2]
	var a: Dictionary = QaUtil.generate_record(sc)
	var b: Dictionary = QaUtil.generate_record(sc)
	assert_eq(JSON.stringify(a), JSON.stringify(b), "two bot runs from the same seeds are identical")
	assert_eq(QaUtil.replay_record(a).size(), 0, "replay of a fresh record is clean")
