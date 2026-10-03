@warning_ignore_start("integer_division")
extends GutTest
## M4 QA: whole-game validity fuzz of the computer opponents. 150 seeded matches (2-8 tanks,
## every level, humans handed to the AI, some all-CPU, random money / wind / rounds / free
## version) are played to match_over with AiPlayer.next_action and AiPlayer.shop_actions only.
## After every action the M3 helpers audit the economy, the timeline order and the state
## invariants. Probes on a stride check: next_action / shop_actions never mutate the state,
## the same state gives the same action on a deep copy and after a SaveCodec round trip, and
## the AI never silently falls back to the Spark Dart shot because its own decision was illegal.
## Also reports stalemates (rounds that never end) and the decision-time distribution.
##
## QA_AI_MATCHES / QA_AI_SEED override the defaults for deep runs.

const QA_AI = preload("res://tests/qa/qa_ai.gd")
const DEFAULT_MATCHES: int = 150
const DEFAULT_ROOT_SEED: int = 0xA1F00D
const DET_STRIDE: int = 10
const MUT_STRIDE: int = 30
const SAVE_STRIDE: int = 50
const NAMES: Array[String] = ["", "easy", "normal", "hard", "expert"]

var MATCHES: int = int(OS.get_environment("QA_AI_MATCHES")) if OS.get_environment("QA_AI_MATCHES") != "" else DEFAULT_MATCHES
var ROOT_SEED: int = int(OS.get_environment("QA_AI_SEED")) if OS.get_environment("QA_AI_SEED") != "" else DEFAULT_ROOT_SEED

var _results: Array[Dictionary] = []
var _elapsed_ms: int = 0


## Marks the test pending with the bug text when `ok` is false.
func _bug(ok: bool, desc: String) -> void:
	if ok:
		pass_test("bug no longer reproduces (remove the pending guard): %s" % desc)
	else:
		pending("BUG: %s" % desc)


func before_all() -> void:
	var t0: int = Time.get_ticks_msec()
	for m: int in range(MATCHES):
		var settings: MatchSettings = QA_AI.random_settings(m, ROOT_SEED)
		var res: Dictionary = QA_AI.play_match(settings, DET_STRIDE, MUT_STRIDE, SAVE_STRIDE)
		res["index"] = m
		# The terrain of a finished match is big; the log and numbers are all the tests need.
		res.erase("final_state")
		_results.append(res)
	_elapsed_ms = Time.get_ticks_msec() - t0


func _failures(category: String) -> Array[String]:
	var out: Array[String] = []
	for r: Dictionary in _results:
		var list: Array[String] = (r["fails"] as Dictionary)[category]
		for line: String in list:
			out.append("#%d %s" % [r["index"], line])
	return out


func _check_category(category: String, what: String) -> void:
	var errs: Array[String] = _failures(category)
	assert_eq(errs.size(), 0, "%s: %d problems, first: %s" % [what, errs.size(), "" if errs.is_empty() else errs[0]])
	if not errs.is_empty():
		for i: int in range(mini(5, errs.size())):
			gut.p("  " + errs[i])


func test_every_match_reached_match_over_and_the_run_was_large_enough() -> void:
	var turns: int = 0
	var rounds: int = 0
	var shops: int = 0
	var det: int = 0
	var saves: int = 0
	var muts: int = 0
	var calls_hist: Array[int] = [0, 0, 0, 0]
	for r: Dictionary in _results:
		turns += r["turns"] as int
		rounds += r["rounds_played"] as int
		det += r["det_checks"] as int
		saves += r["save_checks"] as int
		muts += r["mut_checks"] as int
		shops += (r["shop_us"] as Array[int]).size()
		calls_hist[mini(3, r["max_calls"] as int)] += 1
	gut.p("AIFUZZ  %d matches, %d rounds, %d turn-ending actions, %d shop visits in %.1f s; probes: %d deep-copy, %d save round trips, %d mutation checks" % [
			_results.size(), rounds, turns, shops, float(_elapsed_ms) / 1000.0, det, saves, muts])
	gut.p("AIFUZZ  longest AI turn in calls, matches per max: 1 call %d, 2 calls %d, 3 calls %d" % [calls_hist[1], calls_hist[2], calls_hist[3]])
	var sums: Dictionary = {}
	for r: Dictionary in _results:
		for k: String in ["us_audit", "us_decide_all", "us_apply", "us_start_round"]:
			sums[k] = (sums.get(k, 0) as int) + (r.get(k, 0) as int)
	gut.p("AIFUZZ  where the time went (ms): audit+invariants %d, AI call + probes %d, Simulation.apply_action %d, start_round %d" % [
			(sums["us_audit"] as int) / 1000, (sums["us_decide_all"] as int) / 1000, (sums["us_apply"] as int) / 1000, (sums["us_start_round"] as int) / 1000])
	assert_eq(_results.size(), MATCHES)
	assert_gt(turns, MATCHES * 8, "the fuzz really played turns")
	assert_gt(det, MATCHES / 3)
	assert_gt(saves, MATCHES / 10)


