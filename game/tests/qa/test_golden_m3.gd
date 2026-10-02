extends GutTest
## Golden replays v2 (M3). A seeded SHOPPING BOT (buys a random affordable mix across the whole
## catalog, then moves, shields, repairs, passes and fires every kind of weapon) played four
## scenarios; every action, the fingerprint after it, the event-type sequence and a payload
## digest were recorded to game/tests/qa/fixtures/m3_*.json. Replaying the recorded actions
## (through JSON-normalised dictionaries, the bot is NOT consulted) must reproduce all of it.
## To accept an intentional simulation change run `tools/qa/regen_golden.sh`.
## The six M2 fixtures (test_golden_replays.gd) are separate and untouched.

const QaUtil = preload("res://tests/qa/qa_util.gd")
const M3 = preload("res://tests/qa/qa_m3.gd")


func _check_scenario(index: int) -> void:
	var sc: Dictionary = M3.scenarios()[index]
	var name: String = sc["name"]
	if QaUtil.regen_enabled():
		var rec: Dictionary = M3.generate_record(sc)
		assert_true(M3.save_fixture(name, rec), "wrote fixture %s" % M3.fixture_path(name))
		gut.p("REGENERATED %s: %d steps, final phase %s" % [name, (rec["steps"] as Array).size(), rec["final_phase"]])
		return
	var rec: Dictionary = M3.load_fixture(name)
	if rec.is_empty():
		fail_test(("GOLDEN FIXTURE MISSING or unreadable: %s. Run tools/qa/regen_golden.sh to create it "
				+ "(only if the simulation change is intentional).") % ProjectSettings.globalize_path(M3.fixture_path(name)))
		return
	assert_gt((rec["steps"] as Array).size(), 20, "%s fixture has steps" % name)
	assert_eq(rec["final_phase"], "match_over", "%s fixture plays the match to the end" % name)
	var problems: Array[String] = M3.replay_record(rec)
	assert_eq(problems.size(), 0, "GOLDEN MISMATCH in %s (if intentional run tools/qa/regen_golden.sh):\n%s"
			% [name, "\n".join(problems)])


func test_golden_trio_3_tanks_3_rounds_normal_money() -> void:
	_check_scenario(0)


func test_golden_hexa_6_tanks_2_rounds_rich() -> void:
	_check_scenario(1)


func test_golden_duel_2_tanks_5_rounds_wind_100() -> void:
	_check_scenario(2)


func test_golden_octo_8_tanks_1_round_poor() -> void:
	_check_scenario(3)


## The scenario table itself is part of the contract (a silent edit would invalidate the fixtures).
func test_scenario_table_matches_the_task() -> void:
	var s: Array[Dictionary] = M3.scenarios()
	assert_eq(s.size(), 4)
	assert_eq([s[0]["tanks"], s[0]["rounds"]], [3, 3])
	assert_eq([s[1]["tanks"], s[1]["rounds"], s[1]["start_money"]], [6, 2, 25000])
	assert_eq([s[2]["tanks"], s[2]["rounds"], s[2]["wind_max"]], [2, 5, 100])
	assert_eq([s[3]["tanks"], s[3]["rounds"]], [8, 1])
	assert_lt(s[3]["start_money"], 5000, "low money scenario")
	var state: MatchState = Simulation.new_match(M3.make_settings(s[2]))
	M3.apply(state, {"kind": "ready", "tank": 0})
	M3.apply(state, {"kind": "ready", "tank": 1})
	M3.apply(state, {"kind": M3.START_ROUND})
	assert_eq(absi(state.wind), 100, "the wind scenario opens at the wind limit")


## Coverage claim: across the four fixtures every one of the 21 weapons and 7 items is used
## in play (weapon fired, shield / repulsor / repair used, Fuel Cell drawn by a move, Drift
## Chute spent on a fall). Proven by replaying the recorded actions and watching the stock.
func test_fixtures_exercise_every_weapon_and_item() -> void:
	if QaUtil.regen_enabled():
		pass_test("regenerating")
		return
	var ledger: Dictionary = {}
	var hook: Callable = func(state: MatchState, action: Dictionary, _events: Array[Dictionary],
			inv_before: Array[PackedInt32Array]) -> void:
		M3.note_usage(ledger, state, action, inv_before)
	for sc: Dictionary in M3.scenarios():
		var rec: Dictionary = M3.load_fixture(sc["name"])
		if rec.is_empty():
			fail_test("GOLDEN FIXTURE MISSING: %s. Run tools/qa/regen_golden.sh" % sc["name"])
			return
		assert_eq(M3.replay_record(rec, hook).size(), 0, "%s replays cleanly" % sc["name"])
	var missing: Array[String] = []
	for id: String in Catalog.IDS:
		if not ledger.has(id):
			missing.append(id)
	assert_eq(Catalog.count(), 28, "21 weapons + 7 items")
	assert_eq(missing, [] as Array[String], "catalog entries never exercised by the golden fixtures")
	gut.p("coverage: %s" % str(ledger))


## The fixtures must also exercise the interesting M3 paths, or they guard nothing.
func test_fixtures_cover_interesting_event_types() -> void:
	if QaUtil.regen_enabled():
		pass_test("regenerating")
		return
	var seen: Dictionary = {}
	var reasons: Dictionary = {}
	var matches_over: int = 0
	for sc: Dictionary in M3.scenarios():
		var rec: Dictionary = M3.load_fixture(sc["name"])
		if rec.is_empty():
			fail_test("GOLDEN FIXTURE MISSING: %s. Run tools/qa/regen_golden.sh" % sc["name"])
			return
		for step: Dictionary in (rec["steps"] as Array):
			for t: String in (step["ev"] as String).split(","):
				seen[t] = true
		matches_over += 1 if rec["final_phase"] == "match_over" else 0
	for t: String in ["money", "shield_on", "shield_hit", "repulsor_on", "repair", "tank_move", "ready", "round_start",
			"round_end", "tank_destroyed", "tank_fall", "tunnel", "terrain_add", "terrain_pour", "flames", "beam",
			"well_on", "tank_drag", "chute", "projectile_end", "explosion"]:
		reasons[t] = seen.has(t)
	var missing: Array[String] = []
	for k: String in reasons:
		if not reasons[k]:
			missing.append(k)
	assert_eq(missing, [] as Array[String], "event types never seen in any golden fixture")
	assert_eq(matches_over, 4, "all four scenarios end in match_over")


## Same scenario twice from the bot gives byte-identical records (no hidden global state).
func test_recording_twice_is_identical() -> void:
	var sc: Dictionary = M3.scenarios()[3]
	var a: Dictionary = M3.generate_record(sc)
	var b: Dictionary = M3.generate_record(sc)
	assert_eq(JSON.stringify(a), JSON.stringify(b), "two bot runs from the same seeds are identical")
	assert_eq(M3.replay_record(a).size(), 0, "replay of a fresh record is clean")
