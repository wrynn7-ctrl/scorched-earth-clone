extends GutTest
## Compute budget (docs/ARCHITECTURE.md section 28/30): a decision must stay well under
## 50 ms on a mid-range phone, which is about 3x slower than this container, so the p95 here
## must be <= 15 ms x PERF_BUDGET_SCALE. Real Ballistics.trace calls are bounded (<= 48).

const BUDGET_MS: float = 15.0


func _time_ms(state: MatchState) -> float:
	var t0: int = Time.get_ticks_usec()
	AiPlayer.next_action(state, state.current_tank)
	return float(Time.get_ticks_usec() - t0) / 1000.0


func _p(values: Array[int], pct: int) -> float:
	return float(AiTestUtil.percentile(values, pct)) / 1000.0


func test_decision_time_on_ordinary_duels() -> void:
	var by_level: Dictionary = {}
	var all_us: Array[int] = []
	for level: int in [1, 2, 3, 4]:
		var us: Array[int] = []
		for i: int in range(60):
			var p: Vector2i = AiTestUtil.params(i, 600 + level)
			var state: MatchState = AiTestUtil.duel(6000 + i, level, p.x, p.y)
			var t0: int = Time.get_ticks_usec()
			AiPlayer.next_action(state, 0)
			us.append(Time.get_ticks_usec() - t0)
		by_level[level] = us
		all_us.append_array(us)
	gut.p("BUDGET  ordinary duels, decision time ms (median / p95 / max): easy %.1f/%.1f/%.1f  normal %.1f/%.1f/%.1f  hard %.1f/%.1f/%.1f  expert %.1f/%.1f/%.1f   (limit p95 %.1f)" % [
			_p(by_level[1], 50), _p(by_level[1], 95), _p(by_level[1], 100),
			_p(by_level[2], 50), _p(by_level[2], 95), _p(by_level[2], 100),
			_p(by_level[3], 50), _p(by_level[3], 95), _p(by_level[3], 100),
			_p(by_level[4], 50), _p(by_level[4], 95), _p(by_level[4], 100),
			SimTestUtil.perf_budget_f(BUDGET_MS)])
	assert_lte(_p(all_us, 95), SimTestUtil.perf_budget_f(BUDGET_MS), "p95 decision time (ms)")


func test_decision_time_on_fuzzed_states_with_specials() -> void:
	# Random mid-round states: 2-6 tanks, every weapon and item, shields, repulsors, wells.
	var us: Array[int] = []
	var worst_traces: int = 0
	for i: int in range(120):
		var state: MatchState = AiTestUtil.random_state(700 + i)
		var t0: int = Time.get_ticks_usec()
		AiPlayer.next_action(state, state.current_tank)
		us.append(Time.get_ticks_usec() - t0)
		worst_traces = maxi(worst_traces, AimSolver.trace_count)
	gut.p("BUDGET  fuzzed states, decision time ms: median %.1f  p95 %.1f  max %.1f  (limit p95 %.1f); most real traces in one decision: %d (limit %d)" % [
			_p(us, 50), _p(us, 95), _p(us, 100), SimTestUtil.perf_budget_f(BUDGET_MS), worst_traces, AimSolver.TRACE_BUDGET])
	assert_lte(_p(us, 95), SimTestUtil.perf_budget_f(BUDGET_MS), "p95 decision time on fuzzed states (ms)")
	assert_lte(worst_traces, AimSolver.TRACE_BUDGET)


func test_worst_case_scenarios_stay_bounded() -> void:
	# A gravity well, a repulsor on the target, a third tank in the line of fire, a tall wall
	# and a target out of reach: the search has to give up gracefully, not grind.
	var state: MatchState = AiTestUtil.flat_duel(SimConstants.CTRL_EXPERT, 1250, -100,
			{"pulse_missile": 9, "seeker": 2, "photon_lance": 2, "deep_bore": 2})
	state.terrain.flatten(560, 640, 120)
	state.tanks[1].repulsor_charge = 100
	state.wells.append({"owner": 1, "x": 900, "y": 300, "expires_turn": 9})
	state.tanks[0].fuel = 200
	var worst_ms: float = 0.0
	var worst_traces: int = 0
	for level: int in [3, 4]:
		state.settings.controllers[0] = level
		for wind: int in [-100, 0, 100]:
			state.wind = wind
			worst_ms = maxf(worst_ms, _time_ms(state))
			worst_traces = maxi(worst_traces, AimSolver.trace_count)
	gut.p("BUDGET  worst-case scenarios: slowest decision %.1f ms, most real traces %d" % [worst_ms, worst_traces])
	assert_lte(worst_traces, AimSolver.TRACE_BUDGET)
	assert_lte(worst_ms, SimTestUtil.perf_budget_f(50.0), "even the worst case is within the phone's 50 ms (x3 slower)")


func test_ordinary_decisions_use_few_real_traces_and_many_cheap_model_flights() -> void:
	var traces: Array[int] = []
	var model: Array[int] = []
	for i: int in range(40):
		var p: Vector2i = AiTestUtil.params(i, 9)
		var state: MatchState = AiTestUtil.duel(7000 + i, SimConstants.CTRL_EXPERT, p.x, p.y)
		AiPlayer.next_action(state, 0)
		traces.append(AimSolver.trace_count)
		model.append(AimSolver.model_count)
	gut.p("BUDGET  per decision: real traces median %d max %d, model flights median %d max %d" % [
			AiTestUtil.median(traces), AiTestUtil.percentile(traces, 100),
			AiTestUtil.median(model), AiTestUtil.percentile(model, 100)])
	assert_lte(AiTestUtil.percentile(traces, 100), 6)
	assert_lte(AiTestUtil.percentile(model, 100), 80)