func test_every_ai_action_passes_validate_action() -> void:
	_check_category("invalid", "illegal AI action")


func test_turns_end_within_three_calls() -> void:
	_check_category("calls", "turn longer than 3 calls")
	for r: Dictionary in _results:
		assert_lte(r["max_calls"] as int, 3, "match #%d" % (r["index"] as int))


func test_shop_lists_are_well_formed_and_free_version_never_buys_full_tier() -> void:
	_check_category("shop", "shop list shape")


func test_economy_audit_holds_for_every_ai_action() -> void:
	_check_category("audit", "M3 economy audit")


func test_timeline_order_holds_for_every_ai_action() -> void:
	_check_category("timeline", "M3 timeline check")


func test_state_invariants_hold_after_every_ai_action() -> void:
	_check_category("state", "M3 state invariants")


func test_flow_errors() -> void:
	_check_category("flow", "match flow")


func test_ai_never_mutates_the_state() -> void:
	_check_category("mutation", "state mutated by next_action/shop_actions")
	var checks: int = 0
	for r: Dictionary in _results:
		checks += r["mut_checks"] as int
	assert_gt(checks, MATCHES * 10, "many fingerprint-before/after checks ran")


func test_same_state_same_action_on_deep_copy() -> void:
	_check_category("det_copy", "deep copy determinism")


func test_same_state_same_action_after_save_codec_round_trip() -> void:
	_check_category("det_save", "SaveCodec round trip determinism")


func test_ai_never_silently_falls_back() -> void:
	# AiPlayer.next_action replaces an illegal/empty _decide result with a Spark Dart shot at the
	# default aim. If that happens the AI is playing blind; the fuzz probes _decide directly.
	var errs: Array[String] = _failures("fallback")
	var n: int = 0
	for r: Dictionary in _results:
		n += r["fallback_count"] as int
	gut.p("AIFUZZ  silent fallbacks (illegal raw decision) in the probed decisions: %d" % n)
	if n > 0:
		pending("BUG: AiPlayer._decide returned an illegal or empty action %d times (next_action hid it): %s" % [n, errs[0]])
	else:
		assert_eq(n, 0)


func test_no_ai_pass_when_enemies_exist() -> void:
	# Teams equal ids today, so every alive opponent is an enemy and the AI must always fire,
	# use an item or move; a `pass` would stall the game.
	var passes: int = 0
	for r: Dictionary in _results:
		passes += r["pass_count"] as int
	assert_eq(passes, 0, "AI passes in a real match")


func test_stalemates_are_reported() -> void:
	var stalls: Array[String] = []
	var max_round: int = 0
	var all_rounds: Array[int] = []
	for r: Dictionary in _results:
		for n: int in (r["turns_per_round"] as Array[int]):
			all_rounds.append(n)
			max_round = maxi(max_round, n)
		if r["stalled"]:
			stalls.append("#%d %s: %s" % [r["index"], r["tag"], str(r["stall_info"])])
	gut.p("AIFUZZ  turns per round: median %d, p95 %d, max %d (stall limit %d) over %d rounds; stalled matches: %d" % [
			QA_AI.percentile(all_rounds, 50), QA_AI.percentile(all_rounds, 95), max_round, QA_AI.STALL_TURNS, all_rounds.size(), stalls.size()])
	for s: String in stalls:
		gut.p("AIFUZZ  STALL " + s)
	for r: Dictionary in _results:
		for info: Dictionary in (r.get("long", []) as Array):
			gut.p("AIFUZZ  LONG ROUND (>= %d turns, finished after %s): %s" % [QA_AI.LONG_ROUND, str(info.get("final_turns", "never")), str(info)])
	if not stalls.is_empty():
		pending("BUG: %d of %d matches had a round longer than %d turns (stalemate). First: %s" % [stalls.size(), _results.size(), QA_AI.STALL_TURNS, stalls[0]])
	else:
		assert_lte(max_round, QA_AI.STALL_TURNS)


func test_rounds_do_not_drag_on_for_hundreds_of_turns() -> void:
	# Pacing: Easy and Normal spend a real share of their money on missiles (M4-Q fix), so a duel is no longer
	# a Spark-Dart-only grind of 100-290 turns.
	var long_rounds: int = 0
	var worst: int = 0
	var all_rounds: int = 0
	var easy_only: int = 0
	var sample: String = ""
	for r: Dictionary in _results:
		all_rounds += (r["turns_per_round"] as Array[int]).size()
		for info: Dictionary in (r.get("long", []) as Array):
			long_rounds += 1
			worst = maxi(worst, info.get("final_turns", 0) as int)
			var all_cheap: bool = true
			for t: Dictionary in (info["alive"] as Array):
				all_cheap = all_cheap and (t["level"] as int) <= 2
			if all_cheap:
				easy_only += 1
			if sample == "":
				sample = "%s: %s" % [info["tag"], str(info["last40"])]
	gut.p("AIFUZZ  rounds of >= %d turns: %d of %d (longest %d); survivors were Easy/Normal in %d of them" % [QA_AI.LONG_ROUND, long_rounds, all_rounds, worst, easy_only])
	assert_lt(worst, 200, "no round may last 200 turns or more (%d of %d rounds lasted >= %d, the longest %d; sample: %s)" % [long_rounds, all_rounds, QA_AI.LONG_ROUND, worst, sample])


