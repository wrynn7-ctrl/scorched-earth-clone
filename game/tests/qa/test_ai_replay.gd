@warning_ignore_start("integer_division")
extends GutTest
## M4 QA: the AI is a pure function of the state, so a match can be re-derived from settings + action
## log (replays, online play) and resumed from a save. For 10 seeded AI matches:
##  1. the log survives SaveCodec's JSON round trip unchanged after normalize_action;
##  2. re-deriving the state by replaying that log from the settings gives, at every AI turn and
##     every shop visit, exactly the action (list) the AI originally chose;
##  3. the replayed final state has the original final fingerprint;
##  4. a save taken half-way, loaded and played on by the AI, ends in the same fingerprint as the
##     uninterrupted match (so save/load never changes the AI's future decisions).

const QA_AI = preload("res://tests/qa/qa_ai.gd")
const MATCHES: int = 10
const ROOT_SEED: int = 0x5EED51

var _problems: Array[String] = []
var _stats: Dictionary = {"aim": 0, "shop": 0, "resumed": 0, "matches": 0}
var _elapsed_ms: int = 0


## Advances one step of the AI-driven match (shop for every tank, start_round, or one aim action),
## appending applied actions to `log`. Returns false when the match is over.
func _step(state: MatchState, log: Array[Dictionary]) -> bool:
	if state.phase == SimConstants.PHASE_MATCH_OVER:
		return false
	if state.phase == SimConstants.PHASE_SHOP:
		for t: TankState in state.tanks:
			for a: Dictionary in AiPlayer.shop_actions(state, t.id):
				Simulation.apply_action(state, a)
				log.append(a)
		if Simulation.all_ready(state):
			Simulation.start_round(state)
		return true
	var action: Dictionary = AiPlayer.next_action(state, state.current_tank)
	Simulation.apply_action(state, action)
	log.append(action)
	return true


func _play_out(state: MatchState, log: Array[Dictionary]) -> void:
	var guard: int = 0
	while guard < 4000 and _step(state, log):
		guard += 1


func before_all() -> void:
	var t0: int = Time.get_ticks_msec()
	for m: int in range(MATCHES):
		var settings: MatchSettings = QA_AI.random_settings(m * 3 + 1, ROOT_SEED)
		if settings.num_tanks > 5:
			settings.num_tanks = 5
			settings.controllers.resize(5)
		settings.rounds = mini(settings.rounds, 2)
		_check_match(m, settings)
		_stats["matches"] = (_stats["matches"] as int) + 1
	_elapsed_ms = Time.get_ticks_msec() - t0


func _check_match(m: int, settings: MatchSettings) -> void:
	var tag: String = "#%d seed %d (%d tanks, ctrl %s, rounds %d)" % [m, settings.seed, settings.num_tanks, str(settings.controllers), settings.rounds]
	# --- the original run
	var state: MatchState = Simulation.new_match(settings)
	var log: Array[Dictionary] = []
	_play_out(state, log)
	if state.phase != SimConstants.PHASE_MATCH_OVER:
		_problems.append("%s: original match did not finish" % tag)
		return
	var final_fp: String = Simulation.fingerprint(state)
	# --- 1. JSON round trip of the log
	var dec: Dictionary = SaveCodec.decode(SaveCodec.encode(state, log))
	if not dec["ok"]:
		_problems.append("%s: save of the finished match failed to decode: %s" % [tag, str(dec["error"])])
		return
	var loaded_log: Array[Dictionary] = []
	for a: Dictionary in (dec["actions"] as Array):
		loaded_log.append(Simulation.normalize_action(a))
	if loaded_log != log:
		_problems.append("%s: the action log changed in the save round trip (%d vs %d entries)" % [tag, loaded_log.size(), log.size()])
		return
	# --- 2/3. re-derive from the settings, comparing the AI at every decision
	var s2: MatchState = Simulation.new_match(settings)
	var expect_shop: Array[Dictionary] = []
	var expect_tank: int = -1
	var half_at: int = loaded_log.size() / 2
	var forked: bool = false
	for i: int in range(loaded_log.size()):
		var a: Dictionary = loaded_log[i]
		if Simulation.validate_action(s2, a) != "":
			_problems.append("%s: logged action %d %s is illegal on the re-derived state: %s" % [tag, i, str(a), Simulation.validate_action(s2, a)])
			return
		if s2.phase == SimConstants.PHASE_SHOP:
			var tank: int = a["tank"]
			if expect_shop.is_empty() or expect_tank != tank:
				expect_shop = AiPlayer.shop_actions(s2, tank)
				expect_tank = tank
			if expect_shop.is_empty() or expect_shop[0] != a:
				_problems.append("%s: shop action %d differs on the re-derived state: logged %s, AI now %s" % [tag, i, str(a), str(expect_shop[0] if not expect_shop.is_empty() else "{}")])
				return
			expect_shop.pop_front()
			_stats["shop"] = (_stats["shop"] as int) + 1
		else:
			var ai: Dictionary = AiPlayer.next_action(s2, s2.current_tank)
			if ai != a:
				_problems.append("%s: aim action %d differs on the re-derived state: logged %s, AI now %s" % [tag, i, str(a), str(ai)])
				return
			_stats["aim"] = (_stats["aim"] as int) + 1
			if i >= half_at and not forked:
				forked = true
				_resume_from_save(tag, s2, loaded_log.slice(0, i), final_fp)
		Simulation.apply_action(s2, a)
		if Simulation.all_ready(s2):
			Simulation.start_round(s2)
	if Simulation.fingerprint(s2) != final_fp:
		_problems.append("%s: replayed final fingerprint %s != original %s" % [tag, Simulation.fingerprint(s2), final_fp])


## Saves `state` (with the log so far), loads it and lets the AI finish the match; the result must
## equal the uninterrupted run.
func _resume_from_save(tag: String, state: MatchState, log_so_far: Array[Dictionary], final_fp: String) -> void:
	var typed: Array[Dictionary] = []
	typed.append_array(log_so_far)
	var dec: Dictionary = SaveCodec.decode(SaveCodec.encode(state, typed))
	if not dec["ok"]:
		_problems.append("%s: mid-match save failed to decode: %s" % [tag, str(dec["error"])])
		return
	var resumed: MatchState = dec["state"]
	var tail: Array[Dictionary] = []
	_play_out(resumed, tail)
	_stats["resumed"] = (_stats["resumed"] as int) + 1
	if resumed.phase != SimConstants.PHASE_MATCH_OVER:
		_problems.append("%s: resumed match did not finish" % tag)
	elif Simulation.fingerprint(resumed) != final_fp:
		_problems.append("%s: match resumed from a save ended in %s, the uninterrupted one in %s" % [tag, Simulation.fingerprint(resumed), final_fp])


func test_replay_and_resume_are_identical_to_the_original() -> void:
	gut.p("AIREPLAY %d matches in %.1f s: %d aim decisions and %d shop actions re-derived identically, %d mid-match saves resumed; problems: %d" % [
			_stats["matches"], float(_elapsed_ms) / 1000.0, _stats["aim"], _stats["shop"], _stats["resumed"], _problems.size()])
	for p: String in _problems:
		gut.p("AIREPLAY PROBLEM " + p)
	assert_eq(_problems.size(), 0, "first problem: %s" % ("" if _problems.is_empty() else _problems[0]))
	assert_eq(_stats["matches"], MATCHES)
	assert_gt(_stats["aim"] as int, 200)
	assert_eq(_stats["resumed"], MATCHES)
