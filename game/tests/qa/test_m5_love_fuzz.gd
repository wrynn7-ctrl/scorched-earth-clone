@warning_ignore_start("integer_division")
extends GutTest
## M5 QA: Love Edition fuzz (docs/ARCHITECTURE.md section 37). 200 seeded love matches: a scripted
## human against every CPU level, and CPU against CPU. After every action: meters in 0..100, terrain
## bytes untouched, only fire(heart)/pass legal, no damage or money events, the winner is the shooter
## who filled the meter, and the match is over afterwards. Every few actions the state goes through
## SaveCodec and play continues from the decoded copy; at the end a replay from settings + log must
## match the live fingerprint after every single action.

const QaUtil = preload("res://tests/qa/qa_util.gd")
const M5 = preload("res://tests/qa/qa_m5.gd")

const ROOT_SEED: int = 5150
const HUMAN_MATCHES: int = 100
const CPU_MATCHES: int = 100
const ROUNDTRIP_STRIDE: int = 10

var _turns_by_pairing: Dictionary = {}
var _decoded_checks: int = 0
var _actions_total: int = 0


## Plan of match `i`: {settings, label, human_seat (-1 = none)}.
func _plan(i: int) -> Dictionary:
	var r: Rng = Rng.derive(ROOT_SEED, 100 + i)
	var wind: int = [100, 30, 0, 12, 100][i % 5]
	var seed_value: int = r.next_u32() + i
	if i < HUMAN_MATCHES:
		var level: int = 1 + (i / 2) % 4
		var seat: int = i % 2
		var ctrl: Array[int] = [level, level]
		ctrl[seat] = SimConstants.CTRL_HUMAN
		return {"settings": M5.love_settings(seed_value, ctrl[0], ctrl[1], wind), "human_seat": seat,
				"label": "human vs L%d" % level}
	var a: int = r.range_int(1, 4)
	var b: int = r.range_int(1, 4)
	return {"settings": M5.love_settings(seed_value, a, b, wind), "human_seat": -1,
			"label": "L%d vs L%d" % [mini(a, b), maxi(a, b)]}


func _next_action(state: MatchState, plan: Dictionary, rng: Rng) -> Dictionary:
	if state.current_tank == (plan["human_seat"] as int):
		return M5.scripted_action(state, rng)
	return AiPlayer.next_action(state, state.current_tank)


## Plays one match; returns the problems found (empty = clean).
func _play(i: int) -> Array[String]:
	var plan: Dictionary = _plan(i)
	var settings: MatchSettings = plan["settings"]
	var tag: String = "match %d (%s, seed %d, wind_max %d)" % [i, plan["label"], settings.seed, settings.wind_max]
	var problems: Array[String] = []
	var state: MatchState = Simulation.new_match(settings)
	if state.phase != SimConstants.PHASE_AIM or state.round_index != 0 or state.terrain == null:
		problems.append("%s: new_match did not start straight into round 0 (%s)" % [tag, state.phase])
		return problems
	if state.settings.wind_max > SimConstants.LOVE_WIND_MAX or state.settings.num_tanks != 2 \
			or state.settings.rounds != 1 or state.settings.start_money != 0:
		problems.append("%s: love settings not clamped" % tag)
	var rng: Rng = Rng.derive(ROOT_SEED, 9000 + i)
	var terrain_ref: PackedByteArray = state.terrain.cells.duplicate()
	var log: Array[Dictionary] = []
	var fps: PackedStringArray = PackedStringArray()
	var love: Array[int] = [0, 0]
	while state.phase == SimConstants.PHASE_AIM and log.size() < M5.MAX_ACTIONS:
		var action: Dictionary = _next_action(state, plan, rng)
		var verr: String = Simulation.validate_action(state, action)
		if verr != "":
			problems.append("%s: action %d %s rejected '%s'" % [tag, log.size(), str(action), verr])
			return problems
		if log.size() % 3 == 0:
			for e: String in M5.illegal_probes(state):
				problems.append("%s: action %d probe %s" % [tag, log.size(), e])
		var events: Array[Dictionary] = Simulation.apply_action(state, action)
		log.append(action)
		for e: String in M5.audit_love_action(state, action, events, love, terrain_ref):
			problems.append("%s: action %d: %s" % [tag, log.size() - 1, e])
		love = [state.tanks[0].love, state.tanks[1].love]
		fps.append(M5.lite_fp(state))
		if problems.size() > 8:
			return problems
		if log.size() % ROUNDTRIP_STRIDE == 0 and state.phase == SimConstants.PHASE_AIM:
			state = _roundtrip(state, log, fps[fps.size() - 1], tag, problems)
			if state == null:
				return problems
	_actions_total += log.size()
	if state.phase != SimConstants.PHASE_MATCH_OVER:
		problems.append("%s: not over after %d actions (love %s)" % [tag, log.size(), str(love)])
		return problems
	_finish_checks(state, log, fps, settings, tag, problems)
	var key: String = plan["label"]
	if not _turns_by_pairing.has(key):
		_turns_by_pairing[key] = []
	(_turns_by_pairing[key] as Array).append(log.size())
	return problems