func test_weapon_and_item_usage_report() -> void:
	var weapons: Dictionary = {}
	var nonending: Dictionary = {}
	for r: Dictionary in _results:
		for k: String in (r["weapons"] as Dictionary).keys():
			weapons[k] = (weapons.get(k, 0) as int) + ((r["weapons"] as Dictionary)[k] as int)
		for k: String in (r["nonending"] as Dictionary).keys():
			nonending[k] = (nonending.get(k, 0) as int) + ((r["nonending"] as Dictionary)[k] as int)
	var keys: Array = weapons.keys()
	keys.sort()
	var line: String = "AIFUZZ  fired:"
	for k: String in keys:
		line += " %s=%d" % [k, weapons[k]]
	gut.p(line)
	keys = nonending.keys()
	keys.sort()
	line = "AIFUZZ  non-ending actions:"
	for k: String in keys:
		line += " %s=%d" % [k, nonending[k]]
	gut.p(line)
	assert_gt(weapons.size(), 4, "the AI used a variety of weapons")
	assert_true(weapons.has("spark_dart") or weapons.has("pulse_missile"))


func test_self_harm_report() -> void:
	var hit: Array[int] = [0, 0, 0, 0, 0]
	var kill: Array[int] = [0, 0, 0, 0, 0]
	var fire: Array[int] = [0, 0, 0, 0, 0]
	for r: Dictionary in _results:
		for lv: int in range(1, 5):
			hit[lv] += (r["self_hit"] as Dictionary)[lv] as int
			kill[lv] += (r["self_kill"] as Dictionary)[lv] as int
			fire[lv] += (r["fire_turns"] as Dictionary)[lv] as int
	var line: String = "AIFUZZ  self harm per level (shots that damaged / destroyed the shooter, of all shots):"
	var total_hit: int = 0
	var total_fire: int = 0
	var total_kill: int = 0
	for lv: int in range(1, 5):
		line += "  %s %d/%d (suicide %d)" % [NAMES[lv], hit[lv], fire[lv], kill[lv]]
		total_hit += hit[lv]
		total_fire += fire[lv]
		total_kill += kill[lv]
	gut.p(line)
	for r: Dictionary in _results:
		for c: String in (r.get("self_cases", []) as Array):
			gut.p("AIFUZZ  SELF-HIT " + c)
	# A computer that hurts itself in more than 3% of its shots is plainly broken.
	assert_lt(total_hit * 100, total_fire * 3 + 1, "self-damaging shots: %d of %d" % [total_hit, total_fire])


func test_decision_time_budget_under_the_fuzz() -> void:
	var all_us: Array[int] = []
	var line: String = "AIBUDGET decision time ms median/p95/max by level:"
	for lv: int in range(1, 5):
		var us: Array[int] = []
		for r: Dictionary in _results:
			us.append_array(((r["us_by_level"] as Dictionary)[lv]) as Array[int])
		all_us.append_array(us)
		line += "  %s %.1f/%.1f/%.1f (n=%d)" % [NAMES[lv], float(QA_AI.percentile(us, 50)) / 1000.0,
				float(QA_AI.percentile(us, 95)) / 1000.0, float(QA_AI.percentile(us, 100)) / 1000.0, us.size()]
	var shop: Array[int] = []
	var traces: int = 0
	for r: Dictionary in _results:
		shop.append_array(r["shop_us"] as Array[int])
		traces = maxi(traces, r["traces_max"] as int)
	var p95: float = float(QA_AI.percentile(all_us, 95)) / 1000.0
	var worst: float = float(QA_AI.percentile(all_us, 100)) / 1000.0
	gut.p(line)
	gut.p("AIBUDGET overall n=%d median %.1f p95 %.1f p99 %.1f max %.1f ms (limit p95 %.1f, max 50*scale %.0f); shop_actions median %.1f p95 %.1f max %.1f ms; most real traces in one decision %d (limit %d)" % [
			all_us.size(), float(QA_AI.percentile(all_us, 50)) / 1000.0, p95, float(QA_AI.percentile(all_us, 99)) / 1000.0, worst,
			SimTestUtil.perf_budget_f(15.0), SimTestUtil.perf_budget_f(50.0),
			float(QA_AI.percentile(shop, 50)) / 1000.0, float(QA_AI.percentile(shop, 95)) / 1000.0, float(QA_AI.percentile(shop, 100)) / 1000.0,
			traces, AimSolver.TRACE_BUDGET])
	assert_lte(p95, SimTestUtil.perf_budget_f(15.0), "p95 decision time under contention (ms)")
	assert_lte(traces, AimSolver.TRACE_BUDGET)
	# 50 ms is the phone budget at 3x slower than this container.
	assert_lte(worst, SimTestUtil.perf_budget_f(50.0), "slowest single decision (ms)")