## SaveCodec round trip; returns the decoded state to carry on with (null on failure).
func _roundtrip(state: MatchState, log: Array[Dictionary], fp: String, tag: String, problems: Array[String]) -> MatchState:
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(state, log))
	if not (res["ok"] as bool):
		problems.append("%s: round trip failed '%s'" % [tag, res["error"]])
		return null
	var back: MatchState = res["state"]
	_decoded_checks += 1
	if Simulation.fingerprint(back) != Simulation.fingerprint(state) or M5.lite_fp(back) != fp:
		problems.append("%s: fingerprint differs after the round trip at action %d" % [tag, log.size()])
		return null
	if (res["actions"] as Array).size() != log.size():
		problems.append("%s: action log length %d after the round trip" % [tag, (res["actions"] as Array).size()])
	if state.current_tank == 0 or state.current_tank == 1:
		# The CPU decides identically from the decoded copy.
		var c: int = state.current_tank
		if AiProfile.level_of(state, c) > 0 and AiPlayer.next_action(state, c) != AiPlayer.next_action(back, c):
			problems.append("%s: CPU decision differs after the round trip" % tag)
	return back


func _finish_checks(state: MatchState, log: Array[Dictionary], fps: PackedStringArray, settings: MatchSettings,
		tag: String, problems: Array[String]) -> void:
	# After the win nothing more is legal, and a rejected action changes nothing.
	var final_fp: String = Simulation.fingerprint(state)
	for a: Dictionary in [M5.heart(0, 450, 500), M5.heart(1, 450, 500), {"kind": "pass", "tank": state.current_tank}]:
		if Simulation.validate_action(state, a) != "bad_phase":
			problems.append("%s: action after match_over -> '%s'" % [tag, Simulation.validate_action(state, a)])
		if not Simulation.apply_action(state, a).is_empty():
			problems.append("%s: an action applied after match_over" % tag)
	if Simulation.fingerprint(state) != final_fp:
		problems.append("%s: state changed by a rejected action" % tag)
	if not Simulation.start_round(state).is_empty():
		problems.append("%s: start_round worked after match_over" % tag)
	# Save the finished match, decode, replay the DECODED log from the settings.
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(state, log))
	if not (res["ok"] as bool):
		problems.append("%s: final decode failed '%s'" % [tag, res["error"]])
		return
	if Simulation.fingerprint(res["state"] as MatchState) != final_fp:
		problems.append("%s: final decode fingerprint" % tag)
	var replay: MatchState = Simulation.new_match(settings)
	var actions: Array[Dictionary] = res["actions"]
	for k: int in range(actions.size()):
		var a: Dictionary = Simulation.normalize_action(actions[k])
		if Simulation.validate_action(replay, a) != "":
			problems.append("%s: replay action %d rejected '%s'" % [tag, k, Simulation.validate_action(replay, a)])
			return
		Simulation.apply_action(replay, a)
		if M5.lite_fp(replay) != fps[k]:
			problems.append("%s: replay diverges at action %d" % [tag, k])
			return
	if replay.phase != SimConstants.PHASE_MATCH_OVER:
		problems.append("%s: replay ended in phase %s" % [tag, replay.phase])
	if Simulation.fingerprint(replay) != final_fp:
		problems.append("%s: replay final fingerprint differs from the live one" % tag)


func _run_range(first: int, count: int) -> void:
	var bad: Array[String] = []
	for i: int in range(first, first + count):
		bad.append_array(_play(i))
	assert_eq(bad.size(), 0, "love fuzz problems:\n  " + "\n  ".join(bad.slice(0, 12)))


func test_human_vs_every_cpu_level() -> void:
	_run_range(0, HUMAN_MATCHES * M5.scale())
	_report()


func test_cpu_vs_cpu() -> void:
	_run_range(HUMAN_MATCHES, CPU_MATCHES * M5.scale())
	_report()


func _report() -> void:
	var keys: Array = _turns_by_pairing.keys()
	keys.sort()
	var parts: PackedStringArray = PackedStringArray()
	for k: Variant in keys:
		var arr: Array = _turns_by_pairing[k]
		var total: int = 0
		var mx: int = 0
		for n: Variant in arr:
			total += n as int
			mx = maxi(mx, n as int)
		parts.append("%s: %.1f avg (max %d, n=%d)" % [str(k), float(total) / float(arr.size()), mx, arr.size()])
	gut.p("LOVE FUZZ  turns per match (actions incl. passes), %d state round trips, %d actions: %s" % [
			_decoded_checks, _actions_total, "; ".join(parts)])
	_turns_by_pairing.clear()


func test_fuzz_coverage_is_real() -> void:
	# The scripted human really plays hearts and the CPUs really win some matches from either seat.
	var winners: Array[int] = [0, 0]
	for i: int in range(0, 40):
		var plan: Dictionary = _plan(i)
		var state: MatchState = Simulation.new_match(plan["settings"] as MatchSettings)
		var rng: Rng = Rng.derive(ROOT_SEED, 9000 + i)
		var guard: int = 0
		while state.phase == SimConstants.PHASE_AIM and guard < M5.MAX_ACTIONS:
			guard += 1
			var ev: Array[Dictionary] = Simulation.apply_action(state, _next_action(state, plan, rng))
			for e: Dictionary in QaUtil.find(ev, "round_end"):
				winners[e["winner"]] += 1
	assert_gt(winners[0], 5, "seat 0 wins sometimes: %s" % str(winners))
	assert_gt(winners[1], 5, "seat 1 wins sometimes: %s" % str(winners))
